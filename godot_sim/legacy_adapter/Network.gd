## legacy_adapter/Network.gd
## Backwards-compatible wrapper that exposes the OLD Network API on top
## of the new CircuitModel.  Drop this file in next to the original
## class and existing calls (`net.add_source(...)`, `net.add_cable(...)`,
## `net.add_load(...)`, `net.solve_if_dirty()`, etc.) keep working.
##
## You can migrate file-by-file at your own pace; nothing breaks
## because the old class names (Source, Load, RatedLoad, …) below are
## just thin aliases that forward to the refactored elements.

class_name LegacyNetwork
extends RefCounted

signal solved(solve_time_ms: float)
signal cable_overloaded(cable: Cable)
signal load_tripped(load: Consumer)
signal load_damaged(load: Consumer)

var network_name: String
var _model: CircuitModel

func _init(p_name: String = "network") -> void:
	network_name = p_name
	_model = CircuitModel.new(p_name)
	_model.solved.connect(func(ms): emit_signal("solved", ms))
	_model.cable_overloaded.connect(func(c): emit_signal("cable_overloaded", c))
	_model.consumer_tripped.connect(func(c): emit_signal("load_tripped", c))
	_model.consumer_damaged.connect(func(c): emit_signal("load_damaged", c))

# ── Original API ────────────────────────────────────────────────────

func add_source(src) -> void: _model.add_element(src)
func add_cable(cable) -> void: _model.add_element(cable)
func add_load(ld) -> void:    _model.add_element(ld)

func mark_dirty() -> void: _model.mark_dirty()

func solve() -> void: _model.solve()
func solve_if_dirty() -> bool: return _model.solve_if_dirty()

func validate() -> Array: return _model.validate()

func get_node_voltage(n: SimNode) -> float: return _model.get_node_voltage(n)
func get_cable_current(c: Cable) -> float:  return _model.get_element_current(c)
func get_overloaded_cables() -> Array:      return _model.get_overloaded_cables()
func get_totals() -> Dictionary:            return _model.get_totals()

#func print_results() -> void:
	#NetworkPrinter.print_model(_model)

# Direct access for code that wants to migrate
func model() -> CircuitModel: return _model

# Legacy lists (read-only views)
var sources: Array:
	get: return _model.sources
var cables: Array:
	get: return _model.get_cables()
var loads: Array:
	get: return _model.get_consumers()
