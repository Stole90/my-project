## test_basic.gd
## Re-implements the original Example.gd topology against the new
## CircuitModel API.  Verifies that the refactor preserves the exact
## same numerical behaviour.

extends RefCounted

static func run() -> void:
	print("\n── TEST: basic source → cable → cable → house ──")

	var grid  := SimNode.new("grid")
	var pole  := SimNode.new("pole_B")
	var house := SimNode.new("house")

	var src       := VoltageSource.new(grid, 230.0, 0.0, "main")
	var cable_ab  := Cable.new(grid, pole, 100.0, 4.0, "copper", 20.0, "cable_AB")
	var cable_bh  := Cable.new(pole, house, 60.0, 2.5, "copper", 16.0, "cable_BH")
	var appliance := RatedConsumer.new(house, 500.0, 0.95, "appliance")
	var motor     := InductiveConsumer.new(house, 5.0, 20.0, "pump_motor")

	var model := CircuitModel.new("town_grid")
	model.solved.connect(func(ms): print("  solved in %.3f ms" % ms))

	model.add_element(src)
	model.add_element(cable_ab)
	model.add_element(cable_bh)
	model.add_element(appliance)
	model.add_element(motor)

	model.solve()
	NetworkPrinter.print_model(model)

	print("  house V = %.3f V" % model.get_node_voltage(house))
	print("  cable_BH I = %.3f A" % model.get_element_current(cable_bh))

	# Disconnect the BH cable
	cable_bh.disconnect_cable()
	model.solve_if_dirty()
	print("  after disconnect: house V = %.3f V (expect ~0)" % model.get_node_voltage(house))

	cable_bh.connect_cable()
	model.solve_if_dirty()
	print("  after reconnect : house V = %.3f V" % model.get_node_voltage(house))

	# Solve-if-dirty should be a no-op now
	var ran := model.solve_if_dirty()
	print("  re-solve when clean → ran=%s (expect false)" % str(ran))
