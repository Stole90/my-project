## ThreePhaseCableBridge.gd
## Typed bridge za ThreePhaseCable element.
## Koristi se u: ThreePhaseCableNode.gd
##
## Čita: currents (L1/L2/L3/N), temperature, overload, overheat,
##       damaged, loading%, resistance, dissipated power.

class_name ThreePhaseCableBridge
extends ElementBridge

# ── Vizuelni state ────────────────────────────────────────────────────────────

var vis_currents_a:    Array = [0.0, 0.0, 0.0, 0.0]  # [L1, L2, L3, N]
var vis_loading_pct:   float = 0.0
var vis_temperature_c: float = 25.0
var vis_resistance:    float = 0.0
var vis_dissipated_w:  float = 0.0

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
	super._sync_visual_state()
	var c: ThreePhaseCable = element as ThreePhaseCable
	if c == null:
		return

	vis_damaged    = c.damaged
	vis_overloaded = c.is_overloaded
	vis_overheated = c.is_overheated

	vis_temperature_c = c.temperature_c
	vis_resistance    = c.phase_impedance().re
	vis_dissipated_w  = c.dissipated_power()

	# Struje po fazama
	for i in range(3):
		var ph: int = [Phase.L1, Phase.L2, Phase.L3][i]
		vis_currents_a[i] = c.current_magnitude(ph)
	vis_currents_a[3] = c.current_magnitude(Phase.NEUTRAL) if c.has_neutral() else 0.0
	vis_current_a = vis_currents_a[0]

	# Koristimo max od strujnog i termičkog opterećenja
	var thermal_pct: float = c.thermal_loading() * 100.0
	vis_loading_pct = max(c.loading() * 100.0, thermal_pct)

# ── Info za InfoPanel ─────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	var c: ThreePhaseCable = element as ThreePhaseCable
	if c == null:
		return { "name": "3ph_kabl", "type": "3-fazni kabl", "rows": [] }

	var state_parts: Array = []
	if c.damaged:       state_parts.append("oštećen")
	if c.is_overheated: state_parts.append("pregrejan")
	if c.is_overloaded: state_parts.append("preopterećen")
	if state_parts.is_empty(): state_parts.append("ok")

	var rows: Array = [
		row("Dužina",       c.length_m,           "%.1f m"),
		row("Presek",       c.cross_mm2,           "%.1f mm²"),
		row("Materijal",    c.material),
		row("Maks. struja", c.max_current_a,       "%.0f A"),
		row("Opterećenje",  vis_loading_pct,       "%.0f %%"),
		row("Struja L1",    vis_currents_a[0],     "%.2f A"),
		row("Struja L2",    vis_currents_a[1],     "%.2f A"),
		row("Struja L3",    vis_currents_a[2],     "%.2f A"),
	]

	if c.has_neutral():
		rows.append(row("Struja N",  vis_currents_a[3],            "%.2f A"))
		rows.append(row("Presek N",  c.neutral_impedance_per_m.re, "%.4f Ω/m"))

	rows.append_array([
		row("Otpor (T)",   vis_resistance,        "%.4f Ω"),
		row("Disipacija",  vis_dissipated_w,      "%.2f W"),
		row("Temperatura", vis_temperature_c,     "%.1f °C"),
		row("Ambijent",    c.ambient_c,           "%.1f °C"),
		row("Limit izol.", c.insulation_max_c,    "%.0f °C"),
		row("Stanje",      ", ".join(state_parts)),
	])

	return {
		"name":    c.element_name,
		"type":    "3-fazni kabl" + (" (N)" if c.has_neutral() else ""),
		"damaged": c.damaged,
		"rows":    rows,
	}

# ── Interakcije ───────────────────────────────────────────────────────────────

func interact_repair() -> void:
	var c: ThreePhaseCable = element as ThreePhaseCable
	if c == null: return
	c.repair()
	if model != null: model.mark_dirty()

func interact_toggle() -> void:
	var c: ThreePhaseCable = element as ThreePhaseCable
	if c == null: return
	if c.enabled: c.disconnect_cable()
	else: c.connect_cable()
	if model != null: model.mark_dirty()
