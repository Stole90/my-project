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

# ── internal widgets (built procedurally) ──────────────────────────────────
var _mode: Mode = Mode.ADD

var _lbl_title:       Label
var _edt_label:       LineEdit
var _opt_cross:       OptionButton   # cable type / cross section dropdown
var _opt_material:    OptionButton   # Copper / Aluminium
var _opt_insulation:  OptionButton   # PVC / XLPE / EPR
var _opt_method:      OptionButton   # Installation method
var _spin_ambient_temp: SpinBox
var _spin_soil_temp:  SpinBox
var _chk_soil_advanced: CheckButton
var _opt_soil_type:   OptionButton
var _spin_soil_resistivity: SpinBox
var _spin_grouped_circuits: SpinBox
var _opt_grouping_arrangement: OptionButton
var _chk_harmonics_advanced: CheckButton
var _opt_harmonic_level: OptionButton
var _spin_thd:        SpinBox
var _spin_max_current: SpinBox       # manual override max current (A)

# Environment rows for visibility toggling
var _row_ambient_temp: Control
var _row_soil_temp: Control
var _soil_subarea: Control
var _row_soil_type: Control
var _row_soil_resistivity: Control

# Harmonics rows for visibility toggling
var _row_harmonic_level: Control
var _row_thd: Control

# Results labels
var _lbl_base_current: Label
var _lbl_k1: Label
var _lbl_k2: Label
var _lbl_k3: Label
var _lbl_k4: Label
var _lbl_k5: Label
var _lbl_iz_final: Label
var _lbl_notes: Label

var _btn_confirm:     Button
var _btn_cancel:      Button

# Last rating results
var _last_rating: CableRatingResult = null

# Reference kept for EDIT mode
var _target_cable: Node2D = null

# ──────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	visible = false

