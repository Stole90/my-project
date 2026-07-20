## FaultManagerNode.gd
## Game-layer Node that drives the simulation-layer FaultManager.
##
## Place once as a child of the World node (world.gd creates it in _ready()).
## Ticks the FaultManager every physics frame and re-emits its signals
## as named Godot signals so UI / visual nodes can subscribe without
## depending on the simulation layer directly.
##
## Public API (called by UI / other game scripts):
##   inject_fault(element, type, magnitude) -> FaultRecord
##   clear_fault(record)
##   clear_all()
##   enable_random_faults(element, prob_per_sec, type, magnitude)
##   disable_random_faults(element)
##   has_fault(element) -> bool
##   get_faults_for(element) -> Array[FaultRecord]

class_name FaultManagerNode
extends Node

# ── Signals ───────────────────────────────────────────────────────────

signal fault_applied(element_name: String, fault_type: String)
signal fault_cleared(element_name: String)
signal random_fault_triggered(element_name: String, fault_type: String)

# ── Public properties ─────────────────────────────────────────────────

## Direct access to the simulation-layer manager (for advanced use).
var fault_manager: FaultManager

var _model: CircuitModel = null

# ── Lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	fault_manager = FaultManager.new()
	fault_manager.fault_applied.connect(_on_fault_applied)
	fault_manager.fault_cleared.connect(_on_fault_cleared)
	fault_manager.random_fault_triggered.connect(_on_random_fault)

## Bind this node to the circuit model.  Call from world.gd after model creation.
func set_model(model: CircuitModel) -> void:
	_model = model

# ── Frame tick ────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _model == null or fault_manager == null:
		return
	fault_manager.tick_random(delta, _model)

# ── Intentional fault API ─────────────────────────────────────────────

## Inject a fault on any CircuitElement.
## Returns the FaultRecord — keep it to call clear_fault() later.
func inject_fault(
	element:   CircuitElement,
	type:      int   = FaultManager.FaultType.OPEN_CIRCUIT,
	magnitude: float = 1.0,
	phase:     int   = -1,
	phase_b:   int   = -1
) -> FaultManager.FaultRecord:
	if _model == null or fault_manager == null:
		push_warning("FaultManagerNode: set_model() must be called before inject_fault().")
		return null
	return fault_manager.apply_fault(element, type, magnitude, _model, false, phase, phase_b)

## Clear one specific fault record.
func clear_fault(rec: FaultManager.FaultRecord) -> void:
	if _model == null or rec == null:
		return
	fault_manager.clear_fault(rec, _model)

## Clear every active fault in the model.
func clear_all() -> void:
	if _model == null:
		return
	fault_manager.clear_all_faults(_model)

## Clear all faults on one element.
func clear_faults_for(element: CircuitElement) -> void:
	if _model == null or element == null:
		return
	fault_manager.clear_faults_for(element, _model)

# ── Random fault configuration ────────────────────────────────────────

## Enable random fault generation for `element`.
## `prob_per_sec` — probability per second (0.005 ≈ one fault every ~200 s).
func enable_random_faults(
	element:      CircuitElement,
	prob_per_sec: float,
	type:         int   = FaultManager.FaultType.OPEN_CIRCUIT,
	magnitude:    float = 10.0
) -> void:
	if fault_manager == null:
		return
	fault_manager.enable_random_faults(element, prob_per_sec, type, magnitude)

## Remove random fault generation for `element`.
func disable_random_faults(element: CircuitElement) -> void:
	if fault_manager == null:
		return
	fault_manager.disable_random_faults(element)

# ── Query helpers ─────────────────────────────────────────────────────

func has_fault(element: CircuitElement) -> bool:
	if fault_manager == null or element == null:
		return false
	return fault_manager.has_fault(element)

func get_faults_for(element: CircuitElement) -> Array:
	if fault_manager == null or element == null:
		return []
	return fault_manager.get_faults_for(element)

func get_all_active_faults() -> Array:
	if fault_manager == null:
		return []
	return fault_manager.get_all_active_faults()

# ── Signal forwarding ─────────────────────────────────────────────────

func _on_fault_applied(rec: FaultManager.FaultRecord) -> void:
	emit_signal("fault_applied",
		rec.element.element_name,
		FaultManager.type_to_string(rec.fault_type))

func _on_fault_cleared(rec: FaultManager.FaultRecord) -> void:
	emit_signal("fault_cleared", rec.element.element_name)

func _on_random_fault(rec: FaultManager.FaultRecord) -> void:
	emit_signal("random_fault_triggered",
		rec.element.element_name,
		FaultManager.type_to_string(rec.fault_type))
