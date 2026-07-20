# res://scripts/ui/DiagnosticHUD.gd
## Floating HUD panel za dijagnostičke alate.
##
## ── Šta se promenilo vs. stara verzija ───────────────────────────────────────
## • Hardkodirani `_btn_multi`, `_btn_thermal`, `_btn_clamp` varijable su uklonjeni.
## • Tool dugmad se grade automatski iz `_tools` niza.
## • Dodavanje novog alata = samo `_tools.append(MyTool.new())` u _ready().
##   Više nije potrebno dirati _build_ui() ni _refresh_tool_buttons().
## • _format_reading() koristi tool.tool_name umesto hardkodiranog match bloka;
##   svaki novi tool dodaje samo svoju _add_<tool>_lines() metodu.
## ─────────────────────────────────────────────────────────────────────────────

class_name DiagnosticHUD
extends PanelContainer

# ── Signals ───────────────────────────────────────────────────────────────────
signal inject_fault_requested(target: Node2D, fault_type: int, phase: int, phase_b: int, cross_node: bool)
signal clear_faults_requested(target: Node2D)

# ── Tool registry — dodaj novi alat samo ovde ─────────────────────────────────
var _tools:       Array  = []             # Array[DiagnosticTool]
var _active_tool: DiagnosticTool = null
var _target:      Node2D = null

# ── UI refs (punjene u _build_ui) ─────────────────────────────────────────────
var _lbl_tool:       Label
var _lbl_reading:    RichTextLabel
var _toolbar:        HBoxContainer
var _tool_btns:      Array[Button] = []   # paralelni niz dugmadi za tool toolbar
var _fault_section:  VBoxContainer
var _lbl_fault_status: Label

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# ── Dodaj alate ovde — sve ostalo se generiše automatski ─────────────────
	_tools = [
		Multimeter.new(),
		ThermalCamera.new(),
		ClampMeter.new(),
	]
	_active_tool = _tools[0]
	_build_ui()
	visible = false

func _build_ui() -> void:
	custom_minimum_size = Vector2(260, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Diagnostic Tools"
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# ── Dinamički tool toolbar ────────────────────────────────────────────────
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	vbox.add_child(_toolbar)

	_tool_btns.clear()
	for i: int in _tools.size():
		var tool: DiagnosticTool = _tools[i]
		var btn := Button.new()
		btn.text                  = tool.tool_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_tool.bind(i))
		_toolbar.add_child(btn)
		_tool_btns.append(btn)

	vbox.add_child(HSeparator.new())

	# Active tool label
	_lbl_tool = Label.new()
	_lbl_tool.text = "No target selected"
	_lbl_tool.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_lbl_tool.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_lbl_tool)

	# Readings area
	_lbl_reading = RichTextLabel.new()
	_lbl_reading.bbcode_enabled       = true
	_lbl_reading.custom_minimum_size  = Vector2(0, 120)
	_lbl_reading.fit_content          = true
	vbox.add_child(_lbl_reading)

	vbox.add_child(HSeparator.new())

	# Fault injection section
	var fault_title := Label.new()
	fault_title.text = "Fault Injection"
	fault_title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	fault_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(fault_title)

	_fault_section = VBoxContainer.new()
	_fault_section.add_theme_constant_override("separation", 3)
	vbox.add_child(_fault_section)

	# Phase selectors for advanced faults
	var hb := HBoxContainer.new()
	var lbl_a := Label.new(); lbl_a.text = "Phase A:"; hb.add_child(lbl_a)
	var opt_a := OptionButton.new();
	opt_a.name = "phase_a"
	opt_a.add_item(Phase.name_of(Phase.L1), Phase.L1)
	opt_a.add_item(Phase.name_of(Phase.L2), Phase.L2)
	opt_a.add_item(Phase.name_of(Phase.L3), Phase.L3)
	hb.add_child(opt_a)
	var lbl_b := Label.new(); lbl_b.text = " B:"; hb.add_child(lbl_b)
	var opt_b := OptionButton.new();
	opt_b.name = "phase_b"
	opt_b.add_item("None", -1)
	opt_b.add_item(Phase.name_of(Phase.L1), Phase.L1)
	opt_b.add_item(Phase.name_of(Phase.L2), Phase.L2)
	opt_b.add_item(Phase.name_of(Phase.L3), Phase.L3)
	hb.add_child(opt_b)
	_fault_section.add_child(hb)

	var chk_cross := CheckBox.new()
	chk_cross.name = "cross_node"
	chk_cross.text = "Between buses (use cable ends)"
	_fault_section.add_child(chk_cross)

	_fault_section.add_child(_fault_button("Open Circuit",    FaultManager.FaultType.OPEN_CIRCUIT))
	_fault_section.add_child(_fault_button("High Resistance", FaultManager.FaultType.HIGH_RESISTANCE))
	_fault_section.add_child(_fault_button("Short Circuit",   FaultManager.FaultType.SHORT_CIRCUIT))

	var btn_clear := Button.new()
	btn_clear.text = "Clear Faults"
	btn_clear.pressed.connect(_on_clear_faults)
	_fault_section.add_child(btn_clear)

	_lbl_fault_status = Label.new()
	_lbl_fault_status.text = ""
	_lbl_fault_status.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_lbl_fault_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fault_section.add_child(_lbl_fault_status)

	_refresh_tool_buttons()