# ──────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	custom_minimum_size = Vector2(420, 520)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Title
	_lbl_title = Label.new()
	_lbl_title.text = "Cable Inspector"
	_lbl_title.add_theme_font_size_override("font_size", 16)
	main_vbox.add_child(_lbl_title)

	main_vbox.add_child(HSeparator.new())

	# ScrollContainer to hold collapsible sections
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# ── Section 1: Electrical ───────────────────────────────────────────────
	var body_elec = _make_collapsible_section(vbox, "Electrical")

	# Label field
	_add_row(body_elec, "Cable label:")
	_edt_label = LineEdit.new()
	_edt_label.placeholder_text = "e.g. Main_to_DistBox"
	body_elec.add_child(_edt_label)

	# Material dropdown
	_add_row(body_elec, "Conductor material:")
	_opt_material = OptionButton.new()
	_opt_material.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_material.add_item("Copper",    0)
	_opt_material.add_item("Aluminium", 1)
	_opt_material.selected = 0
	_opt_material.item_selected.connect(func(_idx): _recalculate_and_refresh_results())
	body_elec.add_child(_opt_material)

	# Insulation type dropdown
	_add_row(body_elec, "Insulation type:")
	_opt_insulation = OptionButton.new()
	_opt_insulation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_insulation.add_item("PVC")
	_opt_insulation.set_item_metadata(0, "pvc")
	_opt_insulation.add_item("XLPE")
	_opt_insulation.set_item_metadata(1, "xlpe")
	_opt_insulation.add_item("EPR")
	_opt_insulation.set_item_metadata(2, "epr")
	_opt_insulation.selected = 0
	_opt_insulation.item_selected.connect(func(_idx): _recalculate_and_refresh_results())
	body_elec.add_child(_opt_insulation)

	# Cross-section dropdown
	_add_row(body_elec, "Cable type (cross-section):")
	_opt_cross = OptionButton.new()
	_opt_cross.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	const SIZES = [1.5, 2.5, 4.0, 6.0, 10.0, 16.0, 25.0, 35.0, 50.0, 70.0, 95.0, 120.0]
	for idx in SIZES.size():
		var size = SIZES[idx]
		var label = "%.1f mm²" % size if size != int(size) else "%d mm²" % int(size)
		_opt_cross.add_item(label)
		_opt_cross.set_item_metadata(idx, size)
	_opt_cross.selected = 2  # default: 4 mm²
	_opt_cross.item_selected.connect(func(_idx): _recalculate_and_refresh_results())
	body_elec.add_child(_opt_cross)

	# ── Section 2: Installation ─────────────────────────────────────────────
	var body_inst = _make_collapsible_section(vbox, "Installation")

	_add_row(body_inst, "Installation method:")
	_opt_method = OptionButton.new()
	_opt_method.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var codes = InstallationMethodDB.all_codes()
	for idx in codes.size():
		var code = codes[idx]
		var method = InstallationMethodDB.get_method(code)
		var display_lbl = method.display_name if method else code
		_opt_method.add_item("%s — %s" % [code, display_lbl])
		_opt_method.set_item_metadata(idx, code)
	_opt_method.selected = 0
	_opt_method.item_selected.connect(func(_idx): _recalculate_and_refresh_results())
	body_inst.add_child(_opt_method)

	# ── Section 3: Environment ──────────────────────────────────────────────
	var body_env = _make_collapsible_section(vbox, "Environment")

	# Ambient Temperature Row (Air methods)
	_row_ambient_temp = VBoxContainer.new()
	_add_row(_row_ambient_temp, "Ambient temperature (°C):")
	_spin_ambient_temp = SpinBox.new()
	_spin_ambient_temp.min_value = -20.0
	_spin_ambient_temp.max_value = 100.0
	_spin_ambient_temp.step = 1.0
	_spin_ambient_temp.value = 30.0
	_spin_ambient_temp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_ambient_temp.value_changed.connect(func(_val): _recalculate_and_refresh_results())
	_row_ambient_temp.add_child(_spin_ambient_temp)
	body_env.add_child(_row_ambient_temp)

	# Soil Temperature Row (Buried methods)
	_row_soil_temp = VBoxContainer.new()
	_add_row(_row_soil_temp, "Soil temperature (°C):")
	_spin_soil_temp = SpinBox.new()
	_spin_soil_temp.min_value = -10.0
	_spin_soil_temp.max_value = 80.0
	_spin_soil_temp.step = 1.0
	_spin_soil_temp.value = 20.0
	_spin_soil_temp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_soil_temp.value_changed.connect(func(_val): _recalculate_and_refresh_results())
	_row_soil_temp.add_child(_spin_soil_temp)
	body_env.add_child(_row_soil_temp)

	# Soil Subarea
	_soil_subarea = VBoxContainer.new()
	_soil_subarea.add_theme_constant_override("separation", 6)
	body_env.add_child(_soil_subarea)

	# Simple/Advanced mode toggle
	_chk_soil_advanced = CheckButton.new()
	_chk_soil_advanced.text = "Advanced Soil Resistivity"
	_chk_soil_advanced.toggled.connect(func(_val): _recalculate_and_refresh_results())
	_soil_subarea.add_child(_chk_soil_advanced)

	# Soil Type Row
	_row_soil_type = VBoxContainer.new()
	_add_row(_row_soil_type, "Soil type:")
	_opt_soil_type = OptionButton.new()
	_opt_soil_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var soil_types = SoilTypeDB.all_types()
	for idx in soil_types.size():
		var st = soil_types[idx]
		_opt_soil_type.add_item(st.capitalize())
		_opt_soil_type.set_item_metadata(idx, st)
	_opt_soil_type.selected = 0
	_opt_soil_type.item_selected.connect(func(_idx): _recalculate_and_refresh_results())
	_row_soil_type.add_child(_opt_soil_type)
	_soil_subarea.add_child(_row_soil_type)

	# Soil thermal resistivity Row
	_row_soil_resistivity = VBoxContainer.new()
	_add_row(_row_soil_resistivity, "Thermal resistivity (K·m/W):")
	_spin_soil_resistivity = SpinBox.new()
	_spin_soil_resistivity.min_value = 0.1
	_spin_soil_resistivity.max_value = 10.0
	_spin_soil_resistivity.step = 0.1
	_spin_soil_resistivity.value = 2.5
	_spin_soil_resistivity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_soil_resistivity.value_changed.connect(func(_val): _recalculate_and_refresh_results())
	_row_soil_resistivity.add_child(_spin_soil_resistivity)
	_soil_subarea.add_child(_row_soil_resistivity)

	# ── Section 4: Correction Factors ───────────────────────────────────────
	var body_corr = _make_collapsible_section(vbox, "Correction Factors")

	# Grouped circuits
	_add_row(body_corr, "Grouped circuits:")
	_spin_grouped_circuits = SpinBox.new()
	_spin_grouped_circuits.min_value = 1.0
	_spin_grouped_circuits.max_value = 12.0
	_spin_grouped_circuits.step = 1.0
	_spin_grouped_circuits.value = 1.0
	_spin_grouped_circuits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_grouped_circuits.value_changed.connect(func(_val): _recalculate_and_refresh_results())
	body_corr.add_child(_spin_grouped_circuits)

	# Grouping arrangement
	_add_row(body_corr, "Grouping arrangement:")
	_opt_grouping_arrangement = OptionButton.new()
	_opt_grouping_arrangement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	const ARRANGEMENTS = ["touching", "spacing", "tray", "conduit", "bundle"]
	for idx in ARRANGEMENTS.size():
		var arr = ARRANGEMENTS[idx]
		_opt_grouping_arrangement.add_item(arr.capitalize())
		_opt_grouping_arrangement.set_item_metadata(idx, arr)
	_opt_grouping_arrangement.selected = 0
	_opt_grouping_arrangement.item_selected.connect(func(_idx): _recalculate_and_refresh_results())
	body_corr.add_child(_opt_grouping_arrangement)

	# Harmonics Subarea
	var harmonics_subarea = VBoxContainer.new()
	harmonics_subarea.add_theme_constant_override("separation", 6)
	body_corr.add_child(harmonics_subarea)

	# Harmonics Advanced toggle
	_chk_harmonics_advanced = CheckButton.new()
	_chk_harmonics_advanced.text = "Advanced THD %"
	_chk_harmonics_advanced.toggled.connect(func(_val): _recalculate_and_refresh_results())
	harmonics_subarea.add_child(_chk_harmonics_advanced)

	# Harmonic level dropdown
	_row_harmonic_level = VBoxContainer.new()
	_add_row(_row_harmonic_level, "Harmonic level:")
	_opt_harmonic_level = OptionButton.new()
	_opt_harmonic_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var harm_levels = HarmonicLevelDB.all_levels()
	for idx in harm_levels.size():
		var hl = harm_levels[idx]
		_opt_harmonic_level.add_item(hl.capitalize())
		_opt_harmonic_level.set_item_metadata(idx, hl)
	_opt_harmonic_level.selected = 0
	_opt_harmonic_level.item_selected.connect(func(_idx): _recalculate_and_refresh_results())
	_row_harmonic_level.add_child(_opt_harmonic_level)
	harmonics_subarea.add_child(_row_harmonic_level)

	# THD SpinBox
	_row_thd = VBoxContainer.new()
	_add_row(_row_thd, "THD %:")
	_spin_thd = SpinBox.new()
	_spin_thd.min_value = 0.0
	_spin_thd.max_value = 100.0
	_spin_thd.step = 1.0
	_spin_thd.value = 0.0
	_spin_thd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_thd.value_changed.connect(func(_val): _recalculate_and_refresh_results())
	_row_thd.add_child(_spin_thd)
	harmonics_subarea.add_child(_row_thd)

	# ── Section 5: Results ──────────────────────────────────────────────────
	var body_results = _make_collapsible_section(vbox, "Results")

	_lbl_base_current = Label.new()
	_lbl_base_current.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	body_results.add_child(_lbl_base_current)

	_lbl_k1 = Label.new()
	_lbl_k1.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	body_results.add_child(_lbl_k1)

	_lbl_k2 = Label.new()
	_lbl_k2.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	body_results.add_child(_lbl_k2)

	_lbl_k3 = Label.new()
	_lbl_k3.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	body_results.add_child(_lbl_k3)

	_lbl_k4 = Label.new()
	_lbl_k4.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	body_results.add_child(_lbl_k4)

	_lbl_k5 = Label.new()
	_lbl_k5.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	body_results.add_child(_lbl_k5)

	_lbl_iz_final = Label.new()
	_lbl_iz_final.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	body_results.add_child(_lbl_iz_final)

	_lbl_notes = Label.new()
	_lbl_notes.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lbl_notes.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	body_results.add_child(_lbl_notes)

	# ── Bottom controls ─────────────────────────────────────────────────────
	main_vbox.add_child(HSeparator.new())

	var override_hbox := HBoxContainer.new()
	override_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(override_hbox)

	var lbl_override := Label.new()
	lbl_override.text = "Manual override (A) — optional:"
	lbl_override.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	override_hbox.add_child(lbl_override)

	_spin_max_current = SpinBox.new()
	_spin_max_current.min_value = 1.0
	_spin_max_current.max_value = 1000.0
	_spin_max_current.step      = 0.5
	_spin_max_current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	override_hbox.add_child(_spin_max_current)

	main_vbox.add_child(HSeparator.new())

	# Confirm / Cancel row
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(hbox)

	_btn_confirm = Button.new()
	_btn_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_confirm.pressed.connect(_on_confirm)
	hbox.add_child(_btn_confirm)

	_btn_cancel = Button.new()
	_btn_cancel.text = "Cancel"
	_btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cancel.pressed.connect(_on_cancel)
	hbox.add_child(_btn_cancel)

	# Initial results refresh
	_recalculate_and_refresh_results()

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
	_opt_cross.selected  = 2 # default: 4 mm²
	_opt_material.selected = 0 # default: Copper
	_opt_insulation.selected = 0 # default: PVC
	_opt_method.selected = 0 # default: A1
	_spin_ambient_temp.value = 30.0
	_spin_soil_temp.value = 20.0
	_opt_soil_type.selected = 0 # default: normal
	_spin_soil_resistivity.value = 2.5
	_chk_soil_advanced.button_pressed = false
	_spin_grouped_circuits.value = 1
	_opt_grouping_arrangement.selected = 0 # default: touching
	_opt_harmonic_level.selected = 0 # default: none
	_spin_thd.value = 0.0
	_chk_harmonics_advanced.button_pressed = false

	_recalculate_and_refresh_results()
	visible = true

