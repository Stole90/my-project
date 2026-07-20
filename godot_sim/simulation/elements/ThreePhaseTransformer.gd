## ThreePhaseTransformer.gd
## Three-phase power transformer for Y-Bus simulation.
##
## ── Supported vector groups ───────────────────────────────────────────────────
##
##   "YNyn0"  — Wye-neutral primary, wye-neutral secondary, 0° phase shift.
##              Modelled as three independent single-phase transformers, one
##              per phase, sharing the same TransformerData parameters.
##              Most common in residential LV distribution (secondary 230/400 V).
##
##   "Dyn11"  — Delta primary, wye-neutral secondary, −30° phase shift.
##              Most common MV/LV distribution transformer in Europe.
##              Modelled as three separate windings:
##                  Winding 1: primary Pa−Pb  →  secondary Sa
##                  Winding 2: primary Pb−Pc  →  secondary Sb
##                  Winding 3: primary Pc−Pa  →  secondary Sc
##              Turns ratio per winding: n_w = √3 · n_ll
##              where n_ll = V1_LL / V2_LL (nameplate L-L ratio).
##
## ── Winding stamp (Dyn11 derivation) ─────────────────────────────────────────
##
##   For one winding with primary across nodes Pi−Pj (voltage V_ij = V_Pi − V_Pj)
##   and secondary at node Sk (voltage V_Sk) with series admittance ys and
##   turns ratio n_w = V_ij_rated / V_Sk_rated:
##
##     I_Pi  = (ys/n_w²)·V_Pi − (ys/n_w²)·V_Pj − (ys/n_w)·V_Sk
##     I_Pj  =−(ys/n_w²)·V_Pi + (ys/n_w²)·V_Pj + (ys/n_w)·V_Sk
##     I_Sk  =−(ys/n_w )·V_Pi + (ys/n_w )·V_Pj +  ys      ·V_Sk
##
##   Stamp:
##     Y[Pi][Pi] += ys/n²;   Y[Pi][Pj] -= ys/n²;   Y[Pi][Sk] -= ys/n
##     Y[Pj][Pi] -= ys/n²;   Y[Pj][Pj] += ys/n²;   Y[Pj][Sk] += ys/n
##     Y[Sk][Pi] -= ys/n;    Y[Sk][Pj] += ys/n;     Y[Sk][Sk] += ys
##
## ── YNyn0 stamp ───────────────────────────────────────────────────────────────
##
##   For each phase ph independently:
##     Y[p_ph][p_ph] += ys/n² + ym
##     Y[s_ph][s_ph] += ys
##     Y[p_ph][s_ph] -= ys/n
##     Y[s_ph][p_ph] -= ys/n
##
## ── Shunt admittance (Dyn11) ─────────────────────────────────────────────────
##
##   The magnetising branch is split equally across the three primary phases:
##     Y[ Pa ][ Pa ] += ym/3
##     Y[ Pb ][ Pb ] += ym/3
##     Y[ Pc ][ Pc ] += ym/3
##
## ── Thermal model ─────────────────────────────────────────────────────────────
##
##   C_th · dT/dt = P_core + P_copper − (T − T_amb) / R_th
##
##   P_core   = Gc × |Vp_L1|²        (approximated from L1 phase voltage)
##   P_copper = Σ |I_s_ph|² × Req    (sum over all three phases)
##
## ── Backward compatibility ────────────────────────────────────────────────────
##
##   Inherits from CircuitElement (not Transformer) to avoid conflicting with
##   the single-phase Transformer class.  Reuses TransformerData for all
##   nameplate values; the same data resource can be shared with Transformer.

class_name ThreePhaseTransformer
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## Nameplate and electrical parameters (shared with Transformer.gd).
var data: TransformerData

## IEC vector group.  Supported: "YNyn0", "Dyn11".
var vector_group: String = "YNyn0"

# ── Thermal state ─────────────────────────────────────────────────────────────

