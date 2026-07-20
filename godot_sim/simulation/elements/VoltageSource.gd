## VoltageSource.gd
## Ideal AC voltage source — a slack node for Y-bus solvers.
##
## Variants supported via `internal_resistance_ohm`:
##   = 0.0  → ideal source  (slack-bus substitution)
##   > 0.0  → Thevenin source (voltage behind series resistance)
##
## For Phase 0 we still treat ANY VoltageSource as a slack bus (the
## solver substitutes the source row).  The internal resistance and
## current_limit fields are stored so the future MNA / generator solver
## can use them without breaking the public API.
##
## Multi-phase ready:
##   - single-phase: pass one SimNode
##   - 3-phase    : pass three SimNodes; angles taken from Phase.reference_angle_rad

class_name VoltageSource
extends CircuitElement

const TYPE_IDEAL:    String = "ideal"
const TYPE_THEVENIN: String = "thevenin"
const TYPE_GENERATOR:String = "generator"
const TYPE_NOISY:    String = "noisy"

var voltage_rms: float
var phase_deg: float
var internal_resistance_ohm: float = 0.0
var current_limit_a: float         = INF      # for generator type
var noise_amplitude: float         = 0.0      # for noisy type
var source_type: String            = TYPE_IDEAL

# Solved current delivered (filled by CircuitModel)
# (`current` field already declared in CircuitElement)

func _init(node: SimNode, p_voltage_rms: float = 230.0, p_phase_deg: float = 0.0, p_name: String = "") -> void:
        super._init(p_name)
        terminals = [[node]]
        voltage_rms = p_voltage_rms
        phase_deg = p_phase_deg
        _stamp_voltage()

func node() -> SimNode:
        return terminals[0][0]

# ── Slack stamping ──────────────────────────────────────────────────

## Write the source's phasor straight into the bus.
func _stamp_voltage() -> void:
        var n: SimNode = node()
        n.voltage = Complex.from_polar(voltage_rms, deg_to_rad(phase_deg))

func set_voltage(rms: float, deg: float = 0.0) -> void:
        voltage_rms = rms
        phase_deg   = deg
        _stamp_voltage()
        mark_dirty()

# Solver does the actual substitution; the source itself does not
# stamp Y-entries (slack rows are replaced afterwards).
func stamp_ybus(_Y: Array, _I_inj: Array, _node_idx: Dictionary, _source_nodes: Array) -> void:
        pass

# Power query
func active_power() -> float:
        if current == null or node().voltage == null:
                return 0.0
        return node().voltage.mul(current.conjugate()).re

func reactive_power() -> float:
        if current == null or node().voltage == null:
                return 0.0
        return node().voltage.mul(current.conjugate()).im

func _to_string() -> String:
        return "VoltageSource('%s', %.1fV ∠%.1f°, type=%s)" % [
                element_name, voltage_rms, phase_deg, source_type
        ]

# ── Three-phase extension ────────────────────────────────────────────

## Single-phase sources are slack nodes — ThreePhaseYBusSolver uses this.
func is_slack_source() -> bool:
        return true

## Returns the single [node, L1] slack pair that this source controls.
func slack_node_phases() -> Array:
        return [[node(), Phase.L1]]
