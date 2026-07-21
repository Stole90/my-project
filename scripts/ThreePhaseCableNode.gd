## ThreePhaseCableNode.gd (refaktorisan — sa VisualizationManager integracijom)
## Vizuelni node za trofazni kabl.
## Sim logika i stanje → ThreePhaseCableBridge.
##
## Promena u odnosu na prethodnu verziju:
##   _draw() više ne sadrži color logiku — delegirana je VisualizationManager-u.
##   Nema promena u setup(), bus logici, sim elementima, signalima ili javnom API-u.

class_name ThreePhaseCableNode
extends Node2D

@export var cable_label:       String = "3ph_cable"
@export var length_m:          float  = 50.0
@export var cross_mm2:         float  = 4.0
@export var cable_core:        String = "copper"
@export var max_current:       float  = 16.0
@export var line_width:        float  = 10.0
@export var phase_spacing:     float  = 15.0
@export var neutral_cross_mm2: float  = 0.0

## ── Editor-postavljanje ──────────────────────────────────────────────────────
@export var node_a: Node2D = null
@export var node_b: Node2D = null

var sim_cable: ThreePhaseCable = null

signal cable_clicked(cable_node: ThreePhaseCableNode)

var _bridge: ThreePhaseCableBridge = null
var _node_a: Node2D                = null
var _node_b: Node2D                = null
var _model:  CircuitModel          = null
## Visual-only waypoints (global positions) for turns/joints. Purely cosmetic.
var _waypoints: Array[Vector2] = []

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup_from_editor(model: CircuitModel) -> void:
	if node_a == null or node_b == null:
		push_warning("ThreePhaseCableNode '%s': node_a / node_b nisu podešeni u Inspectoru." % cable_label)
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

	# ── Korak 2: čitaj bus-eve ────────────────────────────────────────────────
	var bus_a: SimNode = a.get_sim_bus() if a.has_method("get_sim_bus") else null
	var bus_b: SimNode = b.get_sim_bus() if b.has_method("get_sim_bus") else null

	if a is DistBoxNode and a._initialized:
		var real_b: SimNode = a.get_consumer_bus(b)
		if real_b != null: bus_b = real_b
	if b is DistBoxNode and b._initialized:
		var real_a: SimNode = b.get_consumer_bus(a)
		if real_a != null: bus_a = real_a

	if a is ThreePhaseTransformerNode: bus_a = _pick_3ph_transformer_bus(a)
	if b is ThreePhaseTransformerNode: bus_b = _pick_3ph_transformer_bus(b)

	if bus_a == null or bus_b == null:
		push_warning("ThreePhaseCableNode '%s': node nema SimNode bus! (a=%s, b=%s)" % [cable_label, str(bus_a), str(bus_b)])
		return
	if bus_a == bus_b:
		push_warning("ThreePhaseCableNode '%s': oba kraja imaju isti bus!" % cable_label)
		return

	# ── Korak 3: kreiraj sim element ──────────────────────────────────────────
	# ThreePhaseCable sam računa otpor iz cross_mm2 + material (temp-korigovano,
	# isti model kao Cable) — ne treba ga računati ovde unapred.
	sim_cable = ThreePhaseCable.new(bus_a, bus_b, length_m, 0.0, 0.0, max_current, cable_label)
	sim_cable.cross_mm2 = cross_mm2
	sim_cable.material  = cable_core

	if neutral_cross_mm2 > 0.0:
		var rho: float = SimConstants.RESISTIVITY.get(cable_core, 1.72e-8)
		var r_n: float = rho / (neutral_cross_mm2 * 1e-6)
		sim_cable.neutral_impedance_per_m = Complex.new(r_n, 0.0)

	model.add_element(sim_cable)

	# ── Korak 4: bridge ───────────────────────────────────────────────────────
	_bridge = ThreePhaseCableBridge.new()
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

	set_meta("selected", false)

	# ── Registruj se kod VisualizationManager-a ───────────────────────────────
	#if is_instance_valid(VisualizationManager):
	VisualizationManager.register_3ph_cable(self)

	queue_redraw()

# ── InfoPanel API ─────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	return _bridge.get_info() if _bridge != null else {"name": cable_label, "type": "3-fazni kabl", "rows": []}

# ── Game actions ──────────────────────────────────────────────────────────────

func connect_cable() -> void:
	if _bridge != null: _bridge.interact_toggle()

func disconnect_cable() -> void:
	if _bridge != null: _bridge.interact_toggle()

func toggle() -> void:
	if _bridge != null: _bridge.interact_toggle()

func repair() -> void:
	if _bridge != null: _bridge.interact_repair()

