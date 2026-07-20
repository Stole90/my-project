## VisualizationModeSelector.gd
## Ready-to-use HBoxContainer that displays one button per visualization mode.
## Drop into any HUD scene — it reads available modes from VisualizationManager
## and rebuilds itself automatically.
##
## Usage:
##   1. Add a VisualizationModeSelector node to your HUD scene.
##   2. The node auto-populates with buttons on _ready().
##   3. Clicking a button calls VisualizationManager.set_mode(id).
##   4. The active button is highlighted; the rest are dimmed.
##
## Customise appearance via the @export variables or by attaching a Theme.

class_name VisualizationModeSelector
extends HBoxContainer

@export var active_color:   Color = Color(0.2, 0.7, 1.0)
@export var inactive_color: Color = Color(0.6, 0.6, 0.6)
@export var button_min_w:   int   = 110

## Optional label displayed before the buttons.
@export var show_label: bool = true

var _buttons: Dictionary = {}  # mode_id → Button

func _ready() -> void:
	if show_label:
		var lbl := Label.new()
		lbl.text = "Prikaz:"
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(lbl)

	#if not is_instance_valid(VisualizationManager):
		#push_warning("VisualizationModeSelector: VisualizationManager autoload nije pronađen.")
	#return

	_build_buttons()
	VisualizationManager.mode_changed.connect(_on_mode_changed)

func _build_buttons() -> void:
	var modes: Array[Dictionary] = VisualizationManager.get_available_modes()
	var active_id: StringName    = VisualizationManager.get_active_mode_id()

	for mode_info in modes:
		var mode_id: StringName    = mode_info["id"]
		var display_name: String   = mode_info["display_name"]

		var btn := Button.new()
		btn.text                          = display_name
		btn.custom_minimum_size           = Vector2(button_min_w, 0)
		btn.toggle_mode                   = false
		btn.modulate                      = active_color if mode_id == active_id else inactive_color
		btn.pressed.connect(_on_button_pressed.bind(mode_id))
		add_child(btn)
		_buttons[mode_id] = btn

func _on_button_pressed(mode_id: StringName) -> void:
	#if is_instance_valid(VisualizationManager):
	VisualizationManager.set_mode(mode_id)

func _on_mode_changed(new_id: StringName) -> void:
	for mode_id in _buttons:
		_buttons[mode_id].modulate = active_color if mode_id == new_id else inactive_color
