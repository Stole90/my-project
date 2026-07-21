## DCSourceNode.gd
## Scene node wrapping DCVoltageSource (battery, PSU, PV panel, etc.).
## API consistent with ThreePhaseSourceNode and SinglePhaseSourceNode.

class_name DCSourceNode
extends Node2D

@export var voltage_v:    float  = 12.0   # V DC
@export var source_name:  String = ""

signal power_cut()
signal power_restored()

var _source:      DCVoltageSource = null
var _bus:         SimNode         = null
var _bridge:      DCSourceBridge  = null
var _initialized: bool            = false

func get_sim_bus() -> SimNode: return _bus

func is_free_phase_source() -> bool:
	return true

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup_in(model: CircuitModel) -> void:
	if _initialized:
		return
	var sname: String = source_name if not source_name.is_empty() else name

	_bus    = SimNode.new("%s_bus" % sname)
	_source = DCVoltageSource.new(_bus, voltage_v, sname)
	model.add_element(_source)

	_bridge = DCSourceBridge.new()
	_bridge.name = "%s_Bridge" % sname
	add_child(_bridge)
	_bridge.bind(_source, model)

	_bridge.solved.connect(queue_redraw)
	_bridge.power_cut.connect(func(): emit_signal("power_cut"); queue_redraw())
	_bridge.power_restored.connect(func(): emit_signal("power_restored"); queue_redraw())

	_initialized = true

# ── Game actions ──────────────────────────────────────────────────────────────

func cut_power()     -> void: if _bridge != null: _bridge.interact_toggle()
func restore_power() -> void: if _bridge != null: _bridge.interact_repair()
func toggle_power()  -> void: if _bridge != null: _bridge.interact_toggle()
func is_active()     -> bool: return _bridge != null and _bridge.vis_enabled

func get_info() -> Dictionary:
	var info: Dictionary = _bridge.get_info() if _bridge != null \
		else {"name": source_name, "type": "DC source", "rows": []}
	info["nominal_v"] = voltage_v
	return info

func apply_params(params: Dictionary) -> void:
	var new_name: String = params.get("appliance_name", "")
	if not new_name.is_empty():
		source_name = new_name
	var new_v: float = params.get("nominal_voltage", -1.0)
	if new_v > 0.0:
		voltage_v = new_v
		if _source != null:
			_source.set_voltage(voltage_v)
	queue_redraw()

# ── Draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var col: Color
	if _bridge == null:
		col = Color(0.5, 0.5, 0.5)
	elif not _bridge.vis_enabled:
		col = Color(0.6, 0.6, 0.6)
	else:
		col = Color(0.2, 0.6, 1.0)   # blue = DC
	draw_circle(Vector2.ZERO, 8.0, col)
	draw_circle(Vector2.ZERO, 8.0, Color.WHITE, false, 1.5)
	var lbl: String = "OFF" if (_bridge != null and not _bridge.vis_enabled) else "DC"
	draw_string(ThemeDB.fallback_font, Vector2(-8, 5), lbl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
