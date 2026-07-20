## DistBoxNode.gd (v4)
##
## Fix P2 — topology_changed signal: DistBoxPanel treba da se konektuje na
##   ovaj signal i uradi call_deferred("_rebuild_list") da refreshuje
##   vrednosti posle add_fuse_for() (solve se desi na sledećem frame-u).
##
## Fix P5/P6 — _is_3ph_consumer() sada proverava samo get_sim_bus(),
##   ne i plug_into(). add_fuse_for() i remove_fuse_for() koriste
##   notify_supply_bus() kao fallback ako plug_into() ne postoji —
##   ovo omogućava ThreePhaseOvenNode (bez plug_into) da bude u strujnom putu.
##
## Fix thermal_pct — get_consumer_data() nije smelo * 100 jer FuseBridge
##   vis_thermal_pct je već u procentima.

class_name DistBoxNode
extends Node2D

@export var box_name: String = "razvodna_kutija"

signal fuse_blown(fuse_node: Node2D)
signal consumer_registered(consumer: Node2D)
signal phase_changed(consumer: Node2D, new_phase: int)
## Emituje se posle add_fuse_for() i remove_fuse_for() — DistBoxPanel
## se konektuje na ovaj signal i radi call_deferred("_rebuild_list").
signal topology_changed

var _bus:         SimNode         = null
var _model:       CircuitModel    = null
var _bridge:      DistBoxBridge   = null
var _dist_box:    DistributionBox = null
var _initialized: bool            = false

# consumer_node → { "fuse": FuseNode|null, "phase": int, "in_bus": SimNode|null }
# "in_bus" je privremeni SimNode između distbox._bus i potrošača.
# Dok nema osigurača: consumer_in_bus je floating (nema konekcije ka _bus) → nema struje.
# Kada se doda osigurač: Fuse se ubacuje između _bus i consumer_in_bus.
var _consumer_data: Dictionary = {}

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup_in(_bus_in: SimNode, model: CircuitModel) -> void:
	if _initialized: return
	_initialized = true
	_model       = model
	_bus         = SimNode.new(box_name)

	_dist_box = DistributionBox.new(_bus, box_name)
	model.add_element(_dist_box)

	_bridge = DistBoxBridge.new()
	_bridge.name = "%s_Bridge" % box_name
	add_child(_bridge)
	_bridge.bind_with_bus(_dist_box, _bus, model, self)
	_bridge.solved.connect(queue_redraw)

	for child in get_children():
		if child is Node2D and _is_registrable(child):
			_register_consumer_editor_child(child)

func get_sim_bus() -> SimNode:
	return _bus

# ── Registracija potrošača ────────────────────────────────────────────────────

func register_consumer(consumer: Node2D) -> void:
	if consumer in _consumer_data: return

	# Kreiraj izolovani bus za ovog potrošača.
	# Dok nema osigurača ovaj bus je floating → nema struje kroz potrošača.
	var in_bus   := SimNode.new("%s_in_%s"    % [box_name, consumer.name])
	var cable_bus := SimNode.new("%s_cable_%s" % [box_name, consumer.name])

	# Preplaguj potrošača na izolovani bus
	if consumer is BaseAppliance:
		_remove_consumer_sim_elements(consumer)
		consumer.plug_into(in_bus, _model)
	elif _is_3ph_consumer(consumer):
		_plug_consumer_into(consumer, in_bus)

	_consumer_data[consumer] = { "fuse": null, "phase": Phase.L1, "in_bus": in_bus, "cable_bus": cable_bus, "cable_node": null }
	emit_signal("consumer_registered", consumer)

func _register_consumer_editor_child(consumer: Node2D) -> void:
	if consumer in _consumer_data: return

	var in_bus := SimNode.new("%s_in_%s" % [box_name, consumer.name])
	var cable_bus := SimNode.new("%s_cable_%s" % [box_name, consumer.name])

	if consumer is BaseAppliance:
		_remove_consumer_sim_elements(consumer)
		consumer.plug_into(in_bus, _model)
	elif _is_3ph_consumer(consumer):
		_plug_consumer_into(consumer, in_bus)

	_consumer_data[consumer] = { "fuse": null, "phase": Phase.L1, "in_bus": in_bus, "cable_bus": cable_bus, "cable_node": null }

