# res://scripts/CableInspectorDialog.gd
# Dual-mode inspector popup:
#   MODE_ADD  — shown before drawing; "Confirm" starts drafting mode.
#   MODE_EDIT — shown after selecting a cable; "Confirm" applies changes live.
class_name CableInspectorDialog
extends PanelContainer

enum Mode { ADD, EDIT }

# ── signals ────────────────────────────────────────────────────────────────
## Emitted in ADD mode: carries the chosen params dict.
signal params_confirmed(params: Dictionary)
## Emitted in EDIT mode: carries the updated params dict.
signal edit_confirmed(params: Dictionary)
## Emitted when the dialog is closed / cancelled.
signal cancelled()

# ── cable type lookup table (cross_mm2 → max_current copper / aluminium) ──
# Values are approximate IEC 60364 / NF C 15-100 free-air ratings.
# Format: { label, cross_mm2, max_cu_a, max_al_a }
const CABLE_TYPES: Array[Dictionary] = [
	{ "label": "1.5 mm²",  "cross_mm2": 1.5,  "max_cu_a": 16.0,  "max_al_a": 13.0 },
	{ "label": "2.5 mm²",  "cross_mm2": 2.5,  "max_cu_a": 20.0,  "max_al_a": 16.0 },
	{ "label": "4 mm²",    "cross_mm2": 4.0,  "max_cu_a": 25.0,  "max_al_a": 20.0 },
	{ "label": "6 mm²",    "cross_mm2": 6.0,  "max_cu_a": 32.0,  "max_al_a": 25.0 },
	{ "label": "10 mm²",   "cross_mm2": 10.0, "max_cu_a": 50.0,  "max_al_a": 40.0 },
	{ "label": "16 mm²",   "cross_mm2": 16.0, "max_cu_a": 63.0,  "max_al_a": 50.0 },
	{ "label": "25 mm²",   "cross_mm2": 25.0, "max_cu_a": 80.0,  "max_al_a": 63.0 },
	{ "label": "35 mm²",   "cross_mm2": 35.0, "max_cu_a": 100.0, "max_al_a": 80.0 },
	{ "label": "50 mm²",   "cross_mm2": 50.0, "max_cu_a": 125.0, "max_al_a": 100.0 },
	{ "label": "70 mm²",   "cross_mm2": 70.0, "max_cu_a": 160.0, "max_al_a": 125.0 },
	{ "label": "95 mm²",   "cross_mm2": 95.0, "max_cu_a": 200.0, "max_al_a": 160.0 },
	{ "label": "120 mm²",  "cross_mm2": 120.0,"max_cu_a": 230.0, "max_al_a": 185.0 },
]

# ── internal widgets (built procedurally) ──────────────────────────────────
var _mode: Mode = Mode.ADD

var _lbl_title:       Label
var _edt_label:       LineEdit
var _opt_cross:       OptionButton   # cable type / cross section dropdown
var _opt_material:    OptionButton   # Copper / Aluminium
var _spin_max_current: SpinBox       # overridden max current (A)
var _lbl_current_hint: Label         # shows lookup suggestion
var _btn_confirm:     Button
var _btn_cancel:      Button

# Reference kept for EDIT mode
var _target_cable: Node2D = null

# ──────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	visible = false

