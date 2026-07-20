## ThreePhaseConsumer.gd
## Three-phase load element: wye (L-N) or delta (L-L) connection.
##
## ── Wye (Y) connection ────────────────────────────────────────────────────────
##
##   Each phase connects from the phase conductor to neutral (ground).
##   The per-phase admittance is derived from the rated power and voltage:
##
##     Y_ph = conj(S_ph) / V_ln_nom²
##          = (P_ph − jQ_ph) / V_ln_nom²
##
##   Default stamp (use_explicit_neutral = false):
##     Y[ node_ph ][ node_ph ] += Y_ph   (return current flows to implicit ground)
##
##   Explicit-neutral stamp (use_explicit_neutral = true):
##     Y[ node_ph ][ node_ph ] += Y_ph
##     Y[ node_N  ][ node_N  ] += Y_ph
##     Y[ node_ph ][ node_N  ] -= Y_ph
##     Y[ node_N  ][ node_ph ] -= Y_ph
##
##   Use use_explicit_neutral = true whenever the network has a physical neutral
##   conductor (ThreePhaseCable with has_neutral() = true) so that return
##   current flows through the neutral bus rather than to the implicit ground.
##   This allows the solver to compute neutral voltage rise and I_N correctly.
##
## ── Delta (Δ) connection ──────────────────────────────────────────────────────
##
##   Each element connects between two line conductors of the same bus.
##   Pairs: (L1−L2), (L2−L3), (L3−L1).  Per-pair admittance:
##
##     Y_pair = conj(S_pair) / V_ll_nom²
##
##   Stamp (e.g. for L1−L2 pair with admittance y_ab):
##     Y[ a ][ a ] += y_ab;   Y[ b ][ b ] += y_ab
##     Y[ a ][ b ] -= y_ab;   Y[ b ][ a ] -= y_ab
##
##   For a balanced delta the three per-pair powers are equal.
##   An unbalanced delta is specified via set_delta_unbalanced().
##   Delta loads do not use the neutral conductor regardless of
##   use_explicit_neutral.
##
## ── Consumer state machine ────────────────────────────────────────────────────
##
##   Each phase independently tracks NORMAL / TRIPPED_UV / DAMAGED_OV.
##   A per-phase trip removes just that phase from the stamp (sets Y_ph = 0).
##   A full disable() / enable() controls all phases together.
##
## ── Backward compatibility ────────────────────────────────────────────────────
##
##   Single-phase Consumer / RatedConsumer are unchanged and participate in
##   both YBusSolver and ThreePhaseYBusSolver via the default fallback.
##   use_explicit_neutral defaults to false, so all existing scenes continue
##   to work without modification.

class_name ThreePhaseConsumer
extends CircuitElement

# ── Connection type ───────────────────────────────────────────────────────────

const CONNECTION_WYE:   String = "wye"
const CONNECTION_DELTA: String = "delta"

var connection: String = CONNECTION_WYE

# ── Per-phase state machine ───────────────────────────────────────────────────

const STATE_NORMAL:     String = "normal"
const STATE_TRIPPED_UV: String = "tripped_undervoltage"
const STATE_DAMAGED_OV: String = "damaged_overvoltage"
const STATE_OFF:        String = "off"

## Per-phase state: Phase.L1/L2/L3 → state constant.
var phase_state: Dictionary = {}

# ── Electrical parameters ─────────────────────────────────────────────────────

## Nominal line-to-neutral voltage [V].  Used to derive admittances.
var nominal_v_ln: float = SimConstants.NOMINAL_V

## Nominal line-to-line voltage [V].  Auto-set from v_ln in constructor.
var nominal_v_ll: float

## Per-phase complex power [VA] for wye: { Phase.L1: Complex(P,Q), … }
## For delta: { 0: S_L1L2, 1: S_L2L3, 2: S_L3L1 } (index = pair index, not phase)
var phase_power: Dictionary = {}

## Voltage thresholds for the per-phase state machine.
var undervoltage_pu: float = SimConstants.UNDERVOLTAGE_PU
var overvoltage_pu: float  = SimConstants.OVERVOLTAGE_PU

## When true, wye-connected phases stamp a two-port between the phase row
## and the NEUTRAL row of the same bus.  This routes return current through
## the physical neutral conductor instead of the implicit ground reference.
##
## Set to true when the bus is connected via a ThreePhaseCable that has
## has_neutral() = true and the load has a physical neutral connection.
## Leave false (default) for delta loads or when no neutral conductor exists.
var use_explicit_neutral: bool = false

# Computed state
var is_overloaded:  bool  = false   # any phase above rated current

# ── Constructor helpers ───────────────────────────────────────────────────────

