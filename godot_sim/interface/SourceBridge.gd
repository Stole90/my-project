## SourceBridge.gd
## Typed bridge za ThreePhaseVoltageSource — koristi se i za mono i za 3-fazni
## source node pošto je sim klasa ista (ThreePhaseVoltageSource).
##
## "Disabled" izvor = nestanak struje / planski isklop sa trafo strane.
## Implementacija: kada se disable-uje, napon se setuje na 0 za sve faze.
## Kada se enable-uje, naponi se vraćaju na originalne vrednosti.
##
## Nema "damaged" state — izvor se ili popravlja ili ne (no thermal degradation).
## repair() == enable() za izvore.
##
## Signali:
##   power_cut()       — izvor je upravo isključen
##   power_restored()  — izvor je upravo uključen

class_name SourceBridge
extends ElementBridge

signal power_cut()
signal power_restored()

## Snimljeni originalni naponi po fazama [rms, deg] za restore.
var _saved_voltages: Dictionary = {}

var vis_voltages_v:  Array = [0.0, 0.0, 0.0]   # [L1, L2, L3] RMS
var vis_currents_a:  Array = [0.0, 0.0, 0.0]   # [L1, L2, L3]
var vis_power_total_w: float = 0.0
var vis_v_pe:          float = 0.0
var vis_v_n:           float = 0.0

# ── Bind ──────────────────────────────────────────────────────────────────────

func bind(p_element: CircuitElement, p_model: CircuitModel) -> void:
	super.bind(p_element, p_model)
	_save_voltages()

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
	var src: ThreePhaseVoltageSource = element as ThreePhaseVoltageSource
	if src == null: return

	vis_enabled = src.enabled

	var bus: SimNode = src.bus_node()
	for ph_idx in range(3):
		var ph: int = [Phase.L1, Phase.L2, Phase.L3][ph_idx]
		vis_voltages_v[ph_idx] = bus.voltage_magnitude(ph)
		var ic: Complex = src.currents_by_phase.get(ph, null)
		vis_currents_a[ph_idx] = 0.0 if ic == null else ic.magnitude()

	vis_power_total_w = src.active_power_total()
	vis_v_pe          = bus.pe_voltage_magnitude()
	vis_v_n           = bus.neutral_displacement_v()

# ── Interakcije ───────────────────────────────────────────────────────────────

func interact_toggle() -> void:
	var src: ThreePhaseVoltageSource = element as ThreePhaseVoltageSource
	if src == null: return
	if src.enabled:
		_cut_power(src)
	else:
		_restore_power(src)
	if model != null: model.mark_dirty()

func interact_repair() -> void:
	var src: ThreePhaseVoltageSource = element as ThreePhaseVoltageSource
	if src == null: return
	if not src.enabled:
		_restore_power(src)
		if model != null: model.mark_dirty()

# ── Privatne metode ───────────────────────────────────────────────────────────

func _cut_power(src: ThreePhaseVoltageSource) -> void:
	_save_voltages()
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		src.set_phase_voltage(ph, 0.0, 0.0)
	src.enabled = false
	emit_signal("power_cut")

func _restore_power(src: ThreePhaseVoltageSource) -> void:
	src.enabled = true
	if _saved_voltages.is_empty():
		src.clear_overrides()
	else:
		for ph in [Phase.L1, Phase.L2, Phase.L3]:
			var saved: Array = _saved_voltages.get(ph, [src.voltage_ln_rms, 0.0])
			src.set_phase_voltage(ph, saved[0], saved[1])
	emit_signal("power_restored")

func _save_voltages() -> void:
	var src: ThreePhaseVoltageSource = element as ThreePhaseVoltageSource
	if src == null: return
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var p: Complex = src.voltage_phasor(ph)
		_saved_voltages[ph] = [p.magnitude(), rad_to_deg(atan2(p.im, p.re))]

# ── Info ──────────────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	var src: ThreePhaseVoltageSource = element as ThreePhaseVoltageSource
	if src == null: return {"name": "izvor", "type": "Izvor napajanja", "rows": []}

	var sname: String = src.element_name
	var rows: Array   = []

	rows.append(row("Stanje", "aktivan" if src.enabled else "ISKLJUČEN"))
	rows.append(row("Nom. L-N", src.voltage_ln_rms,              "%.0f V"))
	rows.append(row("Nom. L-L", src.voltage_ll_rms(),            "%.0f V"))
	rows.append(row("─── Naponi ───", ""))
	for ph_idx in range(3):
		rows.append(row("Napon %s" % ["L1","L2","L3"][ph_idx],
			vis_voltages_v[ph_idx], "%.2f V"))

	var n_lbl: String = "ok (%.1f V)" % vis_v_n if vis_v_n < 5.0 else "! (%.1f V)" % vis_v_n
	var pe_lbl: String
	if vis_v_pe < 10.0:    pe_lbl = "ok (%.1f V)" % vis_v_pe
	elif vis_v_pe < 50.0:  pe_lbl = "upozorenje (%.1f V)" % vis_v_pe
	else:                   pe_lbl = "OPASNO (%.1f V)" % vis_v_pe

	rows.append(row("Nulti prov.", n_lbl))
	rows.append(row("PE provodnik", pe_lbl))
	rows.append(row("─── Struje ───", ""))
	for ph_idx in range(3):
		rows.append(row("Struja %s" % ["L1","L2","L3"][ph_idx],
			vis_currents_a[ph_idx], "%.2f A"))
	rows.append(row("─── Snaga ───", ""))
	rows.append(row("Uk. aktivna", vis_power_total_w / 1000.0, "%.3f kW"))

	return {"name": sname, "type": "3-fazni izvor napajanja", "rows": rows}
