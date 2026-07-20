## CableNode.gd (refaktorisan — sa VisualizationManager integracijom)
## Vizuelni node za monofazni kabl.
## Sva sim logika i stanje čitanja delegirani na CableBridge.
## Ovaj fajl odgovara SAMO za: crtanje, klik detekciju, scenu.
##
## Promena u odnosu na prethodnu verziju:
##   _draw() više ne sadrži color logiku — ona je premešten u VisualizationMode
##   klase.  CableNode pita VisualizationManager za boju i samo crta.
##   Nema promena u setup(), bus logici, sim elementima, signalima ili javnom API-u.

class_name CableNode
extends Node2D

@export var cable_label: String = "cable"
@export var length_m:    float  = 50.0
@export var cross_mm2:   float  = 4.0
@export var cable_core:  String = "copper"
@export var max_current: float  = 16.0
@export var line_width:  float  = 10.0

## ── Editor-postavljanje ──────────────────────────────────────────────────────
## Popuni ova dva polja u Inspectoru kad kabl postavljaš direktno u editoru
## (umesto kroz CableManager runtime flow). Node mora imati get_sim_bus().
@export var node_a: Node2D = null
@export var node_b: Node2D = null

## Direktan pristup sim elementu (za CableManager / world.gd kompatibilnost).
var sim_cable: Cable = null

signal cable_clicked(cable_node: CableNode)

var _bridge: CableBridge  = null
var _node_a: Node2D       = null
var _node_b: Node2D       = null
var _model:  CircuitModel = null
## Visual-only waypoints (global positions) for turns/joints. Purely cosmetic.
var _waypoints: Array[Vector2] = []

# ── Setup ─────────────────────────────────────────────────────────────────────

## Poziva world.gd u _ready() za kablove postavljene u editoru (node_a/node_b
## popunjeni preko Inspectora). Radi isti posao kao CableManager._spawn_cable(),
## samo bez runtime klik-flow-a.
func setup_from_editor(model: CircuitModel) -> void:
	if node_a == null or node_b == null:
		push_warning("CableNode '%s': node_a / node_b nisu podešeni u Inspectoru." % cable_label)
		return
	setup(node_a, node_b, model, _waypoints)

func setup(a: Node2D, b: Node2D, model: CircuitModel, waypoints: Array[Vector2] = []) -> void:
	_node_a = a
	_node_b = b
	_model  = model
	_waypoints = waypoints

	var dist_px: float = a.global_position.distance_to(b.global_position)
	length_m = maxf(dist_px * 0.1, 0.5)

	# ── Korak 1: inicijalizuj grid nodove koji čekaju bus ─────────────────────
	_init_pending_grid_node(a, b, model)
	_init_pending_grid_node(b, a, model)
	_try_register_consumer(a, b)
	_try_register_consumer(b, a)

	# ── Korak 2: čitaj bus-eve (posle init-a) ────────────────────────────────
	var bus_a: SimNode = a.get_sim_bus() if a.has_method("get_sim_bus") else null
	var bus_b: SimNode = b.get_sim_bus() if b.has_method("get_sim_bus") else null

	if a is DistBoxNode and a._initialized:
		var real_b: SimNode = a.get_consumer_bus(b)
		if real_b != null: bus_b = real_b
	if b is DistBoxNode and b._initialized:
		var real_a: SimNode = b.get_consumer_bus(a)
		if real_a != null: bus_a = real_a

	if a is SwitchAppliance:           bus_a = _pick_switch_bus(a)
	if b is SwitchAppliance:           bus_b = _pick_switch_bus(b)
	if a is TransformerNode:           bus_a = _pick_transformer_bus(a)
	if b is TransformerNode:           bus_b = _pick_transformer_bus(b)
	if a is ThreePhaseTransformerNode: bus_a = _pick_3ph_transformer_bus(a)
	if b is ThreePhaseTransformerNode: bus_b = _pick_3ph_transformer_bus(b)
	# _pick_socket_bus() ne sme da prepiše bus koji je već postavio DistBoxNode.
	if a is SocketAppliance and not (b is DistBoxNode and b._initialized and b._consumer_data.has(a)):
		bus_a = _pick_socket_bus(a)
	if b is SocketAppliance and not (a is DistBoxNode and a._initialized and a._consumer_data.has(b)):
		bus_b = _pick_socket_bus(b)

	if bus_a == null or bus_b == null:
		push_warning("CableNode '%s': node nema SimNode bus!" % cable_label)
		return
	if bus_a == bus_b:
		push_warning("CableNode '%s': oba kraja imaju isti SimNode bus!" % cable_label)
		return

	# ── Korak 3: kreiraj sim element ──────────────────────────────────────────
	sim_cable = Cable.new(bus_a, bus_b, length_m, cross_mm2, cable_core, max_current, cable_label)
	model.add_element(sim_cable)

	# ── Korak 4: bridge ───────────────────────────────────────────────────────
	_bridge = CableBridge.new()
	_bridge.name = "%s_Bridge" % cable_label
	add_child(_bridge)
	_bridge.bind(sim_cable, model)

	_bridge.solved.connect(queue_redraw)
	_bridge.overloaded.connect(func(_v): queue_redraw())
	_bridge.overheated.connect(func(_v): queue_redraw())
	_bridge.enabled_changed.connect(func(_v): queue_redraw())

	model.mark_dirty()

	if b is BaseAppliance and not (a is DistBoxNode): b.notify_supply_bus(bus_a)
	if a is BaseAppliance and not (b is DistBoxNode): a.notify_supply_bus(bus_b)
	if b.has_method("notify_supply_bus") and not (b is BaseAppliance) and not (a is DistBoxNode): b.notify_supply_bus(bus_a)
	if a.has_method("notify_supply_bus") and not (a is BaseAppliance) and not (b is DistBoxNode): a.notify_supply_bus(bus_b)

	if a is DistBoxNode and a._initialized:
		a.register_consumer_cable(b, self)
	elif b is DistBoxNode and b._initialized:
		b.register_consumer_cable(a, self)

	if a is SocketAppliance and b is BaseAppliance and not (b is SocketAppliance):
		a.register_consumer_appliance(b, self)
	elif b is SocketAppliance and a is BaseAppliance and not (a is SocketAppliance):
		b.register_consumer_appliance(a, self)

	set_meta("selected", false)

	# ── Registruj se kod VisualizationManager-a ───────────────────────────────
	#if is_instance_valid(VisualizationManager):
	VisualizationManager.register_cable(self)

	queue_redraw()

