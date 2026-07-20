# res://scripts/appliances/Lamp.gd
class_name Lamp
extends BaseAppliance

@export var lamp_name:      String = "Sijalica"
@export var rated_power_w: float   = 60.0
@export var power_factor: float    = 1.0
@export var nominal_voltage: float = 230.0

func plug_into(bus: SimNode, model: CircuitModel) -> void:
    _bus = bus

    if _bridge != null:
        _bridge.queue_free()
        _bridge = null

    _consumer = RatedConsumer.new(bus, rated_power_w, power_factor, name, nominal_voltage, false)
    model.add_element(_consumer)

    var cb := ConsumerBridge.new()
    cb.name = "%s_Bridge" % name
    add_child(cb)
    cb.bind(_consumer, model)
    _bridge = cb

    cb.solved.connect(func(): _solved = true)
    cb.damaged.connect(func(): push_warning("[%s] sijalica je pregorela!" % name))

func repair() -> void:
    if _bridge: _bridge.interact_repair()

func get_info() -> Dictionary:
    if not _solved:
        return {
            "name":    lamp_name,
            "type":    "Sijalica",
            "enabled": is_enabled(),
            "rows": [
                row("Nom. snaga",   rated_power_w,   "%.0f W"),
                row("Faktor snage", power_factor,    "%.2f"),
                row("Nom. napon",   nominal_voltage, "%.0f V"),
                row("Stanje",       "nepovezano"),
            ]
        }

    var cb: ConsumerBridge = _bridge as ConsumerBridge
    var v: float   = cb.vis_voltage_v if cb != null else 0.0
    var i: float   = cb.vis_current_a if cb != null else 0.0
    var st: String = cb.vis_state     if cb != null else "unknown"

    return {
        "name":    lamp_name,
        "type":    "Sijalica",
        "enabled": is_enabled(),
        "rows": [
            row("Nom. snaga",   rated_power_w,      "%.0f W"),
            row("Faktor snage", power_factor,       "%.2f"),
            row("Nom. napon",   nominal_voltage,    "%.0f V"),
            row("Napon",        v,                  "%.2f V"),
            row("Pad nap.",     get_voltage_drop(), "%.2f V"),
            row("Struja",       i,                  "%.2f A"),
            row("Snaga",        v * i,               "%.1f W"),
            row("Stanje",       st),
        ]
    }

func apply_params(params: Dictionary) -> void:
    var new_name: String = params.get("appliance_name", name)
    if not new_name.is_empty():
        name = new_name
    rated_power_w   = params.get("rated_power_w",  rated_power_w)
    nominal_voltage = params.get("nominal_voltage", nominal_voltage)
    power_factor    = params.get("power_factor",    power_factor)
    if _consumer != null:
        _consumer.power_w         = rated_power_w
        _consumer.nominal_voltage = nominal_voltage
        _consumer.rated_pf        = power_factor
        _consumer.element_name    = name
        _consumer.mark_dirty()
