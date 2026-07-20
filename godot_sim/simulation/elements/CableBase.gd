## CableBase.gd
## Zajednička baza za Cable (1-fazni) i ThreePhaseCable (3-fazni).
##
## Sadrži sve što je identično kod oba tipa kabla:
##   - fizičke parametre provodnika (dužina, presek, materijal, ageing)
##   - termalni model (kapacitet, otpor, vremenska konstanta, integracija)
##   - game-state (damaged / is_overloaded / is_overheated)
##   - game akcije (connect/disconnect/damage/repair)
##   - temperaturski korigovan proračun otpora iz preseka + materijala
##
## Podklase (Cable, ThreePhaseCable) implementiraju samo ono specifično za
## broj faza: impedansu/admitansu, Y-bus stamp, update_state, i osnovu za
## Joule disipaciju (override _heating_power_w()).
##
## Termalni model (lumped first-order):
##   Joule heating         P_in  = _heating_power_w()
##   Newton cooling        P_out = (T - T_ambient) / R_thermal
##   Heat balance          C_th · dT/dt = P_in - P_out
##   ↓ discretised (forward Euler, sub-stepped if dt is large):
##                         T(t+dt) = T(t) + (dt / τ) · (T_ss - T(t))
##   where τ = C_th · R_thermal and T_ss = T_ambient + P_in · R_thermal.

class_name CableBase
extends CircuitElement

# ── Fizički parametri provodnika ──────────────────────────────────────────────
var length_m: float
var cross_mm2: float = 0.0
var material: String = "copper"
var ageing_factor: float = 1.0      # 1.0 = brand new

# ── Termalno stanje i konfiguracija ───────────────────────────────────────────
var temperature_c: float = SimConstants.DEFAULT_AMBIENT_C
var ambient_c: float     = SimConstants.DEFAULT_AMBIENT_C

var thermal_capacity_per_m: float   = 0.0
var thermal_resistance_per_m: float = SimConstants.DEFAULT_THERMAL_RESISTANCE_PER_M
var insulation_max_c: float         = SimConstants.DEFAULT_INSULATION_MAX_C
var damage_temp_c: float            = SimConstants.DEFAULT_DAMAGE_TEMP_C
var thermal_damage_enabled: bool    = true

# ── Game-state ────────────────────────────────────────────────────────────────
var damaged: bool       = false
var is_overloaded: bool = false
var is_overheated: bool = false

const _TEMP_DIRTY_DELTA_C: float = 1.0
var _temp_at_last_solve: float = SimConstants.DEFAULT_AMBIENT_C

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

# ── Temperaturski korigovan otpor iz preseka + materijala ─────────────────────

## Temperaturski faktor: (1 + α·(T - T_ref)). α je osobina materijala i važi
## bez obzira da li je R₂₀ izračunat iz preseka ili zadat direktno (Ω/m) —
## fizički zakon otpora ne zavisi od toga OTKUD znamo R₂₀.
func _temp_factor() -> float:
	var alpha: float = SimConstants.TEMP_COEFF_PER_C.get(material, 3.93e-3)
	return 1.0 + alpha * (temperature_c - SimConstants.TEMP_REFERENCE_C)

## R₂₀ (otpor na referentnoj temperaturi) jednog provodnika iz preseka i
## materijala [Ω]. Vraća INF ako cross_mm2 nije postavljen — pozivalac mora
## imati fallback (npr. direktno zadat resistance_per_m).
func _resistance_cold_from_cross_section() -> float:
	if cross_mm2 <= 0.0:
		return INF
	var rho_20: float = SimConstants.RESISTIVITY.get(material, 1.72e-8)
	return rho_20 * length_m / (cross_mm2 * 1e-6) * ageing_factor

# ── Termalne osobine ───────────────────────────────────────────────────────────