## Current temperature of the transformer body [°C].
var temperature_c: float = 0.0

## When true, the transformer auto-damages and is disabled.
var damaged: bool = false

## True when temperature_c exceeds the overheating warning threshold.
var is_overheating: bool = false

## True when load_percent > 100.
var is_overloaded: bool = false

# Tracks T at last solve to decide when to mark dirty (resistance feedback).
const _TEMP_DIRTY_DELTA_C: float = 2.0
var _temp_at_last_solve: float   = 0.0

# Fraction of (max_temp − ambient) at which `overheating` state begins.
const _OVERHEAT_FRACTION: float = 0.80

# ── State machine constants ────────────────────────────────────────────────────

const STATE_NORMAL:      String = "normal"
const STATE_OVERLOADED:  String = "overloaded"
const STATE_OVERHEATING: String = "overheating"
const STATE_FAULTED:     String = "faulted"
const STATE_OFFLINE:     String = "offline"

# ── Runtime electrical values ─────────────────────────────────────────────────

## Per-phase secondary current phasors [A].
var secondary_currents: Dictionary = {}   # Phase.L1/L2/L3 → Complex

## Per-phase primary current phasors [A].
var primary_currents: Dictionary   = {}   # Phase.L1/L2/L3 → Complex

## Total three-phase load as % of rated kVA (100 = full load).
var load_percent: float = 0.0

## Total three-phase losses [kW].
var losses_kw: float = 0.0

## Total three-phase input power [kW].
var input_power_kw: float = 0.0

## Total three-phase output power delivered to load [kW].
var output_power_kw: float = 0.0

## Actual efficiency at the current operating point [0..1].
var efficiency_actual: float = 1.0

## Mean primary voltage magnitude across all three phases [V].
## Equivalent to primary_voltage(Phase.L1) for balanced systems.
var primary_voltage_actual: float = 0.0

## Mean secondary voltage magnitude across all three phases [V].
var secondary_voltage_actual: float = 0.0

# ── Internal loss cache ────────────────────────────────────────────────────────

var _p_core_w: float   = 0.0
var _p_copper_w: float = 0.0

# ── Constructor ───────────────────────────────────────────────────────────────

## Create a three-phase transformer.
##
##   node_primary   — three-phase primary bus (HV side)
##   node_secondary — three-phase secondary bus (LV side)
##   p_data         — TransformerData (voltages, impedances, thermal params)
##   p_vector_group — "YNyn0" (default) or "Dyn11"
##   p_name         — optional display name
func _init(
        node_primary:   SimNode,
        node_secondary: SimNode,
        p_data:         TransformerData,
        p_vector_group: String = "YNyn0",
        p_name: String         = ""
) -> void:
        super._init(p_name)
        terminals     = [[node_primary], [node_secondary]]
        data          = p_data
        vector_group  = p_vector_group
        temperature_c       = p_data.ambient_temperature_c
        _temp_at_last_solve = p_data.ambient_temperature_c
        if not p_data.enabled:
                enabled = false

func node_primary()   -> SimNode: return terminals[0][0]
func node_secondary() -> SimNode: return terminals[1][0]

# ── Electrical parameters (delegates to TransformerData) ─────────────────────

## Series leakage admittance referred to secondary side [S].
## ys = 1 / (Req + jXeq)
func series_admittance() -> Complex:
        var z_base: float = data.secondary_base_impedance_ohm()
        var r_eq: float   = data.winding_resistance_pu * z_base
        var x_eq: float   = data.leakage_reactance_pu  * z_base
        if r_eq <= 0.0 and x_eq <= 0.0:
                r_eq = 1.0e-6   # tiny series R for numerical stability
        return Complex.new(r_eq, x_eq).reciprocal()

