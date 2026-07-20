## Refrigerator.gd (refaktorisan)
## Sva logika stanja → ConsumerBridge.
## get_info() čita iz _bridge.vis_* umesto lokalnih varijabli.

class_name Refrigerator
extends BaseAppliance

@export var refrigerator_name:   String = "Frizider"
@export var rated_power_w:       float  = 150.0
@export var power_factor:        float  = 0.85
@export var nominal_voltage:     float  = 230.0
@export var inrush_factor:       float  = 4.0
@export var inrush_duration_s:   float  = 0.2

## Operating modes: off / eco / normal / fast_cool / freeze
const MODE_POWER_W: Dictionary = {
	"off":       0.0,
	"eco":       80.0,
	"normal":    150.0,
	"fast_cool": 250.0,
	"freeze":    350.0,
}
const MODE_TEMP_C: Dictionary = {
	"off":       20.0,
	"eco":       8.0,
	"normal":    4.0,
	"fast_cool": 1.0,
	"freeze":    -18.0,
}
const MODE_LABEL: Dictionary = {
	"off":       "Isključen",
	"eco":       "Eco",
	"normal":    "Normalan",
	"fast_cool": "Brzo hlađenje",
	"freeze":    "Zamrzavanje",
}

var current_mode: String = "normal"

func plug_into(bus: SimNode, model: CircuitModel) -> void:
	_bus = bus

	if _bridge != null:
		_bridge.queue_free()
		_bridge = null

	_consumer = RatedConsumer.new(
		bus, rated_power_w, power_factor, name, nominal_voltage, true
	)
	_consumer.inrush_factor     = inrush_factor
	_consumer.inrush_duration_s = inrush_duration_s
	model.add_element(_consumer)

	var cb := ConsumerBridge.new()
	cb.name = "%s_Bridge" % name
	add_child(cb)
	cb.bind(_consumer, model)
	_bridge = cb

	cb.solved.connect(func(): _solved = true)
	cb.damaged.connect(func(): push_warning("[%s] frižider je pregoreo!" % name))

func get_info() -> Dictionary:
	if not _solved:
		return {
			"name": refrigerator_name, "type": "Frizider",
			"enabled": true,
			"rows": [
				row("Mod",    MODE_LABEL.get(current_mode, current_mode)),
				row("Stanje", "nepovezano"),
			]
		}

	var cb: ConsumerBridge = _bridge as ConsumerBridge
	var v: float   = cb.vis_voltage_v if cb != null else 0.0
	var i: float   = cb.vis_current_a if cb != null else 0.0
	var st: String = cb.vis_state     if cb != null else "unknown"

	var temp_str: String = "—" if current_mode == "off" else ("%.0f °C" % MODE_TEMP_C.get(current_mode, 0.0))

	return {
		"name":    refrigerator_name,
		"type":    "Frizider",
		"enabled": is_enabled(),
		"rows": [
			row("Mod",           MODE_LABEL.get(current_mode, current_mode)),
			row("Ciljana temp.", temp_str),
			row("Nom. snaga",    rated_power_w,        "%.0f W"),
			row("Faktor snage",  power_factor,         "%.2f"),
			row("Nom. napon",    nominal_voltage,      "%.0f V"),
			row("Inrush faktor", inrush_factor,        "%.1fx"),
			row("Inrush vreme",  inrush_duration_s,    "%.2f s"),
			row("Napon",         v,                    "%.2f V"),
			row("Pad nap.",      get_voltage_drop(),   "%.2f V"),
			row("Struja",        i,                    "%.2f A"),
			row("Snaga",         v * i,                "%.1f W"),
			row("Stanje",        st),
		]
	}

func apply_params(params: Dictionary) -> void:
	var new_name: String = params.get("appliance_name", name)
	if not new_name.is_empty(): name = new_name

	# Mode change
	if params.has("mode"):
		var m: String = params["mode"]
		if MODE_POWER_W.has(m):
			current_mode  = m
			rated_power_w = MODE_POWER_W[m]

	rated_power_w     = params.get("rated_power_w",     rated_power_w)
	nominal_voltage   = params.get("nominal_voltage",    nominal_voltage)
	power_factor      = params.get("power_factor",       power_factor)
	inrush_factor     = params.get("inrush_factor",      inrush_factor)
	inrush_duration_s = params.get("inrush_duration_s",  inrush_duration_s)

	if _consumer != null:
		_consumer.power_w           = rated_power_w
		_consumer.nominal_voltage   = nominal_voltage
		_consumer.rated_pf          = power_factor
		_consumer.inrush_factor     = inrush_factor
		_consumer.inrush_duration_s = inrush_duration_s
		_consumer.element_name      = name
		_consumer.mark_dirty()
