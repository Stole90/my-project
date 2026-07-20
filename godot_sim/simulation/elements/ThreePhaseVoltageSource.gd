## ThreePhaseVoltageSource.gd
## Ideal three-phase balanced (or unbalanced) voltage source.
##
## ── Usage (balanced, positive-sequence EU supply) ────────────────────────────
##
##   var bus := SimNode.new("HV_bus")
##   var src := ThreePhaseVoltageSource.new(bus, 230.0)   # 230 V L-N RMS
##   model.add_element(src)
##
## ── Voltage phasors ──────────────────────────────────────────────────────────
##
##   Positive-sequence (ABC, default):
##     Va = V_ln ∠ (offset + 0°)
##     Vb = V_ln ∠ (offset − 120°)
##     Vc = V_ln ∠ (offset + 120°)
##
##   Negative-sequence (ACB, sequence = -1):
##     Va = V_ln ∠ (offset + 0°)
##     Vb = V_ln ∠ (offset + 120°)
##     Vc = V_ln ∠ (offset − 120°)
##
##   Unbalanced: call set_phase_voltage(ph, rms, deg) per-phase.
##
## ── PE slack ─────────────────────────────────────────────────────────────────
##
##   For TN systems, the PE conductor on the source bus is also a slack node
##   at V=0 (reference potential). For IT systems, PE floats and is NOT a slack.
##   Set grounding_system to a GroundingSystem reference to control this.
##   Default (grounding_system == null) behaves as TN (PE is slack at 0 V).
##
## ── Backward compatibility ────────────────────────────────────────────────────
##
##   The source can sit alongside single-phase VoltageSource objects in the
##   same CircuitModel.  ThreePhaseYBusSolver treats all is_slack_source()
##   elements uniformly.

class_name ThreePhaseVoltageSource
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## Line-to-neutral RMS voltage [V].
var voltage_ln_rms: float

## Phase rotation applied to the whole system [degrees].
var phase_offset_deg: float = 0.0

## Sequence direction: +1 → positive (ABC, default), -1 → negative (ACB).
var sequence: int = 1

## Per-phase override voltages [rms, deg].
## Format: { Phase.L1: [rms, deg], Phase.L2: [rms, deg], ... }
var _phase_override: Dictionary = {}

## Optional reference to the network grounding system.
## null or TN_S/TN_C → PE is a slack at 0 V.
## IT              → PE is NOT a slack (it floats).
var grounding_system: GroundingSystem = null

# ── Constructor ───────────────────────────────────────────────────────────────

## Create a balanced three-phase source on `bus_node`.
##
##   bus_node        — the SimNode that represents this three-phase bus
##   p_voltage_ln    — line-to-neutral RMS voltage [V]  (default 230 V)
##   p_phase_offset  — global angle offset [degrees]    (default 0°)
##   p_sequence      — +1 positive-seq (ABC) / -1 negative-seq (ACB)
##   p_name          — optional display name
func _init(
	bus_node: SimNode,
	p_voltage_ln: float    = SimConstants.NOMINAL_V,
	p_phase_offset: float  = 0.0,
	p_sequence: int        = 1,
	p_name: String         = ""
) -> void:
	super._init(p_name)
	terminals        = [[bus_node]]
	voltage_ln_rms   = p_voltage_ln
	phase_offset_deg = p_phase_offset
	sequence         = p_sequence
	_stamp_all_phases()

func bus_node() -> SimNode:
	return terminals[0][0]

# ── Voltage API ───────────────────────────────────────────────────────────────

## Voltage phasor for `phase_id` (Phase.L1/L2/L3).
func voltage_phasor(phase_id: int) -> Complex:
	if _phase_override.has(phase_id):
		var ov: Array = _phase_override[phase_id]
		return Complex.from_polar(ov[0], deg_to_rad(ov[1]))
	var base_rad: float = Phase.reference_angle_rad(phase_id) * float(sequence)
	return Complex.from_polar(voltage_ln_rms, deg_to_rad(phase_offset_deg) + base_rad)

