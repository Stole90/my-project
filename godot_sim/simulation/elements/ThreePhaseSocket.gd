## ThreePhaseSocket.gd
## Trofazna utičnica — tri nezavisna kontakta (L1, L2, L3).
## Svaki kontakt modelovan kao serijski otpornik R_contact.

class_name ThreePhaseSocket
extends CircuitElement

var contact_resistance_cold_ohm: float = SimConstants.SOCKET_CONTACT_RESISTANCE_NEW_OHM
var contact_material: String = "brass"
var max_current_a: float = 16.0
var ageing_factor: float = 1.0
var plugged_in: bool = true
var damaged: bool = false
var is_overloaded: bool = false
var is_overheated: bool = false
var temperature_c: float = SimConstants.DEFAULT_AMBIENT_C
var ambient_c: float = SimConstants.DEFAULT_AMBIENT_C
var thermal_capacity_j_per_k: float = SimConstants.DEFAULT_SOCKET_THERMAL_CAPACITY_J_PER_K
var thermal_resistance_k_per_w: float = SimConstants.DEFAULT_SOCKET_THERMAL_RESISTANCE_K_PER_W
var insulation_max_c: float = SimConstants.DEFAULT_SOCKET_INSULATION_MAX_C
var damage_temp_c: float = SimConstants.DEFAULT_SOCKET_DAMAGE_TEMP_C
var thermal_damage_enabled: bool = true

const _TEMP_DIRTY_DELTA_C: float = 1.0
var _temp_at_last_solve: float = SimConstants.DEFAULT_AMBIENT_C

func _init(
    node_supply: SimNode,
    node_load: SimNode,
    p_r_cold: float = SimConstants.SOCKET_CONTACT_RESISTANCE_NEW_OHM,
    p_max_a: float = 16.0,
    p_material: String = "brass",
    p_name: String = ""
) -> void:
    super._init(p_name)
    terminals = [[node_supply], [node_load]]
    contact_resistance_cold_ohm = p_r_cold
    max_current_a = p_max_a
    contact_material = p_material.to_lower()

func node_supply() -> SimNode: return terminals[0][0]
func node_load()   -> SimNode: return terminals[1][0]

func resistance() -> float:
    var alpha: float = SimConstants.CONTACT_TEMP_COEFF_PER_C.get(contact_material, 1.5e-3)
    return contact_resistance_cold_ohm * ageing_factor * (1.0 + alpha * (temperature_c - SimConstants.TEMP_REFERENCE_C))

func admittance() -> Complex:
    var r: float = resistance()
    return Complex.new(1.0 / max(r, 1e-9), 0.0)

func dissipated_power() -> float:
    var i_total: float = 0.0
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        var c: Complex = currents_by_phase.get(ph, null)
        if c != null:
            i_total += c.magnitude() * c.magnitude()
    return i_total * resistance()

# ── Stamps ────────────────────────────────────────────────────────────

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _src: Array) -> void:
    if damaged or not enabled or not plugged_in:
        return
    var i: int = node_idx.get(node_supply(), -1)
    var j: int = node_idx.get(node_load(),   -1)
    if i < 0 or j < 0:
        return
    var y: Complex = admittance()
    Y[i][i].add_inplace(y); Y[j][j].add_inplace(y)
    Y[i][j].sub_inplace(y); Y[j][i].sub_inplace(y)

func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _src_np: Dictionary) -> void:
    if damaged or not enabled or not plugged_in:
        return
    var y: Complex = admittance()
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        var rs: int = np_idx.get(node_supply().id + ":" + str(ph), -1)
        var rl: int = np_idx.get(node_load().id   + ":" + str(ph), -1)
        if rs < 0 or rl < 0:
            continue
        Y[rs][rs].add_inplace(y); Y[rl][rl].add_inplace(y)
        Y[rs][rl].sub_inplace(y); Y[rl][rs].sub_inplace(y)

# ── State update ──────────────────────────────────────────────────────

func update_state(_nv: Dictionary, _dt: float = 0.0) -> void:
    if damaged or not enabled or not plugged_in:
        current = Complex.zero()
        is_overloaded = false
        return
    var vs: Complex = node_supply().get_voltage(Phase.L1)
    var vl: Complex = node_load().get_voltage(Phase.L1)
    if vs == null or vl == null:
        current = Complex.zero()
        return
    current = vs.sub(vl).div(Complex.new(resistance(), 0.0))
    is_overloaded = current.magnitude() > max_current_a
    _temp_at_last_solve = temperature_c

func update_state_3ph(_dt: float = 0.0) -> void:
    if damaged or not enabled or not plugged_in:
        current = Complex.zero()
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
            currents_by_phase[ph] = Complex.zero()
        is_overloaded = false
        _temp_at_last_solve = temperature_c
        return
    var z: Complex = Complex.new(resistance(), 0.0)
    var max_mag: float = 0.0
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        var vs: Complex = node_supply().get_voltage(ph)
        var vl: Complex = node_load().get_voltage(ph)
        if vs == null or vl == null:
            currents_by_phase[ph] = Complex.zero()
            continue
        var i: Complex = vs.sub(vl).div(z)
        currents_by_phase[ph] = i
        max_mag = max(max_mag, i.magnitude())
    current = currents_by_phase.get(Phase.L1, Complex.zero())
    is_overloaded = max_mag > max_current_a
    _temp_at_last_solve = temperature_c

# ── Thermal ───────────────────────────────────────────────────────────

func update_thermal(dt: float, p_ambient_c: float = NAN) -> bool:
    if dt <= 0.0: return false
    if not is_nan(p_ambient_c): ambient_c = p_ambient_c
    if damaged:
        _relax_to_ambient(dt); return false
    if not enabled or not plugged_in:
        _relax_to_ambient(dt); _check_dirty(); return false
    var c_th: float = thermal_capacity_j_per_k
    var r_th: float = thermal_resistance_k_per_w
    if c_th <= 0.0 or r_th <= 0.0: return false
    var tau: float = c_th * r_th
    var steps: int = max(1, int(ceil(dt / max(tau * 0.25, 1e-3))))
    var sub_dt: float = dt / float(steps)
    var newly_damaged: bool = false
    for _i in steps:
        var p_in: float  = dissipated_power()
        var p_out: float = (temperature_c - ambient_c) / r_th
        temperature_c += (p_in - p_out) * sub_dt / c_th
        is_overheated = temperature_c > insulation_max_c
        if thermal_damage_enabled and temperature_c >= damage_temp_c and not damaged:
            damage(); newly_damaged = true; break
    _check_dirty()
    return newly_damaged

func _relax_to_ambient(dt: float) -> void:
    var tau: float = thermal_capacity_j_per_k * thermal_resistance_k_per_w
    if tau <= 0.0: return
    temperature_c += (ambient_c - temperature_c) * clampf(dt / tau, 0.0, 1.0)
    is_overheated = temperature_c > insulation_max_c

func _check_dirty() -> void:
    if absf(temperature_c - _temp_at_last_solve) >= _TEMP_DIRTY_DELTA_C:
        mark_dirty()

func damage() -> void:
    damaged = true; enabled = false; mark_dirty()

func repair() -> void:
    damaged = false; enabled = true
    temperature_c = ambient_c; is_overheated = false
    _temp_at_last_solve = temperature_c; mark_dirty()
