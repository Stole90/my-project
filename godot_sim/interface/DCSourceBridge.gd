## DCSourceBridge.gd
## Bridge for DCVoltageSource.
## Provides the same enable/disable/info interface as SourceBridge.
##
## Signals:
##   power_cut()
##   power_restored()

class_name DCSourceBridge
extends ElementBridge

signal power_cut()
signal power_restored()

var _saved_voltage_v: float = 0.0

var vis_power_w:   float = 0.0

# ── Bind ──────────────────────────────────────────────────────────────────────

func bind(p_element: CircuitElement, p_model: CircuitModel) -> void:
	super.bind(p_element, p_model)
	_save_voltage()

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
	var src: DCVoltageSource = element as DCVoltageSource
	if src == null:
		return
	vis_enabled   = src.enabled
	vis_voltage_v = src.bus_node().voltage_magnitude(Phase.L1)
	var ic: Complex = src.currents_by_phase.get(Phase.L1, null)
	vis_current_a = 0.0 if ic == null else ic.magnitude()
	vis_power_w   = src.active_power()

# ── Interactions ──────────────────────────────────────────────────────────────

func interact_toggle() -> void:
	var src: DCVoltageSource = element as DCVoltageSource
	if src == null:
		return
	if src.enabled:
		_cut_power(src)
	else:
		_restore_power(src)
	if model != null:
		model.mark_dirty()

func interact_repair() -> void:
	var src: DCVoltageSource = element as DCVoltageSource
	if src == null:
		return
	if not src.enabled:
		_restore_power(src)
		if model != null:
			model.mark_dirty()

# ── Private ───────────────────────────────────────────────────────────────────

func _cut_power(src: DCVoltageSource) -> void:
	_save_voltage()
	src.set_voltage(0.0)
	src.enabled = false
	emit_signal("power_cut")

func _restore_power(src: DCVoltageSource) -> void:
	src.enabled = true
	src.set_voltage(_saved_voltage_v)
	emit_signal("power_restored")

func _save_voltage() -> void:
	var src: DCVoltageSource = element as DCVoltageSource
	if src == null:
		return
	_saved_voltage_v = src.voltage_v

# ── Info ──────────────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	var src: DCVoltageSource = element as DCVoltageSource
	if src == null:
		return {"name": "dc_source", "type": "DC source", "rows": []}
	var rows: Array = []
	rows.append(row("Status",   "active" if src.enabled else "OFF"))
	rows.append(row("Voltage",  vis_voltage_v, "%.2f V"))
	rows.append(row("Current",  vis_current_a, "%.2f A"))
	rows.append(row("Power",    vis_power_w,   "%.2f W"))
	return {"name": src.element_name, "type": "DC Voltage Source", "rows": rows}