## Shunt (core-loss + magnetising) admittance referred to primary [S].
## ym = Gc − jBm
func shunt_admittance() -> Complex:
        var v1: float    = data.primary_voltage
        var gc: float    = (data.core_loss_kw * 1e3) / max(v1 * v1, 1.0)
        var i1_r: float  = data.rated_primary_current_a()
        var i_mag: float = (data.magnetizing_current_percent / 100.0) * i1_r
        var bm: float    = i_mag / max(v1, 1.0)
        return Complex.new(gc, -bm)

## Nominal turns ratio L-L: n_ll = V1_LL / V2_LL (includes tap).
func effective_turns_ratio_ll() -> float:
        return data.effective_turns_ratio()

# ── Thermal parameters ────────────────────────────────────────────────────────

## Total thermal capacity [J/K].
func thermal_capacity_j_per_k() -> float:
        return data.thermal_capacity_kj_per_k * 1e3

## Total thermal resistance to ambient [K/W].
func thermal_resistance_k_per_w() -> float:
        var cr: float = data.cooling_rate_kw_per_k * 1e3   # convert to W/K
        return 1.0 / max(cr, 1.0e-9)

## Thermal time constant τ = C × R [s].
func thermal_time_constant() -> float:
        return thermal_capacity_j_per_k() * thermal_resistance_k_per_w()

## Temperature above which `overheating` state is flagged [°C].
func overheating_threshold_c() -> float:
        var span: float = data.max_temperature_c - data.ambient_temperature_c
        return data.ambient_temperature_c + _OVERHEAT_FRACTION * span

## Analytical steady-state temperature at the current loss level [°C].
func steady_state_temperature() -> float:
        return data.ambient_temperature_c + (_p_core_w + _p_copper_w) * thermal_resistance_k_per_w()

## 0..1 thermal loading (0 = ambient, 1 = overheating threshold, >1 = above it).
func thermal_loading() -> float:
        var span: float = overheating_threshold_c() - data.ambient_temperature_c
        if span <= 0.0:
                return 0.0
        return (temperature_c - data.ambient_temperature_c) / span

# ── Y-Bus stamps ──────────────────────────────────────────────────────────────

func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _src_np: Dictionary) -> void:
        if damaged or not enabled:
                return

        var ys: Complex = series_admittance()
        var ym: Complex = shunt_admittance()
        var np: SimNode = node_primary()
        var ns: SimNode = node_secondary()

        match vector_group:
                "YNyn0":
                        _stamp_ynyn0(Y, np_idx, np, ns, ys, ym)
                "Dyn11":
                        _stamp_dyn11(Y, np_idx, np, ns, ys, ym)
                _:
                        push_error("ThreePhaseTransformer: unsupported vector group '%s'" % vector_group)

## YNyn0: three independent single-phase transformers, one per phase.
func _stamp_ynyn0(
        Y: Array, np_idx: Dictionary,
        np: SimNode, ns: SimNode,
        ys: Complex, ym: Complex
) -> void:
        var n: float  = effective_turns_ratio_ll()
        var n2: float = n * n

        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                var p_row: int = np_idx.get(np.id + ":" + str(ph), -1)
                var s_row: int = np_idx.get(ns.id + ":" + str(ph), -1)
                if p_row < 0 or s_row < 0:
                        continue
                # Y[p][p] += ys/n² + ym
                Y[p_row][p_row].add_inplace(ys.scale(1.0 / n2))
                Y[p_row][p_row].add_inplace(ym)
                # Y[s][s] += ys
                Y[s_row][s_row].add_inplace(ys)
                # Y[p][s] -= ys/n
                Y[p_row][s_row].sub_inplace(ys.scale(1.0 / n))
                # Y[s][p] -= ys/n
                Y[s_row][p_row].sub_inplace(ys.scale(1.0 / n))

