# res://scripts/appliances/Boiler.gd
class_name Boiler
extends BaseAppliance

@export var boiler_name:      String = "Bojler"
@export var rated_power_w:    float  = 2000.0
@export var nominal_voltage:  float  = 230.0

## Operating modes: off / eco / normal / boost
const MODE_POWER_W: Dictionary = {
	"off":    0.0,
	"eco":    1000.0,
	"normal": 2000.0,
	"boost":  3000.0,
}
const MODE_TEMP_C: Dictionary = {
	"off":    0.0,
	"eco":    45.0,
	"normal": 60.0,
	"boost":  75.0,
}
const MODE_LABEL: Dictionary = {
	"off":    "Isključen",
	"eco":    "Ekonomičan",
	"normal": "Normalan",
	"boost":  "Brzo zagrevanje",
}

var current_mode: String = "normal"

func plug_into(bus: SimNode, model: CircuitModel) -> void:
	_bus = bus

	if _bridge != null:
		_bridge.queue_free()
		_bridge = null

	_consumer = RatedConsumer.new(bus, rated_power_w, 1.0, name, nominal_voltage, false)
	model.add_element(_consumer)

	var cb := ConsumerBridge.new()
	cb.name = "%s_Bridge" % name
	add_child(cb)
	cb.bind(_consumer, model)
	_bridge = cb

	cb.solved.connect(func(): _solved = true)
	cb.damaged.connect(func(): push_warning("[%s] bojler je pregoreo!" % name))

func repair() -> void:
	if _bridge: _bridge.interact_repair()

func get_info() -> Dictionary:
	if not _solved:
		return {
			"name":    boiler_name,
			"type":    "Bojler",
			"enabled": is_enabled(),
			"rows": [
				row("Mod",           MODE_LABEL.get(current_mode, current_mode)),
				row("Ciljana temp.", "—" if current_mode == "off" else ("%.0f °C" % MODE_TEMP_C.get(current_mode, 0.0))),
				row("Nom. snaga",    rated_power_w,   "%.0f W"),
				row("Nom. napon",    nominal_voltage, "%.0f V"),
				row("Stanje",        "nepovezano"),
			]
		}

	var cb: ConsumerBridge = _bridge as ConsumerBridge
	var v: float   = cb.vis_voltage_v if cb != null else 0.0
	var i: float   = cb.vis_current_a if cb != null else 0.0
	var st: String = cb.vis_state     if cb != null else "unknown"

	return {
		"name":    boiler_name,
		"type":    "Bojler",
		"enabled": is_enabled(),
		"rows": [
			row("Mod",           MODE_LABEL.get(current_mode, current_mode)),
			row("Ciljana temp.", "—" if current_mode == "off" else ("%.0f °C" % MODE_TEMP_C.get(current_mode, 0.0))),
			row("Nom. snaga",    rated_power_w,      "%.0f W"),
			row("Nom. napon",    nominal_voltage,    "%.0f V"),
			row("Napon",         v,                  "%.2f V"),
			row("Pad nap.",      get_voltage_drop(), "%.2f V"),
			row("Struja",        i,                  "%.2f A"),
			row("Snaga",         v * i,              "%.1f W"),
			row("Stanje",        st),
		]
	}

func apply_params(params: Dictionary) -> void:
	var new_name: String = params.get("appliance_name", name)
	if not new_name.is_empty():
		name = new_name

	# Mode change
	if params.has("mode"):
		var m: String = params["mode"]
		if MODE_POWER_W.has(m):
			current_mode  = m
			rated_power_w = MODE_POWER_W[m]

	rated_power_w   = params.get("rated_power_w",   rated_power_w)
	nominal_voltage = params.get("nominal_voltage",  nominal_voltage)

	if _consumer != null:
		_consumer.power_w         = rated_power_w
		_consumer.nominal_voltage = nominal_voltage
		_consumer.element_name    = name
		_consumer.mark_dirty()
