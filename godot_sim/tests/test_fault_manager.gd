## test_fault_manager.gd
## Headless test for FaultManager simulation integration.
## Run: godot4 --headless --script godot_sim/tests/test_fault_manager.gd

extends SceneTree

const SimNodeC      := preload("res://godot_sim/simulation/SimNode.gd")
const CircuitModelC := preload("res://godot_sim/simulation/CircuitModel.gd")
const VoltSrcC      := preload("res://godot_sim/simulation/elements/VoltageSource.gd")
const CableC        := preload("res://godot_sim/simulation/elements/Cable.gd")
const RatedConsC    := preload("res://godot_sim/simulation/elements/RatedConsumer.gd")
const FaultMgrC     := preload("res://godot_sim/simulation/FaultManager.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("=== FaultManager test ===")

	var bus_src  := SimNodeC.new("src")
	var bus_load := SimNodeC.new("load")
	var model    := CircuitModelC.new("fault_test")

	var vsrc  := VoltSrcC.new(bus_src, 230.0, 0.0, "grid")
	model.add_element(vsrc)

	var cable := CableC.new(bus_src, bus_load, 10.0, 4.0, "copper", 16.0, "main_cable")
	model.add_element(cable)

	var load := RatedConsC.new(bus_load, 500.0, 1.0, "heater", 230.0, false)
	model.add_element(load)

	model.solve()
	_check("Initial solve OK",         model.last_solved_ok)
	var i_before: float = cable.current.magnitude() if cable.current else 0.0
	_check("Current > 0 before fault", i_before > 0.0)

	var fm := FaultMgrC.new()

	# ── OPEN_CIRCUIT ─────────────────────────────────────────────────
	var rec_open := fm.apply_fault(cable, FaultMgrC.FaultType.OPEN_CIRCUIT, 1.0, model, false)
	model.solve()
	var i_open: float = cable.current.magnitude() if cable.current else 0.0
	_check("OPEN_CIRCUIT: cable disabled",  not cable.enabled)
	_check("OPEN_CIRCUIT: current ≈ 0",     i_open < 0.01)
	_check("FaultRecord active",            rec_open.active)
	_check("has_fault() true",              fm.has_fault(cable))

	fm.clear_fault(rec_open, model)
	model.solve()
	var i_after: float = cable.current.magnitude() if cable.current else 0.0
	_check("After clear: cable re-enabled",   cable.enabled)
	_check("After clear: current restored",   i_after > 0.1)
	_check("FaultRecord no longer active",    not rec_open.active)
	_check("has_fault() false after clear",   not fm.has_fault(cable))

	# ── HIGH_RESISTANCE ───────────────────────────────────────────────
	var ageing_before: float = cable.ageing_factor
	var rec_hr := fm.apply_fault(cable, FaultMgrC.FaultType.HIGH_RESISTANCE, 50.0, model, false)
	_check("HIGH_RESISTANCE: ageing_factor = 50",
		absf(cable.ageing_factor - 50.0) < 0.01)
	model.solve()
	var i_hr: float = cable.current.magnitude() if cable.current else 0.0
	_check("HIGH_RESISTANCE: current still > 0", i_hr > 0.0)
	fm.clear_fault(rec_hr, model)
	_check("HIGH_RESISTANCE cleared: ageing restored",
		absf(cable.ageing_factor - ageing_before) < 0.01)

	# ── get_all_active_faults ─────────────────────────────────────────
	var _rec_a := fm.apply_fault(cable, FaultMgrC.FaultType.OPEN_CIRCUIT, 1.0, model, false)
	_check("get_all_active_faults has 1 entry",
		fm.get_all_active_faults().size() == 1)
	fm.clear_all_faults(model)
	_check("After clear_all: no active faults",
		fm.get_all_active_faults().size() == 0)

	# ── type_to_string helper ─────────────────────────────────────────
	_check("type_to_string OPEN_CIRCUIT",
		FaultMgrC.type_to_string(FaultMgrC.FaultType.OPEN_CIRCUIT) == "Open Circuit")
	_check("type_to_string HIGH_RESISTANCE",
		FaultMgrC.type_to_string(FaultMgrC.FaultType.HIGH_RESISTANCE) == "High Resistance")

	print("Passed: %d  Failed: %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  ✓ %s" % label)
		_passed += 1
	else:
		print("  ✗ FAIL: %s" % label)
		_failed += 1
