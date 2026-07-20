## test_validation.gd
## Verifies the new validation and diagnostics APIs for the simulation core.

extends RefCounted

static func run() -> void:
	print("\n── TEST: validation and diagnostics ──")

	var model := CircuitModel.new("validation_test")
	var report := model.get_diagnostic_report()
	assert(not report.ok, "empty model should fail validation")
	assert(report.issues.size() > 0, "validation should report issues")
	print("  empty model validation OK: %s" % report.issues[0])

	var bus := SimNode.new("bus")
	var source := VoltageSource.new(bus, 230.0, 0.0, "src")
	var load := RatedConsumer.new(bus, 100.0, 1.0, "lamp")
	model.add_element(source)
	model.add_element(load)

	var valid_report := model.get_diagnostic_report()
	assert(valid_report.ok, "valid topology should pass validation")
	assert(valid_report.node_count == 1, "node registry should track the connected bus")
	print("  valid topology validation OK")

	var snapshot := model.get_state_snapshot()
	assert(snapshot.nodes.size() == 1, "state snapshot should include the bus node")
	assert(snapshot.elements.size() == 2, "state snapshot should include both elements")
	assert(snapshot.elements[source.id].enabled, "source should be enabled in the snapshot")
	assert(snapshot.nodes[bus.id].voltages[str(Phase.L1)].magnitude == null, "unsolved L1 voltage should be null")
	print("  state snapshot OK")

	var fm := FaultManager.new()
	var summary := fm.get_diagnostic_summary()
	assert(summary.active_faults == 0, "fault summary should start empty")
	print("  fault summary OK")
