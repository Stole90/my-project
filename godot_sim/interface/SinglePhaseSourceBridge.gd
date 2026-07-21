## SinglePhaseSourceBridge.gd
## Bridge for SinglePhaseVoltageSource — mirrors SourceBridge for 3-phase sources.
##
## Signals:
##   power_cut()       — source just disabled
##   power_restored()  — source just re-enabled

class_name SinglePhaseSourceBridge
extends ElementBridge

signal power_cut()
signal power_restored()

var _saved_rms: float = 0.0
var _saved_deg: float = 0.0

# Visualisation state (read by the scene node for _draw / HUD)

var vis_power_w:    float = 0.0
var vis_v_pe:       float = 0.0

# ── Bind ──────────────────────────────────────────────────────────────────────

func bind(p_element: CircuitElement, p_model: CircuitModel) -> void:
	super.bind(p_element, p_model)
	_save_voltage()

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
	var src: SinglePhaseVoltageSource = element as SinglePhaseVoltageSource
	if src == null:
		return
	vis_enabled   = src.enabled
	var bus: SimNode = src.bus_node()
	vis_voltage_v = bus.voltage_magnitude(Phase.L1)
	var ic: Complex = src.currents_by_phase.get(Phase.L1, null)
	vis_current_a = 0.0 if ic == null else ic.magnitude()
	vis_power_w   = src.active_power()
	vis_v_pe      = bus.pe_voltage_magnitude()

# ── Interactions ──────────────────────────────────────────────────────────────

func interact_toggle() -> void:
	var src: SinglePhaseVoltageSource = element as SinglePhaseVoltageSource
	if src == null:
		return
	if src.enabled:
		_cut_power(src)
	else:
		_restore_power(src)
	if model != null:
		model.mark_dirty()

func interact_repair() -> void:
	var src: SinglePhaseVoltageSource = element as SinglePhaseVoltageSource
	if src == null:
		return
	if not src.enabled:
		_restore_power(src)
		if model != null:
			model.mark_dirty()

# ── Private ───────────────────────────────────────────────────────────────────

func _cut_power(src: SinglePhaseVoltageSource) -> void:
	_save_voltage()
	src.set_voltage(0.0, 0.0)
	src.enabled = false
	emit_signal("power_cut")

func _restore_power(src: SinglePhaseVoltageSource) -> void:
	src.enabled = true
	src.set_voltage(_saved_rms, _saved_deg)
	emit_signal("power_restored")

func _save_voltage() -> void:
	var src: SinglePhaseVoltageSource = element as SinglePhaseVoltageSource
	if src == null:
		return
	_saved_rms = src.voltage_rms
	_saved_deg = src.phase_deg

# ── Info ──────────────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	var src: SinglePhaseVoltageSource = element as SinglePhaseVoltageSource
	if src == null:
		return {"name": "source", "type": "1-phase source", "rows": []}
	var rows: Array = []
	rows.append(row("Status",   "active" if src.enabled else "OFF"))
	rows.append(row("Voltage",  vis_voltage_v,  "%.2f V"))
	rows.append(row("Current",  vis_current_a,  "%.2f A"))
	rows.append(row("Power",    vis_power_w,    "%.1f W"))
	rows.append(row("PE",
		"ok (%.1fV)" % vis_v_pe if vis_v_pe < 10.0 else "! (%.1fV)" % vis_v_pe))
	return {"name": src.element_name, "type": "Single-phase AC source", "rows": rows}
