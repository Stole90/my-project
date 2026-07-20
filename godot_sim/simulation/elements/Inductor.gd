## Inductor.gd
## Two-terminal inductor.
##
## Steady-state AC: Y = 1 / (jωL).
## Transient (backward Euler) companion model:
##     G_eq = Δt / L
##     I_eq = -G_eq · V_prev   (signs depend on convention; see code)

class_name Inductor
extends CircuitElement

var inductance_h: float                 # Henry
var i_prev: Complex = null              # last-step current through inductor
var v_prev: Complex = null              # last-step voltage across inductor

func _init(node_a: SimNode, node_b: SimNode, p_inductance_h: float, p_name: String = "") -> void:
	super._init(p_name)
	terminals = [[node_a], [node_b]]
	inductance_h = max(p_inductance_h, 1e-12)

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

func supports_transient() -> bool:
	return true

func admittance_ac() -> Complex:
	# Y = 1 / (jωL) = -j / (ωL)
	return Complex.new(0.0, -1.0 / (SimConstants.OMEGA * inductance_h))

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	var y: Complex = admittance_ac()
	Y[i][i].add_inplace(y)
	Y[j][j].add_inplace(y)
	Y[i][j].sub_inplace(y)
	Y[j][i].sub_inplace(y)

func stamp_transient(Y: Array, I_inj: Array, node_idx: Dictionary, dt: float, _prev_state: Dictionary, src_nodes: Array) -> void:
	if dt <= 0.0:
		stamp_ybus(Y, I_inj, node_idx, src_nodes)
		return
	var g_eq: float = dt / inductance_h
	var Yl: Complex = Complex.new(g_eq, 0.0)
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	Y[i][i].add_inplace(Yl)
	Y[j][j].add_inplace(Yl)
	Y[i][j].sub_inplace(Yl)
	Y[j][i].sub_inplace(Yl)
	if i_prev != null:
		# Current source modelling stored flux: I_eq = i_prev (direction a→b)
		I_inj[i].sub_inplace(i_prev)
		I_inj[j].add_inplace(i_prev)

func update_state(_node_voltages: Dictionary, dt: float = 0.0) -> void:
	var va: Complex = node_a().voltage
	var vb: Complex = node_b().voltage
	if va == null or vb == null:
		current = Complex.zero()
		return
	var v_now: Complex = va.sub(vb)
	if dt > 0.0 and i_prev != null:
		# i_n = i_{n-1} + (Δt / L) · v_n
		current = i_prev.add(v_now.scale(dt / inductance_h))
	else:
		current = v_now.div(Complex.new(0.0, SimConstants.OMEGA * inductance_h))
	i_prev = current
	v_prev = v_now
