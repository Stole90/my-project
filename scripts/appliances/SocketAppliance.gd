## SocketAppliance.gd (refaktorisan)
## Koristi SocketBridge za sve sim stanje.

class_name SocketAppliance
extends BaseAppliance

@export var socket_name:      String = "Priključnica"
@export var max_current_a:    float  = 16.0
@export var contact_material: String = "brass"

var _socket:    Socket     = null
var _node_load: SimNode    = null
var _model:     CircuitModel = null

func plug_into(bus: SimNode, model: CircuitModel) -> void:
    _bus    = bus
    _model  = model
    _solved = false

    if _bridge != null:
        _bridge.queue_free()
        _bridge = null

    _node_load = SimNode.new("%s_load" % socket_name)

    _socket = Socket.new(
        bus, _node_load,
        SimConstants.SOCKET_CONTACT_RESISTANCE_NEW_OHM,
        max_current_a, contact_material, socket_name
    )
    model.add_element(_socket)

    var sb := SocketBridge.new()
    sb.name = "%s_Bridge" % socket_name
    add_child(sb)
    sb.bind(_socket, model)
    _bridge = sb

    sb.solved.connect(func(): _solved = true)

## Poziva se iz CableNode kada se potrošač priključi u ovu utičnicu.
## Registruje Consumer sim element i kabl radi propagacije faze.
func register_consumer_appliance(appliance: BaseAppliance, cable_node: Node2D = null) -> void:
    if _socket == null: return
    if appliance._consumer != null:
        _socket.register_plugged_consumer(appliance._consumer)
    if cable_node != null:
        _socket.register_consumer_cable(cable_node)

## Poziva se iz CableNode kada se potrošač iskopča.
func unregister_consumer_appliance(appliance: BaseAppliance, cable_node: Node2D = null) -> void:
    if _socket == null: return
    if appliance._consumer != null:
        _socket.unregister_plugged_consumer(appliance._consumer)
    if cable_node != null:
        _socket.unregister_consumer_cable(cable_node)

## SocketAppliance nema _consumer (RatedConsumer) — nosilac .assigned_phase
## mu je _socket (Socket sim element). Ovim override-om get_assigned_phase()/
## set_assigned_phase() iz BaseAppliance rade ispravno i za utičnicu.
func _phase_element() -> Object:
    return _socket

func repair() -> void:
    if _socket != null:
        _socket.repair()

func get_info() -> Dictionary:
    if _bridge == null:
        return { "name": socket_name, "type": "Priključnica", "rows": [] }
    var info := _bridge.get_info()
    # Dodaj pad napona koji zahteva supply_bus (samo BaseAppliance zna)
    var rows: Array = info.get("rows", [])
    # Umetnemo pad napona posle prvog reda (napon)
    rows.insert(1, row("Pad nap.", get_voltage_drop(), "%.2f V"))
    info["rows"] = rows
    info["name"] = socket_name
    return info