## Dyn11: three windings, each with primary across two primary phases
## and secondary connected to one secondary phase.
##
##   Winding 1: Pa−Pb → Sa   (L1−L2 primary → L1 secondary)
##   Winding 2: Pb−Pc → Sb   (L2−L3 primary → L2 secondary)
##   Winding 3: Pc−Pa → Sc   (L3−L1 primary → L3 secondary)
##
##   Turns ratio per winding:
##     n_w = V_ij_rated / V_Sk_rated = V1_LL / V2_LN = √3 · (V1_LL / V2_LL)
func _stamp_dyn11(
        Y: Array, np_idx: Dictionary,
        np: SimNode, ns: SimNode,
        ys: Complex, ym: Complex
) -> void:
        var n_ll: float = effective_turns_ratio_ll()
        var n_w: float  = sqrt(3.0) * n_ll
        var n2: float   = n_w * n_w

        # Winding definitions: [primary_ph_i, primary_ph_j, secondary_ph]
        var windings: Array = [
                [Phase.L1, Phase.L2, Phase.L1],
                [Phase.L2, Phase.L3, Phase.L2],
                [Phase.L3, Phase.L1, Phase.L3],
        ]

        for winding in windings:
                var ph_pi: int = winding[0]
                var ph_pj: int = winding[1]
                var ph_sk: int = winding[2]
                var pi_row: int = np_idx.get(np.id + ":" + str(ph_pi), -1)
                var pj_row: int = np_idx.get(np.id + ":" + str(ph_pj), -1)
                var sk_row: int = np_idx.get(ns.id + ":" + str(ph_sk),  -1)
                if pi_row < 0 or pj_row < 0 or sk_row < 0:
                        continue

                var ys_n2: Complex = ys.scale(1.0 / n2)   # ys / n_w²
                var ys_n: Complex  = ys.scale(1.0 / n_w)  # ys / n_w

                # Row Pi
                Y[pi_row][pi_row].add_inplace(ys_n2)
                Y[pi_row][pj_row].sub_inplace(ys_n2)
                Y[pi_row][sk_row].sub_inplace(ys_n)
                # Row Pj
                Y[pj_row][pi_row].sub_inplace(ys_n2)
                Y[pj_row][pj_row].add_inplace(ys_n2)
                Y[pj_row][sk_row].add_inplace(ys_n)
                # Row Sk
                Y[sk_row][pi_row].sub_inplace(ys_n)
                Y[sk_row][pj_row].add_inplace(ys_n)
                Y[sk_row][sk_row].add_inplace(ys)

        # Shunt admittance: distribute ym equally across the three primary phases
        var ym3: Complex = ym.scale(1.0 / 3.0)
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                var p_row: int = np_idx.get(np.id + ":" + str(ph), -1)
                if p_row >= 0:
                        Y[p_row][p_row].add_inplace(ym3)

## Single-phase fallback: stamp L1 pair only (used if YBusSolver is active).
func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _src: Array) -> void:
        if damaged or not enabled:
                return
        var p: int = node_idx.get(node_primary(),   -1)
        var s: int = node_idx.get(node_secondary(), -1)
        if p < 0 or s < 0:
                return
        var n: float    = effective_turns_ratio_ll()
        var n2: float   = n * n
        var ys: Complex = series_admittance()
        var ym: Complex = shunt_admittance()
        Y[p][p].add_inplace(ys.scale(1.0 / n2)).add_inplace(ym)
        Y[s][s].add_inplace(ys)
        Y[p][s].sub_inplace(ys.scale(1.0 / n))
        Y[s][p].sub_inplace(ys.scale(1.0 / n))

# ── Post-solve state update ───────────────────────────────────────────────────

