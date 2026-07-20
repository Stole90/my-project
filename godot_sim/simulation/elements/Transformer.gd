## Transformer.gd
## Single-phase power transformer for Y-Bus simulation.
##
## ── Electrical model (off-nominal tap π-equivalent) ──────────────────────────
##
##   node_primary ──┬──[ym]──GND     node_secondary
##                  │                      │
##                  └──── ys/n² ─────────── ┘
##                         (ys)
##
## In nodal-admittance form (n = effective turns ratio, V_p/V_s basis):
##
##   Y[p][p] += ys/n² + ym
##   Y[s][s] += ys
##   Y[p][s] -= ys/n
##   Y[s][p] -= ys/n
##
## where:
##   ys = 1 / (Req + jXeq)   series leakage admittance, referred to secondary
##   ym = Gc − jBm            shunt (core loss + magnetising), referred to primary
##   n  = (V1_rated/V2_rated) × (1 + tap × tap_step%)
##
## The solver never inspects element subclasses — it calls the polymorphic
## stamp_ybus / update_state interface, so no solver changes are needed.
##
## ── Thermal model ─────────────────────────────────────────────────────────────
##
##   C_th · dT/dt = P_core + P_copper − (T − T_amb) / R_th
##
##   P_core   = Gc × |Vp|²          constant at rated voltage
##   P_copper = |I_series_s|² × Req  scales with load²
##
## ── Three-phase readiness ─────────────────────────────────────────────────────
##
##   series_admittance(), shunt_admittance(), and effective_turns_ratio() are
##   factored out as virtual-style methods so a future ThreePhaseTransformer
##   subclass can override them and reuse stamp_ybus / update_state logic.
##   TransformerData already carries phase_count and vector_group fields.
##
##   Per-phase diagnostic helpers (secondary_voltage, primary_voltage,
##   secondary_current_magnitude, voltage_regulation_percent with ph argument)
##   mirror the ThreePhaseTransformer API for UI/code symmetry.

class_name Transformer
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## All nameplate and configuration values live in TransformerData so they can
## be shared, serialised, and edited in the Godot Inspector independently.
var data: TransformerData

# ── Thermal state ──────────────────────────────────────────────────────────────

## Current temperature of the transformer body [°C].
var temperature_c: float

## When true, the transformer auto-damages and is disabled.
var damaged: bool = false

# Tracks T at last solve to decide when to mark dirty (resistance feedback).
const _TEMP_DIRTY_DELTA_C: float = 2.0
var _temp_at_last_solve: float = 0.0

# ── Runtime electrical values (populated by update_state) ─────────────────────

## Primary-side solved voltage magnitude [V].
var primary_voltage_actual: float = 0.0

## Secondary-side solved voltage magnitude [V].
var secondary_voltage_actual: float = 0.0

## Primary current phasor [A].  Also stored in base-class `current`.
var primary_current: Complex = null

## Secondary current phasor [A].
var secondary_current: Complex = null

## Electrical power delivered to the primary winding [kW].
var input_power_kw: float = 0.0

## Electrical power delivered to the load [kW].
var output_power_kw: float = 0.0

## Total losses (core + copper) [kW].
var losses_kw: float = 0.0

## Load as % of rated current (100 = full load, >100 = overloaded).
var load_percent: float = 0.0

## Actual efficiency at the current operating point [0..1].
var efficiency_actual: float = 1.0

## True when load_percent > 100.
var is_overloaded: bool = false

## True when temperature_c exceeds the overheating warning threshold.
var is_overheating: bool = false

# Cached loss components used by both update_state and update_thermal.
# Avoids recomputing in the thermal integrator.
var _p_core_w: float   = 0.0    # core (iron) losses [W] — constant at rated V
var _p_copper_w: float = 0.0    # copper losses [W] — scales with I²

# ── State machine constants ────────────────────────────────────────────────────

const STATE_NORMAL:     String = "normal"
const STATE_OVERLOADED: String = "overloaded"
const STATE_OVERHEATING:String = "overheating"
const STATE_FAULTED:    String = "faulted"
const STATE_OFFLINE:    String = "offline"

