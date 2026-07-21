## NortonSource.gd
## Norton equivalent source: ideal current source in parallel with internal admittance.
##
## ── Circuit model ─────────────────────────────────────────────────────────────
##
##   node_a ─────┬──────── node_b
##               │  In ↑   │
##              [Yp]       │
##               │         │
##
##   In  — short-circuit current phasor (flows into node_a, out of node_b)
##   Yp  — parallel internal admittance [S]  (set to zero for an ideal current source)
##
## ── Duality with Thevenin ─────────────────────────────────────────────────────
##
##   Every Norton source has a Thevenin equivalent:
##     EMF = In / Yp,   Zs = 1/Yp
##   Use TheveninSource.gd if you prefer the voltage-behind-impedance form.
##
## ── Stamp ─────────────────────────────────────────────────────────────────────
##
##   Parallel admittance between node_a ↔ node_b  (if Yp ≠ 0).
##   Current In injected INTO node_a, extracted from node_b.
##
## ── Branch current after solve ────────────────────────────────────────────────
##
##   The total current leaving node_a into the external network is:
##     I_ext = In − Yp × V_ab
##   where V_ab = Va − Vb.  This is what update_state() computes so that
##   the `current` field reflects what actually flows in the branch.
##
## ── Usage ─────────────────────────────────────────────────────────────────────
##
##   # 10 A ∠ 0° source with 100 Ω internal shunt resistance
##   var src := NortonSource.new(node_a, node_b,
##                 Complex.from_polar(10.0, 0.0),
##                 Complex.new(1.0 / 100.0, 0.0))
##   model.add_element(src)

class_name NortonSource
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## Short-circuit current phasor [A].
var current_phasor: Complex

## Parallel internal admittance [S].  Set to Complex.zero() for ideal source.
var admittance: Complex

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	node_a: SimNode,
	node_b: SimNode,
	p_current:    Complex,
	p_admittance: Complex,
	p_name:       String = ""
) -> void:
	super._init(p_name)
	terminals       = [[node_a], [node_b]]
	current_phasor  = p_current
	admittance      = p_admittance

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

# ── Source API ────────────────────────────────────────────────────────────────

func set_current(phasor: Complex) -> void:
	current_phasor = phasor
	mark_dirty()

func set_current_polar(rms: float, deg: float) -> void:
	set_current(Complex.from_polar(rms, deg_to_rad(deg)))

func set_admittance(y: Complex) -> void:
	admittance = y
	mark_dirty()

## Open-circuit voltage phasor [V] = In / Yp.
## Returns null for an ideal current source (Yp = 0).
func open_circuit_voltage() -> Complex:
	if admittance.magnitude() < 1e-12:
		return null
	return current_phasor.div(admittance)

# ── Solver interface ──────────────────────────────────────────────────────────

func is_slack_source() -> bool:
	return false

func stamp_ybus(Y: Array, I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]

	# Parallel admittance stamp (only if non-zero — ideal source has none)
	if admittance.magnitude() > 1e-12:
		Y[i][i].add_inplace(admittance)
		Y[j][j].add_inplace(admittance)
		Y[i][j].sub_inplace(admittance)
		Y[j][i].sub_inplace(admittance)

	# Ideal current injection
	I_inj[i].add_inplace(current_phasor)   # In enters node_a
	I_inj[j].sub_inplace(current_phasor)   # In leaves node_b

func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass

## After solve: I_ext = In − Yp × (Va − Vb).
## This accounts for the current flowing through the parallel admittance
## so `current` reflects the real terminal current, not just the source value.
func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	if admittance.magnitude() < 1e-12:
		# Ideal current source — terminal current equals injected current
		current = current_phasor.copy()
		return

	var va: Complex = node_a().get_voltage(Phase.L1)
	var vb: Complex = node_b().get_voltage(Phase.L1)
	if va == null or vb == null:
		current = current_phasor.copy()
		return

	# V_ab = Va − Vb
	var v_ab: Complex = Complex.new(va.re - vb.re, va.im - vb.im)
	# I_through_Yp = Yp × V_ab  (current leaving node_a through the shunt)
	var i_shunt: Complex = admittance.mul(v_ab)
	# Net current into external network from node_a: In − I_shunt
	current = Complex.new(
		current_phasor.re - i_shunt.re,
		current_phasor.im - i_shunt.im
	)

func update_state_3ph(_dt: float = 0.0) -> void:
	update_state({}, _dt)
	currents_by_phase[Phase.L1] = current if current != null else Complex.zero()

# ── Power queries ─────────────────────────────────────────────────────────────

func apparent_power() -> Complex:
	var va: Complex = node_a().get_voltage(Phase.L1)
	var vb: Complex = node_b().get_voltage(Phase.L1)
	if va == null or vb == null or current == null:
		return null
	var v_ab: Complex = Complex.new(va.re - vb.re, va.im - vb.im)
	return v_ab.mul(current.conjugate())

func active_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.re

func reactive_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.im

func _to_string() -> String:
	return "NortonSource('%s', In=%.3fA∠%.1f°, Yp=%.4f+j%.4fS)" % [
		element_name,
		current_phasor.magnitude(), rad_to_deg(atan2(current_phasor.im, current_phasor.re)),
		admittance.re, admittance.im
	]
