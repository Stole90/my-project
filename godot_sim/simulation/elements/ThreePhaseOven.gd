## ThreePhaseOven.gd
## Three-phase electric oven — delta-connected heating element.
##
## Modelled as a balanced delta load whose total power varies with the
## selected cooking mode.  A first-order RC thermal model tracks the
## oven cavity temperature and drives a simple thermostat that cycles
## the heating element on/off around the target temperature.
##
## ── Cooking modes and nominal total 3-phase power ─────────────────────────────
##   OFF      —   0 W
##   PREHEAT  — 1200 W  (fast ramp to 180 °C)
##   BAKE     — 2000 W  (sustained even heat, 200 °C)
##   GRILL    — 2800 W  (top-element full, 250 °C)
##   BROIL    — 3200 W  (maximum, 280 °C)
##
## ── Electrical connection ─────────────────────────────────────────────────────
##   Delta (L1-L2, L2-L3, L3-L1).  All three heating element resistances
##   are equal → perfectly balanced load on a balanced supply.
##
## ── Backward compatibility ────────────────────────────────────────────────────
##   ThreePhaseOven extends ThreePhaseConsumer.  On a single-phase
##   YBusSolver (fallback) only the L1-L2 element is visible via the
##   parent class' stamp_ybus (delta pair 0).

class_name ThreePhaseOven
extends ThreePhaseConsumer

# ── Mode definitions ──────────────────────────────────────────────────────────

const MODE_OFF:     String = "off"
const MODE_PREHEAT: String = "preheat"
const MODE_BAKE:    String = "bake"
const MODE_GRILL:   String = "grill"
const MODE_BROIL:   String = "broil"

## Map mode name → nominal total 3-phase power [W].
const MODE_POWER_W: Dictionary = {
        "off":     0.0,
        "preheat": 2200.0,
        "bake":    2500.0,
        "grill":   2800.0,
        "broil":   3200.0,
}

## Map mode name → target cavity temperature [°C].
const MODE_TARGET_TEMP_C: Dictionary = {
        "off":     20.0,
        "preheat": 180.0,
        "bake":    200.0,
        "grill":   250.0,
        "broil":   280.0,
}

# ── State ─────────────────────────────────────────────────────────────────────

## Current cooking mode string.
var cook_mode: String = MODE_OFF

## Target cavity temperature for the current mode [°C].
var target_temp_c: float = 20.0

# ── Thermal model ─────────────────────────────────────────────────────────────

## Current oven cavity temperature [°C].
var oven_temp_c: float = 20.0

## Ambient / room temperature [°C].
var ambient_temp_c: float = 20.0

## Maximum rated cavity temperature [°C].
var max_oven_temp_c: float = 320.0

## Thermal capacity of oven cavity [J/K].  Typical domestic oven ≈ 5-8 kJ/K.
var thermal_capacity_j_per_k: float = 600.0

## Thermal resistance to ambient [K/W].  Good insulation → small value.
## 0.04 K/W → ~25 W heat loss per Kelvin above ambient.
var thermal_resistance_k_per_w: float = 0.13

## True when thermostat is satisfied (element OFF during coast-down).
var thermostat_satisfied: bool = false

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(bus_node: SimNode, p_name: String = "Oven") -> void:
        super._init(bus_node, p_name)
        connection    = CONNECTION_DELTA
        nominal_v_ll  = SimConstants.NOMINAL_V * sqrt(3.0)
        nominal_v_ln  = SimConstants.NOMINAL_V
        _apply_mode_power()

# ── Mode API ──────────────────────────────────────────────────────────────────

## Set cooking mode.  Resets thermostat and re-stamps admittances.
func set_mode(mode: String) -> void:
        if not MODE_POWER_W.has(mode):
                push_error("ThreePhaseOven: unknown mode '%s'" % mode)
                return
        cook_mode             = mode
        target_temp_c         = MODE_TARGET_TEMP_C[mode]
        thermostat_satisfied  = false
        enabled               = (mode != MODE_OFF)
        _apply_mode_power()
        mark_dirty()

func mode_power_w() -> float:
        return MODE_POWER_W.get(cook_mode, 0.0)

func is_heating() -> bool:
        return enabled and cook_mode != MODE_OFF and not thermostat_satisfied

func temp_percent() -> float:
        var range_c: float = max_oven_temp_c - ambient_temp_c
        return clampf((oven_temp_c - ambient_temp_c) / range_c * 100.0, 0.0, 100.0)

# ── Internal helpers ──────────────────────────────────────────────────────────

func _apply_mode_power() -> void:
        var p_total: float = MODE_POWER_W.get(cook_mode, 0.0)
        var v2_ll: float = nominal_v_ll * nominal_v_ll
        if v2_ll < 1.0:
                v2_ll = (SimConstants.NOMINAL_V * sqrt(3.0)) * (SimConstants.NOMINAL_V * sqrt(3.0))
        var s_pair: Complex = Complex.new(p_total / 3.0, 0.0)
        for pair_idx in range(3):
                phase_power[pair_idx] = s_pair

# ── Three-phase state update ──────────────────────────────────────────────────

func update_state_3ph(dt: float = 0.0) -> void:
        # Update nominal_v_ll from actual solved voltages for accurate power
        var va: Complex = bus_node().get_voltage(Phase.L1)
        var vb: Complex = bus_node().get_voltage(Phase.L2)
        if va != null and vb != null:
                var vll: float = va.sub(vb).magnitude()
                if vll > 1.0:
                        nominal_v_ll = vll
                        nominal_v_ln = vll / sqrt(3.0)
                        _apply_mode_power()

        # Parent computes per-phase delta currents
        super.update_state_3ph(dt)

        if dt <= 0.0:
                return

        # ── Thermostat cycling ────────────────────────────────────────────
        var hyst: float = 5.0
        if thermostat_satisfied and oven_temp_c <= target_temp_c - hyst:
                thermostat_satisfied = false
                if cook_mode != MODE_OFF:
                        enabled = true
                        mark_dirty()
        elif not thermostat_satisfied and oven_temp_c >= target_temp_c + hyst:
                thermostat_satisfied = true
                enabled = false
                mark_dirty()

        # ── First-order thermal model ─────────────────────────────────────
        var p_in: float  = total_active_power_w() if enabled else 0.0
        var p_loss: float = (oven_temp_c - ambient_temp_c) / thermal_resistance_k_per_w
        var dT: float     = (p_in - p_loss) * dt / thermal_capacity_j_per_k
        oven_temp_c = clampf(oven_temp_c + dT, ambient_temp_c, max_oven_temp_c + 20.0)

func _to_string() -> String:
        return "ThreePhaseOven('%s', mode=%s, %.0f°C, %.0f W)" % [
                element_name, cook_mode, oven_temp_c, total_active_power_w()
        ]
