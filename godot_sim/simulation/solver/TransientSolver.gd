## TransientSolver.gd
## Time-stepped backward-Euler solver — Phase 0 SCAFFOLD.
##
## Status:
##   - Architecture is in place.
##   - Capacitor and Inductor already implement stamp_transient() and
##     advance their internal state correctly.
##   - This solver is *functional* for purely passive RLC networks
##     driven by an ideal voltage source, and is the planned host for
##     inrush-current effects, motor start-up dynamics, and switching
##     transients in a later phase.
##
## NOT yet implemented (intentionally — see README):
##   - Newton iteration for non-linear elements.
##   - Variable-step / adaptive Δt.
##   - Three-phase coupling.
##
## Calling convention is identical to YBusSolver.solve(model) but the
## caller must also set model.dt (seconds) before invoking.

class_name TransientSolver
extends CircuitSolver

func solve(model) -> Dictionary:
	var t0: float = Time.get_ticks_usec() / 1e6
	var dt: float = model.dt if model.dt > 0.0 else SimConstants.DEFAULT_DELTA_T

	var nodes: Array = model.nodes
	var N: int = nodes.size()
	if N == 0:
		return {"ok": false, "solve_ms": 0.0, "errors": ["empty network"]}

	var node_idx: Dictionary = {}
	for i in range(N):
		node_idx[nodes[i]] = i

	var source_nodes: Array = []
	for src in model.sources:
		if not source_nodes.has(src.node()):
			source_nodes.append(src.node())

	var Y: Array     = CircuitSolver.make_complex_matrix(N, N)
	var I_inj: Array = CircuitSolver.make_complex_vector(N)

	for n in nodes:
		if not source_nodes.has(n):
			Y[node_idx[n]][node_idx[n]].re += SimConstants.G_FLOOR

	for elem in model.elements:
		if elem.enabled:
			elem.stamp_transient(Y, I_inj, node_idx, dt, {}, source_nodes)

	for src_node in source_nodes:
		var i: int = node_idx[src_node]
		for j in range(N):
			Y[i][j] = Complex.zero()
		Y[i][i] = Complex.one()
		I_inj[i] = src_node.voltage.copy() if src_node.voltage != null else Complex.zero()

	var V_solved: Array = CircuitSolver.gaussian_elimination(Y, I_inj)
	if V_solved.is_empty():
		return {"ok": false, "solve_ms": 0.0, "errors": ["singular Y in transient step"]}

	for n in nodes:
		if not source_nodes.has(n):
			n.voltage = V_solved[node_idx[n]]

	for elem in model.elements:
		elem.update_state({}, dt)

	return {
		"ok": true,
		"solve_ms": (Time.get_ticks_usec()/1e6 - t0)*1000.0,
		"errors": [],
		"dt": dt,
	}