# Fraction of (max_temp − ambient) at which `overheating` state begins.
const _OVERHEAT_FRACTION: float = 0.80

# ── Constructor ───────────────────────────────────────────────────────────────

## Create a transformer between two SimNodes.
##
##   node_primary   — HV / input bus (connected to source side)
##   node_secondary — LV / output bus (connected to load side)
##   p_data         — TransformerData resource with all nameplate values
##   p_name         — optional display name
func _init(
        node_primary: SimNode,
        node_secondary: SimNode,
        p_data: TransformerData,
        p_name: String = ""
) -> void:
        super._init(p_name)
        terminals = [[node_primary], [node_secondary]]
        data = p_data
        temperature_c       = p_data.ambient_temperature_c
        _temp_at_last_solve = p_data.ambient_temperature_c
        # Inherit enabled state from the data resource.
        if not p_data.enabled:
                enabled = false

func node_primary() -> SimNode:
        return terminals[0][0]

func node_secondary() -> SimNode:
        return terminals[1][0]

# ── Electrical parameters (overrideable for future subclasses) ────────────────

## Effective turns ratio including tap:  n = (V1/V2) × tap_factor.
## Override this in ThreePhaseTransformer for per-phase ratios.
func effective_turns_ratio() -> float:
        return data.effective_turns_ratio()

## Series leakage admittance referred to the secondary side [S].
## ys = 1 / (Req + jXeq)
## Override for 3-phase or temperature-dependent winding resistance.
func series_admittance() -> Complex:
        var z_base: float = data.secondary_base_impedance_ohm()
        var r_eq: float   = data.winding_resistance_pu * z_base
        var x_eq: float   = data.leakage_reactance_pu  * z_base
        if r_eq <= 0.0 and x_eq <= 0.0:
                # Ideal transformer — use a very small series resistance for numerical
                # stability (avoids a zero-impedance short that would make the matrix
                # degenerate when V_p/n ≠ V_s).
                r_eq = 1.0e-6
        return Complex.new(r_eq, x_eq).reciprocal()

## Shunt (magnetising + core-loss) admittance referred to the primary side [S].
## ym = Gc − jBm
## Override for 3-phase or saturation models.
func shunt_admittance() -> Complex:
        var v1: float  = data.primary_voltage
        # Core-loss conductance: Gc = P_core / V1²
        var gc: float  = (data.core_loss_kw * 1e3) / max(v1 * v1, 1.0)
        # Magnetising susceptance: Bm = Im / V1,  Im = (Im% / 100) × I1_rated
        var i1_rated: float = data.rated_primary_current_a()
        var i_mag: float    = (data.magnetizing_current_percent / 100.0) * i1_rated
        var bm: float       = i_mag / max(v1, 1.0)
        return Complex.new(gc, -bm)

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

# ── Y-Bus stamp ───────────────────────────────────────────────────────────────

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
        if damaged or not enabled:
                return
        var p: int = node_idx[node_primary()]
        var s: int = node_idx[node_secondary()]
        var n: float       = effective_turns_ratio()
        var ys: Complex    = series_admittance()
        var ym: Complex    = shunt_admittance()
        var n2: float      = n * n

        # Y[p][p] += ys/n² + ym
        Y[p][p].add_inplace(ys.scale(1.0 / n2))
        Y[p][p].add_inplace(ym)
        # Y[s][s] += ys
        Y[s][s].add_inplace(ys)
        # Y[p][s] -= ys/n
        Y[p][s].sub_inplace(ys.scale(1.0 / n))
        # Y[s][p] -= ys/n
        Y[s][p].sub_inplace(ys.scale(1.0 / n))