# ── InfoPanel API ─────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	if _bridge != null:
		return _bridge.get_info()
	return { "name": cable_label, "type": "Kabl", "rows": [] }

# ── Game actions ──────────────────────────────────────────────────────────────

func connect_cable() -> void:
	if _bridge != null: _bridge.interact_toggle()

func disconnect_cable() -> void:
	if _bridge != null: _bridge.interact_toggle()

func toggle() -> void:
	if _bridge != null: _bridge.interact_toggle()

func repair() -> void:
	if _bridge != null: _bridge.interact_repair()

## Primeni parametre iz CableInspectorDialog (EDIT mode).
func apply_params(params: Dictionary) -> void:
	cable_label = params.get("cable_label", cable_label)
	cross_mm2   = params.get("cross_mm2",   cross_mm2)
	cable_core  = params.get("cable_core",  cable_core)
	max_current = params.get("max_current", max_current)
	if sim_cable != null:
		sim_cable.cross_mm2    = cross_mm2
		sim_cable.material     = cable_core
		sim_cable.max_current  = max_current
		sim_cable.element_name = cable_label
		if _model: _model.mark_dirty()
	queue_redraw()

# ── Klik detekcija ────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		return
	if _is_mouse_near_cable(get_local_mouse_position(), 6.0):
		get_viewport().set_input_as_handled()
		emit_signal("cable_clicked", self)

func _is_mouse_near_cable(mouse_pos: Vector2, threshold: float) -> bool:
	if _node_a == null or _node_b == null:
		return false
	var points: Array[Vector2] = _build_local_points()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		if ab.length_squared() < 0.001:
			continue
		var t := clampf((mouse_pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if mouse_pos.distance_to(a + ab * t) <= threshold:
			return true
	return false

# ── Crtanje ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _node_a == null or _node_b == null:
		return

	var points := _build_local_points()

	# ── Delegiraj color logiku VisualizationManager-u ────────────────────────
	# Modus operandi: VisualizationManager čita vis_* iz _bridge-a i vraća boju.
	# Nema solver poziva, nema dupliranja kalkulacija.
	var col: Color
	if is_instance_valid(VisualizationManager):
		col = VisualizationManager.get_cable_color(self)
	else:
		# Fallback ako VisualizationManager nije učitan (editor play bez autoload-a).
		col = _fallback_color()

	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], col, line_width)

	# Draw small circles at joint/turn positions
	if _waypoints.size() > 0:
		var joint_col := col.lightened(0.3)
		for wp in _waypoints:
			draw_circle(to_local(wp), line_width + 2.0, joint_col)

	if get_meta("selected", false):
		for i in range(points.size() - 1):
			draw_line(points[i], points[i + 1], Color(0.2, 0.8, 1.0, 0.5), line_width + 6.0)

