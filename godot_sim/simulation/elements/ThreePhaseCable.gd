## ThreePhaseCable.gd
## Three-phase cable / overhead line between two SimNodes.
##
## ── Physical model ────────────────────────────────────────────────────────────
##
##   Each SimNode represents a three-phase bus.  The cable carries three
##   conductors (L1, L2, L3) from bus_a to bus_b with optional neutral
##   and optional PE (protective earth) conductors.
##
## ── Two stamping modes ────────────────────────────────────────────────────────
##
##   BALANCED (default, use_sequence_model = false):
##     All three phases have the same per-phase impedance Z = R+jX.
##     The 3×3 phase-admittance matrix is diagonal: Y_ph = y_phase * I₃.
##     Equivalent to three independent single-phase cables in parallel.
##
##   SEQUENCE (use_sequence_model = true):
##     Zero-sequence impedance Z0 and positive-sequence Z1 are given
##     separately (typical for overhead lines with ground-return current).
##     The phase-domain admittance matrix is derived via symmetrical
##     components:
##
##         Y_ph = A * diag(Y0, Y1, Y1) * A⁻¹
##
##     where Y0=1/Z0, Y1=1/Z1, A=[1,1,1; 1,a²,a; 1,a,a²], a=e^{j2π/3}.
##     Result for a transposed / balanced-geometry line:
##
##         Y_self = (Y0 + 2·Y1) / 3       (diagonal)
##         Y_mut  = (Y0 −   Y1) / 3       (off-diagonal, all equal)
##
## ── PE conductor ─────────────────────────────────────────────────────────────
##
##   When pe_impedance_per_m is non-zero (re or im > 0), a PE conductor is
##   stamped as an additional 2-port between Phase.PE rows of the two nodes,
##   identical in structure to the neutral conductor stamp.
##
## ── Stamp structure ───────────────────────────────────────────────────────────
##
##   The full L1/L2/L3 stamp is a 6×6 two-port across
##   [phA_a,phB_a,phC_a, phA_b,phB_b,phC_b].
##   Neutral and PE are independent scalar 2-ports on their own rows.
##
## ── Resistance model ──────────────────────────────────────────────────────────
##
##   R je UVEK temperaturski korigovana (isti fizički zakon kao Cable):
##     - ako je cross_mm2 postavljen → R₂₀ se računa iz preseka + materijala
##     - inače → R₂₀ = resistance_per_m * length_m (npr. nadzemni vod iz tablice
##       proizvođača, bez poznatog preseka)
##   U oba slučaja R₂₀ se skalira sa istim temperaturskim faktorom
##   (_temp_factor(), definisan u CableBase). Videti phase_impedance().
##
## ── Thermal model (lumped first-order, per-phase) ─────────────────────────────
##
##   Joule heating (worst phase)  P_in  = max(|I_ph|²) · R(T)
##   Newton cooling               P_out = (T - T_ambient) / R_thermal
##   Heat balance                 C_th · dT/dt = P_in - P_out
##   ↓ discretised (forward Euler, sub-stepped if dt is large):
##                                T(t+dt) = T(t) + (dt / τ) · (T_ss - T(t))
##   where τ = C_th · R_thermal and T_ss = T_ambient + P_in · R_thermal.
##
##   Note: A single lumped temperature is tracked for the whole cable body.
##   The worst-case phase current drives the heating (conservative approach).
##   Zajednička termalna infrastruktura (kapacitet, integracija, relax-to-ambient)
##   živi u CableBase — ovde se samo definiše _heating_power_w().

class_name ThreePhaseCable
extends CableBase

# ── Configuration ─────────────────────────────────────────────────────────────

## Per-phase series resistance per metre [Ω/m].
## Koristi se SAMO kao fallback kada cross_mm2 nije postavljen — ako je
## cross_mm2 > 0, resistance_per_m se ignoriše i otpor se računa iz preseka +
## materijala (sa temperaturskom korekcijom). Videti phase_impedance().
var resistance_per_m: float = 0.0

## Per-phase series reactance per metre [Ω/m] (inductive).
var reactance_per_m: float = 0.0

## Rated current per phase [A].
var max_current_a: float = INF

# ── Neutral conductor ─────────────────────────────────────────────────────────

## Neutral conductor impedance per metre [Ω/m].
## Complex(0, 0) = no neutral conductor (default — backward compatible).
var neutral_impedance_per_m: Complex = Complex.new(0.0, 0.0)

