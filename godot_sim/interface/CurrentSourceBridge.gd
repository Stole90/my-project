## CurrentSourceBridge.gd
## Bridge for ACCurrentSource and DCCurrentSource.
## Supports toggling the source on/off by zeroing the injected current.
##
## Signals:
##   power_cut()
##   power_restored()

class_name CurrentSourceBridge
extends ElementBridge

signal power_cut()
signal power_restored()

var _saved_phasor: Complex = null

var vis_power_w:   float = 0.0

# ── Bind ──────────────────────────────────────────────────────────────────────

func bind(p_element: CircuitElement, p_model: CircuitModel) -> void:
	super.bind(p_element, p_model)
	_save_current()

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
	vis_enabled = element.enabled
	if element.current != null:
		vis_current_a = element.current.magnitude()
	else:
		vis_current_a = 0.0
	# power is best-effort (needs voltage context)
	var ac: ACCurrentSource = element as ACCurrentSource
	if ac != null:
		vis_power_w = ac.active_power()
	var dc: DCCurrentSource = element as DCCurrentSource
	if dc != null:
		vis_power_w = dc.active_power()

# ── Interactions ──────────────────────────────────────────────────────────────

func interact_toggle() -> void:
	if element == null:
		return
	if element.enabled:
		_cut_current()
	else:
		_restore_current()
	if model != null:
		model.mark_dirty()

func interact_repair() -> void:
	if element != null and not element.enabled:
		_restore_current()
		if model != null:
			model.mark_dirty()

# ── Private ───────────────────────────────────────────────────────────────────

func _cut_current() -> void:
	_save_current()
	_zero_current()
	element.enabled = false
	emit_signal("power_cut")

func _restore_current() -> void:
	element.enabled = true
	_apply_saved_current()
	emit_signal("power_restored")

func _save_current() -> void:
	var ac: ACCurrentSource = element as ACCurrentSource
	if ac != null:
		_saved_phasor = ac.current_phasor.copy()
		return
	var dc: DCCurrentSource = element as DCCurrentSource
	if dc != null:
		_saved_phasor = Complex.new(dc.current_a, 0.0)

func _zero_current() -> void:
	var ac: ACCurrentSource = element as ACCurrentSource
	if ac != null:
		ac.set_current(Complex.zero())
		return
	var dc: DCCurrentSource = element as DCCurrentSource
	if dc != null:
		dc.set_current(0.0)

func _apply_saved_current() -> void:
	if _saved_phasor == null:
		return
	var ac: ACCurrentSource = element as ACCurrentSource
	if ac != null:
		ac.set_current(_saved_phasor)
		return
	var dc: DCCurrentSource = element as DCCurrentSource
	if dc != null:
		dc.set_current(_saved_phasor.re)

# ── Info ──────────────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	if element == null:
		return {"name": "current_src", "type": "Current Source", "rows": []}
	var rows: Array = []
	rows.append(row("Status",   "active" if element.enabled else "OFF"))
	rows.append(row("Current",  vis_current_a, "%.3f A"))
	rows.append(row("Power",    vis_power_w,   "%.2f W"))
	var ac: ACCurrentSource = element as ACCurrentSource
	if ac != null:
		rows.append(row("Angle",
			"%.1f°" % rad_to_deg(atan2(ac.current_phasor.im, ac.current_phasor.re))))
	return {"name": element.element_name, "type": "Current Source", "rows": rows}