func thermal_capacity_total() -> float:
	if thermal_capacity_per_m > 0.0:
		return thermal_capacity_per_m * length_m
	if cross_mm2 <= 0.0:
		push_warning("%s '%s': cross_mm2 nije postavljen — termalni model je onemogućen. Postavi cross_mm2 ili thermal_capacity_per_m." % [get_class(), element_name])
		return 0.0
	var c_vol: float = SimConstants.VOLUMETRIC_HEAT_CAPACITY.get(material, 3.45e6)
	return c_vol * cross_mm2 * 1e-6 * length_m

func thermal_resistance_total() -> float:
	var L: float = max(length_m, 1.0e-3)
	return thermal_resistance_per_m / L

func thermal_time_constant() -> float:
	var c: float = thermal_capacity_total()
	var r: float = thermal_resistance_total()
	if c <= 0.0 or r <= 0.0:
		return 0.0
	return c * r

func steady_state_temperature() -> float:
	var p: float = _heating_power_w()
	return ambient_c + p * thermal_resistance_total()

func thermal_loading() -> float:
	var span: float = insulation_max_c - ambient_c
	if span <= 0.0:
		return 0.0
	return (temperature_c - ambient_c) / span

## Snaga koja greje provodnik u ovom koraku [W]. Podklasa određuje da li se
## bazira na jednoj struji (1-fazni) ili na najgoroj fazi (3-fazni).
## Bazna implementacija vraća 0 — svaka podklasa MORA da je override-uje.
func _heating_power_w() -> float:
	return 0.0

# ── Termalna integracija ───────────────────────────────────────────────────────

## Advance the thermal state by `dt` seconds. Returns true if newly damaged.
func update_thermal(dt: float, p_ambient_c: float = NAN) -> bool:
	if dt <= 0.0:
		return false
	if not is_nan(p_ambient_c):
		ambient_c = p_ambient_c
	if damaged:
		_relax_to_ambient(dt)
		return false
	if not enabled:
		_relax_to_ambient(dt)
		_check_dirty_from_temp_change()
		return false

	var c_th: float = thermal_capacity_total()
	var r_th: float = thermal_resistance_total()
	if c_th <= 0.0 or r_th <= 0.0:
		return false

	var tau: float    = c_th * r_th
	var steps: int    = max(1, int(ceil(dt / max(tau * 0.25, 1.0e-3))))
	var sub_dt: float = dt / float(steps)
	var newly_damaged: bool = false

	for _i in steps:
		var p_in: float  = _heating_power_w()
		var p_out: float = (temperature_c - ambient_c) / r_th
		temperature_c += (p_in - p_out) * sub_dt / c_th

	is_overheated = temperature_c > insulation_max_c

	if thermal_damage_enabled and temperature_c >= damage_temp_c and not damaged:
		damage()
		newly_damaged = true

	_check_dirty_from_temp_change()
	return newly_damaged

## Cool the cable toward ambient (used when disabled or damaged).
func _relax_to_ambient(dt: float) -> void:
	var c_th: float = thermal_capacity_total()
	var r_th: float = thermal_resistance_total()
	if c_th <= 0.0 or r_th <= 0.0:
		return
	var tau: float   = c_th * r_th
	var alpha: float = clampf(dt / tau, 0.0, 1.0)
	temperature_c += (ambient_c - temperature_c) * alpha
	is_overheated = temperature_c > insulation_max_c

func _check_dirty_from_temp_change() -> void:
	if absf(temperature_c - _temp_at_last_solve) >= _TEMP_DIRTY_DELTA_C:
		mark_dirty()

# ── Game akcije ─────────────────────────────────────────────────────────────

func disconnect_cable() -> void:
	disable()

func connect_cable() -> void:
	enable()

func damage() -> void:
	damaged = true
	enabled = false
	mark_dirty()

func repair() -> void:
	damaged       = false
	enabled       = true
	temperature_c = ambient_c
	is_overheated = false
	_temp_at_last_solve = temperature_c
	mark_dirty()
