## SimNode.gd
## Electrical bus (connection point) in the 5-conductor AC network.
##
## Stores one voltage phasor per conductor: L1, L2, L3, NEUTRAL, PE.
## null = not yet solved on that conductor.
##
## Backward-compatible: `voltage` property returns L1.

class_name SimNode
extends RefCounted

var id: String
var node_name: String

## Per-phase solved voltage phasors.
## Keyed by Phase.L1 / L2 / L3 / NEUTRAL / PE.
var voltages_by_phase: Dictionary = {}

func _init(p_name: String = "") -> void:
	node_name = p_name
	id = _generate_id()
	voltages_by_phase[Phase.L1]      = null
	voltages_by_phase[Phase.L2]      = null
	voltages_by_phase[Phase.L3]      = null
	voltages_by_phase[Phase.NEUTRAL] = null
	voltages_by_phase[Phase.PE]      = null   # ← fix: PE slot dodat

# ── Backward-compatible single-phase accessor ───────────────────────

var voltage: Complex:
	get:
		return voltages_by_phase.get(Phase.L1, null)
	set(value):
		voltages_by_phase[Phase.L1] = value

# ── Multi-phase API ─────────────────────────────────────────────────

func set_voltage(phase_id: int, v: Complex) -> void:
	voltages_by_phase[phase_id] = v

func get_voltage(phase_id: int) -> Complex:
	return voltages_by_phase.get(phase_id, null)

func clear_solved() -> void:
	for k in voltages_by_phase.keys():
		voltages_by_phase[k] = null

# ── Convenience ─────────────────────────────────────────────────────

func has_power(phase_id: int = Phase.L1) -> bool:
	var v: Complex = get_voltage(phase_id)
	return v != null and v.magnitude() > 1.0

func voltage_magnitude(phase_id: int = Phase.L1) -> float:
	var v: Complex = get_voltage(phase_id)
	return 0.0 if v == null else v.magnitude()

func voltage_phase_deg(phase_id: int = Phase.L1) -> float:
	var v: Complex = get_voltage(phase_id)
	return 0.0 if v == null else v.phase_deg()

## Napon PE provodnika u odnosu na zemlju [V].
## U zdravom TN sistemu ≈ 0 V.  Visoka vrednost = kvar PE.
func pe_voltage_magnitude() -> float:
	return voltage_magnitude(Phase.PE)

## Pomeraj neutralnog provodnika od zemlje [V].
## U zdravom TN sistemu ≈ 0–5 V (pad na bonding impedansi).
## Visoka vrednost = prekinuta nula ili loš kontakt.
func neutral_displacement_v() -> float:
	return voltage_magnitude(Phase.NEUTRAL)

# ── Internal ────────────────────────────────────────────────────────

static func _generate_id() -> String:
	return "%08x-%08x" % [randi(), randi()]

func _to_string() -> String:
	var v: Complex = voltage
	if v != null:
		return "SimNode('%s', V=%.2fV ∠%.2f°)" % [node_name, v.magnitude(), v.phase_deg()]
	return "SimNode('%s', V=unsolved)" % node_name