# ── Public API ────────────────────────────────────────────────────────────────

func set_target(node: Node2D) -> void:
	_target = node
	visible  = true
	_refresh_reading()

func clear_target() -> void:
	_target  = null
	visible  = false

## Poziva world.gd / UILayer posle svakog solve ciklusa dok je HUD vidljiv.
func refresh() -> void:
	_refresh_reading()

# ── Tool selection ────────────────────────────────────────────────────────────

func _select_tool(idx: int) -> void:
	if idx < 0 or idx >= _tools.size():
		return
	_active_tool = _tools[idx]
	_refresh_tool_buttons()
	_refresh_reading()

## Osvetljava aktivno dugme, gasi ostale — radi za bilo koji broj alata.
func _refresh_tool_buttons() -> void:
	for i: int in _tool_btns.size():
		_tool_btns[i].modulate = Color(1.0, 0.85, 0.3) if _tools[i] == _active_tool else Color.WHITE

# ── Reading display ───────────────────────────────────────────────────────────

func _refresh_reading() -> void:
	if _target == null or _active_tool == null:
		_lbl_tool.text         = "No target selected"
		_lbl_reading.text      = ""
		_lbl_fault_status.text = ""
		return

	if not _active_tool.can_measure(_target):
		_lbl_tool.text    = "%s — incompatible target" % _active_tool.tool_name
		_lbl_reading.text = "[color=gray]This tool cannot measure %s[/color]" % _target.name
		return

	var data: Dictionary = _active_tool.measure(_target)
	_lbl_tool.text    = "%s → %s" % [_active_tool.tool_name, data.get("target_name", _target.name)]
	_lbl_reading.text = _format_reading(data)

	if data.get("fault_detected", false):
		_lbl_fault_status.text = "⚠ %s" % str(data.get("state", "fault"))
	else:
		_lbl_fault_status.text = ""

# ── Formatteri ────────────────────────────────────────────────────────────────

func _format_reading(data: Dictionary) -> String:
	var lines: Array[String] = []
	if data.get("fault_detected", false):
		lines.append("[color=red][b]⚠ FAULT DETECTED[/b][/color]")

	match data.get("tool", ""):
		"Multimeter":     _add_multimeter_lines(data, lines)
		"Thermal Camera": _add_thermal_lines(data, lines)
		"Clamp Meter":    _add_clamp_lines(data, lines)
		_:
			# Nepoznat alat — prikaži sve ključeve generički
			for key: String in data.keys():
				if key not in ["tool", "target_name", "target_type", "fault_detected"]:
					lines.append("[color=silver]%s:[/color] %s" % [key, str(data[key])])

	return "\n".join(lines)

