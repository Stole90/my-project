## test_faults_phase.gd
## Verifies per-phase fault metadata and summary APIs.

extends RefCounted

static func run() -> void:
    print("\n── TEST: fault per-phase metadata ──")

    var bus_a := SimNode.new("A1")
    var bus_b := SimNode.new("B1")

    var model := CircuitModel.new("phase_fault_test")
    var src := VoltageSource.new(bus_a, 230.0, 0.0, "src")
    var cable := Cable.new(bus_a, bus_b, 10.0, 4.0, "copper", 16.0, "test_cable")
    model.add_element(src)
    model.add_element(cable)

    var fm := FaultManager.new()
    # Apply a global open-circuit
    var r1 := fm.apply_fault(cable, FaultManager.FaultType.OPEN_CIRCUIT, 1.0, model)
    assert(r1 != null and r1.active)

    # Apply a phase-annotated fault (phase value stored only)
    var r2 := fm.apply_fault(cable, FaultManager.FaultType.HIGH_RESISTANCE, 10.0, model, false, Phase.L2)
    assert(r2 != null and r2.active and r2.phase == Phase.L2)

    var summary := fm.get_diagnostic_summary_per_phase()
    assert(summary.total_active == 2)
    assert(summary.by_phase.global == 1)
    assert(summary.by_phase[str(Phase.L2)] == 1)

    # Apply a phase-specific short circuit and verify injected FaultElement
    var r3 := fm.apply_fault(cable, FaultManager.FaultType.SHORT_CIRCUIT, 1.0, model, false, Phase.L1)
    assert(r3 != null and r3.active)
    var active := fm.get_all_active_faults()
    var found_short := false
    for rec in active:
        if rec._short_cable != null and rec._short_cable is FaultElement:
            var fe := rec._short_cable as FaultElement
            if fe.fault_type == FaultElement.PHASE_SERIES_SHORT and fe.faulted_phase == Phase.L1:
                found_short = true
                break
    assert(found_short, "phase-series short should be injected as FaultElement")

    # Now test a line-to-line (L-L) short between L1 and L2 at the same bus
    var r4 := fm.apply_fault(cable, FaultManager.FaultType.SHORT_CIRCUIT, 0.001, model, false, Phase.L1, Phase.L2)
    assert(r4 != null and r4.active)
    var found_ll := false
    for rec in fm.get_all_active_faults():
        if rec._short_cable != null and rec._short_cable is FaultElement:
            var fe2 := rec._short_cable as FaultElement
            if fe2.fault_type == FaultElement.PHASE_TO_PHASE and fe2.faulted_phase == Phase.L1 and fe2.faulted_phase_b == Phase.L2:
                found_ll = true
                break
    assert(found_ll, "line-to-line short should be injected as FaultElement PHASE_TO_PHASE")

    print("  per-phase fault summary OK: %s" % summary)
