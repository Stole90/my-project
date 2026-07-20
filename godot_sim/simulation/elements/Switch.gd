class_name Switch
extends CircuitElement

const CLOSED_RES := 1e-6
const OPEN_RES := 1e12

var closed := true

func _init(
	node_a: SimNode,
	node_b: SimNode,
	p_closed := true,
	p_name := ""
) -> void:
	super._init(p_name)

	terminals = [[node_a], [node_b]]
	closed = p_closed

func node_a() -> SimNode:
	return terminals[0][0]

func node_b() -> SimNode:
	return terminals[1][0]

func set_closed(v: bool) -> void:
	if closed == v:
		return

	closed = v
	mark_dirty()

func toggle() -> void:
	set_closed(!closed)

func resistance() -> float:
	return CLOSED_RES if closed and enabled else OPEN_RES

func stamp_ybus(
	Y: Array,
	_I_inj: Array,
	node_idx: Dictionary,
	_source_nodes: Array
) -> void:

	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]

	var y := Complex.new(1.0 / resistance(), 0.0)

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

	current = va.sub(vb).scale(1.0 / resistance())
