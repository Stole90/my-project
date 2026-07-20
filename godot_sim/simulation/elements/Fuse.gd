## Fuse.gd
## Two-terminal protective device sa B/C/D krivom okidanja.
##
## Thermal model:
##   - thermal_energy raste proporcionalno (I/In)² kada I > In
##   - thermal_energy opada kada I <= In
##   - okidanje kada thermal_energy >= 1.0
##
## B kriva: okida pri 3-5x In
## C kriva: okida pri 5-10x In
## D kriva: okida pri 10-20x In

class_name Fuse
extends CircuitElement

const SERIES_RES: float = 1e-6

enum TripCurve { B, C, D }

var rated_current_a: float
var blown: bool        = false
var resettable: bool   = false
var curve: TripCurve       = TripCurve.C

## Akumulirana toplotna energija [0.0 - 1.0]. Pregori na 1.0.
var thermal_energy: float    = 0.0
var current_magnitude: float = 0.0
var assigned_phase: int = Phase.L1

func _init(
    node_a: SimNode,
    node_b: SimNode,
    p_rated_current_a: float,
    p_resettable: bool = false,
    p_name: String     = "",
    p_curve: TripCurve     = TripCurve.C
) -> void:
    super._init(p_name)
    terminals       = [[node_a], [node_b]]
    rated_current_a = p_rated_current_a
    resettable      = p_resettable
    curve           = p_curve

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

func is_closed() -> bool:
    return enabled and not blown

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
    if not is_closed():
        return
    var i: int = node_idx[node_a()]
    var j: int = node_idx[node_b()]
    var y: Complex = Complex.new(1.0 / SERIES_RES, 0.0)
    Y[i][i].add_inplace(y)
    Y[j][j].add_inplace(y)
    Y[i][j].sub_inplace(y)
    Y[j][i].sub_inplace(y)

func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _src: Dictionary) -> void:
    if not is_closed():
        return
    var key_a: String = node_a().id + ":" + str(assigned_phase)
    var key_b: String = node_b().id + ":" + str(assigned_phase)
    var ra: int = np_idx.get(key_a, -1)
    var rb: int = np_idx.get(key_b, -1)
    if ra < 0 or rb < 0:
        return
    var y: Complex = Complex.new(1.0 / SERIES_RES, 0.0)
    Y[ra][ra].add_inplace(y)
    Y[rb][rb].add_inplace(y)
    Y[ra][rb].sub_inplace(y)
    Y[rb][ra].sub_inplace(y)

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
    if not is_closed():
        current           = Complex.zero()
        current_magnitude = 0.0
        return
    var va: Complex = node_a().voltage
    var vb: Complex = node_b().voltage
    if va == null or vb == null:
        current           = Complex.zero()
        current_magnitude = 0.0
        return
    current           = va.sub(vb).scale(1.0 / SERIES_RES)
    current_magnitude = current.magnitude()

func update_state_3ph(_dt: float = 0.0) -> void:
    if not is_closed():
        current           = Complex.zero()
        current_magnitude = 0.0
        return
    var va: Complex = node_a().get_voltage(assigned_phase)
    var vb: Complex = node_b().get_voltage(assigned_phase)
    if va == null or vb == null:
        current           = Complex.zero()
        current_magnitude = 0.0
        return
    current           = va.sub(vb).scale(1.0 / SERIES_RES)
    current_magnitude = current.magnitude()

## Poziva FuseNode._process() svaki frame.
## Vraća true ako je osigurač upravo pregoreo.
func tick_thermal(dt: float) -> bool:
    if not is_closed():
        thermal_energy = maxf(thermal_energy - dt * 0.5, 0.0)
        return false

    var ratio: float = current_magnitude / rated_current_a if rated_current_a > 0.0 else 0.0

    if ratio <= 1.0:
        thermal_energy = maxf(thermal_energy - dt * 0.2, 0.0)
        return false

    thermal_energy += _heat_rate(ratio) * dt

    if thermal_energy >= 1.0:
        thermal_energy = 1.0
        blown = true
        mark_dirty()
        return true

    return false

func _heat_rate(ratio: float) -> float:
    var instant_trip: float
    match curve:
        TripCurve.B: instant_trip = 3.0
        TripCurve.C: instant_trip = 5.0
        TripCurve.D: instant_trip = 10.0
        _:       instant_trip = 5.0

    if ratio >= instant_trip:
        return 10.0  # pregori za ~0.1s

    var overshoot: float = ratio - 1.0
    var t_trip: float    = 10.0 / (overshoot * overshoot + 0.1)
    return 1.0 / maxf(t_trip, 0.05)

func reset() -> void:
    if resettable:
        blown          = false
        thermal_energy = 0.0
        mark_dirty()

func replace() -> void:
    blown          = false
    thermal_energy = 0.0
    mark_dirty()

func curve_name() -> String:
    match curve:
        TripCurve.B: return "B"
        TripCurve.C: return "C"
        TripCurve.D: return "D"
    return "?"

static func curve_from_string(s: String) -> Fuse.TripCurve:
    match s.to_upper():
        "B": return Fuse.TripCurve.B
        "C": return Fuse.TripCurve.C
        "D": return Fuse.TripCurve.D
    return Fuse.TripCurve.C
