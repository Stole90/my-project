## CurrentSource.gd
## Ideal AC current source between two nodes.  Injects I from node_a into node_b.

class_name CurrentSource
extends CircuitElement

var current_phasor: Complex

func _init(node_a: SimNode, node_b: SimNode, p_current: Complex, p_name: String = "") -> void:
	super._init(p_name)
	terminals = [[node_a], [node_b]]
	current_phasor = p_current

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

func stamp_ybus(_Y: Array, I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	I_inj[i].sub_inplace(current_phasor)   # current leaves node_a
	I_inj[j].add_inplace(current_phasor)   # current enters node_b

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	current = current_phasor.copy()
