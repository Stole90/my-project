## TransformerBridge.gd
## Typed bridge za Transformer element.
## Koristi se u: TransformerNode.gd

class_name TransformerBridge
extends ElementBridge

var vis_load_pct:  float  = 0.0
var vis_temp_c:    float  = 0.0
var vis_losses_w:  float  = 0.0
var vis_losses_kw: float  = 0.0
var vis_op_state:  String = "normal"
var vis_prim_v:    float  = 0.0
var vis_sec_v:     float  = 0.0

func _sync_visual_state() -> void:
	super._sync_visual_state()
	var t: Transformer = element as Transformer
	if t == null: return

	vis_enabled    = t.enabled
	vis_damaged    = t.damaged
	vis_overloaded = t.is_overloaded
	vis_overheated = t.is_overheating
	vis_load_pct   = t.load_percent
	vis_temp_c     = t.temperature_c
	vis_losses_w   = t.losses_kw * 1000.0
	vis_losses_kw  = t.losses_kw
	vis_op_state   = t.operational_state()
	vis_prim_v     = t.primary_voltage_actual
	vis_sec_v      = t.secondary_voltage_actual
	vis_current_a  = t.primary_current.magnitude() if t.primary_current != null else 0.0
	vis_state      = vis_op_state

func get_info() -> Dictionary:
	var t: Transformer = element as Transformer
	if t == null: return { "name": "transformator", "type": "Transformator", "rows": [] }

	var prim_i: float = t.primary_current.magnitude()   if t.primary_current   != null else 0.0
	var sec_i:  float = t.secondary_current.magnitude() if t.secondary_current != null else 0.0

	var rows: Array = [
		row("Snaga",       t.data.rated_power_kva,             "%.0f kVA"),
		row("HV napon",    vis_prim_v,                         "%.1f V"),
		row("LV napon",    vis_sec_v,                          "%.1f V"),
		row("HV struja",   prim_i,                             "%.2f A"),
		row("LV struja",   sec_i,                              "%.2f A"),
		row("Ul. snaga",   t.input_power_kw * 1000.0,          "%.0f W"),
		row("Izl. snaga",  t.output_power_kw * 1000.0,         "%.0f W"),
		row("Gubici",      vis_losses_w,                       "%.1f W"),
		row("Efikasnost",  t.efficiency_actual * 100.0,        "%.1f %%"),
		row("Opterećenje", vis_load_pct,                       "%.0f %%"),
		row("Reg. nap.",   t.voltage_regulation_percent(),     "%.2f %%"),
		row("Temperatura", vis_temp_c,                         "%.1f °C"),
		row("Tap",         t.data.tap_position,                "%d"),
		row("Stanje",      vis_op_state),
	]

	# Per-fazne struje — dostupne kad se transformator koristi u 3-faznom solveru.
	# currents_by_phase se puni u update_state_3ph(); u monofaznom modu su nule.
	rows.append(row("─── Faze ───", ""))
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var lbl: String = ["L1", "L2", "L3"][ph]
		var i_ph: Complex = t.currents_by_phase.get(ph, null)
		rows.append(row("Struja %s" % lbl, i_ph.magnitude() if i_ph != null else 0.0, "%.2f A"))

	return {
		"name":    t.element_name,
		"type":    "Transformator %.0f/%.0f V" % [t.data.primary_voltage, t.data.secondary_voltage],
		"enabled": t.enabled,
		"rows":    rows,
	}

func interact_toggle() -> void:
	var t: Transformer = element as Transformer
	if t == null: return
	if t.enabled: t.trip()
	else: t.reclose()
	if model != null: model.mark_dirty()

func interact_repair() -> void:
	var t: Transformer = element as Transformer
	if t == null: return
	t.repair()
	if model != null: model.mark_dirty()
