## TransformerData.gd
## Configuration resource for a single-phase (or future multi-phase) transformer.
##
## Extends Resource so it can be saved as a .tres asset in the Godot editor,
## configured via the Inspector, and shared between multiple Transformer instances.
##
## ── How to use ────────────────────────────────────────────────────────────────
##   var td := TransformerData.new()
##   td.primary_voltage   = 11000.0
##   td.secondary_voltage = 400.0
##   td.rated_power_kva   = 100.0
##   var t := Transformer.new(node_p, node_s, td, "MV/LV main")
##
## ── Parameter conventions ──────────────────────────────────────────────────────
##   All voltages in Volts, power in kVA/kW, currents in Amperes.
##   Per-unit quantities (pu) are on the transformer's own MVA/kV base.
##   "referred to secondary" means quantities are expressed on the LV side.
##
## ── Three-phase readiness ─────────────────────────────────────────────────────
##   phase_count, vector_group, and neutral_grounded are stored here so the
##   future ThreePhaseTransformer subclass can read the same resource without
##   a schema change.  Single-phase operation ignores them.

class_name TransformerData
extends Resource

# ── Nameplate — voltage & power ───────────────────────────────────────────────

## Rated primary (HV / input) voltage [V].
@export var primary_voltage: float = 11000.0

## Rated secondary (LV / output) voltage at no load [V].
@export var secondary_voltage: float = 400.0

## Rated apparent power [kVA].
@export var rated_power_kva: float = 100.0

## Nominal frequency [Hz].
@export var frequency_hz: float = 50.0

# ── Winding impedance (per-unit on transformer own base) ──────────────────────
##
## Per-unit base:   Z_base = V2_rated² / S_rated_VA
##
## Actual ohms referred to secondary:
##   R_eq = winding_resistance_pu × Z_base
##   X_eq = leakage_reactance_pu  × Z_base

## Total winding (series) resistance, both windings referred to secondary [pu].
## Typical distribution transformer: 0.01 (1%) to 0.02 (2%).
@export var winding_resistance_pu: float = 0.01

## Total leakage reactance, both windings referred to secondary [pu].
## Typical distribution transformer: 0.04 (4%) to 0.06 (6%).
@export var leakage_reactance_pu: float = 0.05

# ── No-load (core / iron) losses ──────────────────────────────────────────────

## Magnetising current as a percentage of rated primary current [%].
## Drives the imaginary part of the shunt admittance (reactive no-load current).
## Typical: 0.5 %–3 % for distribution transformers.
@export var magnetizing_current_percent: float = 1.0

## No-load (core / iron) losses [kW].
## Applied constantly regardless of load.  Drives the real part of the shunt.
@export var core_loss_kw: float = 0.3

# ── Full-load (copper / winding) losses ───────────────────────────────────────
## Nameplate copper loss at rated current [kW].
## Used as a reference / cross-check.  The simulation derives actual copper loss
## from winding_resistance_pu so it scales correctly with current.
@export var copper_loss_kw: float = 1.5

# ── Tap changer ───────────────────────────────────────────────────────────────

## Current tap position (integer step, 0 = nominal ratio).
## Positive → raises secondary voltage; negative → lowers it.
@export var tap_position: int = 0

## Voltage step per tap position [% of rated secondary voltage].
@export var tap_step_percent: float = 2.5

## Maximum allowed positive tap steps.
@export var max_tap_up: int = 2

## Maximum (absolute) allowed negative tap steps.
@export var max_tap_down: int = 2

# ── Thermal model ─────────────────────────────────────────────────────────────
##
## Lumped first-order model:
##   C_th · dT/dt = P_loss − (T − T_amb) / R_th
##
##   C_th = thermal_capacity_kj_per_k × 1000   [J/K]
##   R_th = 1 / (cooling_rate_kw_per_k × 1000) [K/W]

## Total thermal mass of the transformer body (core + windings + oil) [kJ/K].
## Oil-cooled distribution transformers: 50–200 kJ/K.
## Dry-type small transformers: 5–30 kJ/K.
@export var thermal_capacity_kj_per_k: float = 50.0

## Thermal conductance to ambient [kW/K].  Higher → cools faster.
## Equivalent to 1/R_thermal.
@export var cooling_rate_kw_per_k: float = 0.05

## Temperature at which the transformer is considered damaged [°C].
## Insulation class limits: A=105°C, E=120°C, B=130°C, F=155°C, H=180°C.
@export var max_temperature_c: float = 120.0

## Ambient (surrounding air or oil) temperature [°C].
@export var ambient_temperature_c: float = 25.0

## True when the transformer uses oil cooling (ONAN / ONAF / OFAF).
## Informational flag — no mechanical model of the oil pump yet.
@export var oil_cooled: bool = true

# ── Operational flags ─────────────────────────────────────────────────────────

## If false the transformer contributes nothing to the Y-bus (open breaker).
@export var enabled: bool = true

# ── Three-phase preparation (ignored by current single-phase implementation) ──

## Number of phases (1 = single-phase, 3 = three-phase).
@export var phase_count: int = 1

## IEC vector group (e.g. "Dyn11", "YNyn0", "Yd1").
## Reserved for the future ThreePhaseTransformer subclass.
@export var vector_group: String = "Ii0"

## Whether the secondary neutral is solidly grounded.
@export var neutral_grounded: bool = true

# ── Helpers ───────────────────────────────────────────────────────────────────

## Rated apparent power in VA (convenience).
func rated_power_va() -> float:
	return rated_power_kva * 1e3

## Rated primary current [A].
func rated_primary_current_a() -> float:
	return rated_power_va() / max(primary_voltage, 1.0)

## Rated secondary current [A].
func rated_secondary_current_a() -> float:
	return rated_power_va() / max(secondary_voltage, 1.0)

## Secondary-side base impedance [Ω].  Per-unit quantities multiply by this.
func secondary_base_impedance_ohm() -> float:
	return (secondary_voltage * secondary_voltage) / max(rated_power_va(), 1.0)

## Nominal turns ratio n = V1_rated / V2_rated (always ≥ 1 for step-down).
func nominal_turns_ratio() -> float:
	return primary_voltage / max(secondary_voltage, 1.0)

## Effective turns ratio including the current tap position.
## n_eff = n_nominal × (1 + tap_position × tap_step_percent / 100)
## A positive tap step raises the secondary voltage (lowers n_eff).
func effective_turns_ratio() -> float:
	var tap_factor: float = 1.0 + float(tap_position) * tap_step_percent / 100.0
	return nominal_turns_ratio() * tap_factor

## Validate the tap position and clamp it to the allowed range.
func validate_tap(pos: int) -> int:
	return clampi(pos, -abs(max_tap_down), abs(max_tap_up))

## Verify copper-loss consistency:
## returns the winding-resistance-derived rated copper loss [kW].
## Should be close to copper_loss_kw for a well-parameterised transformer.
func derived_copper_loss_kw() -> float:
	var z_base: float  = secondary_base_impedance_ohm()
	var r_eq: float    = winding_resistance_pu * z_base
	var i2: float      = rated_secondary_current_a()
	return i2 * i2 * r_eq / 1e3
