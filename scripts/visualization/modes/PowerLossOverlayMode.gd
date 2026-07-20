## PowerLossOverlayMode.gd
## Overlay: cable color based on active power loss (I² × R, in watts).
##
## Data source:
##   current_a   — from bridge.vis_loading_pct × max_current (single-phase)
##                 or bridge.vis_currents_a (three-phase)
##   resistance  — sim_cable.resistance_per_m × sim_cable.length_m
##                 (or resistance_ohm if the solver caches total resistance)
##
## Color scale (power loss in watts):
##    0 W    → green   (negligible loss)
##   50 W    → yellow
##  200 W    → orange
##  500 W+   → red     (significant loss)
##
## The thresholds are configurable via exported variables so the operator
## can tune them for their grid scale without modifying code.

class_name PowerLossOverlayMode
extends VisualizationMode

## Watt thresholds for the four-stop gradient.
## Tune to match the typical cable ratings in your simulation.
var warn_w:   float = 50.0    # green → yellow
var limit_w:  float = 200.0   # yellow → orange
var severe_w: float = 500.0   # orange → red

func _init() -> void:
	mode_id      = &"power_loss"
	display_name = "Gubici snage (I²R)"

# ── Single-phase cable ────────────────────────────────────────────────────────

func get_cable_color(cable_node: Node2D) -> Color:
	var bridge    = cable_node.get("_bridge")
	var sim_cable = cable_node.get("sim_cable")

	if bridge == null or not bridge.vis_enabled:
		return Color(0.35, 0.35, 0.35)
	if sim_cable != null and sim_cable.get("damaged") == true:
		return Color(0.25, 0.05, 0.05)

	var loss_w: float = _single_phase_loss(bridge, sim_cable)
	return _loss_color(loss_w)

# ── Three-phase cable ─────────────────────────────────────────────────────────

func get_3ph_cable_colors(cable_node: Node2D, num_lines: int) -> Array[Color]:
	var result: Array[Color] = []
	var bridge    = cable_node.get("_bridge")
	var sim_cable = cable_node.get("sim_cable")

	if bridge == null or not bridge.vis_enabled or sim_cable == null:
		for _i in num_lines:
			result.append(Color(0.35, 0.35, 0.35))
		return result

	var _max_i: float  = maxf(safe_float(sim_cable, &"max_current_a", 16.0), 0.001)
	var currents: Array = bridge.vis_currents_a
	var r_total: float  = _total_resistance(sim_cable)

	for i in num_lines:
		if i >= 3:
			# Neutral: separate resistance possibly, shown lighter
			var i_n: float = float(currents[i]) if currents.size() > i else 0.0
			var r_n: float = _neutral_resistance(sim_cable)
			result.append(_loss_color(i_n * i_n * r_n))
		else:
			var i_ph: float = float(currents[i]) if currents.size() > i else 0.0
			result.append(_loss_color(i_ph * i_ph * r_total))

	return result

# ── Loss calculation ──────────────────────────────────────────────────────────

func _single_phase_loss(bridge: Object, sim_cable: Object) -> float:
	# Reconstruct current from loading_pct and max_current.
	var max_i: float   = safe_float(sim_cable, &"max_current", 16.0)
	if max_i <= 0.0:
		max_i = safe_float(sim_cable, &"max_current_a", 16.0)
	var load_pct: float = safe_float(bridge, &"vis_loading_pct", 0.0)
	var current_a: float = (load_pct / 100.0) * max_i

	# Prefer direct current from bridge if available.
	var direct_i = bridge.get(&"vis_current_mag")
	if direct_i != null and float(direct_i) > 0.0:
		current_a = float(direct_i)

	var r: float = _total_resistance(sim_cable)
	return current_a * current_a * r

func _total_resistance(sim_cable: Object) -> float:
	if sim_cable == null:
		return 0.0

	# Try cached total resistance first.
	var r_total = sim_cable.get(&"resistance_ohm")
	if r_total != null and float(r_total) > 0.0:
		return float(r_total)

	# Reconstruct: resistance_per_m × length_m
	var r_per_m: float = safe_float(sim_cable, &"resistance_per_m", 0.0)
	if r_per_m <= 0.0:
		# Derive from cross_mm2 and material resistivity
		var cross_mm2: float = safe_float(sim_cable, &"cross_mm2", 4.0)
		# copper ≈ 1.72e-8 Ω·m → r_per_m for 4 mm² ≈ 0.0043 Ω/m
		r_per_m = 1.72e-8 / maxf(cross_mm2 * 1e-6, 1e-9)
	var length_m: float = safe_float(sim_cable, &"length_m", 1.0)
	return r_per_m * length_m

func _neutral_resistance(sim_cable: Object) -> float:
	# ThreePhaseCable may have neutral_impedance_per_m (a Complex).
	var nipm = sim_cable.get(&"neutral_impedance_per_m")
	if nipm != null and nipm.has_method(&"real"):
		var r_n: float = float(nipm.call(&"real"))
		var length_m: float = safe_float(sim_cable, &"length_m", 1.0)
		if r_n > 0.0:
			return r_n * length_m
	# Fallback: same as phase conductor
	return _total_resistance(sim_cable)

# ── Color mapping ─────────────────────────────────────────────────────────────

func _loss_color(loss_w: float) -> Color:
	if loss_w <= 0.0:
		return Color(0.1, 0.9, 0.1)                                     # green — no loss
	elif loss_w <= warn_w:
		return Color(0.1, 0.9, 0.1).lerp(Color(1.0, 0.85, 0.0), loss_w / warn_w)
	elif loss_w <= limit_w:
		return Color(1.0, 0.85, 0.0).lerp(Color(1.0, 0.45, 0.0), (loss_w - warn_w) / (limit_w - warn_w))
	elif loss_w <= severe_w:
		return Color(1.0, 0.45, 0.0).lerp(Color(1.0, 0.05, 0.0), (loss_w - limit_w) / (severe_w - limit_w))
	else:
		return Color(1.0, 0.0, 0.0)                                     # red — severe loss
