## CurrentSourceNode.gd
## Scene node wrapping ACCurrentSource or DCCurrentSource.
##
## ── Two-terminal node ─────────────────────────────────────────────────────────
##
##   Current sources are two-terminal: they inject current between two existing
##   network buses.  Unlike voltage sources (which create their own bus),
##   CurrentSourceNode needs references to two SimNodes already in the model.
##
##   Two wiring patterns are supported:
##
##   1. setup(node_a, node_b, model)  — you supply both SimNodes directly.
##      Use this when wiring from code (e.g. in CircuitWorld.gd).
##
##   2. setup_in(model)  — the node creates two internal buses (same as voltage
##      source nodes).  Use this when the current source is floating or drives
##      an isolated branch.  Connect the buses later via cables.
##
## ── @export fields ────────────────────────────────────────────────────────────
##
##   current_a  — magnitude [A]
##   phase_deg  — angle [°] for AC (ignored for DC)
##   is_dc      — true → DCCurrentSource; false → ACCurrentSource
##   source_name — display name

class_name CurrentSourceNode
extends Node2D

@export var current_a:   float  = 1.0
@export var phase_deg:   float  = 0.0
@export var is_dc:       bool   = false
@export var source_name: String = ""

signal power_cut()
signal power_restored()

var _source:      CircuitElement      = null
var _node_a:      SimNode             = null
var _node_b:      SimNode             = null
var _bridge:      CurrentSourceBridge = null
var _initialized: bool                = false

# ── Setup ─────────────────────────────────────────────────────────────────────

## Variant 1: supply external SimNodes (most common for current sources).
func setup(node_a: SimNode, node_b: SimNode, model: CircuitModel) -> void:
	if _initialized:
		return
	_do_setup(node_a, node_b, model)

## Variant 2: create internal floating buses — connect them with cables.
func setup_in(model: CircuitModel) -> void:
	if _initialized:
		return
	var sname: String = source_name if not source_name.is_empty() else name
	var na: SimNode = SimNode.new("%s_A" % sname)
	var nb: SimNode = SimNode.new("%s_B" % sname)
	_do_setup(na, nb, model)

# ── Shared init ───────────────────────────────────────────────────────────────

func _do_setup(node_a: SimNode, node_b: SimNode, model: CircuitModel) -> void:
	var sname: String = source_name if not source_name.is_empty() else name
	_node_a = node_a
	_node_b = node_b

	if is_dc:
		_source = DCCurrentSource.new(_node_a, _node_b, current_a, sname)
	else:
		var phasor: Complex = Complex.from_polar(current_a, deg_to_rad(phase_deg))
		_source = ACCurrentSource.new(_node_a, _node_b, phasor, sname)

	model.add_element(_source)

	_bridge = CurrentSourceBridge.new()
	_bridge.name = "%s_Bridge" % sname
	add_child(_bridge)
	_bridge.bind(_source, model)

	_bridge.solved.connect(queue_redraw)
	_bridge.power_cut.connect(func(): emit_signal("power_cut"); queue_redraw())
	_bridge.power_restored.connect(func(): emit_signal("power_restored"); queue_redraw())

	_initialized = true

## The two bus nodes (for wiring cables to them when using setup_in).
func get_node_a() -> SimNode: return _node_a
func get_node_b() -> SimNode: return _node_b

# ── Game actions ──────────────────────────────────────────────────────────────

func cut_power()     -> void: if _bridge != null: _bridge.interact_toggle()
func restore_power() -> void: if _bridge != null: _bridge.interact_repair()
func toggle_power()  -> void: if _bridge != null: _bridge.interact_toggle()
func is_active()     -> bool: return _bridge != null and _bridge.vis_enabled

func get_info() -> Dictionary:
	if _bridge != null:
		return _bridge.get_info()
	return {"name": source_name, "type": "Current source", "rows": []}

func apply_params(params: Dictionary) -> void:
	var new_i: float = params.get("current_a", -1.0)
	if new_i >= 0.0:
		current_a = new_i
		if _source != null and not is_dc:
			(_source as ACCurrentSource).set_current_polar(current_a, phase_deg)
		elif _source != null and is_dc:
			(_source as DCCurrentSource).set_current(current_a)
	queue_redraw()

# ── Draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	var col: Color
	if _bridge == null:
		col = Color(0.5, 0.5, 0.5)
	elif not _bridge.vis_enabled:
		col = Color(0.6, 0.6, 0.6)
	else:
		col = Color(1.0, 0.7, 0.0)   # amber = current source
	draw_circle(Vector2.ZERO, 8.0, col)
	draw_circle(Vector2.ZERO, 8.0, Color.WHITE, false, 1.5)
	var lbl: String = "OFF" if (_bridge != null and not _bridge.vis_enabled) \
		else ("IDC" if is_dc else "IAC")
	draw_string(ThemeDB.fallback_font, Vector2(-9, 5), lbl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
