## DCCurrentSource.gd
## Ideal DC current source between two nodes.
## Injects a constant real current from node_a into node_b.
##
## ── Usage ────────────────────────────────────────────────────────────────────
##
##   var src := DCCurrentSource.new(node_plus, node_minus, 5.0)  # 5 A
##   model.add_element(src)
##
## ── Sign convention ───────────────────────────────────────────────────────────
##
##   current_a > 0 → conventional current flows: node_a → external circuit → node_b
##   (current enters node_b, leaves node_a in the Y-bus injection vector)

class_name DCCurrentSource
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## DC current magnitude [A].
var current_a: float

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	node_a: SimNode,
	node_b: SimNode,
	p_current_a: float  = 1.0,
	p_name:      String = ""
) -> void:
	super._init(p_name)
	terminals  = [[node_a], [node_b]]
	current_a  = p_current_a

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

# ── Current API ───────────────────────────────────────────────────────────────

## Phasor representation of the DC current (angle = 0°).
func current_phasor() -> Complex:
	return Complex.new(current_a, 0.0)

func set_current(a: float) -> void:
	current_a = a
	mark_dirty()

# ── Solver interface ──────────────────────────────────────────────────────────

func is_slack_source() -> bool:
	return false

func stamp_ybus(_Y: Array, I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	var ip: Complex = current_phasor()
	I_inj[i].sub_inplace(ip)   # leaves node_a
	I_inj[j].add_inplace(ip)   # enters node_b

func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass   # handled by single-phase stamp_ybus path

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	current = current_phasor().copy()

func update_state_3ph(_dt: float = 0.0) -> void:
	current = current_phasor().copy()

# ── Power queries ─────────────────────────────────────────────────────────────

## Power delivered into node_b [W].
func active_power() -> float:
	var va: Complex = node_a().get_voltage(Phase.L1)
	var vb: Complex = node_b().get_voltage(Phase.L1)
	if va == null or vb == null:
		return 0.0
	# V_ab = Va - Vb;  P = V_ab * I (real part, DC)
	return (va.re - vb.re) * current_a

func _to_string() -> String:
	return "DCCurrentSource('%s', %.3fA DC)" % [element_name, current_a]
