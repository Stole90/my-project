## CurrentOverlayMode.gd
## Overlay: cable color based on current utilization (% of rated max current).
##
## Color scale:
##   0 %   → deep blue  (no load)
##  50 %   → green      (normal)
##  80 %   → yellow     (approaching limit)
## 100 %+  → red        (at/over limit)
##
## For three-phase cables the worst-loaded phase drives the legend color;
## each individual conductor is still colored by its own utilization so
## the operator can spot phase imbalance at a glance.

class_name CurrentOverlayMode
extends VisualizationMode

func _init() -> void:
	mode_id      = &"current"
	display_name = "Pregled struje"

# ── Single-phase cable ────────────────────────────────────────────────────────

func get_cable_color(cable_node: Node2D) -> Color:
	var bridge = cable_node.get("_bridge")
	if bridge == null:
		return Color(0.3, 0.3, 0.3)

	if not bridge.vis_enabled:
		return Color(0.35, 0.35, 0.35)

	var sim_cable = cable_node.get("sim_cable")
	if sim_cable != null and sim_cable.get("damaged") == true:
		return Color(0.25, 0.05, 0.05)

	var load_pct: float = safe_float(bridge, &"vis_loading_pct", 0.0)
	return _utilization_color(load_pct / 100.0)

# ── Three-phase cable ─────────────────────────────────────────────────────────

func get_3ph_cable_colors(cable_node: Node2D, num_lines: int) -> Array[Color]:
	var result: Array[Color] = []
	var bridge = cable_node.get("_bridge")
	var sim_cable = cable_node.get("sim_cable")

	if bridge == null or not bridge.vis_enabled or sim_cable == null:
		for _i in num_lines:
			result.append(Color(0.35, 0.35, 0.35))
		return result

	var max_i: float = maxf(safe_float(sim_cable, &"max_current_a", 16.0), 0.001)
	var currents: Array = bridge.vis_currents_a

	for i in num_lines:
		var current_a: float = float(currents[i]) if currents.size() > i else 0.0
		var t: float = clampf(current_a / max_i, 0.0, 1.0)
		# Neutral (index 3) shown in gray-white when present; utilization coloring applies to L1-L3.
		if i >= 3:
			result.append(Color(0.6, 0.6, 0.6).lerp(Color(1.0, 0.4, 0.0), t))
		else:
			result.append(_utilization_color(t))

	return result

# ── Color mapping ─────────────────────────────────────────────────────────────

## Maps utilization fraction [0..1] to a color.
## Uses a four-stop gradient for maximum readability:
##   0.00 → deep blue
##   0.50 → green
##   0.80 → yellow
##   1.00 → red  (clamps above 1.0 to pure red)
static func _utilization_color(t: float) -> Color:
	if t <= 0.0:
		return Color(0.1, 0.3, 0.9)      # deep blue — idle
	elif t <= 0.5:
		return Color(0.1, 0.3, 0.9).lerp(Color(0.1, 0.9, 0.1), t / 0.5)
	elif t <= 0.8:
		return Color(0.1, 0.9, 0.1).lerp(Color(1.0, 0.85, 0.0), (t - 0.5) / 0.3)
	elif t <= 1.0:
		return Color(1.0, 0.85, 0.0).lerp(Color(1.0, 0.05, 0.0), (t - 0.8) / 0.2)
	else:
		return Color(1.0, 0.0, 0.0)      # over limit