func _init(bus_node: SimNode, p_name: String = "") -> void:
	super._init(p_name)
	terminals     = [[bus_node]]
	nominal_v_ll  = nominal_v_ln * sqrt(3.0)
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		phase_state[ph] = STATE_NORMAL

func bus_node() -> SimNode:
	return terminals[0][0]

# ── Factory constructors ──────────────────────────────────────────────────────

## Balanced wye load: same P+jQ on every phase.
## p_total_w is the TOTAL three-phase active power; Q is reactive.
static func balanced_wye(
	bus: SimNode,
	p_total_w: float,
	q_total_var: float   = 0.0,
	p_v_ln: float        = SimConstants.NOMINAL_V,
	p_name: String       = ""
) -> ThreePhaseConsumer:
	var c: ThreePhaseConsumer = ThreePhaseConsumer.new(bus, p_name)
	c.connection  = CONNECTION_WYE
	c.nominal_v_ln = p_v_ln
	c.nominal_v_ll = p_v_ln * sqrt(3.0)
	var s_ph: Complex = Complex.new(p_total_w / 3.0, q_total_var / 3.0)
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		c.phase_power[ph] = s_ph
	return c

## Unbalanced wye load: specify per-phase P [W] and Q [VAr].
## p_powers / q_powers are Arrays of 3 floats: [L1, L2, L3].
static func unbalanced_wye(
	bus: SimNode,
	p_powers_w: Array,
	q_powers_var: Array   = [0.0, 0.0, 0.0],
	p_v_ln: float         = SimConstants.NOMINAL_V,
	p_name: String        = ""
) -> ThreePhaseConsumer:
	var c: ThreePhaseConsumer = ThreePhaseConsumer.new(bus, p_name)
	c.connection   = CONNECTION_WYE
	c.nominal_v_ln = p_v_ln
	c.nominal_v_ll = p_v_ln * sqrt(3.0)
	var phases: Array = [Phase.L1, Phase.L2, Phase.L3]
	for k in range(3):
		c.phase_power[phases[k]] = Complex.new(
			p_powers_w[k] if k < p_powers_w.size()   else 0.0,
			q_powers_var[k] if k < q_powers_var.size() else 0.0
		)
	return c

## Balanced delta load: same S on every L-L pair.
## p_total_w is the TOTAL three-phase active power.
static func balanced_delta(
	bus: SimNode,
	p_total_w: float,
	q_total_var: float  = 0.0,
	p_v_ll: float       = SimConstants.NOMINAL_V * sqrt(3.0),
	p_name: String      = ""
) -> ThreePhaseConsumer:
	var c: ThreePhaseConsumer = ThreePhaseConsumer.new(bus, p_name)
	c.connection   = CONNECTION_DELTA
	c.nominal_v_ll = p_v_ll
	c.nominal_v_ln = p_v_ll / sqrt(3.0)
	var s_pair: Complex = Complex.new(p_total_w / 3.0, q_total_var / 3.0)
	for pair_idx in range(3):   # 0=L1-L2, 1=L2-L3, 2=L3-L1
		c.phase_power[pair_idx] = s_pair
	return c

## Unbalanced delta: per-pair powers.
## p_pairs_w / q_pairs_var are Arrays of 3 floats: [L1L2, L2L3, L3L1].
static func unbalanced_delta(
	bus: SimNode,
	p_pairs_w: Array,
	q_pairs_var: Array = [0.0, 0.0, 0.0],
	p_v_ll: float      = SimConstants.NOMINAL_V * sqrt(3.0),
	p_name: String     = ""
) -> ThreePhaseConsumer:
	var c: ThreePhaseConsumer = ThreePhaseConsumer.new(bus, p_name)
	c.connection   = CONNECTION_DELTA
	c.nominal_v_ll = p_v_ll
	c.nominal_v_ln = p_v_ll / sqrt(3.0)
	for k in range(3):
		c.phase_power[k] = Complex.new(
			p_pairs_w[k]   if k < p_pairs_w.size()   else 0.0,
			q_pairs_var[k] if k < q_pairs_var.size() else 0.0
		)
	return c

# ── Admittance computation ────────────────────────────────────────────────────

## Wye per-phase admittance for phase `ph`.
## Y_ph = conj(S) / V_ln_nom²  →  (P - jQ) / V²
func _wye_admittance(ph: int) -> Complex:
	if phase_state[ph] != STATE_NORMAL:
		return Complex.zero()
	var s: Complex = phase_power.get(ph, Complex.zero())
	if s == null or (s.re == 0.0 and s.im == 0.0):
		return Complex.zero()
	var v2: float = nominal_v_ln * nominal_v_ln
	# Y = conj(S) / V² = (P - jQ) / V²
	return Complex.new(s.re / v2, -s.im / v2)