# ── Post-solve state update ───────────────────────────────────────────────────

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
        if damaged or not enabled:
                _zero_outputs()
                return

        var v_p: Complex = node_primary().voltage
        var v_s: Complex = node_secondary().voltage

        if v_p == null or v_s == null:
                _zero_outputs()
                return

        var n: float    = effective_turns_ratio()
        var ys: Complex = series_admittance()
        var ym: Complex = shunt_admittance()

        # ── Currents ──────────────────────────────────────────────────────────
        # Series branch current on the secondary side:
        #   I_series_s = (Vp/n − Vs) × ys
        var v_p_over_n: Complex = v_p.scale(1.0 / n)
        var i_series_s: Complex = v_p_over_n.sub(v_s).mul(ys)

        # Magnetising branch current on the primary side:
        #   I_mag_p = Vp × ym
        var i_mag_p: Complex = v_p.mul(ym)

        # Primary current = series reflected + magnetising
        #   I_p = I_series_s / n + I_mag_p
        var i_primary: Complex = i_series_s.scale(1.0 / n).add(i_mag_p)

        secondary_current = i_series_s
        primary_current   = i_primary
        current           = i_primary   # base-class field (primary convention)

        # ── Voltages ──────────────────────────────────────────────────────────
        primary_voltage_actual   = v_p.magnitude()
        secondary_voltage_actual = v_s.magnitude()

        # ── Losses ────────────────────────────────────────────────────────────
        var gc: float = ym.re   # core-loss conductance [S]
        var r_eq: float
        var z: Complex = ys.reciprocal()   # series impedance
        r_eq = z.re                        # Req [Ω], referred to secondary

        _p_core_w   = gc * primary_voltage_actual * primary_voltage_actual
        _p_copper_w = i_series_s.magnitude() * i_series_s.magnitude() * r_eq
        losses_kw   = (_p_core_w + _p_copper_w) / 1e3

        # ── Power ─────────────────────────────────────────────────────────────
        var s_in: Complex = v_p.mul(i_primary.conjugate())
        input_power_kw  = s_in.re / 1e3
        output_power_kw = input_power_kw - losses_kw

        if input_power_kw > 1e-6:
                efficiency_actual = clampf(output_power_kw / input_power_kw, 0.0, 1.0)
        else:
                efficiency_actual = 1.0

        # ── Load and overload ─────────────────────────────────────────────────
        var i2_rated: float = data.rated_secondary_current_a()
        load_percent  = (i_series_s.magnitude() / max(i2_rated, 1.0e-9)) * 100.0
        is_overloaded = load_percent > 100.0

        # ── Thermal state flag ────────────────────────────────────────────────
        is_overheating = temperature_c > overheating_threshold_c()

        # Resistance is temperature-dependent in a real transformer (winding R
        # rises ~0.4%/°C for copper).  Once ΔT exceeds the threshold, ask the
        # solver to re-solve next frame so the new R is reflected.
        if absf(temperature_c - _temp_at_last_solve) >= _TEMP_DIRTY_DELTA_C:
                mark_dirty()
        _temp_at_last_solve = temperature_c

func _zero_outputs() -> void:
        primary_current          = Complex.zero()
        secondary_current        = Complex.zero()
        current                  = Complex.zero()
        primary_voltage_actual   = 0.0
        secondary_voltage_actual = 0.0
        input_power_kw           = 0.0
        output_power_kw          = 0.0
        losses_kw                = 0.0
        load_percent             = 0.0
        efficiency_actual        = 1.0
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
        damaged         = false
        enabled         = true
        temperature_c   = data.ambient_temperature_c
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
## Note: `damaged` is checked before `enabled` because damage() sets both flags;
## a damaged transformer must report FAULTED, not OFFLINE.
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

## Rated copper loss from the winding_resistance_pu parameter [kW].
## Should be close to data.copper_loss_kw for a well-parameterised transformer.
func rated_copper_loss_kw() -> float:
        return data.derived_copper_loss_kw()

## Voltage regulation at the current load [%].
## Reg = (V2_noload − V2_load) / V2_noload × 100
##
## `ph` is accepted for API symmetry with ThreePhaseTransformer.
## For a single-phase transformer it is always ignored — there is only one
## secondary voltage (secondary_voltage_actual).
func voltage_regulation_percent(ph: int = Phase.L1) -> float:
        # `ph` intentionally unused — kept for API symmetry with
        # ThreePhaseTransformer.voltage_regulation_percent(ph).
        @warning_ignore("unused_parameter")
        var _ph: int = ph
        var v2_nl: float = data.secondary_voltage   # no-load rated secondary
        var v2_l: float  = secondary_voltage_actual
        if v2_nl <= 0.0:
                return 0.0
        return (v2_nl - v2_l) / v2_nl * 100.0