## Registrable za editor-placed children — mora imati plug_into ili
## notify_supply_bus (za re-plug) i get_sim_bus.
static func _is_registrable(node: Node) -> bool:
	return node is BaseAppliance or (
		node.has_method("get_sim_bus") and (
			node.has_method("plug_into") or node.has_method("notify_supply_bus")
		)
	)

## 3-fazni consumer: BaseAppliance podklase koje vrate true iz
## is_three_phase_appliance(), ili non-BaseAppliance nodovi sa get_sim_bus().
static func _is_3ph_consumer(node: Node) -> bool:
	if node is BaseAppliance:
		return (node as BaseAppliance).is_three_phase_appliance()
	return node.has_method("get_sim_bus")

## Pluguje consumer u dati bus, koristeći plug_into() ako postoji,
## inače notify_supply_bus() (ThreePhaseOvenNode pattern).
func _plug_consumer_into(consumer: Node, bus: SimNode) -> void:
	if consumer.has_method("plug_into"):
		consumer.plug_into(bus, _model)
	elif consumer.has_method("notify_supply_bus"):
		consumer.notify_supply_bus(bus)

## Ukloni SVE sim elemente iz BaseAppliance consumer-a pre re-plugovanja.
## BaseAppliance podklase mogu imati _consumer (RatedConsumer),
## _socket (Socket), ili _three_phase_socket — sve treba ukloniti iz modela
## da ne bi ostali "ghost" elementi koji daju struju bez osigurača.
func _remove_consumer_sim_elements(consumer: BaseAppliance) -> void:
	# RatedConsumer (OvenAppliance, BoilerAppliance, itd.)
	if consumer._consumer != null:
		_model.remove_element(consumer._consumer)
		consumer._consumer = null
	# SocketAppliance koristi _socket
	var sock = consumer.get("_socket")
	if sock != null:
		_model.remove_element(sock)
		consumer.set("_socket", null)
	# ThreePhaseSocketAppliance može imati _three_phase_socket
	var sock3 = consumer.get("_three_phase_socket")
	if sock3 != null:
		_model.remove_element(sock3)
		consumer.set("_three_phase_socket", null)
	# Oslobodi stari bridge koji drži ref na uklonjeni sim element
	var old_bridge = consumer.get("_bridge")
	if old_bridge != null and old_bridge is Node:
		old_bridge.queue_free()
		consumer.set("_bridge", null)
	consumer._bus    = null
	consumer._solved = false

# ── Osigurači ─────────────────────────────────────────────────────────────────

