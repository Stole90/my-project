## PoleNode.gd (refaktorisan)
## collapse/restore → PoleBridge.

class_name PoleNode
extends Node2D

@export var pole_name: String = "stub"

signal pole_collapsed()
signal pole_restored()

var _bus:    SimNode    = null
var _pole:   Pole       = null
var _bridge: PoleBridge = null

func setup_in(model: CircuitModel) -> void:
	_bus  = SimNode.new(pole_name)
	_pole = Pole.new(_bus, pole_name)
	model.add_element(_pole)

	_bridge = PoleBridge.new()
	_bridge.name = "%s_Bridge" % pole_name
	add_child(_bridge)
	_bridge.bind(_pole, model)

	_bridge.pole_collapsed.connect(func(): emit_signal("pole_collapsed"); queue_redraw())
	_bridge.pole_restored.connect(func():  emit_signal("pole_restored");  queue_redraw())
	_bridge.solved.connect(queue_redraw)

func get_sim_bus() -> SimNode: return _bus

# ── Game actions ──────────────────────────────────────────────────────────────

## Obori stub (storm, udes...).
func collapse() -> void:
	if _bridge != null: _bridge.collapse()

## Uspravi stub i popravi kablove.
func restore() -> void:
	if _bridge != null: _bridge.restore()

## Toggle: ako stoji → obori; ako je pao → uspravi.
func toggle() -> void:
	if _bridge != null: _bridge.interact_toggle()

func is_fallen() -> bool:
	return _bridge != null and _bridge.vis_fallen

## Zakači kabl za stub (za phase_loading prikaz u future).
func attach_cable(cable: Cable) -> void:
	if _pole != null: _pole.attach_cable(cable)

func detach_cable(cable: Cable) -> void:
	if _pole != null: _pole.detach_cable(cable)

func get_info() -> Dictionary:
	return _bridge.get_info() if _bridge != null else {"name": pole_name, "type": "Stub", "rows": []}

func _draw() -> void:
	if _bridge == null:
		draw_circle(Vector2.ZERO, 5.0, Color(0.5, 0.5, 0.5))
		return

	var col: Color
	if _bridge.vis_fallen:
		col = Color(0.8, 0.2, 0.0)
	elif _bridge.vis_damaged_cable_count > 0:
		col = Color(1.0, 0.6, 0.0)
	else:
		col = Color(0.55, 0.38, 0.2)  # boja drveta

	draw_circle(Vector2.ZERO, 5.0, col)

	# Vertikalna linija = stub; horizontalna = pao stub
	if _bridge.vis_fallen:
		draw_line(Vector2(-10, 0), Vector2(10, 0), col, 2.0)
	else:
		draw_line(Vector2(0, -18), Vector2(0, 8), col, 3.0)
		draw_line(Vector2(-8, -12), Vector2(8, -12), col, 2.0)