## Open in EDIT mode (cable already drawn).
func open_edit_mode(cn: Node2D) -> void:
	_mode = Mode.EDIT
	_target_cable = cn
	_lbl_title.text   = "Edit Cable — %s" % cn.cable_label
	_btn_confirm.text = "Apply Changes"
	_edt_label.text   = cn.cable_label

	# 1. Match cross-section dropdown to cn.cross_mm2
	var best_idx := 0
	var best_diff := INF
	for i in _opt_cross.get_item_count():
		var size = _opt_cross.get_item_metadata(i)
		if size != null:
			var diff := absf(size - cn.cross_mm2)
			if diff < best_diff:
				best_diff = diff
				best_idx  = i
	_opt_cross.selected = best_idx

	# 2. Material
	_opt_material.selected = 0 if cn.cable_core.to_lower().begins_with("copper") else 1

	# 3. Default the new sections
	var inst_method = "A1"
	var ambient = 30.0
	var soil_temp = 20.0
	var soil_type = "normal"
	var soil_res_adv = 2.5
	var grouped_circ = 1
	var grouping_arr = "touching"
	var harm_lvl = "none"
	var thd_adv = 0.0
	var insulation = "pvc"

	# Try to read insulation from electrical model or sim_cable
	if cn.sim_cable != null:
		if "electrical_model" in cn.sim_cable and cn.sim_cable.electrical_model != null:
			insulation = cn.sim_cable.electrical_model.insulation_type
		elif "insulation_type" in cn.sim_cable:
			insulation = cn.sim_cable.insulation_type

		# Read installation model fields if present
		if "installation_model" in cn.sim_cable and cn.sim_cable.installation_model != null:
			var im = cn.sim_cable.installation_model
			inst_method  = im.installation_method if "installation_method" in im else inst_method
			ambient      = im.ambient_c if "ambient_c" in im else ambient
			soil_temp    = im.soil_temperature_c if "soil_temperature_c" in im else soil_temp
			soil_type    = im.soil_type if "soil_type" in im else soil_type
			soil_res_adv = im.soil_resistivity_advanced if "soil_resistivity_advanced" in im else soil_res_adv
			grouped_circ = im.grouped_circuits if "grouped_circuits" in im else grouped_circ
			grouping_arr = im.grouping_arrangement if "grouping_arrangement" in im else grouping_arr
			harm_lvl     = im.harmonic_level if "harmonic_level" in im else harm_lvl
			thd_adv      = im.thd_percent_advanced if "thd_percent_advanced" in im else thd_adv

	# Set the UI controls based on values
	for i in _opt_insulation.get_item_count():
		if _opt_insulation.get_item_metadata(i) == insulation:
			_opt_insulation.selected = i
			break

	for i in _opt_method.get_item_count():
		if _opt_method.get_item_metadata(i) == inst_method:
			_opt_method.selected = i
			break

	_spin_ambient_temp.value = ambient
	_spin_soil_temp.value = soil_temp

	for i in _opt_soil_type.get_item_count():
		if _opt_soil_type.get_item_metadata(i) == soil_type:
			_opt_soil_type.selected = i
			break
	_spin_soil_resistivity.value = soil_res_adv
	_chk_soil_advanced.button_pressed = (soil_res_adv != 2.5)

	_spin_grouped_circuits.value = grouped_circ

	for i in _opt_grouping_arrangement.get_item_count():
		if _opt_grouping_arrangement.get_item_metadata(i) == grouping_arr:
			_opt_grouping_arrangement.selected = i
			break

	for i in _opt_harmonic_level.get_item_count():
		if _opt_harmonic_level.get_item_metadata(i) == harm_lvl:
			_opt_harmonic_level.selected = i
			break
	_spin_thd.value = thd_adv
	_chk_harmonics_advanced.button_pressed = (thd_adv > 0.0)

	_recalculate_and_refresh_results()

	# Set manual override value (must be done after recalculate, as recalculate overrides it)
	_spin_max_current.value = cn.max_current
	visible = true