# ── PE conductor ──────────────────────────────────────────────────────────────

## PE conductor impedance per metre [Ω/m].
## Complex(0, 0) = no PE conductor (default — backward compatible).
var pe_impedance_per_m: Complex = Complex.new(0.0, 0.0)

# ── Sequence-model parameters (only used when use_sequence_model = true) ──────

## Use sequence-based (Z0/Z1) admittance matrix instead of balanced diagonal.
var use_sequence_model: bool = false

## Zero-sequence impedance per metre [Ω/m].  Includes ground-return path.
var z0_per_m: Complex = Complex.new(0.0, 0.0)

## Positive-sequence impedance per metre [Ω/m].
var z1_per_m: Complex = Complex.new(0.0, 0.0)

# ── Constructor ───────────────────────────────────────────────────────────────

## Create a balanced three-phase cable.
##
##   node_a           — sending-end bus SimNode
##   node_b           — receiving-end bus SimNode
##   p_length_m       — cable length [m]
##   p_resistance_pm  — per-phase resistance per metre [Ω/m] (fallback ako
##                       cross_mm2 nije naknadno postavljen)
##   p_reactance_pm   — per-phase reactance per metre [Ω/m]
##   p_max_current    — rated current per phase [A]
##   p_name           — optional display name
func _init(
	node_a: SimNode,
	node_b: SimNode,
	p_length_m: float,
	p_resistance_pm: float,
	p_reactance_pm: float  = 0.0,
	p_max_current: float   = INF,
	p_name: String         = ""
) -> void:
	super._init(p_name)
	terminals        = [[node_a], [node_b]]
	length_m          = p_length_m
	resistance_per_m  = p_resistance_pm
	reactance_per_m   = p_reactance_pm
	max_current_a     = p_max_current

# ── Electrical parameters ─────────────────────────────────────────────────────

## Per-phase series impedance Z = (R + jX) [Ω].
## R₂₀ dolazi iz preseka (ako je cross_mm2 > 0) ili iz resistance_per_m
## (fallback), a zatim se UVEK skalira temperaturskim faktorom — isti model
## kao Cable.resistance().
func phase_impedance() -> Complex:
	var r20: float
	if cross_mm2 > 0.0:
		r20 = _resistance_cold_from_cross_section()
	else:
		r20 = max(resistance_per_m, 0.0) * length_m
	var R: float = max(r20 * _temp_factor(), 1e-9)
	var X: float = reactance_per_m * length_m
	return Complex.new(R, X)

## Per-phase series admittance Y = 1/Z [S].
func phase_admittance() -> Complex:
	return phase_impedance().reciprocal()

## Zero-sequence impedance Z0 = z0_per_m * length [Ω].
func z0_total() -> Complex:
	return Complex.new(z0_per_m.re * length_m, z0_per_m.im * length_m)

## Positive-sequence impedance Z1 = z1_per_m * length [Ω].
func z1_total() -> Complex:
	return Complex.new(z1_per_m.re * length_m, z1_per_m.im * length_m)

## True when this cable has a neutral conductor.
func has_neutral() -> bool:
	return neutral_impedance_per_m.re > 0.0 or neutral_impedance_per_m.im > 0.0

## Neutral conductor total admittance [S].
func neutral_admittance() -> Complex:
	if not has_neutral():
		return Complex.zero()
	var z: Complex = Complex.new(
		neutral_impedance_per_m.re * length_m,
		neutral_impedance_per_m.im * length_m
	)
	return z.reciprocal()

## True when this cable has a PE conductor.
func has_pe() -> bool:
	return pe_impedance_per_m.re > 0.0 or pe_impedance_per_m.im > 0.0

## PE conductor total admittance [S].
func pe_admittance() -> Complex:
	if not has_pe():
		return Complex.zero()
	var z: Complex = Complex.new(
		pe_impedance_per_m.re * length_m,
		pe_impedance_per_m.im * length_m
	)
	return z.reciprocal()

