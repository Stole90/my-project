# res://scripts/CableManager.gd
class_name CableManager
extends Node2D

signal cable_created(cable_node: CableNode)
signal three_phase_cable_created(cable_node: ThreePhaseCableNode)

var active: bool = false
var _from: Node2D = null        # bilo koji Node2D sa get_sim_bus()
var _preview_line: Line2D
var _model_ref: CircuitModel = null
var _waypoints: Array[Vector2] = []

## Params dict set by CableInspectorDialog before drafting starts.
## Keys: cable_label, cross_mm2, cable_core, max_current
var pending_params: Dictionary = {}

func _ready() -> void:
	_preview_line = Line2D.new()
	_preview_line.width = 3.0
	_preview_line.default_color = Color(1.0, 0.8, 0.0, 0.7)
	_preview_line.visible = false
	add_child(_preview_line)

func enter_cable_mode() -> void:
	active = true
	_from = null
	_waypoints.clear()
	_preview_line.visible = false
	_preview_line.clear_points()

## Enter cable mode with pre-selected parameters from the inspector dialog.
func enter_cable_mode_with_params(params: Dictionary) -> void:
	pending_params = params
	enter_cable_mode()

func exit_cable_mode() -> void:
	active = false
	_from = null
	_waypoints.clear()
	pending_params = {}
	_preview_line.visible = false
	_preview_line.clear_points()

## Returns true if the first endpoint has been selected (currently drawing).
func is_drawing() -> bool:
	return _from != null

## Add a visual waypoint (joint/turn) at the given global position.
func add_waypoint(global_pos: Vector2) -> void:
	if not active or _from == null:
		return
	_waypoints.append(global_pos)

## Prihvata bilo koji Node2D koji implementira get_sim_bus() -> SimNode.
## Vraća true kad je kabl kompletiran (drugi klik).
func handle_click(node: Node2D, model: CircuitModel) -> bool:
	if not active:
		return false
	if not node.has_method("get_sim_bus"):
		push_warning("CableManager: node '%s' nema get_sim_bus() metodu." % node.name)
		return false

	if _from == null:
		_from = node
		_preview_line.clear_points()
		_preview_line.add_point(to_local(node.global_position))
		_preview_line.add_point(to_local(node.global_position))
		_preview_line.visible = true
		return false

	if _from == node:
		return false  # klik na isti node — ignoriši

	_model_ref = model

	# Odluči tip kabla
	var use_3ph: bool = _both_are_three_phase(_from, node)
	if use_3ph:
		var cn3 := _spawn_three_phase_cable(_from, node)
		if cn3 == null:
			return false
		emit_signal("three_phase_cable_created", cn3)
	else:
		var cn := _spawn_cable(_from, node)
		if cn == null:
			return false
		emit_signal("cable_created", cn)

	exit_cable_mode()
	return true

func _spawn_cable(a: Node2D, b: Node2D) -> CableNode:
	var scene := preload("res://scenes/CableNode.tscn")
	var cn: CableNode = scene.instantiate() as CableNode
	if cn == null:
		push_error("CableManager: CableNode.tscn root node mora imati CableNode.gd script!")
		return null
	if not pending_params.is_empty():
		cn.cable_label  = pending_params.get("cable_label",  "%s_to_%s" % [a.name, b.name])
		cn.cross_mm2    = pending_params.get("cross_mm2",    cn.cross_mm2)
		cn.cable_core   = pending_params.get("cable_core",   cn.cable_core)
		cn.max_current  = pending_params.get("max_current",  cn.max_current)
	else:
		cn.cable_label = "%s_to_%s" % [a.name, b.name]
	add_child(cn)
	cn.setup(a, b, _model_ref, _waypoints.duplicate())
	# Cable Rating System (SRPS IEC 60364-5-52): route the full params dict
	# (installation_method, ambient_c, soil_type, ...) through the same
	# apply_params() wiring used by the inspector's EDIT mode — reuses the
	# existing mechanism instead of duplicating field assignment here.
	if not pending_params.is_empty():
		cn.apply_params(pending_params)
	return cn

func _process(_delta: float) -> void:
	if active and _from != null:
		_preview_line.clear_points()
		_preview_line.add_point(to_local(_from.global_position))
		for wp in _waypoints:
			_preview_line.add_point(to_local(wp))
		_preview_line.add_point(to_local(get_global_mouse_position()))

func _is_three_phase_node(n: Node2D) -> bool:
	return (
		n is ThreePhaseSourceNode or n is ThreePhaseOvenNode or
		n is ThreePhaseTransformerNode or n is ThreePhaseSocketAppliance or
		n is ThreePhaseSwitchNode or n is ThreePhaseFuseNode
	)

## Monofazni potrošač = BaseAppliance koji NIJE u trofaznoj listi
## (npr. Refrigerator, RatedConsumer-bazirani uređaji).
func _is_single_phase_appliance(n: Node2D) -> bool:
	return n is BaseAppliance and not _is_three_phase_node(n)

func _both_are_three_phase(a: Node2D, b: Node2D) -> bool:
	# Monofazni potrošač UVEK dobija monofazni kabl, čak i kad je druga
	# strana trofazna (npr. direktno na trofazni trafo/izvor).
	if _is_single_phase_appliance(a) or _is_single_phase_appliance(b):
		return false
	return _is_three_phase_node(a) or _is_three_phase_node(b)

func _spawn_three_phase_cable(a: Node2D, b: Node2D) -> ThreePhaseCableNode:
	var scene := preload("res://scenes/ThreePhaseCableNode.tscn")
	var cn: ThreePhaseCableNode = scene.instantiate() as ThreePhaseCableNode
	if cn == null:
		push_error("CableManager: ThreePhaseCableNode.tscn greška!")
		return null
	if not pending_params.is_empty():
		cn.cable_label = pending_params.get("cable_label", "%s_to_%s" % [a.name, b.name])
		cn.cross_mm2   = pending_params.get("cross_mm2",   cn.cross_mm2)
		cn.cable_core  = pending_params.get("cable_core",  cn.cable_core)
		cn.max_current = pending_params.get("max_current", cn.max_current)
	else:
		cn.cable_label = "%s_to_%s" % [a.name, b.name]
	add_child(cn)
	cn.setup(a, b, _model_ref, _waypoints.duplicate())
	# Cable Rating System (SRPS IEC 60364-5-52): same routing as _spawn_cable().
	if not pending_params.is_empty():
		cn.apply_params(pending_params)
	return cn
