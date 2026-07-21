## ControlledVoltageSource.gd
## Voltage-controlled voltage source (VCVS) and
## current-controlled voltage source (CCVS).
##
## ── Modes ─────────────────────────────────────────────────────────────────────
##
##   VCVS  →  Vout = gain × V_control          (control_type = VOLTAGE)
##   CCVS  →  Vout = transimpedance × I_sense  (control_type = CURRENT)
##
## ── Terminals ─────────────────────────────────────────────────────────────────
##
##   out_node  — the node whose voltage this source fixes (positive terminal)
##   ref_node  — the reference node for the output (the − terminal).
##
##   IMPORTANT: ref_node is the output reference, NOT necessarily ground.
##   Do not connect ref_node to a bus that other elements use as a signal
##   bus — this source stamps it as a second slack row at 0 V.
##   If you want both terminals to float relative to ground, use
##   TheveninSource / NortonSource instead.
##
## ── Quasi-static model ────────────────────────────────────────────────────────
##
##   The controlling quantity must be updated externally before each solve step:
##     csrc.set_control_voltage(some_phasor)
##     model.mark_dirty()
##     model.solve_if_dirty()
##
## ── Usage ─────────────────────────────────────────────────────────────────────
##
##   # VCVS: output = 5 × input voltage
##   var cvsrc := ControlledVoltageSource.new(out_node, gnd_node, 5.0)
##   cvsrc.set_control_voltage(Complex.from_polar(100.0, 0.0))
##   model.add_element(cvsrc)
##
##   # CCVS: transimpedance amplifier, 10 Ω
##   var cvsrc := ControlledVoltageSource.new(out_node, gnd_node, 10.0,
##                   ControlledVoltageSource.CURRENT)
##   cvsrc.set_control_current(Complex.from_polar(2.0, 0.0))
##   model.add_element(cvsrc)

class_name ControlledVoltageSource
extends CircuitElement

enum ControlType { VOLTAGE, CURRENT }

# ── Configuration ─────────────────────────────────────────────────────────────

## Dimensionless gain (VCVS) or transimpedance in Ω (CCVS).
var gain: float

var control_type: ControlType = ControlType.VOLTAGE

## Currently applied controlling quantity (updated externally each cycle).
var _control_value: Complex = Complex.zero()

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	out_node:   SimNode,
	ref_node:   SimNode,
	p_gain:     float       = 1.0,
	p_ctrl:     ControlType = ControlType.VOLTAGE,
	p_name:     String      = ""
) -> void:
	super._init(p_name)
	terminals    = [[out_node], [ref_node]]
	gain         = p_gain
	control_type = p_ctrl

func out_node() -> SimNode: return terminals[0][0]
func ref_node() -> SimNode: return terminals[1][0]

# ── Control API ───────────────────────────────────────────────────────────────

## Update the controlling voltage (VCVS mode) and re-stamp.
func set_control_voltage(v: Complex) -> void:
	_control_value = v
	_stamp()
	mark_dirty()

## Update the controlling current (CCVS mode) and re-stamp.
func set_control_current(i: Complex) -> void:
	_control_value = i
	_stamp()
	mark_dirty()

## Computed output voltage phasor.
func output_phasor() -> Complex:
	return Complex.new(_control_value.re * gain, _control_value.im * gain)

func _stamp() -> void:
	out_node().set_voltage(Phase.L1, output_phasor())
	# ref_node is the differential output reference — stamp it at 0 V
	# relative to this source's own reference frame only.
	# Only safe when ref_node is the circuit's true reference (ground bus).
	ref_node().set_voltage(Phase.L1, Complex.zero())

# ── Solver interface ──────────────────────────────────────────────────────────

func is_slack_source() -> bool:
	return true

func slack_node_phases() -> Array:
	return [
		[out_node(), Phase.L1],
		[ref_node(), Phase.L1],
	]

func stamp_ybus(_Y: Array, _I_inj: Array, _node_idx: Dictionary, _source_nodes: Array) -> void:
	pass

func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass

func update_state_3ph(_dt: float = 0.0) -> void:
	current = currents_by_phase.get(Phase.L1, Complex.zero())

# ── Power queries ─────────────────────────────────────────────────────────────

func apparent_power() -> Complex:
	var v: Complex = out_node().get_voltage(Phase.L1)
	var i: Complex = currents_by_phase.get(Phase.L1, null)
	if v == null or i == null:
		return null
	return v.mul(i.conjugate())

func active_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.re

func _to_string() -> String:
	var mode: String = "VCVS" if control_type == ControlType.VOLTAGE else "CCVS"
	return "ControlledVoltageSource('%s', %s, gain=%.3f)" % [element_name, mode, gain]
