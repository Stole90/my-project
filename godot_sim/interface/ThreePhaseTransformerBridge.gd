## ThreePhaseTransformerBridge.gd
## Typed bridge za ThreePhaseTransformer element.
## Koristi se u: ThreePhaseTransformerNode.gd

class_name ThreePhaseTransformerBridge
extends ElementBridge

var vis_load_pct:  float  = 0.0
var vis_losses_kw: float  = 0.0
var vis_losses_w:  float  = 0.0
var vis_temp_c:    float  = 0.0
var vis_op_state:  String = "normal"
var vis_prim_v:    float  = 0.0
var vis_sec_v:     float  = 0.0

func _sync_visual_state() -> void:
	super._sync_visual_state()
	var t: ThreePhaseTransformer = element as ThreePhaseTransformer
	if t == null: return

	vis_overloaded = t.is_overloaded
	vis_overheated = t.is_overheating
	vis_damaged    = t.damaged
	vis_enabled    = t.enabled
	vis_load_pct   = t.load_percent
	vis_losses_kw  = t.losses_kw
	vis_losses_w   = t.losses_kw * 1000.0
	vis_temp_c     = t.temperature_c
	vis_op_state   = t.operational_state()
	vis_prim_v     = t.primary_voltage_actual
	vis_sec_v      = t.secondary_voltage_actual
	vis_current_a  = t.current.magnitude() if t.current != null else 0.0
	vis_state      = vis_op_state

func get_info() -> Dictionary:
	var t: ThreePhaseTransformer = element as ThreePhaseTransformer
	if t == null: return { "name": "3-fazni trafo", "type": "3-fazni transformator", "rows": [] }

	var np: SimNode = t.node_primary()
	var ns: SimNode = t.node_secondary()

	var rows: Array = [
		row("Vrsta",        t.vector_group),
		row("Snaga",        t.data.rated_power_kva,             "%.0f kVA"),
		row("Opterećenje",  vis_load_pct,                       "%.1f %%"),
		row("Ul. snaga",    t.input_power_kw,                   "%.3f kW"),
		row("Izl. snaga",   t.output_power_kw,                  "%.3f kW"),
		row("Gubici",       vis_losses_kw,                      "%.3f kW"),
		row("Efikasnost",   t.efficiency_actual * 100.0,        "%.1f %%"),
		row("Temperatura",  vis_temp_c,                         "%.1f °C"),
		row("Tap",          t.data.tap_position,                "%d"),
		row("Stanje",       vis_op_state),
	]

	rows.append(row("─── HV ───", ""))
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var lbl: String = ["L1", "L2", "L3"][ph]
		rows.append(row("Napon %s"  % lbl, np.voltage_magnitude(ph) if np else 0.0, "%.0f V"))
		rows.append(row("Struja %s" % lbl, t.primary_currents.get(ph, null).magnitude() if t.primary_currents.get(ph, null) != null else 0.0, "%.2f A"))

	rows.append(row("─── LV ───", ""))
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var lbl: String = ["L1", "L2", "L3"][ph]
		rows.append(row("Napon %s"  % lbl, ns.voltage_magnitude(ph) if ns else 0.0,  "%.1f V"))
		rows.append(row("Struja %s" % lbl, t.secondary_current_magnitude(ph),         "%.2f A"))
		rows.append(row("Reg. %s"   % lbl, t.voltage_regulation_percent(ph),          "%.2f %%"))

	return {
		"name":    t.element_name,
		"type":    "3-fazni transformator %s %.0f/%.0f V" % [t.vector_group, t.data.primary_voltage, t.data.secondary_voltage],
		"enabled": t.enabled,
		"rows":    rows,
	}

func interact_toggle() -> void:
	var t: ThreePhaseTransformer = element as ThreePhaseTransformer
	if t == null: return
	if t.enabled: t.trip()
	else: t.reclose()
	if model != null: model.mark_dirty()

func interact_repair() -> void:
	var t: ThreePhaseTransformer = element as ThreePhaseTransformer
	if t == null: return
	t.repair()
	if model != null: model.mark_dirty()
