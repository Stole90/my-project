## ThreePhaseSocketAppliance.gd (refaktorisan)
## Koristi SocketBridge (ThreePhaseSocket ima isti interface kao Socket za bridge).
## Ako treba specifično 3-fazno prikazivanje, bridge se može proširiti.

class_name ThreePhaseSocketAppliance
extends BaseAppliance

@export var socket_name:      String = "3-fazna priključnica"
@export var max_current_a:    float  = 16.0
@export var contact_material: String = "brass"

var _socket:    ThreePhaseSocket = null
var _node_load: SimNode          = null
var _model:     CircuitModel     = null

func plug_into(bus: SimNode, model: CircuitModel) -> void:
        _bus    = bus
        _model  = model
        _solved = false

        if _bridge != null:
                _bridge.queue_free()
                _bridge = null

        _node_load = SimNode.new("%s_load" % socket_name)

        _socket = ThreePhaseSocket.new(
                bus, _node_load,
                SimConstants.SOCKET_CONTACT_RESISTANCE_NEW_OHM,
                max_current_a, contact_material, socket_name
        )
        model.add_element(_socket)

        # ThreePhaseSocket ima isti API kao Socket za damaged/overloaded/overheated
        # pa koristimo SocketBridge direktno — nema potrebe za posebnom klasom.
        var sb := SocketBridge.new()
        sb.name = "%s_Bridge" % socket_name
        add_child(sb)
        sb.bind(_socket, model)
        _bridge = sb

        sb.solved.connect(func(): _solved = true)

func is_three_phase_appliance() -> bool:
        return true

func repair() -> void:
        if _socket != null: _socket.repair()

## Potrošači se priključuju na load bus, ne supply bus.
func get_sim_bus() -> SimNode:
        return _node_load

func get_info() -> Dictionary:
        if _socket == null or not _solved:
                return {"name": socket_name, "type": "3-fazna priključnica", "enabled": true, "rows": []}

        var rows: Array = []
        for ph in [Phase.L1, Phase.L2, Phase.L3]:
                var lbl: String = ["L1", "L2", "L3"][ph]
                var v: float = _node_load.voltage_magnitude(ph) if _node_load else 0.0
                var ic: Complex = _socket.currents_by_phase.get(ph, null)
                var i: float = 0.0 if ic == null else ic.magnitude()
                rows.append(row("Napon %s"  % lbl, v, "%.1f V"))
                rows.append(row("Struja %s" % lbl, i, "%.2f A"))

        var sb: SocketBridge = _bridge as SocketBridge
        rows.append(row("Temperatura", sb.vis_temperature_c if sb else 0.0, "%.1f °C"))
        rows.append(row("Stanje",      sb.vis_state         if sb else "?"))

        return {
                "name":    socket_name,
                "type":    "3-fazna priključnica",
                "enabled": true,
                "rows":    rows,
        }