func update_state_3ph(_dt: float = 0.0) -> void:
        if damaged or not enabled:
                _zero_outputs()
                return

        var ys: Complex      = series_admittance()
        var ym: Complex      = shunt_admittance()
        var n_ll: float      = effective_turns_ratio_ll()
        var np_node: SimNode = node_primary()
        var ns_node: SimNode = node_secondary()

        var total_load_va:  float = 0.0
        var i2_rated_total: float = data.rated_secondary_current_a() * 3.0

        # Clear per-phase currents before update so Dyn11 contributions
        # don't accumulate across multiple calls.
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                primary_currents[ph] = Complex.zero()

        match vector_group:
                "YNyn0":
                        _update_ynyn0(ys, ym, n_ll, np_node, ns_node)
                "Dyn11":
                        _update_dyn11(ys, ym, n_ll, np_node, ns_node)

        # Base-class current = L1 secondary current
        if secondary_currents.has(Phase.L1):
                current = secondary_currents[Phase.L1]
        # Copy secondary currents to currents_by_phase for KCL symmetry
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                currents_by_phase[ph] = secondary_currents.get(ph, Complex.zero())

        # ── Losses ────────────────────────────────────────────────────────────
        # Core losses: approximate from L1 primary voltage magnitude
        var v_p1: Complex = np_node.get_voltage(Phase.L1)
        var vp1_mag: float = v_p1.magnitude() if v_p1 != null else data.primary_voltage
        _p_core_w   = ym.re * vp1_mag * vp1_mag
        _p_copper_w = 0.0
        var r_eq: float = ys.reciprocal().re
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                var i2: Complex = secondary_currents.get(ph, Complex.zero())
                var i2_mag: float = i2.magnitude()
                _p_copper_w += i2_mag * i2_mag * r_eq
                total_load_va += i2_mag

        losses_kw    = (_p_core_w + _p_copper_w) / 1e3
        load_percent = (total_load_va / max(i2_rated_total, 1.0e-9)) * 100.0
        is_overloaded = load_percent > 100.0

        # ── Power ─────────────────────────────────────────────────────────────
        # Sum apparent input power across all three phases
        input_power_kw = 0.0
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                var v_p: Complex = np_node.get_voltage(ph)
                var i_p: Complex = primary_currents.get(ph, Complex.zero())
                if v_p != null:
                        input_power_kw += v_p.mul(i_p.conjugate()).re / 1e3

        output_power_kw = input_power_kw - losses_kw
        if input_power_kw > 1.0e-6:
                efficiency_actual = clampf(output_power_kw / input_power_kw, 0.0, 1.0)
        else:
                efficiency_actual = 1.0

        # ── Scalar voltage magnitudes (mean of three phases) ──────────────────
        var sum_vp: float = 0.0
        var sum_vs: float = 0.0
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                sum_vp += primary_voltage(ph)
                sum_vs += secondary_voltage(ph)
        primary_voltage_actual   = sum_vp / 3.0
        secondary_voltage_actual = sum_vs / 3.0

        # ── Thermal state flag ────────────────────────────────────────────────
        is_overheating = temperature_c > overheating_threshold_c()

        # Trigger re-solve when temperature change affects winding resistance.
        _check_dirty_from_temp_change()
        _temp_at_last_solve = temperature_c

func _update_ynyn0(ys: Complex, ym: Complex, n: float, np_node: SimNode, ns_node: SimNode) -> void:
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                var v_p: Complex = np_node.get_voltage(ph)
                var v_s: Complex = ns_node.get_voltage(ph)
                if v_p == null or v_s == null:
                        secondary_currents[ph] = Complex.zero()
                        primary_currents[ph]   = Complex.zero()
                        continue
                var v_p_over_n: Complex = v_p.scale(1.0 / n)
                var i_s: Complex        = v_p_over_n.sub(v_s).mul(ys)
                var i_mag: Complex      = v_p.mul(ym)
                var i_p: Complex        = i_s.scale(1.0 / n).add(i_mag)
                secondary_currents[ph] = i_s
                primary_currents[ph]   = i_p

