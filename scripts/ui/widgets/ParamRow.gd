# res://scripts/ui/widgets/ParamRow.gd
## A single label + value row for use in any info or diagnostic panel.
## Instantiate once, call set_row() or set_value() to update.
##
## Usage:
##   var row := ParamRow.new()
##   container.add_child(row)
##   row.set_row("Napon", 230.5, "%.1f V")
##   # later, in refresh:
##   row.set_value(new_voltage, "%.1f V")

class_name ParamRow
extends HBoxContainer

@export var label_min_width: int = 120

var _lbl_key:   Label
var _lbl_value: Label

func _ready() -> void:
	_lbl_key = Label.new()
	_lbl_key.custom_minimum_size.x = label_min_width
	add_child(_lbl_key)

	_lbl_value = Label.new()
	_lbl_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_lbl_value)

## Set key label and formatted value in one call.
## fmt: printf-style format string (e.g. "%.2f V"), or "" for plain str().
func set_row(label: String, value: Variant, fmt: String = "") -> void:
	_lbl_key.text   = label + ":"
	_lbl_value.text = _fmt(value, fmt)

## Update only the value text without rebuilding the row.
func set_value(value: Variant, fmt: String = "") -> void:
	_lbl_value.text = _fmt(value, fmt)

## Apply a color tint to the value label (e.g. red on fault, green on OK).
func set_value_color(color: Color) -> void:
	_lbl_value.add_theme_color_override("font_color", color)

static func _fmt(val: Variant, fmt_str: String) -> String:
	if fmt_str.is_empty():
		return str(val)
	if val is float or val is int:
		return fmt_str % float(val)
	return str(val)
