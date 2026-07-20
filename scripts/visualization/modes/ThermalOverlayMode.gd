## ThermalOverlayMode.gd
## Overlay: cable color based on temperature.
##
## Data sources (in priority order, most specific first):
##   1. sim_cable.temperature_c          — direct thermal value if solver tracks it
##   2. bridge.vis_thermal_pct           — 0-100 % of max temperature (FuseBridge exposes this)
##   3. bridge.vis_overheated            — boolean fallback
##
## Color scale (°C, assuming 90 °C cable rating):
##   < 25 °C  → blue-gray (ambient / cold)
##    50 °C   → green
##    75 °C   → yellow
##    90 °C   → orange
##   ≥100 °C  → red (over limit)
##
## For three-phase cables the max-temp phase drives each wire's color
## because the cable shares a common thermal mass in practice.

class_name ThermalOverlayMode
extends VisualizationMode

## Assumed maximum safe operating temperature for cables (°C).
## Cables with a temperature_c property above this are shown fully red.
const MAX_CABLE_TEMP_C: float = 90.0
const AMBIENT_TEMP_C:   float = 25.0

func _init() -> void:
	mode_id      = &"thermal"
	display_name = "Termalni pregled"

# ── Single-phase cable ────────────────────────────────────────────────────────

func get_cable_color(cable_node: Node2D) -> Color:
	var bridge    = cable_node.get("_bridge")
	var sim_cable = cable_node.get("sim_cable")

	if bridge == null:
		return Color(0.3, 0.3, 0.3)
	if not bridge.vis_enabled:
		return Color(0.35, 0.35, 0.35)
	if sim_cable != null and sim_cable.get("damaged") == true:
		return Color(0.25, 0.05, 0.05)

	return _thermal_color(bridge, sim_cable)

# ── Three-phase cable ─────────────────────────────────────────────────────────

func get_3ph_cable_colors(cable_node: Node2D, num_lines: int) -> Array[Color]:
	var result: Array[Color] = []
	var bridge    = cable_node.get("_bridge")
	var sim_cable = cable_node.get("sim_cable")

	if bridge == null or not bridge.vis_enabled or sim_cable == null:
		for _i in num_lines:
			result.append(Color(0.35, 0.35, 0.35))
		return result

	# For 3-phase cables use a single thermal color for all wires
	# (they share a jacket and thermal model).
	var col: Color = _thermal_color(bridge, sim_cable)
	for _i in num_lines:
		result.append(col)

	return result

# ── Thermal color helper ──────────────────────────────────────────────────────

func _thermal_color(bridge: Object, sim_cable: Object) -> Color:
	# Priority 1: direct temperature value
	if sim_cable != null:
		var temp_val = sim_cable.get(&"temperature_c")
		if temp_val != null:
			return _temp_to_color(float(temp_val))

	# Priority 2: thermal percentage from bridge (0-100)
	if bridge != null:
		var pct_val = bridge.get(&"vis_thermal_pct")
		if pct_val != null:
			var pct: float = clampf(float(pct_val), 0.0, 100.0)
			# Convert % to equivalent temperature for consistent color scale
			var equiv_temp: float = AMBIENT_TEMP_C + (pct / 100.0) * (MAX_CABLE_TEMP_C - AMBIENT_TEMP_C)
			return _temp_to_color(equiv_temp)

	# Priority 3: boolean overheated flag
	if bridge != null and bridge.get(&"vis_overheated") == true:
		return Color(1.0, 0.15, 0.0)

	# No thermal data — show as ambient (blue-gray)
	return Color(0.45, 0.55, 0.75)

## Maps a temperature in °C to a color on the thermal scale.
static func _temp_to_color(temp_c: float) -> Color:
	if temp_c <= AMBIENT_TEMP_C:
		return Color(0.45, 0.55, 0.75)                          # cool / ambient

	var t: float = clampf((temp_c - AMBIENT_TEMP_C) / (MAX_CABLE_TEMP_C - AMBIENT_TEMP_C), 0.0, 1.1)
	return heat_gradient(t)
