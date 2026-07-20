## NormalMode.gd
## Default visualization mode.
## Reproduces the original color logic that was previously embedded inside
## CableNode._draw() and ThreePhaseCableNode._draw(), so removing it from
## those files causes zero visible change when this mode is active.
##
## Single-phase cable coloring:
##   disabled  → dark gray
##   damaged   → very dark red
##   overload / overheat → bright red-orange
##   normal    → green → orange gradient by load %
##
## Three-phase cable coloring:
##   per-phase canonical colors (L1 red / L2 yellow / L3 blue / N green)
##   tinted toward orange by load fraction; full red on overload/overheat.

class_name NormalMode
extends VisualizationMode

func _init() -> void:
	mode_id      = &"normal"
	display_name = "Normalan prikaz"

# ── Single-phase cable ────────────────────────────────────────────────────────

func get_cable_color(cable_node: Node2D) -> Color:
	var bridge = cable_node.get("_bridge")

	if bridge == null:
		return Color(0.5, 0.5, 0.5)

	if not bridge.vis_enabled:
		return Color(0.4, 0.4, 0.4)

	var sim_cable = cable_node.get("sim_cable")
	if sim_cable != null and sim_cable.get("damaged") == true:
		return Color(0.25, 0.05, 0.05)

	if bridge.vis_overloaded or bridge.vis_overheated:
		return Color(1.0, 0.15, 0.0)

	var load_pct: float = safe_float(bridge, &"vis_loading_pct", 0.0)
	return Color(0.1, 0.9, 0.1).lerp(Color(1.0, 0.55, 0.0), clampf(load_pct / 100.0, 0.0, 1.0))

# ── Three-phase cable ─────────────────────────────────────────────────────────

## Canonical phase colors — same as the original hard-coded arrays.
const PHASE_COLORS: Array = [
	Color(0.9, 0.2, 0.2),   # L1
	Color(0.9, 0.8, 0.1),   # L2
	Color(0.2, 0.4, 0.9),   # L3
	Color(0.1, 0.75, 0.15), # N
]

func get_3ph_cable_colors(cable_node: Node2D, num_lines: int) -> Array[Color]:
	var result: Array[Color] = []
	var bridge = cable_node.get("_bridge")
	var sim_cable = cable_node.get("sim_cable")

	if bridge == null or not bridge.vis_enabled or sim_cable == null:
		for _i in num_lines:
			result.append(Color(0.4, 0.4, 0.4))
		return result

	var max_i: float      = maxf(safe_float(sim_cable, &"max_current_a", 16.0), 0.001)
	var currents: Array   = bridge.vis_currents_a
	var overloaded: bool  = bridge.vis_overloaded
	var overheated: bool  = bridge.vis_overheated

	for i in num_lines:
		var load_f: float = 0.0
		if currents.size() > i:
			load_f = clampf(float(currents[i]) / max_i, 0.0, 1.0)

		var col: Color
		if overloaded and i < 3:
			col = Color(1.0, 0.1, 0.0)
		elif overheated:
			col = Color(1.0, 0.15, 0.0)
		else:
			col = PHASE_COLORS[i].lerp(Color(1.0, 0.4, 0.0), load_f)
		result.append(col)

	return result
