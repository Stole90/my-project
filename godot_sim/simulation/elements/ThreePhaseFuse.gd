## ThreePhaseFuse.gd
## Trofazni osigurač — svaka faza ima nezavisni element koji može pregorjeti.

class_name ThreePhaseFuse
extends CircuitElement

@export var rated_current_a: float = 16.0
@export var blow_time_s:     float = 0.1   # vrijeme do pucanja pri preopterećenju

var blown_phases: Dictionary = {
    Phase.L1: false,
    Phase.L2: false,
    Phase.L3: false,
}

var _overcurrent_time: Dictionary = {
    Phase.L1: 0.0,
    Phase.L2: 0.0,
    Phase.L3: 0.0,
}

const SHORT_Y: float = 1.0e6

func _init(node_in: SimNode, node_out: SimNode, p_rated_a: float = 16.0, p_name: String = "") -> void:
    super._init(p_name)
    terminals = [[node_in], [node_out]]
    rated_current_a = p_rated_a

func node_in()  -> SimNode: return terminals[0][0]
func node_out() -> SimNode: return terminals[1][0]

func is_blown() -> bool:
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        if blown_phases[ph]: return true
    return false

func stamp_ybus(Y: Array, _I: Array, node_idx: Dictionary, _src: Array) -> void:
    if not enabled or blown_phases[Phase.L1]: return
    var i: int = node_idx.get(node_in(),  -1)
    var j: int = node_idx.get(node_out(), -1)
    if i < 0 or j < 0: return
    var y: Complex = Complex.new(SHORT_Y, 0.0)
    Y[i][i].add_inplace(y); Y[j][j].add_inplace(y)
    Y[i][j].sub_inplace(y); Y[j][i].sub_inplace(y)

func stamp_ybus_3ph(Y: Array, _I: Array, np_idx: Dictionary, _src: Dictionary) -> void:
    if not enabled: return
    var y: Complex = Complex.new(SHORT_Y, 0.0)
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        if blown_phases[ph]: continue   # pregorjela faza = otvoreno kolo
        var ri: int = np_idx.get(node_in().id  + ":" + str(ph), -1)
        var ro: int = np_idx.get(node_out().id + ":" + str(ph), -1)
        if ri < 0 or ro < 0: continue
        Y[ri][ri].add_inplace(y); Y[ro][ro].add_inplace(y)
        Y[ri][ro].sub_inplace(y); Y[ro][ri].sub_inplace(y)

func update_state_3ph(dt: float = 0.0) -> void:
    if not enabled:
        current = Complex.zero()
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
            currents_by_phase[ph] = Complex.zero()
        return

    var newly_blown: bool = false
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        if blown_phases[ph]:
            currents_by_phase[ph] = Complex.zero()
            continue
        var vi: Complex = node_in().get_voltage(ph)
        var vo: Complex = node_out().get_voltage(ph)
        if vi == null or vo == null:
            currents_by_phase[ph] = Complex.zero()
            continue
        var i: Complex = vi.sub(vo).scale(SHORT_Y)
        currents_by_phase[ph] = i

        # Provjeri preopterećenje i akumuliraj vrijeme
        if dt > 0.0:
            if i.magnitude() > rated_current_a:
                _overcurrent_time[ph] += dt
                if _overcurrent_time[ph] >= blow_time_s:
                    blown_phases[ph] = true
                    newly_blown = true
                    currents_by_phase[ph] = Complex.zero()
            else:
                _overcurrent_time[ph] = 0.0   # resetuj ako struja padne

    current = currents_by_phase.get(Phase.L1, Complex.zero())
    if newly_blown:
        mark_dirty()

func repair() -> void:
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        blown_phases[ph]        = false
        _overcurrent_time[ph]   = 0.0
    enabled = true
    mark_dirty()