## Compute the 3×3 phase-admittance matrix.
## Returns a flat Array of 9 Complex values, row-major (Y_ph[3*i + j]).
func _build_y_phase() -> Array:
	var y_mat: Array = []
	y_mat.resize(9)
	for k in range(9):
		y_mat[k] = Complex.zero()

	if use_sequence_model:
		var Y0: Complex = z0_total().reciprocal()
		var Y1: Complex = z1_total().reciprocal()
		var y_self: Complex = Y0.add(Y1.scale(2.0)).scale(1.0 / 3.0)
		var y_mut: Complex  = Y0.sub(Y1).scale(1.0 / 3.0)
		for i in range(3):
			for j in range(3):
				y_mat[i * 3 + j] = y_self.copy() if i == j else y_mut.copy()
	else:
		var y_ph: Complex = phase_admittance()
		for ph in range(3):
			y_mat[ph * 3 + ph] = y_ph.copy()

	return y_mat

# ── Termalna osnova (specifično za 3-fazni kabl) ──────────────────────────────

## Joule dissipation driven by the worst (hottest) phase [W].
## This is a conservative single-body approximation.
func _worst_phase_dissipation() -> float:
	var r: float = phase_impedance().re
	var p_max: float = 0.0
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var ic: Complex = currents_by_phase.get(ph, null)
		if ic != null:
			var p: float = ic.magnitude() * ic.magnitude() * r
			if p > p_max:
				p_max = p
	return p_max

## Osnova za termalni model iz CableBase — koristi najgoru fazu (konzervativno).
func _heating_power_w() -> float:
	return _worst_phase_dissipation()

## Total three-phase Joule dissipation [W].
func dissipated_power() -> float:
	var r: float = phase_impedance().re
	var p_total: float = 0.0
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var ic: Complex = currents_by_phase.get(ph, null)
		if ic != null:
			p_total += ic.magnitude() * ic.magnitude() * r
	return p_total

# ── Y-Bus stamps ──────────────────────────────────────────────────────────────

## Three-phase stamp: fills L1/L2/L3 rows, optional neutral, optional PE.
func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _source_np: Dictionary) -> void:
	if damaged or not enabled:
		return

	var y_mat: Array = _build_y_phase()

	# ── L1 / L2 / L3 stamp ────────────────────────────────────────────
	var rows_a: Array = []
	var rows_b: Array = []
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		rows_a.append(np_idx.get(node_a().id + ":" + str(ph), -1))
		rows_b.append(np_idx.get(node_b().id + ":" + str(ph), -1))

	for pi in range(3):
		var ra: int = rows_a[pi]
		var rb: int = rows_b[pi]
		for pj in range(3):
			var ca: int    = rows_a[pj]
			var cb: int    = rows_b[pj]
			var y: Complex = y_mat[pi * 3 + pj]
			if ra >= 0 and ca >= 0:
				Y[ra][ca].add_inplace(y)
			if rb >= 0 and cb >= 0:
				Y[rb][cb].add_inplace(y)
			if ra >= 0 and cb >= 0:
				Y[ra][cb].sub_inplace(y)
			if rb >= 0 and ca >= 0:
				Y[rb][ca].sub_inplace(y)

	# ── Neutral conductor stamp ────────────────────────────────────────
	if has_neutral():
		_stamp_scalar_conductor(Y, np_idx, Phase.NEUTRAL, neutral_admittance())

	# ── PE conductor stamp ────────────────────────────────────────────
	if has_pe():
		_stamp_scalar_conductor(Y, np_idx, Phase.PE, pe_admittance())

## Stamp a single scalar 2-port between phase `ph` rows of node_a and node_b.
func _stamp_scalar_conductor(Y: Array, np_idx: Dictionary, ph: int, y: Complex) -> void:
	var ra: int = np_idx.get(node_a().id + ":" + str(ph), -1)
	var rb: int = np_idx.get(node_b().id + ":" + str(ph), -1)
	if ra < 0 or rb < 0:
		return
	Y[ra][ra].add_inplace(y)
	Y[rb][rb].add_inplace(y)
	Y[ra][rb].sub_inplace(y)
	Y[rb][ra].sub_inplace(y)

## Single-phase fallback (used if YBusSolver is active instead of ThreePhaseYBusSolver).
func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	if damaged or not enabled:
		return
	var i: int     = node_idx.get(node_a(), -1)
	var j: int     = node_idx.get(node_b(), -1)
	if i < 0 or j < 0:
		return
	var y: Complex = phase_admittance()
	Y[i][i].add_inplace(y)
	Y[j][j].add_inplace(y)
	Y[i][j].sub_inplace(y)
	Y[j][i].sub_inplace(y)