# ──────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	custom_minimum_size = Vector2(380, 0)

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
	_lbl_title.text = "Cable Inspector"
	_lbl_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_lbl_title)

	vbox.add_child(HSeparator.new())

	# Label field
	_add_row(vbox, "Cable label:")
	_edt_label = LineEdit.new()
	_edt_label.placeholder_text = "e.g. Main_to_DistBox"
	vbox.add_child(_edt_label)

	# Cross-section / type dropdown
	_add_row(vbox, "Cable type (cross-section):")
	_opt_cross = OptionButton.new()
	_opt_cross.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in CABLE_TYPES:
		_opt_cross.add_item(entry["label"])
	_opt_cross.selected = 2  # default: 4 mm²
	_opt_cross.item_selected.connect(_on_cross_changed)
	vbox.add_child(_opt_cross)

	# Material dropdown
	_add_row(vbox, "Conductor material:")
	_opt_material = OptionButton.new()
	_opt_material.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_material.add_item("Copper",    0)
	_opt_material.add_item("Aluminium", 1)
	_opt_material.selected = 0
	_opt_material.item_selected.connect(_on_material_changed)
	vbox.add_child(_opt_material)

	# Max-current hint label
	_lbl_current_hint = Label.new()
	_lbl_current_hint.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	vbox.add_child(_lbl_current_hint)

	# Max current override
	_add_row(vbox, "Max current (A) — override:")
	_spin_max_current = SpinBox.new()
	_spin_max_current.min_value = 1.0
	_spin_max_current.max_value = 1000.0
	_spin_max_current.step      = 0.5
	_spin_max_current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_spin_max_current)

	vbox.add_child(HSeparator.new())

	# Confirm / Cancel row
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	_btn_confirm = Button.new()
	_btn_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_confirm.pressed.connect(_on_confirm)
	hbox.add_child(_btn_confirm)

	_btn_cancel = Button.new()
	_btn_cancel.text = "Cancel"
	_btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cancel.pressed.connect(_on_cancel)
	hbox.add_child(_btn_cancel)

	# Populate hint with default selection
	_refresh_hint()

# ──────────────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────────────

## Open in ADD mode (before drawing). Resets fields to defaults.
func open_add_mode() -> void:
	_mode = Mode.ADD
	_target_cable = null
	_lbl_title.text  = "New Cable — Parameters"
	_btn_confirm.text = "Add  ▶  Start Drawing"
	_edt_label.text   = ""
	_opt_cross.selected  = 2
	_opt_material.selected = 0
	_refresh_hint()
	visible = true

## Open in EDIT mode (cable already drawn).
func open_edit_mode(cn: Node2D) -> void:
	_mode = Mode.EDIT
	_target_cable = cn
	_lbl_title.text   = "Edit Cable — %s" % cn.cable_label
	_btn_confirm.text = "Apply Changes"
	_edt_label.text   = cn.cable_label

	# Match dropdown to cable's cross_mm2 (find closest)
	var best_idx := 0
	var best_diff := INF
	for i in CABLE_TYPES.size():
		var diff := absf(CABLE_TYPES[i]["cross_mm2"] - cn.cross_mm2)
		if diff < best_diff:
			best_diff = diff
			best_idx  = i
	_opt_cross.selected = best_idx

	# Material
	_opt_material.selected = 0 if cn.cable_core.to_lower().begins_with("copper") else 1

	_refresh_hint()
	_spin_max_current.value = cn.max_current
	visible = true

# ──────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────

func _add_row(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	parent.add_child(lbl)

func _refresh_hint() -> void:
	var entry: Dictionary = CABLE_TYPES[_opt_cross.selected]
	var is_al: bool = _opt_material.selected == 1
	var rated: float = entry["max_al_a"] if is_al else entry["max_cu_a"]
	_lbl_current_hint.text = "  IEC lookup → %.0f A  (fill override below to customise)" % rated
	_spin_max_current.value = rated

func _collect_params() -> Dictionary:
	var entry: Dictionary  = CABLE_TYPES[_opt_cross.selected]
	var material: String   = "aluminium" if _opt_material.selected == 1 else "copper"
	var lbl: String        = _edt_label.text.strip_edges()
	if lbl.is_empty():
		lbl = "%s_%s" % [material.left(2).to_upper(), entry["label"]]
	return {
		"cable_label":  lbl,
		"cross_mm2":    entry["cross_mm2"],
		"cable_core":   material,
		"max_current":  _spin_max_current.value,
	}

# ──────────────────────────────────────────────────────────────────────────
# Signal callbacks
# ──────────────────────────────────────────────────────────────────────────

func _on_cross_changed(_idx: int) -> void:
	_refresh_hint()

func _on_material_changed(_idx: int) -> void:
	_refresh_hint()

func _on_confirm() -> void:
	var params := _collect_params()
	if _mode == Mode.ADD:
		emit_signal("params_confirmed", params)
	else:
		if _target_cable != null:
			_target_cable.apply_params(params)
		emit_signal("edit_confirmed", params)
	visible = false

func _on_cancel() -> void:
	emit_signal("cancelled")
	visible = false