func add_fuse_for(
	consumer: Node2D,
	rated_a: float,
	curve: Fuse.TripCurve,
	resettable: bool = true
) -> Node:
	if not (consumer in _consumer_data):
		push_warning("DistBoxNode: consumer nije registrovan: %s" % consumer.name)
		return null

	remove_fuse_for(consumer)

	var phase: int     = _consumer_data[consumer].get("phase", Phase.L1)
	var in_bus: SimNode    = _consumer_data[consumer].get("in_bus", null)
	var cable_bus: SimNode = _consumer_data[consumer].get("cable_bus", null)

	if in_bus == null:
		in_bus = SimNode.new("%s_in_%s" % [box_name, consumer.name])
		_consumer_data[consumer]["in_bus"] = in_bus
		if consumer is BaseAppliance:
			_remove_consumer_sim_elements(consumer)
			consumer.plug_into(in_bus, _model)
		elif _is_3ph_consumer(consumer):
			_plug_consumer_into(consumer, in_bus)

	var is_3ph: bool = _is_3ph_consumer(consumer)

	# When no cable has been drawn from this distbox to the consumer
	# (e.g. editor-placed child nodes), cable_bus is floating and has no
	# connection to _bus.  In that case wire the fuse directly to _bus so
	# the circuit is complete: _bus → fuse → in_bus → consumer.
	var has_cable: bool    = _consumer_data[consumer].get("cable_node", null) != null
	var fuse_input: SimNode = cable_bus if (has_cable and cable_bus != null) else _bus

	if is_3ph:
		# Trofazni potrošač → ThreePhaseFuseNode
		var fn3 := ThreePhaseFuseNode.new()
		fn3.fuse_name       = "%s_F_%s" % [box_name, consumer.name]
		fn3.rated_current_a = rated_a
		add_child(fn3)
		fn3.setup_in_out(fuse_input, in_bus, _model)
		_dist_box.add_output_on_phase(fn3._fuse, phase)
		fn3.fuse_blown.connect(func(_ph): emit_signal("fuse_blown", fn3))
		_consumer_data[consumer]["fuse"] = fn3
		_update_cable_and_fuse_phase(consumer, phase)
		_model.mark_dirty()
		emit_signal("topology_changed")
		return fn3
	else:
		# Monofazni potrošač → FuseNode
		var fn := FuseNode.new()
		fn.fuse_name       = "%s_F_%s" % [box_name, consumer.name]
		fn.rated_current_a = rated_a
		fn.curve           = curve
		fn.resettable      = resettable
		add_child(fn)
		fn.setup_in_out(fuse_input, in_bus, _model)
		_dist_box.add_output_on_phase(fn._fuse, phase)
		fn.fuse_blown.connect(func(f): emit_signal("fuse_blown", f))
		_consumer_data[consumer]["fuse"] = fn
		_update_cable_and_fuse_phase(consumer, phase)
		_model.mark_dirty()
		emit_signal("topology_changed")
		return fn

func remove_fuse_for(consumer: Node2D) -> void:
	if not (consumer in _consumer_data): return
	var fn: Node = _consumer_data[consumer].get("fuse", null)
	if fn == null: return

	var fuse_elem = fn.get("_fuse")
	if fuse_elem != null:
		_model.remove_element(fuse_elem)
		var idx: int = _dist_box.output_fuses.find(fuse_elem)
		if idx >= 0:
			_dist_box.output_fuses.remove_at(idx)
			if idx < _dist_box.circuit_phases.size():
				_dist_box.circuit_phases.remove_at(idx)

	fn.queue_free()
	_consumer_data[consumer]["fuse"] = null
	_model.mark_dirty()
	emit_signal("topology_changed")

## Deregistruje potrošača iz ovog razvodnika — MORA se pozvati PRE
## queue_free() na potrošaču, inače _consumer_data ostaje sa "duh"
## referencom koja puca u DistBoxBridge._sync_visual_state() na sledećem solve().
func remove_consumer(consumer: Node2D) -> void:
	if not (consumer in _consumer_data): return

	remove_fuse_for(consumer)

	_consumer_data.erase(consumer)
	_model.mark_dirty()
	emit_signal("topology_changed")

# ── Faza ──────────────────────────────────────────────────────────────────────

func set_consumer_phase(consumer: Node2D, new_phase: int) -> void:
	if not (consumer in _consumer_data): return
	_consumer_data[consumer]["phase"] = new_phase

	var fn: Node = _consumer_data[consumer].get("fuse", null)
	if fn != null:
		var fuse_elem = fn.get("_fuse")
		if fuse_elem != null:
			var idx: int = _dist_box.output_fuses.find(fuse_elem)
			if idx >= 0:
				_dist_box.set_circuit_phase(idx, new_phase)
		_update_cable_and_fuse_phase(consumer, new_phase)

	# Ažuriraj assigned_phase na sim elementu potrošača (Consumer, Socket, ili
	# bilo šta drugo što BaseAppliance podklasa vrati kroz _phase_element()).
	if consumer is BaseAppliance:
		(consumer as BaseAppliance).set_assigned_phase(new_phase)

	_model.mark_dirty()
	emit_signal("phase_changed", consumer, new_phase)
	emit_signal("topology_changed")