func _update_dyn11(ys: Complex, _ym: Complex, n_ll: float, np_node: SimNode, ns_node: SimNode) -> void:
        var n_w: float = sqrt(3.0) * n_ll
        var windings: Array = [
                [Phase.L1, Phase.L2, Phase.L1],
                [Phase.L2, Phase.L3, Phase.L2],
                [Phase.L3, Phase.L1, Phase.L3],
        ]
        for winding in windings:
                var ph_pi: int = winding[0]; var ph_pj: int = winding[1]; var ph_sk: int = winding[2]
                var v_pi: Complex = np_node.get_voltage(ph_pi)
                var v_pj: Complex = np_node.get_voltage(ph_pj)
                var v_sk: Complex = ns_node.get_voltage(ph_sk)
                if v_pi == null or v_pj == null or v_sk == null:
                        secondary_currents[ph_sk] = Complex.zero()
                        continue
                var v_ij: Complex = v_pi.sub(v_pj)
                var i_s: Complex  = v_ij.scale(1.0 / n_w).sub(v_sk).mul(ys)
                secondary_currents[ph_sk] = i_s
                # Primary per-phase contribution from this winding
                var i_p_contrib: Complex = i_s.scale(1.0 / n_w)
                if not primary_currents.has(ph_pi):
                        primary_currents[ph_pi] = Complex.zero()
                if not primary_currents.has(ph_pj):
                        primary_currents[ph_pj] = Complex.zero()
                primary_currents[ph_pi].add_inplace(i_p_contrib)
                primary_currents[ph_pj].sub_inplace(i_p_contrib)

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
        # Single-phase fallback
        update_state_3ph(0.0)

func _zero_outputs() -> void:
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                secondary_currents[ph] = Complex.zero()
                primary_currents[ph]   = Complex.zero()
                currents_by_phase[ph]  = Complex.zero()
        current                  = Complex.zero()
        load_percent             = 0.0
        losses_kw                = 0.0
        input_power_kw           = 0.0
        output_power_kw          = 0.0
        efficiency_actual        = 1.0
        primary_voltage_actual   = 0.0
        secondary_voltage_actual = 0.0
        is_overloaded            = false
        _p_core_w                = 0.0
        _p_copper_w              = 0.0

# ── Thermal integration ───────────────────────────────────────────────────────

## Advance the lumped thermal model by `dt` seconds.
##
## Should be called once per physics frame by CircuitModel.step_thermal().
## `p_ambient_c` overrides data.ambient_temperature_c for this call (e.g. weather).
##
## Returns true when the transformer is newly damaged this step.
func update_thermal(dt: float, p_ambient_c: float = NAN) -> bool:
        if dt <= 0.0:
                return false

        var amb: float = data.ambient_temperature_c
        if not is_nan(p_ambient_c):
                amb = p_ambient_c
                data.ambient_temperature_c = amb   # propagate to data so UI sees it

        if damaged:
                _relax_to_ambient(dt, amb)
                return false

        if not enabled:
                _relax_to_ambient(dt, amb)
                _check_dirty_from_temp_change()
                return false

        var c_th: float = thermal_capacity_j_per_k()
        var r_th: float = thermal_resistance_k_per_w()
        if c_th <= 0.0 or r_th <= 0.0:
                return false

        # Sub-step: keep forward-Euler stable when dt >> τ.
        var tau: float    = c_th * r_th
        var steps: int    = max(1, int(ceil(dt / max(tau * 0.25, 1.0e-3))))
        var sub_dt: float = dt / float(steps)
        var newly_damaged: bool = false

        for _i in steps:
                var p_in: float  = _p_core_w + _p_copper_w   # total heat input [W]
                var p_out: float = (temperature_c - amb) / r_th
                temperature_c   += (p_in - p_out) * sub_dt / c_th

                is_overheating = temperature_c > overheating_threshold_c()

                if temperature_c >= data.max_temperature_c and not damaged:
                        damage()
                        newly_damaged = true
                        break

        _check_dirty_from_temp_change()
        return newly_damaged

func _relax_to_ambient(dt: float, amb: float) -> void:
        var c_th: float  = thermal_capacity_j_per_k()
        var r_th: float  = thermal_resistance_k_per_w()
        if c_th <= 0.0 or r_th <= 0.0:
                return
        var tau: float   = c_th * r_th
        var alpha: float = clampf(dt / tau, 0.0, 1.0)
        temperature_c   += (amb - temperature_c) * alpha
        is_overheating   = temperature_c > overheating_threshold_c()