## Per-unit load (0 = no load, 1 = full rated load).
func load_pu() -> float:
        return load_percent / 100.0

## Secondary voltage magnitude [V].
##
## `ph` is accepted for API symmetry with ThreePhaseTransformer.
## Always returns secondary_voltage_actual regardless of `ph`.
func secondary_voltage(ph: int = Phase.L1) -> float:
        @warning_ignore("unused_parameter")
        var _ph: int = ph
        return secondary_voltage_actual

## Primary voltage magnitude [V].
##
## `ph` is accepted for API symmetry with ThreePhaseTransformer.
## Always returns primary_voltage_actual regardless of `ph`.
func primary_voltage(ph: int = Phase.L1) -> float:
        @warning_ignore("unused_parameter")
        var _ph: int = ph
        return primary_voltage_actual

## Secondary current magnitude [A].
##
## `ph` is accepted for API symmetry with ThreePhaseTransformer.
## Always returns the magnitude of secondary_current regardless of `ph`.
func secondary_current_magnitude(ph: int = Phase.L1) -> float:
        @warning_ignore("unused_parameter")
        var _ph: int = ph
        if secondary_current == null:
                return 0.0
        return secondary_current.magnitude()

func _to_string() -> String:
        return "Transformer('%s', %.0f/%.0f V, %.0f kVA, tap=%d, T=%.1f°C, %s)" % [
                element_name,
                data.primary_voltage,
                data.secondary_voltage,
                data.rated_power_kva,
                data.tap_position,
                temperature_c,
                operational_state(),
        ]

# ── Three-phase Y-Bus interface (for 3-phase solver compatibility) ────────────

func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _source_np: Dictionary) -> void:
        if damaged or not enabled:
                return
        var n: float    = effective_turns_ratio()
        var ys: Complex = series_admittance()
        var ym: Complex = shunt_admittance()
        var n2: float   = n * n

        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                var key_p: String = node_primary().id   + ":" + str(ph)
                var key_s: String = node_secondary().id + ":" + str(ph)
                var rp: int = np_idx.get(key_p, -1)
                var rs: int = np_idx.get(key_s, -1)
                if rp < 0 or rs < 0:
                        continue
                Y[rp][rp].add_inplace(ys.scale(1.0 / n2))
                Y[rp][rp].add_inplace(ym)
                Y[rs][rs].add_inplace(ys)
                Y[rp][rs].sub_inplace(ys.scale(1.0 / n))
                Y[rs][rp].sub_inplace(ys.scale(1.0 / n))

func update_state_3ph(_dt: float = 0.0) -> void:
        if damaged or not enabled:
                _zero_outputs()
                return
        # Use L1 for scalar quantities — delegates to the main update_state path.
        var v_p: Complex = node_primary().get_voltage(Phase.L1)
        var v_s: Complex = node_secondary().get_voltage(Phase.L1)
        if v_p == null or v_s == null:
                _zero_outputs()
                return
        update_state({}, _dt)
        # Per-phase currents for display / KCL symmetry.
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                var vp: Complex = node_primary().get_voltage(ph)
                var vs: Complex = node_secondary().get_voltage(ph)
                if vp == null or vs == null:
                        currents_by_phase[ph] = Complex.zero()
                        continue
                var n: float    = effective_turns_ratio()
                var ys: Complex = series_admittance()
                var ym: Complex = shunt_admittance()
                var i_s: Complex = vp.scale(1.0 / n).sub(vs).mul(ys)
                var i_p: Complex = i_s.scale(1.0 / n).add(vp.mul(ym))
                currents_by_phase[ph] = i_p
        current = currents_by_phase.get(Phase.L1, Complex.zero())
