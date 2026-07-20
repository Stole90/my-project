## CircuitElement.gd
## Abstract base class for every element in the circuit.
##
## Solver contract — subclasses override:
##   stamp_ybus(Y, I_inj, node_idx, source_nodes)
##       — contribute admittance and/or current-injection entries
##         to the Y-bus matrix for steady-state AC.
##
##   stamp_transient(Y, I_inj, node_idx, dt, prev_state)
##       — contribute companion-model entries for transient
##         backward-Euler integration.  Default implementation
##         falls back to stamp_ybus() (resistive elements).
##
##   update_state(node_voltages, dt)
##       — called after the solve to compute element-internal
##         quantities (current, power, capacitor voltage, etc.).
##
##   supports_transient() -> bool
##       — true if the element has memory (C, L, motor inertia…).
##
## Game-layer contract:
##   enabled    — false → completely excluded from the next solve
##   dirty      — true  → owning CircuitModel must rebuild and re-solve
##   id / name  — stable identifiers for serialisation and UI
##
## Multi-phase support:
##   `terminals` is an Array of *terminal records*; each terminal record
##   is itself an Array[SimNode], one entry per phase index.  A simple
##   single-phase resistor between bus_a and bus_b therefore declares:
##       terminals = [[bus_a], [bus_b]]
##   A 3-phase cable declares:
##       terminals = [[a1,a2,a3], [b1,b2,b3]]
##   Phase 0 elements stay single-phase; the architecture is forwards
##   compatible without changing the base class.

class_name CircuitElement
extends RefCounted

# ── Identity ─────────────────────────────────────────────────────────
var id: String
var element_name: String

# ── Topology ─────────────────────────────────────────────────────────
var terminals: Array = []   # Array[Array[SimNode]] — see file header

# ── Solver state flags ───────────────────────────────────────────────
var enabled: bool = true
var dirty: bool   = true   # true → CircuitModel must re-solve

# ── Result fields populated by update_state() ────────────────────────
var current: Complex          # primary terminal current [A]; null until solved

func _init(p_name: String = "") -> void:
        element_name = p_name
        id = "%08x-%08x" % [randi(), randi()]

# ────────────────────────────────────────────────────────────────────
# Subclass interface — override these
# ────────────────────────────────────────────────────────────────────

## Number of physical phases this element occupies (1, 3, or 4 with neutral).
func phase_count() -> int:
        return 1

## Steady-state Y-bus stamp.  Subclasses implement.
func stamp_ybus(_Y: Array, _I_inj: Array, _node_idx: Dictionary, _source_nodes: Array) -> void:
        pass

## Transient companion-model stamp.  Default: identical to steady-state
## (purely resistive elements have no time dependence).
func stamp_transient(Y: Array, I_inj: Array, node_idx: Dictionary, _dt: float, _prev_state: Dictionary, source_nodes: Array) -> void:
        stamp_ybus(Y, I_inj, node_idx, source_nodes)

## Compute current, power, etc. from solved node voltages.
func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
        pass

## True for elements with internal memory (capacitor, inductor, machine).
func supports_transient() -> bool:
        return false

# ────────────────────────────────────────────────────────────────────
# Game / state-machine helpers
# ────────────────────────────────────────────────────────────────────

func mark_dirty() -> void:
        dirty = true

func clear_dirty() -> void:
        dirty = false

func disable() -> void:
        if enabled:
                enabled = false
                mark_dirty()

func enable() -> void:
        if not enabled:
                enabled = true
                mark_dirty()

# ────────────────────────────────────────────────────────────────────
# Topology iteration helpers
# ────────────────────────────────────────────────────────────────────

## Yield every SimNode this element touches (across all terminals/phases).
func iter_nodes() -> Array:
        var out: Array = []
        for term in terminals:
                for n in term:
                        if n != null and not out.has(n):
                                out.append(n)
        return out

func _to_string() -> String:
        return "%s('%s', enabled=%s)" % [get_class(), element_name, str(enabled)]

# ────────────────────────────────────────────────────────────────────
# Three-phase extension — override in voltage sources and 3-ph elements
# ────────────────────────────────────────────────────────────────────

## Per-phase current phasors populated by update_state_3ph().
## Keyed by Phase.L1 / L2 / L3.  Single-phase elements only populate L1.
var currents_by_phase: Dictionary = {}

## True when this element acts as a slack (fixed-voltage) bus in the network.
## Override and return true in VoltageSource and ThreePhaseVoltageSource.
func is_slack_source() -> bool:
        return false

## Returns an Array of [SimNode, phase_id] pairs whose voltage this element
## fixes (slack nodes).  Used by ThreePhaseYBusSolver for substitution.
## Override in VoltageSource (returns L1 pair) and ThreePhaseVoltageSource
## (returns all three phase pairs).
func slack_node_phases() -> Array:
        return []

## Three-phase Y-bus stamp.
##
## Receives the full 3N×3N matrix Y, injection vector I_inj, the node-phase
## index dict np_idx (maps "nodeId:phaseInt" → row), and source_np (same
## key format → [SimNode, phase_id] for all slack rows).
##
## Default implementation: builds a single-phase node_idx from the L1 rows
## of np_idx and calls the existing stamp_ybus().  This means every 1-phase
## element automatically participates in a 3-phase solve on phase L1, with
## zero code changes required in the element itself.
##
## 3-phase elements override this to stamp all three phases (or cross-phase
## admittance blocks for delta connections and transformers).
func stamp_ybus_3ph(Y: Array, I_inj: Array, np_idx: Dictionary, source_np: Dictionary) -> void:
        var node_idx_1ph: Dictionary = {}
        for term in terminals:
                for n in term:
                        var key: String = n.id + ":" + str(Phase.L1)
                        if np_idx.has(key):
                                node_idx_1ph[n] = np_idx[key]
        # Reconstruct a 1-phase source_nodes array so stamp_ybus signature is met.
        var src_nodes_1ph: Array = []
        for pair in source_np.values():
                if pair[1] == Phase.L1:
                        var sn: SimNode = pair[0]
                        if not src_nodes_1ph.has(sn):
                                src_nodes_1ph.append(sn)
        stamp_ybus(Y, I_inj, node_idx_1ph, src_nodes_1ph)

## Three-phase state update.
##
## Called by ThreePhaseYBusSolver after voltages are written back to nodes.
## Default: calls update_state (reads node.voltage which is voltages_by_phase[L1])
## then copies base-class `current` into currents_by_phase[L1].
## 3-phase elements override this to compute per-phase currents.
func update_state_3ph(dt: float = 0.0) -> void:
        update_state({}, dt)
        currents_by_phase[Phase.L1] = current if current != null else Complex.zero()
