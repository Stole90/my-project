## ThreePhaseSwitch.gd
## Trofazni prekidač — tri galvanski izolovana kontakta.
## closed = kratka veza (velika admitansa), open = otvoreno kolo.

class_name ThreePhaseSwitch
extends CircuitElement

var closed: bool = true

const SHORT_Y: float = 1.0e6   # admitansa zatvorenog kontakta [S]

func _init(node_in: SimNode, node_out: SimNode, p_name: String = "") -> void:
    super._init(p_name)
    terminals = [[node_in], [node_out]]

func node_in()  -> SimNode: return terminals[0][0]
func node_out() -> SimNode: return terminals[1][0]

func stamp_ybus(Y: Array, _I: Array, node_idx: Dictionary, _src: Array) -> void:
    if not closed or not enabled: return
    var i: int = node_idx.get(node_in(),  -1)
    var j: int = node_idx.get(node_out(), -1)
    if i < 0 or j < 0: return
    var y: Complex = Complex.new(SHORT_Y, 0.0)
    Y[i][i].add_inplace(y); Y[j][j].add_inplace(y)
    Y[i][j].sub_inplace(y); Y[j][i].sub_inplace(y)

func stamp_ybus_3ph(Y: Array, _I: Array, np_idx: Dictionary, _src: Dictionary) -> void:
    if not closed or not enabled: return
    var y: Complex = Complex.new(SHORT_Y, 0.0)
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        var ri: int = np_idx.get(node_in().id  + ":" + str(ph), -1)
        var ro: int = np_idx.get(node_out().id + ":" + str(ph), -1)
        if ri < 0 or ro < 0: continue
        Y[ri][ri].add_inplace(y); Y[ro][ro].add_inplace(y)
        Y[ri][ro].sub_inplace(y); Y[ro][ri].sub_inplace(y)

func update_state_3ph(_dt: float = 0.0) -> void:
    if not closed or not enabled:
        current = Complex.zero()
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
            currents_by_phase[ph] = Complex.zero()
        return
    for ph in [Phase.L1, Phase.L2, Phase.L3]:
        var vi: Complex = node_in().get_voltage(ph)
        var vo: Complex = node_out().get_voltage(ph)
        if vi == null or vo == null:
            currents_by_phase[ph] = Complex.zero()
            continue
        currents_by_phase[ph] = vi.sub(vo).scale(SHORT_Y)
    current = currents_by_phase.get(Phase.L1, Complex.zero())

func open_switch()  -> void: closed = false; mark_dirty()
func close_switch() -> void: closed = true;  mark_dirty()
func toggle()       -> void:
    if closed: open_switch() 
    else: close_switch()
