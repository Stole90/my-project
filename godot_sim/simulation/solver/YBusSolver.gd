## YBusSolver.gd
## Steady-state AC solver — single-frequency phasor analysis.
##
## Algorithm (identical to the legacy Network.solve(), now decoupled
## from the model):
##   1. Index nodes 0..N-1.
##   2. Initialise an N×N complex matrix Y and an injection vector I.
##   3. Add a tiny ground shunt to every non-source node (G_FLOOR)
##      so isolated sub-networks do not produce a singular matrix.
##   4. For every enabled element, call element.stamp_ybus(Y, I, …).
##   5. Replace each source-node row with a slack identity row,
##      using the source's stamped voltage as the RHS.
##   6. Gauss-eliminate to get V.
##   7. Write voltages back into SimNodes; call element.update_state().
##   8. Compute source currents via KCL.
##
## The solver itself never looks at element subclasses — it just calls
## the polymorphic stamp_*/update_state methods.  New element types
## are plug-and-play.

class_name YBusSolver
extends CircuitSolver

func solve(model) -> Dictionary:
	var t0: float = Time.get_ticks_usec() / 1e6
	var errors: Array = []

	# ── 1. Validate ───────────────────────────────────────────────
	var issues: Array = model.validate()
	if issues.size() > 0:
		return {"ok": false, "solve_ms": 0.0, "errors": issues}

	var nodes: Array = model.nodes
	var N: int       = nodes.size()
	if N == 0:
		return {"ok": false, "solve_ms": 0.0, "errors": ["empty network"]}

	# ── 2. Index nodes ────────────────────────────────────────────
	var node_idx: Dictionary = {}
	for i in range(N):
		node_idx[nodes[i]] = i

	# Identify source (slack) nodes
	var source_nodes: Array = []
	for src in model.sources:
		if not source_nodes.has(src.node()):
			source_nodes.append(src.node())

	# ── 3. Build matrices ─────────────────────────────────────────
	var Y: Array     = CircuitSolver.make_complex_matrix(N, N)
	var I_inj: Array = CircuitSolver.make_complex_vector(N)

	# Ground floor on non-source nodes
	for n in nodes:
		if not source_nodes.has(n):
			Y[node_idx[n]][node_idx[n]].re += SimConstants.G_FLOOR

	# ── 4. Stamp every enabled element (polymorphic) ──────────────
	for elem in model.elements:
		if elem.enabled:
			elem.stamp_ybus(Y, I_inj, node_idx, source_nodes)

	# ── 5. Slack-node substitution ────────────────────────────────
	for src_node in source_nodes:
		var i: int = node_idx[src_node]
		for j in range(N):
			Y[i][j] = Complex.zero()
		Y[i][i] = Complex.one()
		I_inj[i] = src_node.voltage.copy() if src_node.voltage != null else Complex.zero()

	# ── 6. Solve ──────────────────────────────────────────────────
	var V_solved: Array = CircuitSolver.gaussian_elimination(Y, I_inj)
	if V_solved.is_empty():
		errors.append("singular admittance matrix — isolated node or conflicting sources?")
		return {"ok": false, "solve_ms": (Time.get_ticks_usec()/1e6 - t0)*1000.0, "errors": errors}

	# ── 7. Write voltages back ────────────────────────────────────
	for n in nodes:
		if not source_nodes.has(n):
			n.voltage = V_solved[node_idx[n]]

	# ── 8. Update each element's internal state ───────────────────
	for elem in model.elements:
		elem.update_state({}, model.dt)

	# ── 9. Source currents via KCL ────────────────────────────────
	for src in model.sources:
		var sn: SimNode = src.node()
		var I_total: Complex = Complex.zero()
		for elem in model.elements:
			if not elem.enabled or elem == src:
				continue
			# Cables / two-terminal: current sign depends on which terminal touches sn
			if elem.terminals.size() >= 2 and elem.has_method("update_state"):
				var has_a: bool = elem.terminals[0].has(sn)
				var has_b: bool = elem.terminals[1].has(sn)
				if has_a and elem.current != null:
					I_total.add_inplace(elem.current)
				elif has_b and elem.current != null:
					I_total.sub_inplace(elem.current)
			elif elem.terminals.size() == 1 and elem.terminals[0].has(sn) and elem.current != null:
				I_total.add_inplace(elem.current)
		src.current = I_total

	return {
		"ok": true,
		"solve_ms": (Time.get_ticks_usec()/1e6 - t0)*1000.0,
		"errors": [],
	}