## Delta per-pair admittance for pair_index (0=L1L2, 1=L2L3, 2=L3L1).
func _delta_admittance(pair_idx: int) -> Complex:
	var s: Complex = phase_power.get(pair_idx, Complex.zero())
	if s == null or (s.re == 0.0 and s.im == 0.0):
		return Complex.zero()
	var v2: float = nominal_v_ll * nominal_v_ll
	return Complex.new(s.re / v2, -s.im / v2)

# ── Y-Bus stamps ──────────────────────────────────────────────────────────────

func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _source_np: Dictionary) -> void:
	if not enabled:
		return

	var n: SimNode = bus_node()

	if connection == CONNECTION_WYE:
		# Pre-fetch the neutral row once (used only when use_explicit_neutral = true)
		var n_row: int = -1
		if use_explicit_neutral:
			n_row = np_idx.get(n.id + ":" + str(Phase.NEUTRAL), -1)

		for ph in [Phase.L1, Phase.L2, Phase.L3]:
			var key: String = n.id + ":" + str(ph)
			var ph_row: int = np_idx.get(key, -1)
			if ph_row < 0:
				continue
			var y: Complex = _wye_admittance(ph)
			if y.re == 0.0 and y.im == 0.0:
				continue

			if use_explicit_neutral and n_row >= 0:
				# Two-port stamp: Lph ↔ N
				# Return current flows through the physical neutral conductor.
				Y[ph_row][ph_row].add_inplace(y)
				Y[n_row][n_row].add_inplace(y)
				Y[ph_row][n_row].sub_inplace(y)
				Y[n_row][ph_row].sub_inplace(y)
			else:
				# Single-ended stamp: Lph → implicit ground (staro ponašanje).
				Y[ph_row][ph_row].add_inplace(y)

	else:  # DELTA — connect between pairs on the same bus (neutral nije potreban)
		var pair_phases: Array = [
			[Phase.L1, Phase.L2],   # pair 0 = L1-L2
			[Phase.L2, Phase.L3],   # pair 1 = L2-L3
			[Phase.L3, Phase.L1],   # pair 2 = L3-L1
		]
		for pair_idx in range(3):
			var y: Complex = _delta_admittance(pair_idx)
			var ph_a: int  = pair_phases[pair_idx][0]
			var ph_b: int  = pair_phases[pair_idx][1]
			var row_a: int = np_idx.get(n.id + ":" + str(ph_a), -1)
			var row_b: int = np_idx.get(n.id + ":" + str(ph_b), -1)
			if row_a < 0 or row_b < 0:
				continue
			Y[row_a][row_a].add_inplace(y)
			Y[row_b][row_b].add_inplace(y)
			Y[row_a][row_b].sub_inplace(y)
			Y[row_b][row_a].sub_inplace(y)

## Single-phase fallback (YBusSolver): stamp L1 wye admittance.
func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _src: Array) -> void:
	if not enabled:
		return
	var row: int = node_idx.get(bus_node(), -1)
	if row < 0:
		return
	if connection == CONNECTION_WYE:
		Y[row][row].add_inplace(_wye_admittance(Phase.L1))
	else:
		# Delta → use equivalent wye admittance (Δ→Y: divide by 3)
		Y[row][row].add_inplace(_delta_admittance(0).scale(1.0 / 3.0))

# ── State update ──────────────────────────────────────────────────────────────

