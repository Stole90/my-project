## Capacitor.gd
## Two-terminal capacitor.
##
## Steady-state AC: stamps Y = jωC.
## Transient (backward Euler): companion model
##     G_eq = C / Δt
##     I_eq = G_eq · V_prev
## Stored as a Norton equivalent across the two terminals.

class_name Capacitor
extends CircuitElement

var capacitance_f: float                 # Farads
var v_prev: Complex = null               # last-step voltage across element

func _init(node_a: SimNode, node_b: SimNode, p_capacitance_f: float, p_name: String = "") -> void:
	super._init(p_name)
	terminals = [[node_a], [node_b]]
	capacitance_f = max(p_capacitance_f, 1e-18)

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

func supports_transient() -> bool:
	return true

# ── Steady-state ────────────────────────────────────────────────────
func admittance_ac() -> Complex:
	# Y = jωC
	return Complex.new(0.0, SimConstants.OMEGA * capacitance_f)

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	var y: Complex = admittance_ac()
	Y[i][i].add_inplace(y)
	Y[j][j].add_inplace(y)
	Y[i][j].sub_inplace(y)
	Y[j][i].sub_inplace(y)

# ── Transient (backward Euler companion) ────────────────────────────
func stamp_transient(Y: Array, I_inj: Array, node_idx: Dictionary, dt: float, _prev_state: Dictionary, _source_nodes: Array) -> void:
	if dt <= 0.0:
		stamp_ybus(Y, I_inj, node_idx, _source_nodes)
		return
	var g_eq: float = capacitance_f / dt
	var Yc: Complex = Complex.new(g_eq, 0.0)
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	Y[i][i].add_inplace(Yc)
	Y[j][j].add_inplace(Yc)
	Y[i][j].sub_inplace(Yc)
	Y[j][i].sub_inplace(Yc)
	# Norton current source from previous voltage
	if v_prev != null:
		var I_eq: Complex = v_prev.scale(g_eq)
		I_inj[i].add_inplace(I_eq)
		I_inj[j].sub_inplace(I_eq)

func update_state(_node_voltages: Dictionary, dt: float = 0.0) -> void:
	var va: Complex = node_a().voltage
	var vb: Complex = node_b().voltage
	if va == null or vb == null:
		current = Complex.zero()
		return
	var v_now: Complex = va.sub(vb)
	if dt > 0.0 and v_prev != null:
		# i = C · dV/dt
		current = v_now.sub(v_prev).scale(capacitance_f / dt)
	else:
		current = v_now.mul(admittance_ac())
	v_prev = v_now
