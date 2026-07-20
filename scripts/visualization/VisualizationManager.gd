## VisualizationManager.gd
## Singleton (AutoLoad) that owns and switches visualization modes.
##
## ── Setup ─────────────────────────────────────────────────────────────────────
## Add to Project → Project Settings → AutoLoad:
##   Path:  res://scripts/visualization/VisualizationManager.gd
##   Name:  VisualizationManager
##
## ── Usage (from any scene/script) ─────────────────────────────────────────────
##   VisualizationManager.set_mode(&"normal")
##   VisualizationManager.set_mode(&"current")
##   VisualizationManager.set_mode(&"thermal")
##   VisualizationManager.set_mode(&"voltage_drop")
##   VisualizationManager.set_mode(&"power_loss")
##
##   var col: Color = VisualizationManager.get_cable_color(cable_node)
##   var cols: Array[Color] = VisualizationManager.get_3ph_cable_colors(cable_node, 3)
##
## ── Extending with new modes ───────────────────────────────────────────────────
##   1. Create a class that extends VisualizationMode.
##   2. Add one line to _build_modes() below: _register(MyNewMode.new())
##   3. Call set_mode(&"your_mode_id") anywhere.  Done.
##
## ── Performance notes ─────────────────────────────────────────────────────────
##   • Color is computed lazily inside _draw() calls — only when the node
##     actually redraws.  No per-frame polling.
##   • Mode switching calls queue_redraw() on ALL registered cable nodes once.
##     Non-cable nodes (appliances, fuses…) use modulate; they are updated in
##     batch via _refresh_all_components() which is deferred one frame so the
##     solver has time to post its final values.
##   • The solver is NEVER called from here.  All reads are vis_* cache fields.

#class_name VisualizationManager
extends Node

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted after the active mode has changed and all nodes have been told to redraw.
signal mode_changed(new_mode_id: StringName)

# ── State ─────────────────────────────────────────────────────────────────────

var _modes:       Dictionary   = {}   # StringName → VisualizationMode
var _active_mode: VisualizationMode = null

## Registered cable nodes (CableNode instances).  Populated automatically when
## CableNode calls VisualizationManager.register_cable().
var _cables:       Array[Node2D] = []
## Registered three-phase cable nodes (ThreePhaseCableNode instances).
var _cables_3ph:   Array[Node2D] = []
## Registered generic component nodes (appliances, fuses, sources, transformers…).
var _components:   Array[Node2D] = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_modes()
	# Start in Normal mode — reproduces pre-refactor appearance.
	_active_mode = _modes.get(&"normal", null)

# ── Mode registration ─────────────────────────────────────────────────────────

## Builds the mode registry.  ADD NEW MODES HERE — one line each.
func _build_modes() -> void:
	_register(NormalMode.new())
	_register(CurrentOverlayMode.new())
	_register(ThermalOverlayMode.new())
	_register(VoltageDropOverlayMode.new())
	_register(PowerLossOverlayMode.new())

func _register(mode: VisualizationMode) -> void:
	_modes[mode.mode_id] = mode

# ── Public API ────────────────────────────────────────────────────────────────

## Switch to a named mode.  Silently ignores unknown mode ids.
func set_mode(mode_id: StringName) -> void:
	var next: VisualizationMode = _modes.get(mode_id, null)
	if next == null:
		push_warning("VisualizationManager: unknown mode '%s'" % mode_id)
		return
	if next == _active_mode:
		return
	_active_mode = next
	_invalidate_all()
	emit_signal("mode_changed", mode_id)

## Returns the id of the currently active mode.
func get_active_mode_id() -> StringName:
	return _active_mode.mode_id if _active_mode != null else &""

## Returns all registered modes as an Array of Dictionaries with
## keys: id (StringName), display_name (String).
## Useful for building a mode-selector UI without hardcoding mode names.
func get_available_modes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mode_id in _modes:
		var m: VisualizationMode = _modes[mode_id]
		result.append({ "id": m.mode_id, "display_name": m.display_name })
	return result

# ── Color query API (called from _draw() of cable nodes) ─────────────────────

## Returns the line color for a single-phase CableNode.
## Called from CableNode._draw() — must be fast (no allocations if possible).
func get_cable_color(cable_node: Node2D) -> Color:
	if _active_mode == null:
		return Color(0.5, 0.5, 0.5)
	return _active_mode.get_cable_color(cable_node)

## Returns per-wire colors for a ThreePhaseCableNode.
## num_lines: 3 (L1/L2/L3) or 4 (with neutral N).
func get_3ph_cable_colors(cable_node: Node2D, num_lines: int) -> Array[Color]:
	if _active_mode == null:
		var fallback: Array[Color] = []
		for _i in num_lines:
			fallback.append(Color(0.5, 0.5, 0.5))
		return fallback
	return _active_mode.get_3ph_cable_colors(cable_node, num_lines)

## Returns a modulate color for a generic component node (appliance, fuse, etc.).
## Color.WHITE means "no overlay — keep the node's own _draw() colors."
func get_node_modulate(node: Node2D) -> Color:
	if _active_mode == null:
		return Color.WHITE
	return _active_mode.get_node_modulate(node)

# ── Node registration (called by component nodes in their setup()) ────────────

## Register a single-phase CableNode so it is invalidated on mode changes.
func register_cable(cable_node: Node2D) -> void:
	if cable_node not in _cables:
		_cables.append(cable_node)
		cable_node.tree_exited.connect(_cables.erase.bind(cable_node))

## Register a ThreePhaseCableNode.
func register_3ph_cable(cable_node: Node2D) -> void:
	if cable_node not in _cables_3ph:
		_cables_3ph.append(cable_node)
		cable_node.tree_exited.connect(_cables_3ph.erase.bind(cable_node))

## Register a generic component node (appliance, fuse, source, transformer…).
func register_component(node: Node2D) -> void:
	if node not in _components:
		_components.append(node)
		node.tree_exited.connect(_components.erase.bind(node))

# ── Internal refresh ──────────────────────────────────────────────────────────

## Force a redraw on every tracked node.  Called once per mode switch.
func _invalidate_all() -> void:
	for cn in _cables:
		if is_instance_valid(cn):
			cn.queue_redraw()
	for cn in _cables_3ph:
		if is_instance_valid(cn):
			cn.queue_redraw()
	# Component modulate is cheap — update immediately.
	call_deferred("_refresh_component_modulates")

## Update modulate on all registered component nodes according to the active mode.
## Deferred by one frame so the solver's latest vis_* values are in cache.
func _refresh_component_modulates() -> void:
	for node in _components:
		if not is_instance_valid(node):
			continue
		var col: Color = _active_mode.get_node_modulate(node) if _active_mode != null else Color.WHITE
		node.modulate = col
