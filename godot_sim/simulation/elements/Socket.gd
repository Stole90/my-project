## Socket.gd
## Electrical socket (outlet) element — a two-terminal series resistor
## that models the internal contact resistance and its thermal behaviour.
##
## Topology
## ─────────
##   node_supply ──[R_contact(T)]── node_load
##
##   node_supply  — connected to the grid-side bus
##   node_load    — where consumers plug in (may be the same bus as
##                  node_supply when the socket is modelled as a simple
##                  shunt attachment, but normally it is a distinct SimNode
##                  so that the voltage drop across the contact is visible)
##
## Electrical model
## ─────────────────
##   R(T) = R₂₀ · (1 + α · (T − 20°C))
##
##   where R₂₀ is `contact_resistance_cold_ohm` (specified at 20°C)
##   and α  is the temperature coefficient of the contact material.
##
##   The contact resistance is typically very small (5–50 mΩ for a
##   healthy socket, rising to hundreds of mΩ for a worn/faulty one).
##   The Y-bus stamp is a simple admittance between the two nodes.
##
## Thermal model  (lumped first-order)
## ─────────────────────────────────────
##   Joule heating:   P_in  = |I|² · R(T)
##   Newton cooling:  P_out = (T − T_ambient) / R_th
##   Heat balance:    C_th · dT/dt = P_in − P_out
##
##   Discretised with sub-stepped forward Euler (same approach as Cable).
##
##   Unlike Cable, the thermal capacity and resistance are total per-device
##   values (not per-metre) because a socket is a fixed-size enclosure.
##
## Operational states
## ───────────────────
##   enabled        — circuit-breaker behaviour: false → open contact (no Y stamp)
##   plugged_in     — false → load side is physically disconnected (same as disabled
##                    electrically, but the socket can still heat up if it is in a
##                    damaged/arcing state)
##   damaged        — contact failure (arcing, melting, oxidation): element is
##                    disabled and requires repair to restore service
##   is_overheated  — temperature_c > insulation_max_c (soft warning)
##   is_overloaded  — |I| > max_current_a
##
## Signals / integration
## ──────────────────────
##   Call `update_thermal(dt, ambient_c)` each physics frame from the
##   owning world or CircuitModel.  CircuitModel.step_thermal() handles
##   sockets alongside cables automatically once registered via
##   `add_element()`.
##
## Repair
## ───────
##   `repair()` clears the damage flag, re-enables the element,
##   resets temperature to ambient (fresh start), and marks dirty.
##
## Ageing
## ───────
##   `ageing_factor` multiplies the cold contact resistance so you can
##   model a worn socket (factor > 1) or a freshly cleaned one (factor < 1).
##   Default = 1.0.

class_name Socket
extends CircuitElement

# ── Electrical parameters ───────────────────────────────────────────

## Contact resistance at the reference temperature (20°C) [Ω].
## Realistic values:
##   0.005  Ω  — new, clean contacts
##   0.050  Ω  — worn contacts
##   0.500+ Ω  — faulty / high-resistance joint (arc risk)
var contact_resistance_cold_ohm: float = SimConstants.SOCKET_CONTACT_RESISTANCE_NEW_OHM

## Contact material; drives α and default C_th.
## Supported: "brass" (default), "copper", "stainless_steel".
var contact_material: String = "brass"

## Maximum rated current [A].  Exceeding it sets `is_overloaded`.
## Common values: 16 A (EU), 13 A (UK), 20 A (US), 32 A (industrial).
var max_current_a: float = 16.0

## Multiplier applied to `contact_resistance_cold_ohm` to model ageing.
## 1.0 = brand new, >1 = worn / oxidised, <1 = polished/silver-plated.
var ageing_factor: float = 1.0

## Whether a consumer is currently plugged in.
## When false the load node is effectively open-circuit (no Y stamp).
var plugged_in: bool = true

## Faza na kojoj ovaj socket stampa admitancu u trofaznom solveru.
## Setter automatski propagira fazu na sve registrovane Consumer elemente i kabove.
var assigned_phase: int = Phase.L1 :
    set(v):
        assigned_phase = v
        for elem in _plugged_consumers:
            if elem != null and elem.get("assigned_phase") != null:
                elem.assigned_phase = v
        for cn in _consumer_cables:
            if cn != null and cn.sim_cable != null and cn.sim_cable.get("assigned_phase") != null:
                cn.sim_cable.assigned_phase = v

