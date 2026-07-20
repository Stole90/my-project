## DistributionBox.gd
## Aggregator: a single bus that branches into N protected output circuits.
##
## In three-phase networks each output circuit can be assigned to a
## specific phase (L1, L2 or L3) so that single-phase domestic loads
## are distributed across the available phases.
##
## ── Phase-routing API ────────────────────────────────────────────────────────
##
##   box.add_output_on_phase(fuse, Phase.L2)  — register fuse + assign phase
##   box.set_circuit_phase(0, Phase.L3)        — reassign circuit 0 to L3
##   box.phase_loading()                        — [I_L1, I_L2, I_L3] in Amperes
##   box.balance_summary()                      — "L1=8.0A  L2=6.5A  L3=7.2A"
##   box.least_loaded_phase()                   — index of least-loaded phase
##
## ── Backward compatibility ───────────────────────────────────────────────────
##
##   add_output(fuse) defaults to Phase.L1, matching the previous API.

class_name DistributionBox
extends CircuitElement

var input_bus:      SimNode
var output_fuses:   Array = []   # Array[Fuse]
var circuit_phases: Array = []   # Array[int]  — same index as output_fuses

func _init(p_input_bus: SimNode, p_name: String = "") -> void:
        super._init(p_name)
        input_bus = p_input_bus
        terminals = [[input_bus]]

# ── Output registration ───────────────────────────────────────────────────────

## Register a fuse on a specific phase (Phase.L1, L2 or L3).
## Prihvata Fuse ili ThreePhaseFuse (oba su CircuitElement).
func add_output_on_phase(fuse: CircuitElement, phase: int = Phase.L1) -> void:
        output_fuses.append(fuse)
        circuit_phases.append(phase)

## Legacy: register fuse on L1 for single-phase compat.
func add_output(fuse: CircuitElement) -> void:
        add_output_on_phase(fuse, Phase.L1)

## Change the phase assignment of an existing circuit.
func set_circuit_phase(circuit_idx: int, phase: int) -> void:
        if circuit_idx < 0 or circuit_idx >= circuit_phases.size():
                push_error("DistributionBox: circuit index %d out of range" % circuit_idx)
                return
        circuit_phases[circuit_idx] = phase
        mark_dirty()

## Phase assigned to circuit `circuit_idx`.
func get_circuit_phase(circuit_idx: int) -> int:
        if circuit_idx < 0 or circuit_idx >= circuit_phases.size():
                return Phase.L1
        return circuit_phases[circuit_idx]

## Number of registered circuits.
func circuit_count() -> int:
        return output_fuses.size()

# ── Breaker controls ──────────────────────────────────────────────────────────

## Open (trip) every output fuse (main breaker trip).
func main_breaker_open() -> void:
        for f in output_fuses:
                f.disable()
        mark_dirty()

## Close (reset) every output fuse (main breaker close).
func main_breaker_close() -> void:
        for f in output_fuses:
                f.enable()
                if f is Fuse:       (f as Fuse).replace()
                elif f is ThreePhaseFuse: (f as ThreePhaseFuse).repair()
        mark_dirty()

## Open all circuits wired to `phase`.
func phase_breaker_open(phase: int) -> void:
        for i in range(output_fuses.size()):
                if circuit_phases[i] == phase:
                        output_fuses[i].disable()
        mark_dirty()

## Close all circuits wired to `phase`.
func phase_breaker_close(phase: int) -> void:
        for i in range(output_fuses.size()):
                if circuit_phases[i] == phase:
                        var f: CircuitElement = output_fuses[i]
                        f.enable()
                        if f is Fuse:             (f as Fuse).replace()
                        elif f is ThreePhaseFuse: (f as ThreePhaseFuse).repair()
        mark_dirty()

# ── Load analysis ─────────────────────────────────────────────────────────────

## Return the total RMS current [A] flowing on each phase.
## Index 0 = L1, 1 = L2, 2 = L3.
func phase_loading() -> Array:
        var load: Array = [0.0, 0.0, 0.0]
        for i in range(output_fuses.size()):
                var f: CircuitElement = output_fuses[i]
                var ph: int = circuit_phases[i]
                if ph < 0 or ph >= 3: continue
                # Fuse ima is_closed(), ThreePhaseFuse ima is_blown()
                if f is Fuse:
                        if not (f as Fuse).is_closed(): continue
                        load[ph] += (f as Fuse).current_magnitude
                elif f is ThreePhaseFuse:
                        var tf := f as ThreePhaseFuse
                        if tf.is_blown(): continue
                        # Za trofazni osigurač uzmi struju na dodeljivanoj fazi
                        var ic: Complex = tf.currents_by_phase.get([Phase.L1, Phase.L2, Phase.L3][ph], null)
                        if ic != null: load[ph] += ic.magnitude()
        return load

## One-line summary of per-phase loading.
func balance_summary() -> String:
        var l: Array = phase_loading()
        return "L1=%.1fA  L2=%.1fA  L3=%.1fA" % [l[0], l[1], l[2]]

## Returns the index (0/1/2) of the least-loaded phase.
## Useful when auto-assigning a new circuit.
func least_loaded_phase() -> int:
        var l: Array   = phase_loading()
        var best: int  = 0
        var min_v: float = l[0]
        for ph in [1, 2]:
                if l[ph] < min_v:
                        min_v = l[ph]
                        best  = ph
        return best

## Per-phase imbalance as a fraction [0..1].
## 0 = perfectly balanced; 1 = all load on one phase.
func phase_imbalance() -> float:
        var l: Array   = phase_loading()
        var total: float = l[0] + l[1] + l[2]
        if total < 1e-6:
                return 0.0
        var avg: float = total / 3.0
        var max_dev: float = 0.0
        for ph in [0, 1, 2]:
                max_dev = maxf(max_dev, absf(l[ph] - avg))
        return max_dev / avg
