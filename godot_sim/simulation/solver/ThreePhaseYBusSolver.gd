## ThreePhaseYBusSolver.gd
## Steady-state AC solver for 5-conductor (L1, L2, L3, N, PE) networks.
##
## ── Matrix layout ─────────────────────────────────────────────────────────────
##
##   For N unique SimNodes the system matrix is 5N × 5N.
##   Row/column index for node n on phase ph:
##       row = node_global_idx[n] * 5 + ph
##   (ph is Phase.L1=0 … Phase.PE=4)
##
##   np_idx   : Dictionary  "nodeId:phaseInt" → matrix row (int)
##   source_np: Dictionary  "nodeId:phaseInt" → [SimNode, phase_id]
##
## ── Backward compatibility ────────────────────────────────────────────────────
##
##   Single-phase elements call stamp_ybus_3ph() which falls back to stamp_ybus()
##   on the L1 rows — so every existing element works unchanged.
##   NEUTRAL and PE rows exist for every node; elements only stamp them when they
##   have a neutral or PE conductor.
##
## ── Source-current computation ────────────────────────────────────────────────
##
##   I_src[row] = (Y_orig_row * V_solved) − I_inj_orig[row]

class_name ThreePhaseYBusSolver
extends CircuitSolver

const CONDUCTORS_PER_NODE: int = 5

func solve(model) -> Dictionary:
	var t0: float = Time.get_ticks_usec() / 1e6

	# ── 1. Validate ───────────────────────────────────────────────────
	var issues: Array = model.validate()
	if issues.size() > 0:
		return {"ok": false, "solve_ms": 0.0, "errors": issues}

	var nodes: Array = model.nodes
	var N: int       = nodes.size()
	if N == 0:
		return {"ok": false, "solve_ms": 0.0, "errors": ["empty network"]}

	var DIM: int = CONDUCTORS_PER_NODE * N

	# ── 2. Index nodes ────────────────────────────────────────────────
	var node_by_id: Dictionary = {}
	for i in range(N):
		node_by_id[nodes[i].id] = nodes[i]

	# np_idx: "nodeId:phase" → matrix row (all 5 conductors per node)
	var np_idx: Dictionary = {}
	for i in range(N):
		for ph in Phase.all_conductors():
			np_idx[nodes[i].id + ":" + str(ph)] = i * CONDUCTORS_PER_NODE + ph

	# ── 3. Collect slack (source) node-phase pairs ────────────────────
	var source_np: Dictionary = {}
	for elem in model.elements:
		for pair in elem.slack_node_phases():
			var sn: SimNode = pair[0]
			var ph: int     = pair[1]
			var key: String = sn.id + ":" + str(ph)
			source_np[key] = pair

	# ── 4. Initialise 5N × 5N matrix ─────────────────────────────────
	var Y: Array     = CircuitSolver.make_complex_matrix(DIM, DIM)
	var I_inj: Array = CircuitSolver.make_complex_vector(DIM)

	# G_FLOOR shunt on every non-source row (prevents singularity)
	for key in np_idx:
		if not source_np.has(key):
			var row: int = np_idx[key]
			Y[row][row].re += SimConstants.G_FLOOR

	# ── 5. Stamp every enabled element ───────────────────────────────
	for elem in model.elements:
		if elem.enabled:
			elem.stamp_ybus_3ph(Y, I_inj, np_idx, source_np)

	# Stamp grounding system if present
	if model.grounding_system != null:
		model.grounding_system.stamp_ybus_3ph(Y, I_inj, np_idx, source_np)

	# ── 6. Save ONLY source rows as flat PackedFloat64Array ─────
	var Y_orig_rows: Dictionary = {}
	var I_inj_orig: PackedFloat64Array = PackedFloat64Array()
	I_inj_orig.resize(DIM * 2)

	for i in range(DIM):
		I_inj_orig[i * 2]     = I_inj[i].re
		I_inj_orig[i * 2 + 1] = I_inj[i].im

	for key in source_np:
		var row: int = np_idx[key]
		var flat: PackedFloat64Array = PackedFloat64Array()
		flat.resize(DIM * 2)
		for j in range(DIM):
			flat[j * 2]     = Y[row][j].re
			flat[j * 2 + 1] = Y[row][j].im
		Y_orig_rows[row] = flat

	# ── 7. Slack-node substitution ────────────────────────────────────
	for key in source_np:
		var pair: Array = source_np[key]
		var sn: SimNode = pair[0]
		var ph: int     = pair[1]
		var row: int    = np_idx[key]
		var v: Complex  = sn.get_voltage(ph)
		for j in range(DIM):
			Y[row][j] = Complex.zero()
		Y[row][row] = Complex.one()
		I_inj[row]  = v.copy() if v != null else Complex.zero()

	# ── 8. Solve ──────────────────────────────────────────────────────
	var V_solved: Array = CircuitSolver.gaussian_elimination(Y, I_inj)
	if V_solved.is_empty():
		return {
			"ok": false,
			"solve_ms": (Time.get_ticks_usec() / 1e6 - t0) * 1000.0,
			"errors": ["singular admittance matrix — isolated node or conflicting sources?"],
		}

	# ── 9. Write voltages back to SimNodes ────────────────────────────
	for key in np_idx:
		if source_np.has(key):
			continue
		var row: int     = np_idx[key]
		var parts: Array = key.split(":")
		var n: SimNode   = node_by_id[parts[0]]
		var ph: int      = int(parts[1])
		n.set_voltage(ph, V_solved[row])

	# ── 10. Update element internal states ────────────────────────────
	for elem in model.elements:
		elem.update_state_3ph(model.dt)

	# ── 11. Source currents via pre-substitution KCL ──────────────────
	for elem in model.elements:
		if not elem.is_slack_source():
			continue
		for pair in elem.slack_node_phases():
			var sn: SimNode = pair[0]
			var ph: int     = pair[1]
			var key: String = sn.id + ":" + str(ph)
			if not np_idx.has(key):
				continue
			var row: int = np_idx[key]
			if not Y_orig_rows.has(row):
				continue
			var flat: PackedFloat64Array = Y_orig_rows[row]
			var i_re: float = 0.0
			var i_im: float = 0.0
			for j in range(DIM):
				var v_re: float = V_solved[j].re
				var v_im: float = V_solved[j].im
				var y_re: float = flat[j * 2]
				var y_im: float = flat[j * 2 + 1]
				i_re += y_re * v_re - y_im * v_im
				i_im += y_re * v_im + y_im * v_re
			i_re -= I_inj_orig[row * 2]
			i_im -= I_inj_orig[row * 2 + 1]
			elem.currents_by_phase[ph] = Complex.new(i_re, i_im)
		if elem.currents_by_phase.has(Phase.L1):
			elem.current = elem.currents_by_phase[Phase.L1]

	return {
		"ok": true,
		"solve_ms": (Time.get_ticks_usec() / 1e6 - t0) * 1000.0,
		"errors": [],
	}

# ── Helper ────────────────────────────────────────────────────────────

## String key for (node, phase) pair — used by external callers.
static func np_key(node: SimNode, ph: int) -> String:
	return node.id + ":" + str(ph)