func _check_dirty_from_temp_change() -> void:
        if absf(temperature_c - _temp_at_last_solve) >= _TEMP_DIRTY_DELTA_C:
                mark_dirty()

# ── Game actions ──────────────────────────────────────────────────────────────

## Trip the transformer (open its breaker) without physical damage.
func trip() -> void:
        disable()

## Reclose after a trip (not allowed if faulted / damaged).
func reclose() -> void:
        if not damaged:
                enable()

## Mark the transformer as having suffered insulation damage.
## Called automatically when temperature_c >= max_temperature_c.
func damage() -> void:
        damaged = true
        enabled = false
        mark_dirty()

## Clear fault, re-enable, and reset temperature to ambient.
func repair() -> void:
        damaged       = false
        enabled       = true
        temperature_c = data.ambient_temperature_c
        is_overheating  = false
        is_overloaded   = false
        _temp_at_last_solve = temperature_c
        _zero_outputs()
        mark_dirty()

## Step the tap position by `steps` (positive = up, negative = down).
## Returns the new tap position, clamped to the allowed range.
func adjust_tap(steps: int) -> int:
        var new_pos: int = data.validate_tap(data.tap_position + steps)
        if new_pos != data.tap_position:
                data.tap_position = new_pos
                mark_dirty()
        return data.tap_position

## Set tap position directly.
func set_tap(pos: int) -> int:
        return adjust_tap(pos - data.tap_position)

# ── Gameplay state ────────────────────────────────────────────────────────────

## Returns one of the STATE_* constants representing the current operational mode.
func operational_state() -> String:
        if damaged:
                return STATE_FAULTED
        if not enabled:
                return STATE_OFFLINE
        if is_overheating:
                return STATE_OVERHEATING
        if is_overloaded:
                return STATE_OVERLOADED
        return STATE_NORMAL

## Convenience boolean group (suitable for visual/audio logic).
func is_normal() -> bool:
        return operational_state() == STATE_NORMAL

func is_offline() -> bool:
        return not enabled

func is_faulted() -> bool:
        return damaged

# ── Diagnostics ───────────────────────────────────────────────────────────────

## Secondary voltage magnitude on phase `ph` [V].
func secondary_voltage(ph: int = Phase.L1) -> float:
        var v: Complex = node_secondary().get_voltage(ph)
        return 0.0 if v == null else v.magnitude()

## Primary voltage magnitude on phase `ph` [V].
func primary_voltage(ph: int = Phase.L1) -> float:
        var v: Complex = node_primary().get_voltage(ph)
        return 0.0 if v == null else v.magnitude()

## Secondary current magnitude on phase `ph` [A].
func secondary_current_magnitude(ph: int = Phase.L1) -> float:
        var i: Complex = secondary_currents.get(ph, null)
        return 0.0 if i == null else i.magnitude()

## Voltage regulation on phase `ph` [%].
## Reg = (V2_noload − V2_load) / V2_noload × 100
func voltage_regulation_percent(ph: int = Phase.L1) -> float:
        var v2_nl: float = data.secondary_voltage
        var v2_l: float  = secondary_voltage(ph)
        if v2_nl <= 0.0:
                return 0.0
        return (v2_nl - v2_l) / v2_nl * 100.0

## Rated copper loss from the winding_resistance_pu parameter [kW].
func rated_copper_loss_kw() -> float:
        return data.derived_copper_loss_kw()

## Per-unit load (0 = no load, 1 = full rated load).
func load_pu() -> float:
        return load_percent / 100.0

func _to_string() -> String:
        return "ThreePhaseTransformer('%s', %s, %.0f/%.0f V, %.0f kVA, load=%.1f%%, T=%.1f°C, %s)" % [
                element_name, vector_group,
                data.primary_voltage, data.secondary_voltage,
                data.rated_power_kva, load_percent,
                temperature_c,
                operational_state(),
        ]
