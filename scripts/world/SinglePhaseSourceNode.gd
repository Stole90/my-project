## SinglePhaseSourceNode.gd
## Scene node wrapping SinglePhaseVoltageSource.
## Drop in as a child of your simulation scene.
##
## API is identical to ThreePhaseSourceNode so your game code stays consistent.

class_name SinglePhaseSourceNode
extends Node2D

@export var voltage_rms:  float  = 230.0   # V (RMS)
@export var phase_deg:    float  = 0.0     # degrees
@export var source_name:  String = ""

signal power_cut()
signal power_restored()

var _source:      SinglePhaseVoltageSource = null
var _bus:         SimNode                  = null
var _bridge:      SinglePhaseSourceBridge  = null
var _initialized: bool                     = false

func get_sim_bus() -> SimNode: return _bus

## Single-phase sources expose any phase freely — same contract as 3-phase.
func is_free_phase_source() -> bool:
	return true

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup_in(model: CircuitModel) -> void:
	if _initialized:
		return
	var sname: String = source_name if not source_name.is_empty() else name

	_bus    = SimNode.new("%s_bus" % sname)
	_source = SinglePhaseVoltageSource.new(_bus, voltage_rms, phase_deg, sname)
	model.add_element(_source)

	_bridge = SinglePhaseSourceBridge.new()
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
		else {"name": source_name, "type": "1-phase source", "rows": []}
	info["nominal_v"] = voltage_rms
	return info

func apply_params(params: Dictionary) -> void:
	var new_name: String = params.get("appliance_name", "")
	if not new_name.is_empty():
		source_name = new_name
	var new_v: float = params.get("nominal_voltage", -1.0)
	if new_v > 0.0:
		voltage_rms = new_v
		if _source != null:
			_source.set_voltage(voltage_rms, phase_deg)
	queue_redraw()

# ── Draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var col: Color
	if _bridge == null:
		col = Color(0.5, 0.5, 0.5)
	elif not _bridge.vis_enabled:
		col = Color(0.6, 0.6, 0.6)
	elif _bridge.vis_v_pe > 50.0:
		col = Color(0.9, 0.0, 0.0)
	else:
		col = Color(0.15, 0.75, 0.15)
	draw_circle(Vector2.ZERO, 8.0, col)
	draw_circle(Vector2.ZERO, 8.0, Color.WHITE, false, 1.5)
	var lbl: String = "OFF" if (_bridge != null and not _bridge.vis_enabled) else "1~"
	draw_string(ThemeDB.fallback_font, Vector2(-7, 5), lbl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