# ──────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────

func _add_row(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	parent.add_child(lbl)

func _make_collapsible_section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = true
	btn.text = "▼ " + title
	btn.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	parent.add_child(btn)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	parent.add_child(body)

	btn.toggled.connect(func(is_pressed: bool):
		body.visible = is_pressed
		if is_pressed:
			btn.text = "▼ " + title
		else:
			btn.text = "▶ " + title
	)

	return body

func _update_environment_ui() -> void:
	var method_idx = _opt_method.selected
	var code = _opt_method.get_item_metadata(method_idx) if method_idx >= 0 else "A1"
	var method = InstallationMethodDB.get_method(code)
	var is_buried = method.is_buried if method else false

	_row_ambient_temp.visible = not is_buried
	_row_soil_temp.visible = is_buried
	_soil_subarea.visible = is_buried

	if is_buried:
		var adv = _chk_soil_advanced.button_pressed
		_row_soil_type.visible = not adv
		_row_soil_resistivity.visible = adv

func _update_harmonics_ui() -> void:
	var adv = _chk_harmonics_advanced.button_pressed
	_row_harmonic_level.visible = not adv
	_row_thd.visible = adv

func _recalculate_and_refresh_results() -> void:
	_update_environment_ui()
	_update_harmonics_ui()

	# Electrical Model
	var electrical := CableElectricalModel.new()
	electrical.material = "aluminium" if _opt_material.selected == 1 else "copper"

	var ins_idx = _opt_insulation.selected
	var insulation = _opt_insulation.get_item_metadata(ins_idx) if ins_idx >= 0 else "pvc"
	electrical.insulation_type = insulation

	var cross_idx = _opt_cross.selected
	var cross = _opt_cross.get_item_metadata(cross_idx) if cross_idx >= 0 else 4.0
	electrical.cross_mm2 = cross

	var length_val = 50.0
	if _mode == Mode.EDIT and _target_cable != null and "length_m" in _target_cable:
		length_val = _target_cable.length_m
	electrical.length_m = length_val

	# Installation Model
	var installation := CableInstallationModel.new()

	var method_idx = _opt_method.selected
	var method_code = _opt_method.get_item_metadata(method_idx) if method_idx >= 0 else "A1"
	installation.installation_method = method_code

	var method = InstallationMethodDB.get_method(method_code)
	var is_buried = method.is_buried if method else false

	if is_buried:
		installation.ambient_c = method.reference_ambient_c if method else 30.0
		installation.soil_temperature_c = _spin_soil_temp.value

		if _chk_soil_advanced.button_pressed:
			installation.soil_type = "normal"
			installation.soil_resistivity_advanced = _spin_soil_resistivity.value
		else:
			var soil_idx = _opt_soil_type.selected
			var soil_type = _opt_soil_type.get_item_metadata(soil_idx) if soil_idx >= 0 else "normal"
			installation.soil_type = soil_type
			installation.soil_resistivity_advanced = 2.5
	else:
		installation.ambient_c = _spin_ambient_temp.value
		installation.soil_temperature_c = method.reference_soil_c if method else 20.0
		installation.soil_type = "normal"
		installation.soil_resistivity_advanced = 2.5

	# Grouping factors
	installation.grouped_circuits = int(_spin_grouped_circuits.value)

	var arr_idx = _opt_grouping_arrangement.selected
	var arr = _opt_grouping_arrangement.get_item_metadata(arr_idx) if arr_idx >= 0 else "touching"
	installation.grouping_arrangement = arr

	# Harmonics
	if _chk_harmonics_advanced.button_pressed:
		installation.harmonic_level = "none"
		installation.thd_percent_advanced = _spin_thd.value
	else:
		var harm_idx = _opt_harmonic_level.selected
		var harm_lvl = _opt_harmonic_level.get_item_metadata(harm_idx) if harm_idx >= 0 else "none"
		installation.harmonic_level = harm_lvl
		installation.thd_percent_advanced = 0.0

	# Calculate Rating
	var result = CableRatingCalculator.calculate(electrical, installation)
	_last_rating = result

	# Populate Results labels
	if result != null:
		_lbl_base_current.text = "  Base Current (Iz base): %.1f A" % result.iz_base
		_lbl_k1.text           = "  K1 (Temperature): %.2f" % result.k1_temperature
		_lbl_k2.text           = "  K2 (Grouping): %.2f" % result.k2_grouping
		_lbl_k3.text           = "  K3 (Soil): %.2f" % result.k3_soil
		_lbl_k4.text           = "  K4 (Harmonic): %.2f" % result.k4_harmonic
		_lbl_k5.text           = "  K5 (Installation): %.2f" % result.k5_installation

		if result.is_valid:
			_lbl_iz_final.text = "  Calculated Iz: %.1f A" % result.iz_final
			_lbl_iz_final.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
			_spin_max_current.value = result.iz_final
		else:
			_lbl_iz_final.text = "  Calculated Iz: INVALID"
			_lbl_iz_final.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			_spin_max_current.value = 1.0

		if result.notes and not result.notes.is_empty():
			_lbl_notes.text = "  Note: %s" % result.notes
			_lbl_notes.visible = true
		else:
			_lbl_notes.visible = false
	else:
		_lbl_base_current.text = "  Base Current (Iz base): N/A"
		_lbl_k1.text           = "  K1 (Temperature): N/A"
		_lbl_k2.text           = "  K2 (Grouping): N/A"
		_lbl_k3.text           = "  K3 (Soil): N/A"
		_lbl_k4.text           = "  K4 (Harmonic): N/A"
		_lbl_k5.text           = "  K5 (Installation): N/A"
		_lbl_iz_final.text     = "  Calculated Iz: N/A"
		_lbl_iz_final.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		_lbl_notes.visible     = false

func _collect_params() -> Dictionary:
	var material: String = "aluminium" if _opt_material.selected == 1 else "copper"
	var cross_idx = _opt_cross.selected
	var cross = _opt_cross.get_item_metadata(cross_idx) if cross_idx >= 0 else 4.0

	var lbl: String = _edt_label.text.strip_edges()
	if lbl.is_empty():
		lbl = "%s_%smm2" % [material.left(2).to_upper(), str(cross).replace(".", "_")]

	var method_idx = _opt_method.selected
	var method_code = _opt_method.get_item_metadata(method_idx) if method_idx >= 0 else "A1"

	var ins_idx = _opt_insulation.selected
	var insulation = _opt_insulation.get_item_metadata(ins_idx) if ins_idx >= 0 else "pvc"

	var soil_idx = _opt_soil_type.selected
	var soil_type = _opt_soil_type.get_item_metadata(soil_idx) if soil_idx >= 0 else "normal"

	var arr_idx = _opt_grouping_arrangement.selected
	var arr_code = _opt_grouping_arrangement.get_item_metadata(arr_idx) if arr_idx >= 0 else "touching"

	var harm_idx = _opt_harmonic_level.selected
	var harm_lvl = _opt_harmonic_level.get_item_metadata(harm_idx) if harm_idx >= 0 else "none"

	return {
		"cable_label":  lbl,
		"cross_mm2":    cross,
		"cable_core":   material,
		"max_current":  _spin_max_current.value,

		"installation_method":       method_code,
		"ambient_c":                 _spin_ambient_temp.value,
		"soil_temperature_c":        _spin_soil_temp.value,
		"soil_type":                 soil_type,
		"soil_resistivity_advanced": _spin_soil_resistivity.value,
		"grouped_circuits":          int(_spin_grouped_circuits.value),
		"grouping_arrangement":      arr_code,
		"harmonic_level":            harm_lvl,
		"thd_percent_advanced":      _spin_thd.value,
		"insulation_type":           insulation,
	}

# ──────────────────────────────────────────────────────────────────────────
# Signal callbacks
# ──────────────────────────────────────────────────────────────────────────

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
