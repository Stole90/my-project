## test_dirty.gd
## Verifies the dirty-flag short-circuit:
##   - solve_if_dirty() runs when topology changes
##   - returns false when nothing has changed
##   - element-level mark_dirty() bubbles up to the model

extends RefCounted

static func run() -> void:
	print("\n── TEST: dirty-flag propagation ──")

	var bus := SimNode.new("bus")
	var src := VoltageSource.new(bus, 230.0, 0.0, "src")
	var ld  := RatedConsumer.new(bus, 100.0, 1.0, "lamp")

	var model := CircuitModel.new("dirty_test")
	model.add_element(src)
	model.add_element(ld)

	model.solve()
	assert(model.last_solved_ok, "first solve must succeed")
	print("  initial solve OK; bus V = %.2f V" % model.get_node_voltage(bus))

	# Nothing changed → should NOT re-solve
	var ran1 := model.solve_if_dirty()
	print("  no change → ran=%s (expect false)" % str(ran1))
	assert(not ran1)

	# Element-level dirty → bubbles to model
	ld.disable()
	var ran2 := model.solve_if_dirty()
	print("  element dirty → ran=%s (expect true)" % str(ran2))
	assert(ran2)