func get_consumer_phase(consumer: Node2D) -> int:
	if consumer in _consumer_data:
		return _consumer_data[consumer].get("phase", Phase.L1)
	return Phase.L1

## Da li je ovaj consumer registrovan u ovom DistBox-u?
## Koristi world.gd da odluči ko "poseduje" fazu za dati appliance —
## ovaj DistBox (uvek editable, kaskadno) ili direktna veza na trafo/izvor.
func has_consumer(consumer: Node2D) -> bool:
	return consumer in _consumer_data

## Nađi potrošača kome pripada dati FuseNode/ThreePhaseFuseNode —
## koristi world.gd kad je selektovan sam osigurač (ne potrošač).
func find_consumer_for_fuse(fuse_node: Node2D) -> Node2D:
	for consumer in _consumer_data:
		if _consumer_data[consumer].get("fuse", null) == fuse_node:
			return consumer
	return null

# ── Podaci za DistBoxPanel ────────────────────────────────────────────────────

func get_consumer_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for consumer in _consumer_data:
		var data: Dictionary  = _consumer_data[consumer]
		var fn: Node          = data.get("fuse", null)
		var phase: int        = data.get("phase", Phase.L1)
		var ph_idx_lbl: int   = [Phase.L1, Phase.L2, Phase.L3].find(phase)
		var phase_lbl: String = ["L1", "L2", "L3"][clampi(ph_idx_lbl, 0, 2)]

		var current_a:   float  = 0.0
		var thermal_pct: float  = 0.0
		var fuse_state:  String = "bez osigurača"
		var blown:       bool   = false
		var curve_name:  String = ""
		var rated_a:     float  = 0.0

		var is_3ph: bool = _is_3ph_consumer(consumer)

		# currents_3ph: Array[float] — [L1, L2, L3] — samo za 3-fazne fuse.
		# Ostali slučajevi ostavljaju prazno.
		var currents_3ph: Array = [0.0, 0.0, 0.0]

		if fn != null:
			rated_a = fn.get("rated_current_a") if fn.get("rated_current_a") != null else 0.0
			if is_3ph:
				# ThreePhaseFuseNode — čitaj iz ThreePhaseFuseBridge
				var fb: ThreePhaseFuseBridge = fn.get("_bridge") as ThreePhaseFuseBridge
				if fb != null:
					for k_idx in range(3):
						var k: int = [Phase.L1, Phase.L2, Phase.L3][k_idx]
						currents_3ph[k_idx] = fb.vis_currents_a.get(k, 0.0)
					current_a = (currents_3ph[0] + currents_3ph[1] + currents_3ph[2]) / 3.0
					blown = fn._fuse.is_blown() if fn.get("_fuse") != null else false
				fuse_state = "pregoreo" if blown else "ok"
			else:
				# FuseNode — čitaj iz FuseBridge
				var fb: FuseBridge = fn.get("_bridge") as FuseBridge
				if fb != null:
					current_a   = fb.vis_current_mag
					thermal_pct = fb.vis_thermal_pct
					blown       = fb.vis_blown
				var fuse_elem = fn.get("_fuse")
				if fuse_elem != null:
					if fuse_elem.has_method("curve_name"):
						curve_name = fuse_elem.curve_name()
					fuse_state = "pregoreo" if blown \
						else ("ok" if fuse_elem.is_closed() else "isključen")
		else:
			current_a  = _read_consumer_current(consumer)
			fuse_state = "bez osigurača"

		result.append({
			"consumer":      consumer,
			"consumer_name": consumer.name,
			"has_fuse":      fn != null,
			"fuse_node":     fn,
			"rated_a":       rated_a,
			"curve":         curve_name,
			"phase":         phase,
			"phase_label":   phase_lbl,
			"current_a":     current_a,
			"currents_3ph":  currents_3ph,
			"thermal_pct":   thermal_pct,
			"fuse_state":    fuse_state,
			"blown":         blown,
			"is_3ph":        is_3ph,
		})
	return result

