# res://scripts/ui/base/ModeDialog.gd
## Generic mode-selector dialog.
## Replaces the near-identical BoilerModeDialog / OvenModeDialog / RefrigeratorModeDialog.
##
## Configure via @export vars, populate `modes` in the subclass _ready(), then call
## open_with_mode(current_key).  Emits mode_confirmed(key) on "Primeni".
##
## Each entry in `modes` must have String keys: "key", "label", "power", "temp".
##
## Example subclass (BoilerModeDialog):
##   class_name BoilerModeDialog extends ModeDialog
##   func _ready() -> void:
##       dialog_title = "Mod bojlera"
##       modes = [ { "key": "off", "label": "Isključen", "power": "0 W", "temp": "—" }, ... ]
##       super._ready()

class_name ModeDialog
extends BasePanel

## Emitted when the user presses "Primeni".
signal mode_confirmed(mode_key: String)
## Emitted when the user presses "Otkaži" or the panel is closed without confirming.
signal cancelled()

# ── Configuration (set before _ready or in subclass _ready before super) ─────

@export var dialog_title:    String      = "Izbor moda"
## Minimum column widths: [label_btn, power_col, temp_col]
@export var column_widths:   Array[int]  = [140, 70, 70]

## Array[Dictionary] — each dict must have keys: key, label, power, temp.
## Populate in subclass _ready() before calling super._ready().
var modes: Array[Dictionary] = []

# ── Internal ──────────────────────────────────────────────────────────────────

var _mode_buttons:  Array[Button] = []
var _selected_mode: String        = ""
var _lbl_title:     Label

# ── BasePanel override ────────────────────────────────────────────────────────

func _build_content(container: VBoxContainer) -> void:
	# Compute minimum width from column widths sum + margins
	custom_minimum_size.x = column_widths.reduce(
		func(acc: int, w: int) -> int: return acc + w, 0) + 28

	# Title
	_lbl_title = Label.new()
	_lbl_title.text = dialog_title
	_lbl_title.add_theme_font_size_override("font_size", 16)
	container.add_child(_lbl_title)

	container.add_child(HSeparator.new())

	# Header row
	var header := HBoxContainer.new()
	_add_header_cell(header, "Mod",   column_widths[0])
	_add_header_cell(header, "Snaga", column_widths[1])
	_add_header_cell(header, "Temp.", column_widths[2])
	container.add_child(header)

	# One row per mode
	_mode_buttons.clear()
	for m: Dictionary in modes:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 0)

		var btn := Button.new()
		btn.text                  = m["label"]
		btn.custom_minimum_size.x = column_widths[0]
		btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode           = true
		btn.set_meta("mode_key",   m["key"])
		btn.pressed.connect(_on_mode_btn_pressed.bind(btn))
		hbox.add_child(btn)
		_mode_buttons.append(btn)

		var lp := Label.new()
		lp.text                  = m["power"]
		lp.custom_minimum_size.x = column_widths[1]
		hbox.add_child(lp)

		var lt := Label.new()
		lt.text                  = m["temp"]
		lt.custom_minimum_size.x = column_widths[2]
		hbox.add_child(lt)

		container.add_child(hbox)

	container.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	container.add_child(btn_row)

	var btn_ok := Button.new()
	btn_ok.text                  = "Primeni"
	btn_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_ok.pressed.connect(_on_confirm)
	btn_row.add_child(btn_ok)

	var btn_cancel := Button.new()
	btn_cancel.text                  = "Otkaži"
	btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cancel.pressed.connect(_on_cancel)
	btn_row.add_child(btn_cancel)

# ── Public API ────────────────────────────────────────────────────────────────

## Open the dialog and pre-select `current_mode` key.
func open_with_mode(current_mode: String) -> void:
	_selected_mode = current_mode
	_refresh_buttons()
	open()

# ── Handlers ──────────────────────────────────────────────────────────────────

func _on_mode_btn_pressed(btn: Button) -> void:
	_selected_mode = btn.get_meta("mode_key")
	_refresh_buttons()

func _on_confirm() -> void:
	emit_signal("mode_confirmed", _selected_mode)
	close()

func _on_cancel() -> void:
	emit_signal("cancelled")
	close()

func _refresh_buttons() -> void:
	for btn: Button in _mode_buttons:
		btn.button_pressed = (btn.get_meta("mode_key") == _selected_mode)

# ── Helpers ───────────────────────────────────────────────────────────────────

static func _add_header_cell(parent: HBoxContainer, text: String, min_w: int) -> void:
	var lbl := Label.new()
	lbl.text                  = text
	lbl.custom_minimum_size.x = min_w
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(lbl)