func apply_params(params: Dictionary) -> void:
	cable_label       = params.get("cable_label",       cable_label)
	cross_mm2         = params.get("cross_mm2",         cross_mm2)
	cable_core        = params.get("cable_core",        cable_core)
	max_current       = params.get("max_current",       max_current)
	neutral_cross_mm2 = params.get("neutral_cross_mm2", neutral_cross_mm2)
	if sim_cable != null:
		sim_cable.cross_mm2     = cross_mm2
		sim_cable.material      = cable_core
		sim_cable.max_current_a = max_current
		sim_cable.element_name  = cable_label
		if neutral_cross_mm2 > 0.0:
			var rho: float = SimConstants.RESISTIVITY.get(cable_core, 1.72e-8)
			sim_cable.neutral_impedance_per_m = Complex.new(rho / (neutral_cross_mm2 * 1e-6), 0.0)
		else:
			sim_cable.neutral_impedance_per_m = Complex.new(0.0, 0.0)

		# ── Cable Rating System (SRPS IEC 60364-5-52) — opciono, aditivno ──────
		var has_rating_params: bool = params.has("installation_method")
		if has_rating_params:
			if sim_cable.installation_model == null:
				sim_cable.installation_model = CableInstallationModel.new()
			var im: CableInstallationModel = sim_cable.installation_model
			im.installation_method        = params.get("installation_method", im.installation_method)
			im.ambient_c                   = params.get("ambient_c", im.ambient_c)
			im.soil_temperature_c          = params.get("soil_temperature_c", im.soil_temperature_c)
			im.soil_type                   = params.get("soil_type", im.soil_type)
			im.soil_resistivity_advanced   = params.get("soil_resistivity_advanced", im.soil_resistivity_advanced)
			im.grouped_circuits            = params.get("grouped_circuits", im.grouped_circuits)
			im.grouping_arrangement        = params.get("grouping_arrangement", im.grouping_arrangement)
			im.harmonic_level              = params.get("harmonic_level", im.harmonic_level)
			im.thd_percent_advanced        = params.get("thd_percent_advanced", im.thd_percent_advanced)
			sim_cable.insulation_type      = params.get("insulation_type", sim_cable.insulation_type)
			sim_cable.recalc_rating()

		if _model: _model.mark_dirty()
	queue_redraw()

# ── Klik detekcija ────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		return
	if _is_mouse_near_cable(get_local_mouse_position(), 8.0):
		get_viewport().set_input_as_handled()
		emit_signal("cable_clicked", self)

func _is_mouse_near_cable(mouse_pos: Vector2, threshold: float) -> bool:
	if _node_a == null or _node_b == null: return false
	var points := _build_local_points()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		if ab.length_squared() < 0.001: continue
		var t := clampf((mouse_pos - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if mouse_pos.distance_to(a + ab * t) <= threshold:
			return true
	return false

# ── Crtanje ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _node_a == null or _node_b == null: return

	var points := _build_local_points()

	var has_n: bool    = sim_cable != null and sim_cable.has_neutral()
	var num_lines: int = 4 if has_n else 3

	# ── Delegiraj color logiku VisualizationManager-u ────────────────────────
	var colors: Array[Color]
	if is_instance_valid(VisualizationManager):
		colors = VisualizationManager.get_3ph_cable_colors(self, num_lines)
	else:
		colors = _fallback_colors(num_lines)

	var offset_start: float = -float(num_lines - 1) * 0.5

	# Draw each segment of the cable path
	for seg in range(points.size() - 1):
		var seg_a := points[seg]
		var seg_b := points[seg + 1]
		var dir  := (seg_b - seg_a).normalized()
		var perp := Vector2(-dir.y, dir.x)

		for i in num_lines:
			var offset := perp * (phase_spacing * (offset_start + float(i)))
			draw_line(seg_a + offset, seg_b + offset, colors[i], line_width)

	if get_meta("selected", false):
		for seg in range(points.size() - 1):
			draw_line(points[seg], points[seg + 1], Color(0.2, 0.8, 1.0, 0.4), line_width + 8.0)

## Fallback — reproduces pre-refactor NormalMode colors without VisualizationManager.
const _PHASE_COLORS_FALLBACK: Array = [
	Color(0.9, 0.2, 0.2),
	Color(0.9, 0.8, 0.1),
	Color(0.2, 0.4, 0.9),
	Color(0.1, 0.75, 0.15),
]
func _fallback_colors(num_lines: int) -> Array[Color]:
	var result: Array[Color] = []
	if _bridge == null or not _bridge.vis_enabled or sim_cable == null:
		for _i in num_lines:
			result.append(Color(0.4, 0.4, 0.4))
		return result
	var max_i: float = maxf(sim_cable.max_current_a, 0.001)
	var currents: Array = _bridge.vis_currents_a
	for i in num_lines:
		var load_f: float = clampf(float(currents[i]) / max_i if currents.size() > i else 0.0, 0.0, 1.0)
		var col: Color
		if _bridge.vis_overloaded and i < 3:
			col = Color(1.0, 0.1, 0.0)
		elif _bridge.vis_overheated:
			col = Color(1.0, 0.15, 0.0)
		else:
			col = _PHASE_COLORS_FALLBACK[i].lerp(Color(1.0, 0.4, 0.0), load_f)
		result.append(col)
	return result

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
	if source_bus == null:
		return
	if target is DistBoxNode and not target._initialized:
		target.setup_in(source_bus, model)
	elif target is ThreePhaseSwitchNode and not target._initialized:
		target.setup_in(source_bus, model)
	elif target is ThreePhaseFuseNode and not target._initialized:
		target.setup_in(source_bus, model)
	elif target is ThreePhaseTransformerNode and not target._initialized:
		target.setup_in(model)

func _try_register_consumer(dist_side: Node2D, consumer_side: Node2D) -> void:
	if not (dist_side is DistBoxNode and dist_side._initialized):
		return
	var ok: bool = DistBoxNode._is_registrable(consumer_side)
	if not ok:
		ok = (consumer_side is ThreePhaseOvenNode or
			  consumer_side is ThreePhaseSocketAppliance)
	if ok:
		dist_side.register_consumer(consumer_side)

func _pick_3ph_transformer_bus(tx: ThreePhaseTransformerNode) -> SimNode:
	if tx._transformer == null: return tx.get_primary_bus()
	var primary:   SimNode = tx.get_primary_bus()
	var secondary: SimNode = tx.get_secondary_bus()
	for elem in _model.elements:
		if elem is ThreePhaseCable or elem is Cable:
			if elem.node_a() == primary or elem.node_b() == primary:
				return secondary
	return primary

static func row(label: String, value, fmt: String = "") -> Dictionary:
	return ElementBridge.row(label, value, fmt)