## Lista Consumer sim elemenata priključenih u node_load.
var _plugged_consumers: Array = []
## Lista CableNode-ova između utičnice i priključenih potrošača.
var _consumer_cables: Array = []

func register_plugged_consumer(elem: Object) -> void:
    if not (elem in _plugged_consumers):
        _plugged_consumers.append(elem)
        if elem.get("assigned_phase") != null:
            elem.assigned_phase = assigned_phase

func unregister_plugged_consumer(elem: Object) -> void:
    _plugged_consumers.erase(elem)

func register_consumer_cable(cable_node: Node2D) -> void:
    if not (cable_node in _consumer_cables):
        _consumer_cables.append(cable_node)
        if cable_node.sim_cable != null and cable_node.sim_cable.get("assigned_phase") != null:
            cable_node.sim_cable.assigned_phase = assigned_phase

func unregister_consumer_cable(cable_node: Node2D) -> void:
    _consumer_cables.erase(cable_node)

# ── Thermal parameters ──────────────────────────────────────────────

## Current temperature of the socket body (contacts + housing) [°C].
var temperature_c: float = SimConstants.DEFAULT_AMBIENT_C

## Ambient temperature for Newton cooling [°C].
var ambient_c: float = SimConstants.DEFAULT_AMBIENT_C

## Total thermal capacity of the socket body [J/K].
## ≤0 → derived from contact_material via contact_volume_mm3.
var thermal_capacity_j_per_k: float = SimConstants.DEFAULT_SOCKET_THERMAL_CAPACITY_J_PER_K

## Total thermal resistance from socket body to ambient [K/W].
## Plastic housing adds significant insulation; higher → heats faster.
var thermal_resistance_k_per_w: float = SimConstants.DEFAULT_SOCKET_THERMAL_RESISTANCE_K_PER_W

## Soft limit: above this the insulation starts to degrade [°C].
var insulation_max_c: float = SimConstants.DEFAULT_SOCKET_INSULATION_MAX_C

## Hard limit: above this the socket is auto-damaged [°C].
var damage_temp_c: float = SimConstants.DEFAULT_SOCKET_DAMAGE_TEMP_C

## Volume of the actual metal contact mass [mm³].
## Used only when `thermal_capacity_j_per_k` is overridden to ≤0.
## For a standard EU brass contact strip: ~200–400 mm³.
var contact_volume_mm3: float = 300.0

## If false, the socket will not auto-damage even when damage_temp_c is exceeded.
var thermal_damage_enabled: bool = true

# ── Game state ──────────────────────────────────────────────────────

var damaged: bool     = false
var is_overheated: bool = false
var is_overloaded: bool = false

# Tracks temperature at last solve so we only mark dirty on meaningful
# resistance changes (avoids solver spam from tiny drifts).
const _TEMP_DIRTY_DELTA_C: float = 1.0
var _temp_at_last_solve: float = SimConstants.DEFAULT_AMBIENT_C

# ── Constructor ─────────────────────────────────────────────────────

## Create a socket between two SimNodes.
##
## Parameters
## ──────────
##   node_supply  — grid / distribution bus node
##   node_load    — load / consumer node (can equal node_supply for a
##                  single-bus model, but a distinct node gives voltage-drop info)
##   p_r_cold     — cold contact resistance [Ω] (default = 5 mΩ, healthy)
##   p_max_a      — rated current [A] (default = 16 A, EU standard)
##   p_material   — contact material key (default = "brass")
##   p_name       — element name for UI / debug
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
    if not SimConstants.CONTACT_TEMP_COEFF_PER_C.has(contact_material):
        push_error("Socket: unknown contact material '%s'" % contact_material)

func node_supply() -> SimNode:
    return terminals[0][0]

func node_load() -> SimNode:
    return terminals[1][0]

# ── Electrical properties ───────────────────────────────────────────

## Temperature-corrected contact resistance [Ω].
## R(T) = R₂₀ · (1 + α · (T − 20°C))
func resistance() -> float:
    var alpha: float = SimConstants.CONTACT_TEMP_COEFF_PER_C.get(contact_material, 1.5e-3)
    var factor: float = 1.0 + alpha * (temperature_c - SimConstants.TEMP_REFERENCE_C)
    return contact_resistance_cold_ohm * ageing_factor * factor

