## test_transformer_node.gd
## Headless test for Transformer simulation integration.
## Run: godot4 --headless --script godot_sim/tests/test_transformer_node.gd

extends SceneTree

const SimNodeC      := preload("res://godot_sim/simulation/SimNode.gd")
const CircuitModelC := preload("res://godot_sim/simulation/CircuitModel.gd")
const VoltSrcC      := preload("res://godot_sim/simulation/elements/VoltageSource.gd")
const CableC        := preload("res://godot_sim/simulation/elements/Cable.gd")
const TransDataC    := preload("res://godot_sim/simulation/elements/TransformerData.gd")
const TransformerC  := preload("res://godot_sim/simulation/elements/Transformer.gd")
const RatedConsC    := preload("res://godot_sim/simulation/elements/RatedConsumer.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("=== Transformer simulation test ===")

	var bus_src  := SimNodeC.new("src")
	var bus_hv   := SimNodeC.new("hv")
	var bus_lv   := SimNodeC.new("lv")
	var bus_load := SimNodeC.new("load")

	var model := CircuitModelC.new("xfmr_test")

	var vsrc := VoltSrcC.new(bus_src, 11000.0, 0.0, "grid")
	model.add_element(vsrc)

	var cable_hv := CableC.new(bus_src, bus_hv, 10.0, 25.0, "copper", 100.0, "hv_cable")
	model.add_element(cable_hv)

	var td := TransDataC.new()
	td.primary_voltage   = 11000.0
	td.secondary_voltage = 400.0
	td.rated_power_kva   = 100.0
	var xfmr := TransformerC.new(bus_hv, bus_lv, td, "main_xfmr")
	model.add_element(xfmr)

	var cable_lv := CableC.new(bus_lv, bus_load, 5.0, 10.0, "copper", 100.0, "lv_cable")
	model.add_element(cable_lv)

	var load := RatedConsC.new(bus_load, 10000.0, 0.9, "furnace", 400.0, false)
	model.add_element(load)

	model.solve()

	_check("Solver converged",                model.last_solved_ok)
	_check("Secondary voltage > 300 V",       xfmr.secondary_voltage_actual > 300.0)
	_check("Secondary voltage < 450 V",       xfmr.secondary_voltage_actual < 450.0)
	_check("Load percent > 0",                xfmr.load_percent > 0.0)
	_check("Efficiency > 0.9",                xfmr.efficiency_actual > 0.9)
	_check("Not overloaded at 10kW / 100kVA", not xfmr.is_overloaded)

	# Trip / repair cycle
	xfmr.trip()
	model.solve()
	_check("After trip: secondary_voltage = 0", xfmr.secondary_voltage_actual < 0.1)

	xfmr.repair()
	model.solve()
	_check("After repair: secondary_voltage > 300 V", xfmr.secondary_voltage_actual > 300.0)

	print("Passed: %d  Failed: %d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  ✓ %s" % label)
		_passed += 1
	else:
		print("  ✗ FAIL: %s" % label)
		_failed += 1