func _add_multimeter_lines(data: Dictionary, lines: Array) -> void:
	if data.has("voltages_3ph"):
		var v: Array = data["voltages_3ph"]
		lines.append(_row("V L1/L2/L3", "%.0f / %.0f / %.0f V" % [v[0], v[1], v[2]], ""))
	elif data.has("voltage_hv"):
		lines.append(_row("HV", data["voltage_hv"], "%.1f V"))
		lines.append(_row("LV", data.get("voltage_lv", "---"), "%.1f V"))
	else:
		lines.append(_row("Voltage", data.get("voltage_v"), "%.2f V"))

	if data.has("voltage_drop_v"):
		lines.append(_row("V drop", data["voltage_drop_v"], "%.2f V"))

	if data.has("currents_3ph"):
		var c: Array = data["currents_3ph"]
		lines.append(_row("I L1/L2/L3", "%.2f / %.2f / %.2f A" % [c[0], c[1], c[2]], ""))
	elif data.has("current_hv"):
		lines.append(_row("HV I", data["current_hv"], "%.3f A"))
		lines.append(_row("LV I", data.get("current_lv", "---"), "%.3f A"))
	else:
		lines.append(_row("Current", data.get("current_a"), "%.3f A"))

	var pw_raw: Variant = data.get("power_w", null)
	if pw_raw != null:
		var pw_lbl: String = data.get("power_label", "Power")
		lines.append(_row(pw_lbl if not pw_lbl.is_empty() else "Power", pw_raw, "%.2f W"))
	if data.has("total_power_kw"):
		lines.append(_row("Total",    data["total_power_kw"],  "%.3f kW"))
	if data.has("power_factor"):
		lines.append(_row("PF",       data["power_factor"],    "%.2f"))
	if data.has("dissipation_w"):
		lines.append(_row("Dissip.",  data["dissipation_w"],   "%.2f W"))
	if data.has("load_percent"):
		lines.append(_row("Load",     data["load_percent"],    "%.0f %%"))
	if data.has("efficiency"):
		lines.append(_row("Effic.",   data["efficiency"],      "%.1f %%"))
	if data.has("voltage_regulation"):
		lines.append(_row("Reg.",     data["voltage_regulation"], "%.2f %%"))
	if data.has("resistance_ohm"):
		lines.append(_row("R (hot)",  data["resistance_ohm"],       "%.4f Ω"))
		lines.append(_row("R (cold)", data.get("resistance_cold_ohm", "---"), "%.4f Ω"))
	if data.has("rated_current_a"):
		lines.append(_row("Rated I",  data["rated_current_a"],  "%.0f A"))
	if data.has("thermal_energy_pct"):
		lines.append(_row("Fuse therm", data["thermal_energy_pct"], "%.0f %%"))
	if data.has("tap_position"):
		lines.append("[color=silver]Tap:[/color] [b]%s[/b]" % str(data["tap_position"]))
	if data.has("losses"):
		lines.append(_row("Losses",   data["losses"],           "%.3f kW"))
	if data.has("neutral_status"):
		lines.append("[color=silver]Neutral:[/color] [b]%s[/b]" % str(data["neutral_status"]))
	if data.has("pe_status"):
		lines.append("[color=silver]PE:[/color] [b]%s[/b]" % str(data["pe_status"]))
	if data.has("temperature_c"):
		lines.append(_row("Temp.",    data["temperature_c"],    "%.1f °C"))
	if data.has("cook_mode"):
		lines.append("[color=silver]Mode:[/color] [b]%s[/b]" % str(data["cook_mode"]))
	if data.has("target_temp_c"):
		lines.append(_row("Target T", data["target_temp_c"],    "%.0f °C"))
	if data.has("temp_progress_pct"):
		lines.append(_row("Progress", data["temp_progress_pct"], "%.0f %%"))
	if data.has("length_m"):
		lines.append(_row("Length",   data["length_m"],         "%.1f m"))
	if data.has("cross_mm2"):
		lines.append(_row("Cross",    data["cross_mm2"],        "%.1f mm²"))
	lines.append(_row("State", data.get("state"), "%s"))

func _add_thermal_lines(data: Dictionary, lines: Array) -> void:
	var level: String = str(data.get("thermal_level", "?"))
	var col: String
	match level:
		"Normal": col = "green"
		"Warm":   col = "yellow"
		"Hot":    col = "orange"
		_:        col = "red"

	lines.append(_row("Temperature",  data.get("temperature_c"), "%.1f °C"))
	lines.append("[color=%s][b]Level: %s[/b][/color]" % [col, level])

	if data.has("ambient_c"):
		lines.append(_row("Ambient",    data["ambient_c"],          "%.1f °C"))
	if data.has("insulation_limit_c"):
		lines.append(_row("Ins. limit", data["insulation_limit_c"], "%.0f °C"))
	if data.has("target_temp_c"):
		lines.append(_row("Target",     data["target_temp_c"],      "%.0f °C"))
	if data.has("temp_progress_pct"):
		lines.append(_row("Progress",   data["temp_progress_pct"],  "%.0f %%"))
	if data.has("heating_active"):
		lines.append("[color=silver]Heating:[/color] [b]%s[/b]" % str(data["heating_active"]))
	if data.has("cook_mode"):
		lines.append("[color=silver]Mode:[/color] [b]%s[/b]" % str(data["cook_mode"]))
	if data.has("thermal_energy_pct"):
		lines.append(_row("Fuse therm", data["thermal_energy_pct"], "%.0f %%"))
	if data.has("load_percent"):
		lines.append(_row("Load",       data["load_percent"],       "%.0f %%"))
	if data.has("dissipation_w"):
		lines.append(_row("Dissip.",    data["dissipation_w"],      "%.2f W"))