## Resistance at the reference temperature 20°C [Ω] — stable for UI display.
func resistance_cold() -> float:
    return contact_resistance_cold_ohm * ageing_factor

func impedance() -> Complex:
    return Complex.new(resistance(), 0.0)

func admittance() -> Complex:
    var r: float = resistance()
    if r <= 0.0:
        return Complex.new(1.0e12, 0.0)
    return Complex.new(1.0 / r, 0.0)

# ── Thermal properties ──────────────────────────────────────────────

## Total heat capacity of the socket [J/K].
## When thermal_capacity_j_per_k is explicitly set (>0), that value is
## used directly.  Otherwise it is derived from the contact material
## and contact_volume_mm3.
func thermal_capacity() -> float:
    if thermal_capacity_j_per_k > 0.0:
        return thermal_capacity_j_per_k
    var c_vol: float = SimConstants.CONTACT_VOLUMETRIC_HEAT_CAPACITY.get(contact_material, 3.0e6)
    return c_vol * contact_volume_mm3 * 1.0e-9   # mm³ → m³

## Thermal resistance to ambient [K/W].
func thermal_resistance() -> float:
    return thermal_resistance_k_per_w

## Thermal time constant τ = C · R [s].
func thermal_time_constant() -> float:
    return thermal_capacity() * thermal_resistance()

## Analytical steady-state temperature given the current load.
## Useful for tests and the UI without running the integrator to convergence.
func steady_state_temperature() -> float:
    var i_mag: float = 0.0 if current == null else current.magnitude()
    var p: float = i_mag * i_mag * resistance()
    return ambient_c + p * thermal_resistance()

## Power currently dissipated in the contacts [W].
func dissipated_power() -> float:
    var i_mag: float = 0.0 if current == null else current.magnitude()
    return i_mag * i_mag * resistance()

## 0 .. 1 thermal loading (0 = ambient, 1 = insulation_max_c). >1 = overheated.
func thermal_loading() -> float:
    var span: float = insulation_max_c - ambient_c
    if span <= 0.0:
        return 0.0
    return (temperature_c - ambient_c) / span

## 0 .. 1 current loading (-1 = unrated / unlimited).
func loading_percent() -> float:
    if current == null or max_current_a <= 0.0:
        return -1.0
    return current.magnitude() / max_current_a * 100.0

## Voltage drop across the socket contacts [V phasor].
func voltage_drop() -> Complex:
    var vs: Complex = node_supply().voltage
    var vl: Complex = node_load().voltage
    if vs == null or vl == null:
        return null
    return vs.sub(vl)

## Apparent power dissipated in the contacts [VA].
func apparent_power() -> Complex:
    var dv: Complex = voltage_drop()
    if dv == null or current == null:
        return null
    return dv.mul(current.conjugate())

# ── Solver stamps ───────────────────────────────────────────────────

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
    if damaged or not enabled or not plugged_in:
        return
    var i: int = node_idx[node_supply()]
    var j: int = node_idx[node_load()]
    var y: Complex = admittance()
    Y[i][i].add_inplace(y)
    Y[j][j].add_inplace(y)
    Y[i][j].sub_inplace(y)
    Y[j][i].sub_inplace(y)

func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _source_np: Dictionary) -> void:
    if damaged or not enabled or not plugged_in:
        return
    var y: Complex = admittance()
    # Socket je jednofarni element — stampa se na assigned_phase (default L1).
    var key_s: String = node_supply().id + ":" + str(assigned_phase)
    var key_l: String = node_load().id   + ":" + str(assigned_phase)
    var rs: int = np_idx.get(key_s, -1)
    var rl: int = np_idx.get(key_l, -1)
    if rs < 0 or rl < 0:
        return
    Y[rs][rs].add_inplace(y)
    Y[rl][rl].add_inplace(y)
    Y[rs][rl].sub_inplace(y)
    Y[rl][rs].sub_inplace(y)

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
    if damaged or not enabled or not plugged_in:
        current       = Complex.zero()
        is_overloaded = false
        _temp_at_last_solve = temperature_c
        return
    var vs: Complex = node_supply().voltage
    var vl: Complex = node_load().voltage
    if vs == null or vl == null:
        current       = Complex.zero()
        is_overloaded = false
        _temp_at_last_solve = temperature_c
        return
    current       = vs.sub(vl).div(impedance())
    is_overloaded = current.magnitude() > max_current_a
    _temp_at_last_solve = temperature_c