## Fallback color — reproduces pre-refactor NormalMode behavior without
## requiring VisualizationManager to be loaded. Used only in development.
func _fallback_color() -> Color:
	if _bridge == null:
		return Color(0.5, 0.5, 0.5)
	if not _bridge.vis_enabled:
		return Color(0.4, 0.4, 0.4)
	if sim_cable != null and sim_cable.damaged:
		return Color(0.25, 0.05, 0.05)
	if _bridge.vis_overloaded or _bridge.vis_overheated:
		return Color(1.0, 0.15, 0.0)
	var load_pct: float = clampf(_bridge.vis_loading_pct / 100.0, 0.0, 1.0)
	return Color(0.1, 0.9, 0.1).lerp(Color(1.0, 0.55, 0.0), load_pct)

## Builds the full point list in local space: node_a → waypoints → node_b.
func _build_local_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	pts.append(to_local(_node_a.global_position))
	for wp in _waypoints:
		pts.append(to_local(wp))
	pts.append(to_local(_node_b.global_position))
	return pts

# ── Grid node init helpers ────────────────────────────────────────────────────

func _init_pending_grid_node(target: Node2D, source: Node2D, model: CircuitModel) -> void:
	var source_bus: SimNode = source.get_sim_bus() if source.has_method("get_sim_bus") else null
	if source_bus == null: return
	if target is DistBoxNode and not target._initialized:
		target.setup_in(source_bus, model)
	elif target is FuseNode and target._bus_in == null:
		target.setup_in(source_bus, model)
	elif target is TransformerNode and not target._initialized:
		target.setup_in(model)
	elif target is ThreePhaseSwitchNode and not target._initialized:
		target.setup_in(source_bus, model)
	elif target is ThreePhaseFuseNode and not target._initialized:
		target.setup_in(source_bus, model)

## Registruje consumer na DistBoxNode ako postoji.
func _try_register_consumer(dist_side: Node2D, consumer_side: Node2D) -> void:
	if not (dist_side is DistBoxNode and dist_side._initialized):
		return
	var ok: bool = DistBoxNode._is_registrable(consumer_side)
	if not ok:
		ok = (consumer_side is ThreePhaseOvenNode or
			  consumer_side is ThreePhaseSocketAppliance)
	if ok:
		dist_side.register_consumer(consumer_side)

func _pick_switch_bus(sw: SwitchAppliance) -> SimNode:
	for elem in sw._model.elements:
		if elem is Cable:
			if elem.node_a() == sw._bus or elem.node_b() == sw._bus:
				return sw._bus_out
	return sw._bus

func _pick_transformer_bus(tx: TransformerNode) -> SimNode:
	if tx._transformer == null: return tx.get_primary_bus()
	var primary: SimNode   = tx.get_primary_bus()
	var secondary: SimNode = tx.get_secondary_bus()
	for elem in tx._model.elements:
		if elem is Cable:
			if elem.node_a() == primary or elem.node_b() == primary:
				return secondary
	return primary

func _pick_socket_bus(sock: SocketAppliance) -> SimNode:
	if sock._socket == null: return sock.get_sim_bus()
	var supply: SimNode = sock._socket.node_supply()
	for elem in sock._model.elements:
		if elem is Cable:
			if elem.node_a() == supply or elem.node_b() == supply:
				return sock._socket.node_load()
	return supply

func _pick_3ph_transformer_bus(tx: ThreePhaseTransformerNode) -> SimNode:
	var primary: SimNode   = tx.get_primary_bus()
	var secondary: SimNode = tx.get_secondary_bus()
	for elem in tx._model.elements:
		if elem is ThreePhaseCable or elem is Cable:
			if elem.node_a() == primary or elem.node_b() == primary:
				return secondary
	return primary

static func row(label: String, value, fmt: String = "") -> Dictionary:
	return ElementBridge.row(label, value, fmt)
