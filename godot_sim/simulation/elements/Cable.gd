## Cable.gd
## Resistive conductor connecting two SimNodes (1-fazni / jedan provodnik).
##
## Fizika, termalni model i sve zajedničko sa ThreePhaseCable žive u
## CableBase. Ovaj fajl sadrži samo ono specifično za 1-fazni kabl:
##   - impedansu/admitansu (uključujući reaktansu)
##   - Y-bus stamp (uključujući stamp_ybus_3ph sa assigned_phase)
##   - update_state / update_state_3ph
##   - diagnostiku (voltage_drop, apparent_power, active/total loss)
##
## Multi-phase note:
##   `assigned_phase` controls which phase row this cable stamps on in the
##   5N ThreePhaseYBusSolver matrix.  Default is Phase.L1 (backward compatible).

class_name Cable
extends CableBase

# Optional reactance per metre [Ω/m] — set to >0 to model line inductance
var reactance_per_m: float = 0.0

## Rated current for this conductor [A].
var max_current: float = INF

## Which phase conductor this single-phase cable represents.
## Phase.L1 (default) = backward compatible; set to L2, L3, NEUTRAL, or PE
## when this cable is dedicated to a specific conductor.
var assigned_phase: int = Phase.L1

func _init(
		node_a: SimNode,
		node_b: SimNode,
		p_length_m: float,
		p_cross_mm2: float,
		p_material: String = "copper",
		p_max_current: float = INF,
		p_name: String = ""
) -> void:
	super._init(p_name)
	terminals   = [[node_a], [node_b]]
	length_m    = p_length_m
	cross_mm2   = p_cross_mm2
	material    = p_material.to_lower()
	max_current = p_max_current
	if not SimConstants.RESISTIVITY.has(material):
		push_error("Cable: unknown material '%s'" % material)

# ── Electrical properties ───────────────────────────────────────────

## Resistance corrected for the current conductor temperature.
func resistance() -> float:
	var r_cold: float = _resistance_cold_from_cross_section()
	if is_inf(r_cold):
		return INF
	return r_cold * _temp_factor()

func resistance_cold() -> float:
	return _resistance_cold_from_cross_section()

func reactance() -> float:
	return reactance_per_m * length_m

func impedance() -> Complex:
	return Complex.new(resistance(), reactance())

func admittance() -> Complex:
	return impedance().reciprocal()

func dissipated_power() -> float:
	var i_mag: float = 0.0 if current == null else current.magnitude()
	return i_mag * i_mag * resistance()

## Osnova za termalni model iz CableBase — 1-fazni kabl ima samo jednu struju.
func _heating_power_w() -> float:
	return dissipated_power()

# ── Solver stamps ───────────────────────────────────────────────────

## Three-phase stamp: uses assigned_phase to select the correct matrix row.
## This overrides the default CircuitElement fallback which always uses Phase.L1.
func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _source_np: Dictionary) -> void:
	if damaged or not enabled:
		return
	var key_a: String = node_a().id + ":" + str(assigned_phase)
	var key_b: String = node_b().id + ":" + str(assigned_phase)
	var ra: int = np_idx.get(key_a, -1)
	var rb: int = np_idx.get(key_b, -1)
	if ra < 0 or rb < 0:
		return
	var y: Complex = admittance()
	Y[ra][ra].add_inplace(y)
	Y[rb][rb].add_inplace(y)
	Y[ra][rb].sub_inplace(y)
	Y[rb][ra].sub_inplace(y)

## Three-phase state update: reads voltage from assigned_phase.
func update_state_3ph(_dt: float = 0.0) -> void:
	if damaged or not enabled:
		current       = Complex.zero()
		is_overloaded = false
		currents_by_phase[assigned_phase] = Complex.zero()
		_temp_at_last_solve = temperature_c
		return
	var va: Complex = node_a().get_voltage(assigned_phase)
	var vb: Complex = node_b().get_voltage(assigned_phase)
	if va == null or vb == null:
		current       = Complex.zero()
		is_overloaded = false
		currents_by_phase[assigned_phase] = Complex.zero()
		_temp_at_last_solve = temperature_c
		return
	current = va.sub(vb).div(impedance())
	is_overloaded = current.magnitude() > max_current
	currents_by_phase[assigned_phase] = current
	_temp_at_last_solve = temperature_c

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	if damaged:
		return
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	var y: Complex = admittance()
	Y[i][i].add_inplace(y)
	Y[j][j].add_inplace(y)
	Y[i][j].sub_inplace(y)
	Y[j][i].sub_inplace(y)

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	if damaged or not enabled:
		current       = Complex.zero()
		is_overloaded = false
		_temp_at_last_solve = temperature_c
		return
	var va: Complex = node_a().voltage
	var vb: Complex = node_b().voltage
	if va == null or vb == null:
		current       = Complex.zero()
		is_overloaded = false
		_temp_at_last_solve = temperature_c
		return
	current       = va.sub(vb).div(impedance())
	is_overloaded = current.magnitude() > max_current
	_temp_at_last_solve = temperature_c

# ── Diagnostics ─────────────────────────────────────────────────────

## Current magnitude [A].  Alias for consistent API with ThreePhaseCable.
func current_magnitude(_ph: int = Phase.L1) -> float:
	return 0.0 if current == null else current.magnitude()

func loading_percent() -> float:
	if current == null or max_current == INF:
		return -1.0
	return current.magnitude() / max_current * 100.0

func voltage_drop() -> Complex:
	var va: Complex = node_a().voltage
	var vb: Complex = node_b().voltage
	if va == null or vb == null:
		return null
	return va.sub(vb)

func apparent_power() -> Complex:
	var dv: Complex = voltage_drop()
	if dv == null or current == null:
		return null
	return dv.mul(current.conjugate())

## Active power loss [W].  Mirrors ThreePhaseCable.active_loss_w() API.
func active_loss_w(_ph: int = Phase.L1) -> float:
	var dv: Complex = voltage_drop()
	if dv == null or current == null:
		return 0.0
	return dv.mul(current.conjugate()).re

## Total active loss [W].  For a single-phase cable this equals active_loss_w().
func total_loss_w() -> float:
	return active_loss_w()

func _to_string() -> String:
	return "Cable('%s', %.0fm, %.1fmm², %s, ph=%d, T=%.1f°C%s%s)" % [
		element_name, length_m, cross_mm2, material, assigned_phase,
		temperature_c,
		", DAMAGED" if damaged else "",
		", OVL" if is_overloaded else "",
	]
