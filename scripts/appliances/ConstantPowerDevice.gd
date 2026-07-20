## ConstantPowerDevice.gd
## Appliance for devices that maintain constant active power regardless of voltage.
## Models: computers, PSUs, switching power supplies, monitors, servers, etc.
## Uses ConstantPowerConsumer (ZIP model "P" load) instead of RatedConsumer.
## Power draw stays the same even when supply voltage fluctuates.

class_name ConstantPowerDevice
extends BaseAppliance

@export var device_name:      String = "Računar"
@export var power_w:          float  = 300.0
@export var power_factor:     float  = 0.95
@export var nominal_voltage:  float  = 230.0
@export var standby_power_w:  float  = 5.0

## Operating modes
const MODE_OFF     := "off"
const MODE_STANDBY := "standby"
const MODE_ON      := "on"

const MODE_LABEL: Dictionary = {
	"off":     "Isključen",
	"standby": "Standby",
	"on":      "Uključen",
}

var current_mode: String = MODE_ON

## Typed reference — BaseAppliance._consumer is RatedConsumer, ours is different.
var _cp_consumer: ConstantPowerConsumer = null

func _get_assigned_phase() -> int:
	if _cp_consumer != null:
		return _cp_consumer.assigned_phase
	return Phase.L1

# ── Plug API ──────────────────────────────────────────────────────────────────

func plug_into(bus: SimNode, model: CircuitModel) -> void:
	_bus = bus

	if _bridge != null:
		_bridge.queue_free()
		_bridge = null

	var active_power: float = _active_power_for_mode(current_mode)

	_cp_consumer = ConstantPowerConsumer.new(
		bus, active_power, power_factor, name, nominal_voltage, false
	)
	model.add_element(_cp_consumer)

	var cb := ConsumerBridge.new()
	cb.name = "%s_Bridge" % name
	add_child(cb)
	cb.bind(_cp_consumer, model)
	_bridge = cb

	cb.solved.connect(func(): _solved = true)
	cb.damaged.connect(func(): push_warning("[%s] uređaj pregoreo!" % name))

# ── Info ─────────────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	if not _solved:
		return {
			"name": device_name, "type": "Konst. snaga uređaj",
			"enabled": true,
			"rows": [
				row("Mod",    MODE_LABEL.get(current_mode, current_mode)),
				row("Stanje", "nepovezano"),
			]
		}

	var cb: ConsumerBridge = _bridge as ConsumerBridge
	var v: float   = cb.vis_voltage_v if cb != null else 0.0
	var i: float   = cb.vis_current_a if cb != null else 0.0
	var st: String = cb.vis_state     if cb != null else "?"

	return {
		"name":    device_name,
		"type":    "Konst. snaga uređaj",
		"enabled": is_enabled(),
		"rows": [
			row("Mod",          MODE_LABEL.get(current_mode, current_mode)),
			row("Nom. snaga",   power_w,             "%.0f W"),
			row("Standby sn.",  standby_power_w,     "%.0f W"),
			row("Faktor snage", power_factor,        "%.2f"),
			row("Nom. napon",   nominal_voltage,     "%.0f V"),
			row("Napon",        v,                   "%.2f V"),
			row("Pad nap.",     get_voltage_drop(),  "%.2f V"),
			row("Struja",       i,                   "%.2f A"),
			row("Akt. snaga",   v * i,               "%.1f W"),
			row("Stanje",       st),
		]
	}

# ── Params / mode ─────────────────────────────────────────────────────────────

func apply_params(params: Dictionary) -> void:
	var new_name: String = params.get("appliance_name", name)
	if not new_name.is_empty(): name = new_name

	if params.has("mode"):
		var m: String = params["mode"]
		if m in [MODE_OFF, MODE_STANDBY, MODE_ON]:
			current_mode = m
			_apply_mode_to_consumer()

	power_w         = params.get("rated_power_w",   power_w)
	standby_power_w = params.get("standby_power_w", standby_power_w)
	nominal_voltage = params.get("nominal_voltage",  nominal_voltage)
	power_factor    = params.get("power_factor",     power_factor)

	if _cp_consumer != null:
		_cp_consumer.power_w         = _active_power_for_mode(current_mode)
		_cp_consumer.rated_pf        = power_factor
		_cp_consumer.nominal_voltage = nominal_voltage
		_cp_consumer.element_name    = name
		_cp_consumer.mark_dirty()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _active_power_for_mode(mode: String) -> float:
	match mode:
		MODE_OFF:     return maxf(standby_power_w * 0.1, 0.1)
		MODE_STANDBY: return maxf(standby_power_w, 0.1)
		MODE_ON:      return maxf(power_w, 0.1)
	return maxf(power_w, 0.1)

func _apply_mode_to_consumer() -> void:
	if _cp_consumer == null: return
	var p: float = _active_power_for_mode(current_mode)
	_cp_consumer.power_w = p
	if current_mode == MODE_OFF:
		_cp_consumer.disable()
	else:
		_cp_consumer.enable()
	_cp_consumer.mark_dirty()