func _add_clamp_lines(data: Dictionary, lines: Array) -> void:
	if data.get("is_3ph", false):
		lines.append(_row("L1",   data.get("current_l1"), "%.3f A"))
		lines.append(_row("L2",   data.get("current_l2"), "%.3f A"))
		lines.append(_row("L3",   data.get("current_l3"), "%.3f A"))
		if data.has("current_n"):
			lines.append(_row("N", data["current_n"],     "%.3f A"))
		lines.append(_row("Avg",  data.get("current_avg"), "%.3f A"))
		lines.append(_row("Max",  data.get("current_max"), "%.3f A"))
		lines.append(_row("Rated",data.get("max_current_a"), "%.0f A"))
		lines.append(_row("Load", data.get("loading"),     "%s"))
		var upct: float = float(data.get("unbalance_pct", 0.0))
		if upct > 0.5:
			var ucol: String = "yellow" if upct < 10.0 else "red"
			lines.append("[color=%s]Unbalance: %.1f %%[/color]" % [ucol, upct])
	elif data.has("current_hv"):
		lines.append(_row("HV I", data.get("current_hv"),   "%.3f A"))
		lines.append(_row("LV I", data.get("current_lv"),   "%.3f A"))
		lines.append(_row("Load", data.get("load_percent"), "%.0f %%"))
	else:
		lines.append(_row("Current",   data.get("current_a"),    "%.3f A"))
		lines.append(_row("Max rated", data.get("max_current_a"),"%.0f A"))
		lines.append(_row("Loading",   data.get("loading"),      "%s"))
		if data.has("thermal_energy_pct"):
			lines.append(_row("Fuse therm", data["thermal_energy_pct"], "%.0f %%"))
		if data.has("temperature_c"):
			lines.append(_row("Temp.",      data["temperature_c"],      "%.1f °C"))
		if data.has("load_percent"):
			lines.append(_row("Load",       data["load_percent"],       "%.0f %%"))

	if data.get("overloaded", false):
		lines.append("[color=red][b]⚠ OVERLOADED[/b][/color]")

static func _row(label: String, value: Variant, fmt: String) -> String:
	var val_str: String
	if fmt.is_empty():
		val_str = str(value)
	elif value is float or value is int:
		val_str = fmt % float(value)
	else:
		val_str = str(value)
	return "[color=silver]%s:[/color] [b]%s[/b]" % [label, val_str]

# ── Fault injection ───────────────────────────────────────────────────────────

func _fault_button(label: String, type: int) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(func(): _on_inject_fault(type))
	return btn

func _on_inject_fault(type: int) -> void:
	if _target == null:
		return
	# read phase selectors and cross flag, emit extended signal
	var p_a: int = -1
	var p_b: int = -1
	var cross: bool = false
	var opt_a: OptionButton = _fault_section.get_node("phase_a") if _fault_section.has_node("phase_a") else null
	var opt_b: OptionButton = _fault_section.get_node("phase_b") if _fault_section.has_node("phase_b") else null
	var chk: CheckBox = _fault_section.get_node("cross_node") if _fault_section.has_node("cross_node") else null
	if opt_a != null:
		p_a = opt_a.get_selected_id()
	if opt_b != null:
		p_b = opt_b.get_selected_id()
	if chk != null:
		cross = chk.button_pressed

	emit_signal("inject_fault_requested", _target, type, p_a, p_b, cross)
	_lbl_fault_status.text = "Fault injected: %s" % FaultManager.type_to_string(type)

func _on_clear_faults() -> void:
	if _target == null:
		return
	emit_signal("clear_faults_requested", _target)
	_lbl_fault_status.text = "Faults cleared"
