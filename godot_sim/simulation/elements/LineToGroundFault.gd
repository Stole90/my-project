## LineToGroundFault.gd
## Models a single-line-to-ground (SLG) fault on a three-phase bus.
##
## ── Physics ───────────────────────────────────────────────────────────────────
##
##   Electrically a shunt admittance Y_f = 1 / R_f from the faulted
##   phase conductor to the network reference (ground / neutral).
##
##   Fault resistance R_f:
##     0.01 Ω  → near-metallic (bolted fault, maximum current)
##     1 Ω     → low-impedance
##     100 Ω+  → high-impedance fault (e.g. downed line on dry soil)
##
## ── Stamp (3-phase solver) ────────────────────────────────────────────────────
##
##     Y[ row(node, fault_phase) ][ row(node, fault_phase) ] += 1 / R_f
##
## ── Post-solve quantities ─────────────────────────────────────────────────────
##
##     fault_current  = V_fault_phase / R_f      [A phasor]
##     fault_power_w  = |I_f|² · R_f             [W, dissipated in arc/path]
##
## ── Toggle ────────────────────────────────────────────────────────────────────
##
##   activate() / deactivate() toggle the fault without removing the
##   element from the circuit model, enabling before/after comparisons.

class_name LineToGroundFault
extends CircuitElement

# ── Parameters ────────────────────────────────────────────────────────────────

## Fault resistance [Ω].  Clamped to ≥ 1e-6 internally to prevent ÷0.
var fault_resistance_ohm: float = 0.1

## Faulted phase: Phase.L1, Phase.L2, or Phase.L3.
var fault_phase: int = Phase.L1

# ── Results ───────────────────────────────────────────────────────────────────

## Phasor fault current [A].  Filled after each solve.
var fault_current: Complex = Complex.zero()

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
        bus_node:          SimNode,
        p_fault_phase:     int     = Phase.L1,
        p_resistance_ohm:  float   = 0.1,
        p_name:            String  = "LGFault"
) -> void:
        super._init(p_name)
        terminals             = [[bus_node]]
        fault_phase           = p_fault_phase
        fault_resistance_ohm  = maxf(p_resistance_ohm, 1e-6)

func bus_node() -> SimNode:
        return terminals[0][0]

# ── Activation API ────────────────────────────────────────────────────────────

func activate() -> void:
        if not enabled:
                enabled = true
                mark_dirty()

func deactivate() -> void:
        if enabled:
                enabled       = false
                fault_current = Complex.zero()
                mark_dirty()

func set_resistance(r_ohm: float) -> void:
        fault_resistance_ohm = maxf(r_ohm, 1e-6)
        mark_dirty()

func set_phase(ph: int) -> void:
        fault_phase = ph
        mark_dirty()

# ── Solver stamps ──────────────────────────────────────────────────────────────

## Three-phase stamp: shunt from faulted phase conductor to ground.
func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _src_np: Dictionary) -> void:
        if not enabled:
                return
        var key: String = bus_node().id + ":" + str(fault_phase)
        var row: int    = np_idx.get(key, -1)
        if row < 0:
                return
        Y[row][row].re += 1.0 / maxf(fault_resistance_ohm, 1e-6)

## Single-phase fallback: only active when fault is on L1.
func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _src: Array) -> void:
        if not enabled or fault_phase != Phase.L1:
                return
        var i: int = node_idx.get(bus_node(), -1)
        if i < 0:
                return
        Y[i][i].re += 1.0 / maxf(fault_resistance_ohm, 1e-6)

# ── State updates ─────────────────────────────────────────────────────────────

func update_state_3ph(_dt: float = 0.0) -> void:
        if not enabled:
                fault_current              = Complex.zero()
                currents_by_phase[fault_phase] = Complex.zero()
                current                    = Complex.zero()
                return
        var v: Complex = bus_node().get_voltage(fault_phase)
        fault_current = Complex.zero() if v == null else v.scale(1.0 / maxf(fault_resistance_ohm, 1e-6))
        currents_by_phase[fault_phase] = fault_current
        current = fault_current

func update_state(_nv: Dictionary, _dt: float = 0.0) -> void:
        if not enabled or fault_phase != Phase.L1:
                fault_current = Complex.zero()
                current       = Complex.zero()
                return
        var v: Complex = bus_node().voltage
        fault_current = Complex.zero() if v == null else v.scale(1.0 / maxf(fault_resistance_ohm, 1e-6))
        current = fault_current

# ── Queries ───────────────────────────────────────────────────────────────────

func fault_current_a() -> float:
        return fault_current.magnitude()

func fault_power_w() -> float:
        var i: float = fault_current.magnitude()
        return i * i * fault_resistance_ohm

func _to_string() -> String:
        return "LineToGroundFault('%s', %s, Rf=%.2f Ω, I=%.1f A)" % [
                element_name, Phase.name_of(fault_phase),
                fault_resistance_ohm, fault_current_a()
        ]
