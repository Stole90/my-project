## Resistor.gd
## Two-terminal pure resistance.

class_name Resistor
extends CircuitElement

var resistance_ohm: float

func _init(node_a: SimNode, node_b: SimNode, p_resistance_ohm: float, p_name: String = "") -> void:
	super._init(p_name)
	terminals = [[node_a], [node_b]]
	resistance_ohm = max(p_resistance_ohm, 1e-9)

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

func impedance() -> Complex:
	return Complex.new(resistance_ohm, 0.0)

func admittance() -> Complex:
	return Complex.new(1.0 / resistance_ohm, 0.0)

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	var y: Complex = admittance()
	Y[i][i].add_inplace(y)
	Y[j][j].add_inplace(y)
	Y[i][j].sub_inplace(y)
	Y[j][i].sub_inplace(y)

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	var va: Complex = node_a().voltage
	var vb: Complex = node_b().voltage
	if va == null or vb == null:
		current = Complex.zero()
		return
	current = va.sub(vb).div(impedance())