# ── State update ──────────────────────────────────────────────────────────────

## Compute per-phase currents and check overload.
func update_state_3ph(_dt: float = 0.0) -> void:
	if damaged or not enabled:
		for ph in [Phase.L1, Phase.L2, Phase.L3]:
			currents_by_phase[ph] = Complex.zero()
		is_overloaded = false
		current       = Complex.zero()
		_temp_at_last_solve = temperature_c
		return

	var y_mat: Array  = _build_y_phase()
	var i_max: float  = 0.0

	for pi in range(3):
		var ph: int = [Phase.L1, Phase.L2, Phase.L3][pi]
		var va: Complex = node_a().get_voltage(ph)
		var vb: Complex = node_b().get_voltage(ph)
		if va == null or vb == null:
			currents_by_phase[ph] = Complex.zero()
			continue

		var I_ph: Complex = Complex.zero()
		for pj in range(3):
			var ph_j: int   = [Phase.L1, Phase.L2, Phase.L3][pj]
			var dv: Complex = (node_a().get_voltage(ph_j) if node_a().get_voltage(ph_j) != null else Complex.zero()).sub(
				node_b().get_voltage(ph_j) if node_b().get_voltage(ph_j) != null else Complex.zero()
			)
			I_ph.add_inplace(y_mat[pi * 3 + pj].mul(dv))
		currents_by_phase[ph] = I_ph
		i_max = max(i_max, I_ph.magnitude())

	current = currents_by_phase.get(Phase.L1, Complex.zero())
	is_overloaded = i_max > effective_max_current(max_current_a)
	_temp_at_last_solve = temperature_c

## Single-phase fallback.
func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	var va: Complex = node_a().voltage
	var vb: Complex = node_b().voltage
	if va == null or vb == null:
		current = Complex.zero()
		return
	current = va.sub(vb).div(phase_impedance())
	is_overloaded = current.magnitude() > effective_max_current(max_current_a)

# ── Diagnostics ───────────────────────────────────────────────────────────────

## Current magnitude for phase `ph` [A].  Returns 0 before first solve.
func current_magnitude(ph: int = Phase.L1) -> float:
	var c: Complex = currents_by_phase.get(ph, null)
	return 0.0 if c == null else c.magnitude()

## Voltage-drop phasor on phase `ph` [V].
func voltage_drop(ph: int = Phase.L1) -> Complex:
	var va: Complex = node_a().get_voltage(ph)
	var vb: Complex = node_b().get_voltage(ph)
	if va == null or vb == null:
		return null
	return va.sub(vb)

## Active power loss on phase `ph` [W].
func active_loss_w(ph: int = Phase.L1) -> float:
	var dv: Complex = voltage_drop(ph)
	var ic: Complex = currents_by_phase.get(ph, null)
	if dv == null or ic == null:
		return 0.0
	return dv.mul(ic.conjugate()).re

## Total three-phase active loss [W].
func total_loss_w() -> float:
	var s: float = 0.0
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		s += active_loss_w(ph)
	return s

## Apparent power phasor on phase `ph` [VA].  S = ΔV · I*.
func apparent_power(ph: int = Phase.L1) -> Complex:
	var dv: Complex = voltage_drop(ph)
	var ic: Complex = currents_by_phase.get(ph, null)
	if dv == null or ic == null:
		return null
	return dv.mul(ic.conjugate())

## Load as fraction of rated current (worst phase).  0.0–1.0+.
func loading() -> float:
	var eff_max := effective_max_current(max_current_a)
	if eff_max == INF or eff_max <= 0.0:
		return 0.0
	var i_max: float = 0.0
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		i_max = max(i_max, current_magnitude(ph))
	return i_max / eff_max

## Load as percentage of rated current (worst phase).
func loading_percent() -> float:
	var eff_max := effective_max_current(max_current_a)
	if eff_max == INF:
		return -1.0
	return loading() * 100.0

func _to_string() -> String:
	return "ThreePhaseCable('%s', %.0fm, R=%.4fΩ/m, X=%.4fΩ/m, %s%s%s, T=%.1f°C)" % [
		element_name, length_m, resistance_per_m, reactance_per_m,
		"SEQ" if use_sequence_model else "BAL",
		", +N" if has_neutral() else "",
		", +PE" if has_pe() else "",
		temperature_c,
	]
