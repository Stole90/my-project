## headless_test.gd
## Run every test scene from a single entry-point WITHOUT any UI.
##
## In Godot 4:
##   - Attach this script to a Node, set it as the project's main scene,
##     OR call HeadlessTest.run_all() from any other script's _ready().

class_name HeadlessTest
extends RefCounted

static func run_all() -> void:
	print("\n" + "═".repeat(60))
	print("  GODOT_SIM  —  HEADLESS TEST RUN")
	print("═".repeat(60))

	var TestBasic = preload("res://godot_sim/tests/test_basic.gd")
	var TestDirty = preload("res://godot_sim/tests/test_dirty.gd")
	var TestFuse  = preload("res://godot_sim/tests/test_fuse_trip.gd")
	var TestValidation = preload("res://godot_sim/tests/test_validation.gd")
	var TestFaultPhase = preload("res://godot_sim/tests/test_faults_phase.gd")

	TestBasic.run()
	TestDirty.run()
	TestFuse.run()
	TestValidation.run()
	TestFaultPhase.run()

	print("\n" + "═".repeat(60))
	print("  TESTS COMPLETE")
	print("═".repeat(60) + "\n")
