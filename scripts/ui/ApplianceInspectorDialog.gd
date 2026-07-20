# res://scripts/ui/ApplianceInspectorDialog.gd
## Inspector popup za editovanje parametara uređaja.
## Čita appliance.get_info() da detektuje tip i popuni polja.
## Poziva appliance.apply_params(dict) na potvrdu.
##
## ── Izmene vs. stara verzija ──────────────────────────────────────────────────
## • Ispravljen bug: `_row_pf.visible` se postavljao dva puta (jednom za Bojler,
##   jednom za Priključnicu) — drugi je silently poništavao prvi.
##   Sada se koristi jedan izraz s logičkim OR.
## • Ispravljen fragilan `_spin_power.get_parent().visible = not is_source`:
##   power red sada ima eksplicitni _row_power kontejner.
## • Sve ostalo nepromenjeno.
## ─────────────────────────────────────────────────────────────────────────────

class_name ApplianceInspectorDialog
extends PanelContainer

signal edit_confirmed(node: Node2D)
signal cancelled()

# ── Widgets ───────────────────────────────────────────────────────────────────
var _lbl_title:          Label
var _edt_name:           LineEdit
var _row_power:          Control   # sakriven za 3-fazne izvore napajanja
var _spin_power:         SpinBox
var _lbl_voltage:        Label
var _spin_voltage:       SpinBox
var _row_pf:             Control   # skriva se za Bojler i Priključnicu
var _spin_pf:            SpinBox
var _row_inrush:         Control   # samo za Frižider
var _spin_inrush_factor: SpinBox
var _spin_inrush_dur:    SpinBox
var _btn_confirm:        Button
var _btn_cancel:         Button

var _target: Node2D = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	visible = false

func _build_ui() -> void:
	custom_minimum_size = Vector2(360, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	_lbl_title = Label.new()
	_lbl_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_lbl_title)

	vbox.add_child(HSeparator.new())

	# Name
	_add_label(vbox, "Naziv:")
	_edt_name = LineEdit.new()
	vbox.add_child(_edt_name)

	# Rated power — eksplicitni kontejner da se može sakriti kao celina
	_row_power = VBoxContainer.new()
	_add_label(_row_power as VBoxContainer, "Nominalna snaga (W):")
	_spin_power = _make_spinbox(1.0, 100000.0, 10.0)
	_row_power.add_child(_spin_power)
	vbox.add_child(_row_power)

	# Nominal voltage (labela se menja zavisno od tipa)
	_lbl_voltage = Label.new()
	_lbl_voltage.text = "Nazivni napon (V):"
	vbox.add_child(_lbl_voltage)
	_spin_voltage = _make_spinbox(1.0, 50000.0, 1.0)
	vbox.add_child(_spin_voltage)

	# Power factor row (skriva se za Bojler i Priključnicu)
	_row_pf = VBoxContainer.new()
	_add_label(_row_pf as VBoxContainer, "Faktor snage (0–1):")
	_spin_pf = _make_spinbox(0.01, 1.0, 0.01)
	_row_pf.add_child(_spin_pf)
	vbox.add_child(_row_pf)

	# Inrush row (samo za Frižider)
	_row_inrush = VBoxContainer.new()
	_add_label(_row_inrush as VBoxContainer, "Inrush faktor:")
	_spin_inrush_factor = _make_spinbox(1.0, 20.0, 0.1)
	_row_inrush.add_child(_spin_inrush_factor)
	_add_label(_row_inrush as VBoxContainer, "Trajanje inrush-a (s):")
	_spin_inrush_dur = _make_spinbox(0.01, 5.0, 0.01)
	_row_inrush.add_child(_spin_inrush_dur)
	vbox.add_child(_row_inrush)

	vbox.add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_btn_confirm = Button.new()
	_btn_confirm.text = "Primeni izmene"
	_btn_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_confirm.pressed.connect(_on_confirm)
	hbox.add_child(_btn_confirm)

	_btn_cancel = Button.new()
	_btn_cancel.text = "Otkaži"
	_btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cancel.pressed.connect(_on_cancel)
	hbox.add_child(_btn_cancel)

# ── Public API ────────────────────────────────────────────────────────────────

func open_for(node: Node2D) -> void:
	if not node.has_method("get_info") or not node.has_method("apply_params"):
		push_warning("ApplianceInspectorDialog: node '%s' nema get_info ili apply_params" % node.name)
		return
	_target = node
	var info: Dictionary = node.get_info()
	var type_str: String = info.get("type", "")
	var is_source: bool  = (type_str == "3-fazni izvor napajanja")

	# Labela napona zavisi od tipa
	_lbl_voltage.text = "Linijski napon L-L (V):" if is_source else "Nazivni napon (V):"
	# Snaga se ne prikazuje za izvor (izvor nema opterećenje u W)
	_row_power.visible = not is_source

	_lbl_title.text     = "Uredi — %s" % info.get("name", node.name)
	_edt_name.text      = info.get("name", node.name)
	_spin_power.value   = info.get("power_w",      0.0)
	_spin_voltage.value = info.get("nominal_v",    230.0)
	_spin_pf.value      = info.get("power_factor", 1.0)

	# FIX: stara verzija je imala dva uzastopna `_row_pf.visible =` —
	# drugi je poništavao prvi. Sada je jedan izraz s OR.
	_row_pf.visible     = (type_str != "Bojler") and (type_str != "Priključnica")
	_row_inrush.visible = (type_str == "Frižider")

	if type_str == "Frižider":
		_spin_inrush_factor.value = info.get("inrush_factor",    4.0)
		_spin_inrush_dur.value    = info.get("inrush_duration_s", 0.2)

	visible = true

# ── Helpers ───────────────────────────────────────────────────────────────────

func _add_label(parent: Node, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	parent.add_child(lbl)

func _make_spinbox(min_v: float, max_v: float, step_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step      = step_v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

func _collect_params() -> Dictionary:
	return {
		"appliance_name":    _edt_name.text.strip_edges(),
		"rated_power_w":     _spin_power.value,
		"nominal_voltage":   _spin_voltage.value,
		"power_factor":      _spin_pf.value,
		"inrush_factor":     _spin_inrush_factor.value,
		"inrush_duration_s": _spin_inrush_dur.value,
	}

# ── Handlers ──────────────────────────────────────────────────────────────────

func _on_confirm() -> void:
	if _target == null:
		return
	_target.apply_params(_collect_params())
	emit_signal("edit_confirmed", _target)
	visible = false

func _on_cancel() -> void:
	emit_signal("cancelled")
	visible = false
