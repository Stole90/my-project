## ThreePhaseSwitchNode.gd
class_name ThreePhaseSwitchNode
extends Node2D

@export var switch_name: String = "3-fazni prekidač"

var _bus_in:   SimNode          = null
var _bus_out:  SimNode          = null
var _switch:   ThreePhaseSwitch = null
var _model:    CircuitModel     = null
var _initialized: bool          = false

func setup_in(source_bus: SimNode, model: CircuitModel) -> void:
    if _initialized: return
    _initialized = true
    _model   = model
    _bus_in  = source_bus
    _bus_out = SimNode.new("%s_out" % switch_name)
    _switch  = ThreePhaseSwitch.new(_bus_in, _bus_out, switch_name)
    model.add_element(_switch)
    model.solved.connect(_on_solved)

func get_sim_bus() -> SimNode:
    # CableNode logika: prvi kabl → _bus_in, drugi → _bus_out
    if _switch == null: return _bus_in
    for elem in _model.elements:
        if (elem is ThreePhaseCable or elem is Cable):
            if elem.node_a() == _bus_in or elem.node_b() == _bus_in:
                return _bus_out
    return _bus_in

func toggle_power() -> void:
    if _switch == null: return
    _switch.toggle()
    if _model: _model.mark_dirty()

func is_enabled() -> bool:
    return _switch != null and _switch.closed

func _on_solved(_ms: float) -> void:
    queue_redraw()

func get_info() -> Dictionary:
    var rows: Array = []
    if _switch != null:
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
            var label: String = ["L1", "L2", "L3"][ph]
            var v_in:  float = _bus_in.voltage_magnitude(ph)  if _bus_in  else 0.0
            var v_out: float = _bus_out.voltage_magnitude(ph) if _bus_out else 0.0
            var i_c: Complex = _switch.currents_by_phase.get(ph, null)
            var i: float = 0.0 if i_c == null else i_c.magnitude()
            rows.append(row("Napon in %s"  % label, v_in,  "%.1f V"))
            rows.append(row("Napon out %s" % label, v_out, "%.1f V"))
            rows.append(row("Struja %s"    % label, i,     "%.2f A"))
    return {
        "name":    switch_name,
        "type":    "3-fazni prekidač",
        "enabled": is_enabled(),
        "rows":    rows
    }

func _draw() -> void:
    var col: Color = Color(0.2, 0.8, 0.2) if is_enabled() else Color(0.6, 0.6, 0.6)
    draw_circle(Vector2.ZERO, 8.0, col)

static func row(label: String, value, fmt: String = "") -> Dictionary:
    return {"label": label, "value": value, "fmt": fmt}
