## ControlledCurrentSource.gd
## Voltage-controlled current source (VCCS) and
## current-controlled current source (CCCS).
##
## ── Modes ─────────────────────────────────────────────────────────────────────
##
##   VCCS  →  Iout = transconductance * V_control  (control_type = VOLTAGE)
##   CCCS  →  Iout = gain * I_sense                (control_type = CURRENT)
##
## ── Usage ─────────────────────────────────────────────────────────────────────
##
##   # VCCS: 0.5 S transconductance — 1 V input → 0.5 A output
##   var src := ControlledCurrentSource.new(node_a, node_b, 0.5)
##   src.set_control_voltage(Complex.from_polar(10.0, 0.0))
##   model.add_element(src)
##
##   # CCCS: current mirror with 3× gain
##   var mirror := ControlledCurrentSource.new(node_a, node_b, 3.0,
##                    ControlledCurrentSource.CURRENT)
##   mirror.set_control_current(Complex.from_polar(1.0, 0.0))
##   model.add_element(mirror)
##
## ── Note ──────────────────────────────────────────────────────────────────────
##
##   Like ControlledVoltageSource, this is a quasi-static model.
##   The controlling quantity must be refreshed each solve step externally.

class_name ControlledCurrentSource
extends CircuitElement

enum ControlType { VOLTAGE, CURRENT }

# ── Configuration ─────────────────────────────────────────────────────────────

## Transconductance [S] (VCCS) or dimensionless current gain (CCCS).
var gain: float

var control_type: ControlType = ControlType.VOLTAGE

var _control_value: Complex = Complex.zero()

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	node_a: SimNode,
	node_b: SimNode,
	p_gain: float         = 1.0,
	p_ctrl: ControlType   = ControlType.VOLTAGE,
	p_name: String        = ""
) -> void:
	super._init(p_name)
	terminals    = [[node_a], [node_b]]
	gain         = p_gain
	control_type = p_ctrl

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

# ── Control API ───────────────────────────────────────────────────────────────

func set_control_voltage(v: Complex) -> void:
	_control_value = v
	mark_dirty()

func set_control_current(i: Complex) -> void:
	_control_value = i
	mark_dirty()

## Computed output current phasor.
func output_phasor() -> Complex:
	return Complex.new(_control_value.re * gain, _control_value.im * gain)

# ── Solver interface ──────────────────────────────────────────────────────────

func is_slack_source() -> bool:
	return false

func stamp_ybus(_Y: Array, I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	var ip: Complex = output_phasor()
	I_inj[i].sub_inplace(ip)   # leaves node_a
	I_inj[j].add_inplace(ip)   # enters node_b

func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	current = output_phasor().copy()

func update_state_3ph(_dt: float = 0.0) -> void:
	current = output_phasor().copy()

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

func _to_string() -> String:
	var mode: String = "VCCS" if control_type == ControlType.VOLTAGE else "CCCS"
	return "ControlledCurrentSource('%s', %s, gain=%.4f)" % [element_name, mode, gain]