## Line-to-line voltage magnitude [V] for a balanced system.
func voltage_ll_rms() -> float:
	return voltage_ln_rms * sqrt(3.0)

## Change the balanced voltage and re-stamp.
func set_balanced_voltage(v_ln: float, offset_deg: float = phase_offset_deg) -> void:
	voltage_ln_rms   = v_ln
	phase_offset_deg = offset_deg
	_phase_override.clear()
	_stamp_all_phases()
	mark_dirty()

## Override the voltage on a single phase (unbalanced mode).
func set_phase_voltage(phase_id: int, rms: float, deg: float) -> void:
	_phase_override[phase_id] = [rms, deg]
	bus_node().set_voltage(phase_id, voltage_phasor(phase_id))
	mark_dirty()

## Clear any per-phase overrides and return to balanced mode.
func clear_overrides() -> void:
	_phase_override.clear()
	_stamp_all_phases()
	mark_dirty()

## Stamp all three phase phasors into the bus node.
func _stamp_all_phases() -> void:
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		bus_node().set_voltage(ph, voltage_phasor(ph))
	# Neutral reference is always 0 V at the source bus.
	bus_node().set_voltage(Phase.NEUTRAL, Complex.zero())
	# PE is 0 V for TN systems (earth reference).
	# For IT systems it is not set here — it floats.
	if not _is_it_system():
		bus_node().set_voltage(Phase.PE, Complex.zero())

# ── Solver interface ──────────────────────────────────────────────────────────

## True when this element fixes voltage on at least one bus.
func is_slack_source() -> bool:
	return true

## Returns [node, phase] pairs for all slack phases.
## For TN: L1, L2, L3, NEUTRAL, PE.
## For IT: L1, L2, L3, NEUTRAL only (PE floats).
func slack_node_phases() -> Array:
	var pairs: Array = [
		[bus_node(), Phase.L1],
		[bus_node(), Phase.L2],
		[bus_node(), Phase.L3],
		[bus_node(), Phase.NEUTRAL],
	]
	if not _is_it_system():
		pairs.append([bus_node(), Phase.PE])
	return pairs

## Voltage is already stamped into the bus node by _stamp_all_phases().
func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass

func stamp_ybus(_Y: Array, _I_inj: Array, _node_idx: Dictionary, _source_nodes: Array) -> void:
	pass

## After ThreePhaseYBusSolver fills currents_by_phase, expose totals.
func update_state_3ph(_dt: float = 0.0) -> void:
	current = currents_by_phase.get(Phase.L1, Complex.zero())

# ── Power queries ─────────────────────────────────────────────────────────────

## Apparent power on phase `ph` [VA].  Returns null before first solve.
func apparent_power_phase(ph: int) -> Complex:
	var v: Complex = bus_node().get_voltage(ph)
	var i: Complex = currents_by_phase.get(ph, null)
	if v == null or i == null:
		return null
	return v.mul(i.conjugate())

## Total three-phase active power delivered [W].
func active_power_total() -> float:
	var total: float = 0.0
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var s: Complex = apparent_power_phase(ph)
		if s != null:
			total += s.re
	return total

## Total three-phase reactive power [VAr].
func reactive_power_total() -> float:
	var total: float = 0.0
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var s: Complex = apparent_power_phase(ph)
		if s != null:
			total += s.im
	return total

## Per-phase active power array [P_L1, P_L2, P_L3] in Watts.
func active_power_per_phase() -> Array:
	var out: Array = []
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var s: Complex = apparent_power_phase(ph)
		out.append(0.0 if s == null else s.re)
	return out

# ── Helpers ───────────────────────────────────────────────────────────────────

## True when the associated grounding system is IT (isolated neutral).
func _is_it_system() -> bool:
	return grounding_system != null and grounding_system.system_type == GroundingSystem.IT

func _to_string() -> String:
	return "ThreePhaseVoltageSource('%s', %.1fV L-N, seq=%+d, %.1f°)" % [
		element_name, voltage_ln_rms, sequence, phase_offset_deg
	]
