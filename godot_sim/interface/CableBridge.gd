## CableBridge.gd
## Typed bridge za Cable element.
##
## Čita: current, temperature, overload, overheat, damaged, loading%.
## Koristi se u: CableNode.gd
##
## Upotreba:
##   _bridge = CableBridge.new()
##   add_child(_bridge)
##   _bridge.bind(sim_cable, model)

class_name CableBridge
extends ElementBridge

# ── Dodatni vizuelni state (specifičan za kabl) ───────────────────────────────

var vis_temperature_c: float = 25.0
var vis_loading_pct:   float = 0.0
var vis_resistance:    float = 0.0
var vis_dissipated_w:  float = 0.0

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
	super._sync_visual_state()
	var c: Cable = element as Cable
	if c == null:
		return

	vis_damaged       = c.damaged
	vis_overloaded    = c.is_overloaded
	vis_overheated    = c.is_overheated
	vis_temperature_c = c.temperature_c
	vis_loading_pct   = c.loading_percent()
	vis_resistance    = c.resistance()
	vis_dissipated_w  = c.dissipated_power()
	vis_current_a     = c.current.magnitude() if c.current != null else 0.0

	# Koristimo max od strujnog i termičkog opterećenja
	var thermal_pct: float = c.thermal_loading() * 100.0
	vis_loading_pct = max(vis_loading_pct, thermal_pct)

# ── Info za InfoPanel ─────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	var c: Cable = element as Cable
	if c == null:
		return { "name": "kabl", "type": "Kabl", "rows": [] }

	var state_parts: Array = []
	if c.damaged:       state_parts.append("oštećen")
	if c.is_overheated: state_parts.append("pregrejan")
	if c.is_overloaded: state_parts.append("preopterećen")
	if state_parts.is_empty(): state_parts.append("ok")

	var rows: Array = [
		row("Dužina",       c.length_m,          "%.1f m"),
		row("Presek",       c.cross_mm2,          "%.1f mm²"),
		row("Materijal",    c.material),
		row("Maks. struja", c.max_current,        "%.0f A"),
		row("Struja",       vis_current_a,        "%.2f A"),
		row("Opterećenje",  c.loading_percent(),  "%.0f %%"),
		row("Otpor (T)",    vis_resistance,       "%.4f Ω"),
		row("Otpor (20°)",  c.resistance_cold(),  "%.4f Ω"),
		row("Disipacija",   vis_dissipated_w,     "%.2f W"),
		row("Temperatura",  vis_temperature_c,    "%.1f °C"),
		row("Ambijent",     c.ambient_c,          "%.1f °C"),
		row("Limit izol.",  c.insulation_max_c,   "%.0f °C"),
		row("Stanje",       ", ".join(state_parts)),
	]

	if c.rating_result != null:
		rows.append(row("Iz base",         c.rating_result.iz_base,        "%.1f A"))
		rows.append(row("K1 (temperatura)", c.rating_result.k1_temperature, "%.3f"))
		rows.append(row("K2 (grupisanje)",  c.rating_result.k2_grouping,    "%.3f"))
		rows.append(row("K3 (tlo)",         c.rating_result.k3_soil,        "%.3f"))
		rows.append(row("K4 (harmonici)",   c.rating_result.k4_harmonic,    "%.3f"))
		rows.append(row("K5 (instalacija)", c.rating_result.k5_installation,"%.3f"))
		rows.append(row("Iz final",         c.rating_result.iz_final,       "%.1f A"))
		rows.append(row("Iskorišćenost",    c.utilization(vis_current_a, c.max_current) * 100.0, "%.0f %%"))

	return {
		"name":    c.element_name,
		"type":    "Kabl",
		"damaged": c.damaged,
		"rows":    rows
	}

# ── Specifične interakcije ─────────────────────────────────────────────────────

func interact_repair() -> void:
	var c: Cable = element as Cable
	if c == null: return
	c.repair()
	if model != null: model.mark_dirty()

func interact_toggle() -> void:
	var c: Cable = element as Cable
	if c == null: return
	if c.enabled: c.disconnect_cable()
	else: c.connect_cable()
	if model != null: model.mark_dirty()