func update_state_3ph(_dt: float = 0.0) -> void:
	if not enabled:
		for ph in [Phase.L1, Phase.L2, Phase.L3]:
			currents_by_phase[ph] = Complex.zero()
		current = Complex.zero()
		return

	var n: SimNode = bus_node()

	if connection == CONNECTION_WYE:
		for ph in [Phase.L1, Phase.L2, Phase.L3]:
			var v_ph: Complex = n.get_voltage(ph)
			if phase_state[ph] != STATE_NORMAL or v_ph == null:
				currents_by_phase[ph] = Complex.zero()
				continue
			var y: Complex = _wye_admittance(ph)
			if use_explicit_neutral:
				# Voltage across the load = V_phase − V_neutral
				var v_n: Complex = n.get_voltage(Phase.NEUTRAL)
				if v_n == null:
					v_n = Complex.zero()
				currents_by_phase[ph] = v_ph.sub(v_n).mul(y)
			else:
				currents_by_phase[ph] = v_ph.mul(y)
			_check_phase_health(ph, v_ph)

	else:  # DELTA
		for ph in [Phase.L1, Phase.L2, Phase.L3]:
			currents_by_phase[ph] = Complex.zero()

		var pair_phases: Array = [
			[Phase.L1, Phase.L2], [Phase.L2, Phase.L3], [Phase.L3, Phase.L1]
		]
		for pair_idx in range(3):
			var ph_a: int   = pair_phases[pair_idx][0]
			var ph_b: int   = pair_phases[pair_idx][1]
			var va: Complex = n.get_voltage(ph_a)
			var vb: Complex = n.get_voltage(ph_b)
			if va == null or vb == null:
				continue
			var y: Complex  = _delta_admittance(pair_idx)
			var I_pair: Complex = va.sub(vb).mul(y)
			currents_by_phase[ph_a].add_inplace(I_pair)
			currents_by_phase[ph_b].sub_inplace(I_pair)

	# Backward compat
	current = currents_by_phase.get(Phase.L1, Complex.zero())

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	if not enabled:
		current = Complex.zero()
		return
	var v: Complex = bus_node().get_voltage(Phase.L1)
	if v == null:
		current = Complex.zero()
		return
	current = v.mul(_wye_admittance(Phase.L1))

# ── Health check ─────────────────────────────────────────────────────────────

func _check_phase_health(ph: int, v: Complex) -> void:
	var mag: float   = v.magnitude()
	var v_min: float = nominal_v_ln * undervoltage_pu
	var v_max: float = nominal_v_ln * overvoltage_pu
	var st: String   = phase_state[ph]
	if st == STATE_DAMAGED_OV or st == STATE_OFF:
		return
	if mag > v_max:
		phase_state[ph] = STATE_DAMAGED_OV
		mark_dirty()
	elif mag < v_min and mag > 1e-3:
		phase_state[ph] = STATE_TRIPPED_UV
		mark_dirty()
	elif st == STATE_TRIPPED_UV and mag >= v_min:
		phase_state[ph] = STATE_NORMAL
		mark_dirty()

# ── Game controls ─────────────────────────────────────────────────────────────

func disable() -> void:
	enabled = false
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		phase_state[ph] = STATE_OFF
	mark_dirty()

func enable() -> void:
	enabled = true
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		if phase_state[ph] != STATE_DAMAGED_OV:
			phase_state[ph] = STATE_NORMAL
	mark_dirty()

func repair() -> void:
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		phase_state[ph] = STATE_NORMAL
	enabled = true
	mark_dirty()

# ── Power queries ─────────────────────────────────────────────────────────────

## Apparent power on phase `ph` (wye) or pair `ph` (delta) [VA].
func apparent_power_phase(ph: int) -> Complex:
	if connection == CONNECTION_WYE:
		var v: Complex = bus_node().get_voltage(ph)
		var i: Complex = currents_by_phase.get(ph, null)
		if v == null or i == null:
			return Complex.zero()
		return v.mul(i.conjugate())
	else:
		# Delta: use pair index
		var pair_phases: Array = [[Phase.L1, Phase.L2], [Phase.L2, Phase.L3], [Phase.L3, Phase.L1]]
		var pair_idx: int = ph   # caller uses 0/1/2 for pair
		if pair_idx < 0 or pair_idx >= 3:
			return Complex.zero()
		var ph_a: int   = pair_phases[pair_idx][0]
		var ph_b: int   = pair_phases[pair_idx][1]
		var va: Complex = bus_node().get_voltage(ph_a)
		var vb: Complex = bus_node().get_voltage(ph_b)
		if va == null or vb == null:
			return Complex.zero()
		var y: Complex = _delta_admittance(pair_idx)
		var I_pair: Complex = va.sub(vb).mul(y)
		return va.sub(vb).mul(I_pair.conjugate())

## Total three-phase active power drawn [W].
func total_active_power_w() -> float:
	var total: float = 0.0
	if connection == CONNECTION_WYE:
		for ph in [Phase.L1, Phase.L2, Phase.L3]:
			total += apparent_power_phase(ph).re
	else:
		for pair_idx in range(3):
			total += apparent_power_phase(pair_idx).re
	return total

## True if any phase is in TRIPPED or DAMAGED state.
func any_phase_faulted() -> bool:
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var st: String = phase_state.get(ph, STATE_NORMAL)
		if st == STATE_TRIPPED_UV or st == STATE_DAMAGED_OV:
			return true
	return false

func _to_string() -> String:
	var p: float = total_active_power_w() / 1000.0
	var n_str: String = " (N explicit)" if use_explicit_neutral else ""
	return "ThreePhaseConsumer('%s', %s%s, %.2f kW)" % [element_name, connection, n_str, p]
