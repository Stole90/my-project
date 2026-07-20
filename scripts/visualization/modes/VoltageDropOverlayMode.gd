## VoltageDropOverlayMode.gd
## Overlay: cable color based on voltage deviation at the load end.
##
## Data source: sim_cable.node_b() (or node_a — whichever is the load side)
## → SimNode.voltage_magnitude(phase) compared to SimConstants.NOMINAL_V.
##
## Color scale (voltage drop as % of nominal):
##    0 %   → green  (no drop)
##    3 %   → yellow (IEC 60038 residential warning threshold)
##    5 %   → orange (at standard limit)
##   ≥10 %  → red    (severe drop)
##
## For three-phase cables the worst-phase voltage drop drives all wire colors.
## If voltage data is unavailable (bridge not yet solved), shows neutral gray.

class_name VoltageDropOverlayMode
extends VisualizationMode

## IEC 60038 / EN 50160 nominal voltage (V, phase-to-neutral).
## Falls back to SimConstants.NOMINAL_V at runtime if available.
const FALLBACK_NOMINAL_V: float = 230.0

func _init() -> void:
	mode_id      = &"voltage_drop"
	display_name = "Pad napona"

# ── Single-phase cable ────────────────────────────────────────────────────────

func get_cable_color(cable_node: Node2D) -> Color:
	var bridge    = cable_node.get("_bridge")
	var sim_cable = cable_node.get("sim_cable")

	if bridge == null or not bridge.vis_enabled:
		return Color(0.35, 0.35, 0.35)
	if sim_cable != null and sim_cable.get("damaged") == true:
		return Color(0.25, 0.05, 0.05)

	var drop_pu: float = _single_phase_drop(sim_cable)
	if drop_pu < 0.0:
		return Color(0.5, 0.5, 0.5)  # no voltage data yet

	return _drop_color(drop_pu)

# ── Three-phase cable ─────────────────────────────────────────────────────────

func get_3ph_cable_colors(cable_node: Node2D, num_lines: int) -> Array[Color]:
	var result: Array[Color] = []
	var bridge    = cable_node.get("_bridge")
	var sim_cable = cable_node.get("sim_cable")

	if bridge == null or not bridge.vis_enabled or sim_cable == null:
		for _i in num_lines:
			result.append(Color(0.35, 0.35, 0.35))
		return result

	var worst_drop: float = _three_phase_worst_drop(sim_cable)
	var col: Color
	if worst_drop < 0.0:
		col = Color(0.5, 0.5, 0.5)
	else:
		col = _drop_color(worst_drop)

	for _i in num_lines:
		result.append(col)

	return result

# ── Voltage drop calculation ──────────────────────────────────────────────────

## Returns voltage drop as per-unit (0.0 = no drop, 1.0 = 100 % drop),
## or -1.0 if data is unavailable.
func _single_phase_drop(sim_cable: Object) -> float:
	if sim_cable == null:
		return -1.0

	var bus_a = _get_sim_bus(sim_cable, &"node_a")
	var bus_b = _get_sim_bus(sim_cable, &"node_b")
	if bus_a == null or bus_b == null:
		return -1.0

	# Assigned phase — default L1 (= 0 in Phase enum)
	var ph: int = 0
	var ap = sim_cable.get(&"assigned_phase")
	if ap != null:
		ph = int(ap)

	var v_nom: float = _nominal_v()
	var v_a: float   = _bus_voltage(bus_a, ph)
	var v_b: float   = _bus_voltage(bus_b, ph)
	if v_a <= 0.0 and v_b <= 0.0:
		return -1.0

	# Drop = difference between the higher-voltage end and lower-voltage end.
	var v_drop: float = absf(v_a - v_b)
	return clampf(v_drop / maxf(v_nom, 1.0), 0.0, 1.0)

## Returns the worst (highest) per-unit voltage drop across all three phases,
## or -1.0 if no voltage data is available.
func _three_phase_worst_drop(sim_cable: Object) -> float:
	if sim_cable == null:
		return -1.0

	var bus_a = _get_sim_bus(sim_cable, &"node_a")
	var bus_b = _get_sim_bus(sim_cable, &"node_b")
	if bus_a == null or bus_b == null:
		return -1.0

	var v_nom: float = _nominal_v()
	var worst: float = -1.0

	for ph in [0, 1, 2]:  # L1, L2, L3
		var v_a: float = _bus_voltage(bus_a, ph)
		var v_b: float = _bus_voltage(bus_b, ph)
		if v_a <= 0.0 and v_b <= 0.0:
			continue
		var drop_pu: float = clampf(absf(v_a - v_b) / maxf(v_nom, 1.0), 0.0, 1.0)
		if drop_pu > worst:
			worst = drop_pu

	return worst

# ── SimNode helpers ───────────────────────────────────────────────────────────

## Safely call node_a() or node_b() on a sim cable element.
static func _get_sim_bus(sim_cable: Object, method: StringName) -> Object:
	if sim_cable == null:
		return null
	if sim_cable.has_method(method):
		return sim_cable.call(method)
	return null

## Safely read voltage_magnitude from a SimNode for a given phase index.
static func _bus_voltage(bus: Object, phase: int) -> float:
	if bus == null:
		return 0.0
	if bus.has_method(&"voltage_magnitude"):
		return float(bus.call(&"voltage_magnitude", phase))
	return 0.0

static func _nominal_v() -> float:
	if ClassDB.class_exists("SimConstants"):
		var v = ClassDB.instantiate("SimConstants")
		if v != null and v.get("NOMINAL_V") != null:
			return float(v.NOMINAL_V)
	# Fallback — SimConstants is a static class, try direct access
	# (works if SimConstants is an autoload or global class with const).
	return FALLBACK_NOMINAL_V

# ── Color mapping ─────────────────────────────────────────────────────────────

## Maps voltage drop per-unit to a color.
## Thresholds: 3 % warn, 5 % limit, 10 % severe.
static func _drop_color(drop_pu: float) -> Color:
	if drop_pu <= 0.0:
		return Color(0.1, 0.9, 0.1)                                # green — no drop
	elif drop_pu <= 0.03:
		return Color(0.1, 0.9, 0.1).lerp(Color(1.0, 0.85, 0.0), drop_pu / 0.03)
	elif drop_pu <= 0.05:
		return Color(1.0, 0.85, 0.0).lerp(Color(1.0, 0.45, 0.0), (drop_pu - 0.03) / 0.02)
	elif drop_pu <= 0.10:
		return Color(1.0, 0.45, 0.0).lerp(Color(1.0, 0.05, 0.0), (drop_pu - 0.05) / 0.05)
	else:
		return Color(1.0, 0.0, 0.0)                                # red — severe
