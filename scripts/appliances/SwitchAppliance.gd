class_name SwitchAppliance
extends BaseAppliance

@export var switch_name: String = "Prekidač"
@export var closed:      bool   = true

var _switch:       Switch
var _bus_out:      SimNode
var _last_current: float = 0.0
var _last_voltage: float = 0.0
var _model:        CircuitModel  

func plug_into(bus: SimNode, model: CircuitModel) -> void:
    _bus    = bus
    _model  = model
    _solved = false

    # Ukloni stari bridge ako postoji
    if _bridge != null:
        _bridge.queue_free()
        _bridge = null

    _bus_out = SimNode.new("%s_out" % switch_name)
    _switch  = Switch.new(_bus, _bus_out, closed, switch_name)
    model.add_element(_switch)

    _bridge = ElementBridge.new()
    _bridge.name = "%s_Bridge" % switch_name
    add_child(_bridge)
    _bridge.bind(_switch, model)

    # Bridge čita napon sa terminals[0][0] = node_a = ulaz.
    # Nama treba izlazni bus (_bus_out) — čitamo ga sami.
    _bridge.current_changed.connect(func(a): _last_current = a)
    _bridge.voltage_changed.connect(func(_v, _d):
        _solved = true
        _last_voltage = _bus_out.voltage_magnitude() if _bus_out else 0.0
    )

func get_sim_bus() -> SimNode:
    return _bus

func toggle_power() -> void:
    if _switch == null:
        return
    _switch.toggle()
    closed = _switch.closed

func get_info() -> Dictionary:
    var state_str: String
    if not _solved:
        state_str = "nepovezano"
    elif closed:
        state_str = "uključen"
    else:
        state_str = "isključen"

    return {
        "name":    switch_name,
        "type":    "Prekidač",
        "enabled": closed,
        "rows": [
            row("Napon",    _last_voltage,                "%.2f V"),
            row("Pad nap.", get_voltage_drop(),           "%.2f V"),
            row("Struja",   _last_current,                "%.2f A"),
            row("Snaga",    _last_voltage * _last_current,"%.1f W"),
            row("Stanje",   state_str),
        ]
    }
