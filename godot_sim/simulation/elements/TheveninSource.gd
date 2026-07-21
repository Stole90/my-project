## TheveninSource.gd
## Thevenin equivalent source: ideal voltage source + series internal impedance.
##
## ── Circuit model ─────────────────────────────────────────────────────────────
##
##   node_a (+) ──[Zs]── node_b (−)
##             (+) EMF (−)
##
##   node_a  — positive terminal (higher potential side)
##   node_b  — reference terminal (lower potential / network reference)
##   EMF     — open-circuit voltage phasor  [V]
##   Zs      — series internal impedance    [Ω]  (R + jX)
##
## ── Companion model stamp ─────────────────────────────────────────────────────
##
##   The branch is represented as a Norton equivalent injected into the Y-bus:
##     admittance  Ys = 1/Zs  stamped between node_a ↔ node_b
##     injection   I_src = EMF/Zs  at node_a (into node_a, out of node_b)
##
##   After solve, the branch current is:
##     I = (EMF − Va) / Zs
##   where Va is the solved voltage at node_a relative to the common reference.
##   This is correct because node_b is the reference terminal at whatever
##   potential the rest of the network places it (often ground, but not always).
##
## ── Usage ─────────────────────────────────────────────────────────────────────
##
##   # 230 V AC generator with 0.5 + j0.1 Ω internal impedance
##   var gen := TheveninSource.new(bus_a, gnd_bus,
##                 Complex.from_polar(230.0, 0.0),
##                 Complex.new(0.5, 0.1))
##   model.add_element(gen)

class_name TheveninSource
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## Open-circuit voltage phasor [V].
var emf: Complex

## Series internal impedance [Ω].  Must not be zero (use an ideal slack source).
var impedance: Complex

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	node_a: SimNode,
	node_b: SimNode,
	p_emf:       Complex,
	p_impedance: Complex,
	p_name:      String = ""
) -> void:
	super._init(p_name)
	terminals  = [[node_a], [node_b]]
	emf        = p_emf
	impedance  = p_impedance

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

# ── Source API ────────────────────────────────────────────────────────────────

func set_emf(phasor: Complex) -> void:
	emf = phasor
	mark_dirty()

func set_emf_polar(rms: float, deg: float) -> void:
	set_emf(Complex.from_polar(rms, deg_to_rad(deg)))

func set_impedance(z: Complex) -> void:
	impedance = z
	mark_dirty()

## Short-circuit current phasor [A]  (terminal shorted: Va = Vb).
func short_circuit_current() -> Complex:
	return emf.div(impedance)

# ── Solver interface ──────────────────────────────────────────────────────────

func is_slack_source() -> bool:
	return false

## Stamp the Norton companion model (admittance + current injection).
func stamp_ybus(Y: Array, I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]

	var ys: Complex    = impedance.reciprocal()   # Ys = 1/Zs
	var i_src: Complex = emf.div(impedance)        # I  = EMF/Zs

	# Admittance stamp (π model between a ↔ b)
	Y[i][i].add_inplace(ys)
	Y[j][j].add_inplace(ys)
	Y[i][j].sub_inplace(ys)
	Y[j][i].sub_inplace(ys)

	# Current injection: I_src enters node_a, leaves node_b
	I_inj[i].add_inplace(i_src)
	I_inj[j].sub_inplace(i_src)

func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass   # handled via default stamp_ybus_3ph → stamp_ybus path in CircuitElement

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	# Branch current from Ohm's law.
	# The voltage ACROSS Zs is (EMF − Va), where Va is node_a's voltage
	# relative to the circuit reference and node_b provides that reference.
	# Do NOT use Vab = Va − Vb here; the companion stamp already encodes Vb
	# through the Y-bus — using both would double-count.
	var va: Complex = node_a().get_voltage(Phase.L1)
	if va == null:
		return
	# I = (EMF − Va) / Zs
	var v_across_zs: Complex = Complex.new(emf.re - va.re, emf.im - va.im)
	current = v_across_zs.div(impedance)

func update_state_3ph(_dt: float = 0.0) -> void:
	update_state({}, _dt)
	currents_by_phase[Phase.L1] = current if current != null else Complex.zero()

# ── Power queries ─────────────────────────────────────────────────────────────

## Apparent power delivered into the network at node_a [VA].
func apparent_power() -> Complex:
	if current == null:
		return null
	var v: Complex = node_a().get_voltage(Phase.L1)
	if v == null:
		return null
	return v.mul(current.conjugate())

func active_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.re

func reactive_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.im

func _to_string() -> String:
	return "TheveninSource('%s', EMF=%.1fV∠%.1f°, Zs=%.3f+j%.3fΩ)" % [
		element_name,
		emf.magnitude(), rad_to_deg(atan2(emf.im, emf.re)),
		impedance.re, impedance.im
	]