## Čita struju iz consumer node-a bez osigurača.
## Isti pattern kao DistBoxBridge._read_consumer_current.
func _read_consumer_current(consumer: Node) -> float:
	var bridge = consumer.get("_bridge")
	if bridge is ElementBridge:
		var eb := bridge as ElementBridge
		var currents = bridge.get("vis_currents_a")
		if currents is Array and currents.size() >= 3:
			# Trofazni consumer — uzmi prosek faza
			var sum: float = 0.0
			for i in range(3):
				sum += float(currents[i])
			return sum / 3.0
		return eb.vis_current_a
	var sim_elem = consumer.get("_consumer")
	if sim_elem != null:
		var ic = sim_elem.get("current")
		if ic is Complex:
			return ic.magnitude()
	return 0.0

func register_consumer_cable(consumer: Node2D, cable: Node2D) -> void:
	if consumer in _consumer_data:
		_consumer_data[consumer]["cable_node"] = cable

func _update_cable_and_fuse_phase(consumer: Node2D, phase: int) -> void:
	# Ažuriraj kabl — samo monofazni kabl ima assigned_phase
	var cable: Node2D = _consumer_data[consumer].get("cable_node", null)
	if cable != null:
		var sc = cable.get("sim_cable")
		if sc != null and sc.get("assigned_phase") != null:
			sc.assigned_phase = phase

	# Ažuriraj osigurač — samo monofazni Fuse ima assigned_phase
	var fn: Node = _consumer_data[consumer].get("fuse", null)
	if fn != null:
		var fuse_elem = fn.get("_fuse")
		if fuse_elem != null and fuse_elem.get("assigned_phase") != null:
			fuse_elem.assigned_phase = phase

	_model.mark_dirty()

# ── Breaker API ───────────────────────────────────────────────────────────────

func main_breaker_open() -> void:
	if _bridge != null: _bridge.main_breaker_open()

func main_breaker_close() -> void:
	if _bridge != null: _bridge.main_breaker_close()

func phase_breaker_open(phase: int) -> void:
	if _dist_box != null: _dist_box.phase_breaker_open(phase)
	if _model: _model.mark_dirty()

func phase_breaker_close(phase: int) -> void:
	if _dist_box != null: _dist_box.phase_breaker_close(phase)
	if _model: _model.mark_dirty()

# ── InfoPanel API ─────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	if _bridge == null:
		return {"name": box_name, "type": "Razvodna kutija",
			"rows": [ElementBridge.row("Stanje", "nepovezano")]}
	return _bridge.get_info()

func get_consumer_bus(consumer: Node2D) -> SimNode:
	if consumer in _consumer_data:
		return _consumer_data[consumer].get("cable_bus", null)
	return null
	
# ── Crtanje ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _bridge == null or _bus == null:
		draw_circle(Vector2.ZERO, 8.0, Color(0.5, 0.5, 0.5))
		return

	var col: Color
	match _bridge.vis_state:
		"kvar":
			col = Color(0.9, 0.0, 0.0) if _bridge.vis_v_pe > 50.0 else Color(1.0, 0.7, 0.0)
		"upozorenje":
			col = Color(1.0, 0.5, 0.0)
		_:
			var v_nom:   float = SimConstants.NOMINAL_V
			var min_v:   float = _bridge.vis_phase_voltages.min()
			var drop_pu: float = clampf(1.0 - min_v / maxf(v_nom, 1.0), 0.0, 1.0)
			col = Color(0.2, 0.85, 0.2).lerp(Color(1.0, 0.6, 0.0), drop_pu * 3.0)

	draw_circle(Vector2.ZERO, 8.0, col)

static func row(label: String, value, fmt: String = "") -> Dictionary:
	return ElementBridge.row(label, value, fmt)
