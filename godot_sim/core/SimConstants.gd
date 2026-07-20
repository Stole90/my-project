## SimConstants.gd
## Global numeric defaults for the simulation layer.
## Centralised so they are no longer hardcoded inside individual elements.

class_name SimConstants
extends RefCounted

# ── Network frequency ───────────────────────────────────────────────
const FREQUENCY_HZ: float = 50.0
const OMEGA: float        = 2.0 * PI * FREQUENCY_HZ   # rad/s

# ── Numerical conditioning ──────────────────────────────────────────
const G_FLOOR: float       = 1.0e-9   # ground shunt to prevent singular Y
const PIVOT_EPSILON: float = 1.0e-30  # singular-matrix detection threshold

# ── Default voltage envelope (single-phase EU mains) ────────────────
const NOMINAL_V: float        = 230.0
const UNDERVOLTAGE_PU: float  = 0.85   # trip threshold
const OVERVOLTAGE_PU:  float  = 1.10   # damage threshold

# ── Material resistivities [Ω·m] @ 20°C ─────────────────────────────
const RESISTIVITY: Dictionary = {
        "copper":    1.72e-8,
        "aluminium": 2.82e-8,
        "aluminum":  2.82e-8,
}

# ── Thermal — material properties ───────────────────────────────────
# Reference temperature for tabulated resistivity values [°C].
const TEMP_REFERENCE_C: float = 20.0

# Linear temperature coefficient of resistivity α [1/K] @ 20°C.
# ρ(T) = ρ₂₀ · (1 + α · (T - 20°C))
const TEMP_COEFF_PER_C: Dictionary = {
        "copper":    3.93e-3,
        "aluminium": 4.03e-3,
        "aluminum":  4.03e-3,
}

# Volumetric heat capacity c_v = ρ_mass · c_p  [J/(K·m³)].
# Used to derive a default thermal capacity from a cable's
# cross-section + length when the user does not override it.
const VOLUMETRIC_HEAT_CAPACITY: Dictionary = {
        "copper":    3.45e6,    # 8960 kg/m³ · 385 J/(kg·K)
        "aluminium": 2.42e6,    # 2700 kg/m³ · 897 J/(kg·K)
        "aluminum":  2.42e6,
}

# Default thermal resistance to ambient per metre [K·m/W]
# for a typical PVC-insulated cable in still air. Tuned so that
# the time constant τ = C·R for small cross-sections lands in
# the tens-of-seconds range, which keeps overheating visible
# in gameplay without being instant.
const DEFAULT_THERMAL_RESISTANCE_PER_M: float = 4.0

# Default insulation thermal limits [°C]
const DEFAULT_INSULATION_MAX_C: float  = 90.0   # PVC continuous rating
const DEFAULT_DAMAGE_TEMP_C: float     = 160.0  # insulation breakdown

# Default ambient temperature [°C] for thermal calculations
const DEFAULT_AMBIENT_C: float = 25.0

# ── Transformer defaults ────────────────────────────────────────────
# Typical per-unit leakage impedance for distribution transformers.
const DEFAULT_TRANSFORMER_R_PU: float = 0.01    # 1% winding resistance
const DEFAULT_TRANSFORMER_X_PU: float = 0.05    # 5% leakage reactance

# Typical magnetising / no-load parameters.
const DEFAULT_TRANSFORMER_MAG_PERCENT: float = 1.0   # 1% magnetising current
const DEFAULT_TRANSFORMER_CORE_LOSS_KW: float = 0.3  # kW, iron losses

# Thermal defaults for a 100 kVA oil-cooled distribution transformer.
const DEFAULT_TRANSFORMER_THERMAL_CAP_KJ_PER_K: float = 50.0
const DEFAULT_TRANSFORMER_COOLING_RATE_KW_PER_K: float = 0.05

# Insulation temperature limits [°C].
const DEFAULT_TRANSFORMER_OVERHEAT_C: float = 95.0   # insulation starts to degrade
const DEFAULT_TRANSFORMER_DAMAGE_C: float   = 120.0  # class-E winding limit


# ── Socket / contact thermal defaults ──────────────────────────────
# Resistivity of common contact materials [Ω·m] @ 20°C.
const CONTACT_RESISTIVITY: Dictionary = {
        "brass":          7.0e-8,
        "copper":         1.72e-8,
        "stainless_steel":7.4e-7,
}

# Temperature coefficient of resistivity α [1/K] for contact materials.
const CONTACT_TEMP_COEFF_PER_C: Dictionary = {
        "brass":          1.5e-3,
        "copper":         3.93e-3,
        "stainless_steel":0.9e-3,
}

# Typical per-contact volumetric heat capacity [J/(K·m³)].
# Used to derive C_th from contact_volume_mm3 when user does not override.
const CONTACT_VOLUMETRIC_HEAT_CAPACITY: Dictionary = {
        "brass":          3.0e6,   # ~8500 kg/m³ · 380 J/(kg·K)
        "copper":         3.45e6,
        "stainless_steel":3.9e6,   # ~7900 kg/m³ · 500 J/(kg·K)
}

# Default total thermal capacity of a socket body [J/K].
# Accounts for brass contacts + plastic housing mass.
const DEFAULT_SOCKET_THERMAL_CAPACITY_J_PER_K: float = 100.0

# Default thermal resistance of socket to ambient [K/W].
# Plastic housing provides moderate insulation from air.
const DEFAULT_SOCKET_THERMAL_RESISTANCE_K_PER_W: float = 10.0

# Default socket insulation soft-limit (PVC enclosure) [°C].
const DEFAULT_SOCKET_INSULATION_MAX_C: float = 70.0

# Default socket damage temperature [°C]
# (contacts oxidise / weld / housing melts at this point).
const DEFAULT_SOCKET_DAMAGE_TEMP_C: float = 120.0

# Standard socket contact resistance values (new, clean contacts) [Ω].
const SOCKET_CONTACT_RESISTANCE_NEW_OHM: float  = 0.005   # 5 mΩ — good socket
const SOCKET_CONTACT_RESISTANCE_WORN_OHM: float = 0.050   # 50 mΩ — worn
const SOCKET_CONTACT_RESISTANCE_FAULTY_OHM: float = 0.5   # 500 mΩ — arc risk

# ── Three-phase reference angles [rad] ──────────────────────────────
# Phase L1 = 0°, L2 = -120°, L3 = +120°
const PHASE_ANGLE_RAD: Array = [0.0, -2.0 * PI / 3.0, 2.0 * PI / 3.0]

# ── Time-domain (transient solver) defaults ─────────────────────────
const DEFAULT_DELTA_T: float = 1.0e-3   # 1 ms
