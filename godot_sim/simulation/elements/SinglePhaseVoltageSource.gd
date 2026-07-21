## SinglePhaseVoltageSource.gd
## Ideal single-phase AC voltage source.  Acts as a slack bus on Phase.L1.
##
## ── Usage ────────────────────────────────────────────────────────────────────
##
##   var bus := SimNode.new("mains_bus")
##   var src := SinglePhaseVoltageSource.new(bus, 230.0, 0.0)
##   model.add_element(src)
##
## ── Phasor ───────────────────────────────────────────────────────────────────
##
##   V = voltage_rms ∠ phase_deg
##   Stamped on Phase.L1 of the bus.  Phase.NEUTRAL is always 0 V (TN) or
##   unset (IT) — controlled by grounding_system.
##
## ── Design rule ──────────────────────────────────────────────────────────────
##
##   Mirrors the ThreePhaseVoltageSource API so SourceBridge and solvers
##   can work with both types identically via is_slack_source() /
##   slack_node_phases().

class_name SinglePhaseVoltageSource
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## RMS voltage [V].
var voltage_rms: float

## Phase angle [degrees].
var phase_deg: float = 0.0

## Optional grounding system.  null → TN (NEUTRAL & PE are slack at 0 V).
var grounding_system: GroundingSystem = null

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	bus_node: SimNode,
	p_voltage_rms: float  = SimConstants.NOMINAL_V,
	p_phase_deg:   float  = 0.0,
	p_name:        String = ""
) -> void:
	super._init(p_name)
	terminals   = [[bus_node]]
	voltage_rms = p_voltage_rms
	phase_deg   = p_phase_deg
	_stamp()

func bus_node() -> SimNode:
	return terminals[0][0]

# ── Voltage API ───────────────────────────────────────────────────────────────

## Complex phasor of the source.
func voltage_phasor() -> Complex:
	return Complex.from_polar(voltage_rms, deg_to_rad(phase_deg))

## Change voltage and re-stamp.
func set_voltage(rms: float, deg: float = 0.0) -> void:
	voltage_rms = rms
	phase_deg   = deg
	_stamp()
	mark_dirty()

## Stamp voltage onto the bus node.
func _stamp() -> void:
	bus_node().set_voltage(Phase.L1, voltage_phasor())
	bus_node().set_voltage(Phase.NEUTRAL, Complex.zero())
	if not _is_it_system():
		bus_node().set_voltage(Phase.PE, Complex.zero())

# ── Solver interface ──────────────────────────────────────────────────────────

func is_slack_source() -> bool:
	return true

func slack_node_phases() -> Array:
	var pairs: Array = [
		[bus_node(), Phase.L1],
		[bus_node(), Phase.NEUTRAL],
	]
	if not _is_it_system():
		pairs.append([bus_node(), Phase.PE])
	return pairs

func stamp_ybus(_Y: Array, _I_inj: Array, _node_idx: Dictionary, _source_nodes: Array) -> void:
	pass

func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass

func update_state_3ph(_dt: float = 0.0) -> void:
	current = currents_by_phase.get(Phase.L1, Complex.zero())

# ── Power queries ─────────────────────────────────────────────────────────────

## Apparent power [VA].  Returns null before first solve.
func apparent_power() -> Complex:
	var v: Complex = bus_node().get_voltage(Phase.L1)
	var i: Complex = currents_by_phase.get(Phase.L1, null)
	if v == null or i == null:
		return null
	return v.mul(i.conjugate())

func active_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.re

func reactive_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.im

# ── Helpers ───────────────────────────────────────────────────────────────────

func _is_it_system() -> bool:
	return grounding_system != null and grounding_system.system_type == GroundingSystem.IT

func _to_string() -> String:
	return "SinglePhaseVoltageSource('%s', %.1fV ∠%.1f°)" % [
		element_name, voltage_rms, phase_deg
	]