func update_state_3ph(_dt: float = 0.0) -> void:
    if damaged or not enabled or not plugged_in:
        current = Complex.zero()
        currents_by_phase[assigned_phase] = Complex.zero()
        is_overloaded = false
        return
    var vs: Complex = node_supply().get_voltage(assigned_phase)
    var vl: Complex = node_load().get_voltage(assigned_phase)
    if vs == null or vl == null:
        current = Complex.zero()
        currents_by_phase[assigned_phase] = Complex.zero()
        return
    current = vs.sub(vl).div(impedance())
    currents_by_phase[assigned_phase] = current
    is_overloaded = current.magnitude() > max_current_a
    _temp_at_last_solve = temperature_c

# ── Thermal integration ─────────────────────────────────────────────

## Advance the lumped thermal model by `dt` seconds.
##
## Call once per physics frame.  Pass `p_ambient_c` to override the
## socket's `ambient_c` for the step (e.g. from a weather system).
##
## Returns true when the socket was newly damaged during this step.
func update_thermal(dt: float, p_ambient_c: float = NAN) -> bool:
    if dt <= 0.0:
        return false
    if not is_nan(p_ambient_c):
        ambient_c = p_ambient_c

    if damaged:
        _relax_to_ambient(dt)
        return false

    if not enabled or not plugged_in:
        # No current flowing — socket still cools through housing to air.
        _relax_to_ambient(dt)
        _check_dirty_from_temp_change()
        return false

    var c_th: float = thermal_capacity()
    var r_th: float = thermal_resistance()
    if c_th <= 0.0 or r_th <= 0.0:
        return false

    # Sub-step to keep forward Euler stable if dt >> τ.
    var tau: float    = c_th * r_th
    var steps: int    = max(1, int(ceil(dt / max(tau * 0.25, 1.0e-3))))
    var sub_dt: float = dt / float(steps)
    var newly_damaged: bool = false

    for _i in steps:
        var p_in: float  = dissipated_power()
        var p_out: float = (temperature_c - ambient_c) / r_th
        temperature_c += (p_in - p_out) * sub_dt / c_th

        is_overheated = temperature_c > insulation_max_c

        if thermal_damage_enabled and temperature_c >= damage_temp_c and not damaged:
            damage()
            newly_damaged = true
            break

    _check_dirty_from_temp_change()
    return newly_damaged

func _relax_to_ambient(dt: float) -> void:
    var c_th: float = thermal_capacity()
    var r_th: float = thermal_resistance()
    if c_th <= 0.0 or r_th <= 0.0:
        return
    var tau: float   = c_th * r_th
    var alpha: float = clampf(dt / tau, 0.0, 1.0)
    temperature_c   += (ambient_c - temperature_c) * alpha
    is_overheated    = temperature_c > insulation_max_c

func _check_dirty_from_temp_change() -> void:
    if absf(temperature_c - _temp_at_last_solve) >= _TEMP_DIRTY_DELTA_C:
        mark_dirty()

# ── Game actions ────────────────────────────────────────────────────

## Physically connect (plug in) a consumer.
func plug_in() -> void:
    if not plugged_in:
        plugged_in = true
        mark_dirty()

## Physically disconnect (unplug) a consumer.
func unplug() -> void:
    if plugged_in:
        plugged_in = false
        mark_dirty()

## Electrically isolate the socket (switch / breaker trip) without
## physically removing the plug.
func isolate() -> void:
    disable()

## Restore electrical connection after isolation.
func restore() -> void:
    enable()

## Mark the socket as contact-failure damaged.
## The element is automatically disabled until repaired.
func damage() -> void:
    damaged   = true
    enabled   = false
    mark_dirty()

## Clear damage, re-enable, and reset temperature to ambient.
func repair() -> void:
    damaged       = false
    enabled       = true
    temperature_c = ambient_c
    is_overheated = false
    _temp_at_last_solve = temperature_c
    mark_dirty()

# ── Diagnostics ─────────────────────────────────────────────────────

func _to_string() -> String:
    return "Socket('%s', R_cold=%.4fΩ, T=%.1f°C, %s)" % [
        element_name,
        resistance_cold(),
        temperature_c,
        "DAMAGED" if damaged else ("OH" if is_overheated else "OK"),
    ]
