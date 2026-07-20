## test_fuse_trip.gd
## Verifies fuse self-blow under overcurrent and the resulting
## power loss downstream.

extends RefCounted

static func run() -> void:
	print("\n── TEST: fuse blow under overcurrent ──")

	var grid    := SimNode.new("grid")
	var bus_in  := SimNode.new("bus_in")
	var bus_out := SimNode.new("bus_out")

	var src   := VoltageSource.new(grid, 230.0, 0.0, "src")
	var feed  := Cable.new(grid, bus_in, 10.0, 6.0, "copper", 100.0, "feeder")
	var fuse  := Fuse.new(bus_in, bus_out, 5.0, false, "F1")  # 5 A rating
	var heavy := RatedConsumer.new(bus_out, 5000.0, 1.0, "heater")  # ~21 A

	var model := CircuitModel.new("fuse_test")
	model.fuse_blew.connect(func(f): print("  ⚡ fuse blew: %s" % f.element_name))

	model.add_element(src)
	model.add_element(feed)
	model.add_element(fuse)
	model.add_element(heavy)

	model.solve()
	print("  1st solve: heater V = %.2f V, fuse blown=%s" % [
		model.get_node_voltage(bus_out), str(fuse.blown)
	])

	# After fuse blows it sets dirty → next solve should isolate the load
	model.solve_if_dirty()
	print("  2nd solve: heater V = %.2f V (expect ~0), fuse blown=%s" % [
		model.get_node_voltage(bus_out), str(fuse.blown)
	])
