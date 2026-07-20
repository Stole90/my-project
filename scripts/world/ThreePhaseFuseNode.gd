## ThreePhaseFuseNode.gd (refaktorisan)
## Vizuelni node za trofazni osigurač.
## Sim logika i stanje → ThreePhaseFuseBridge.

class_name ThreePhaseFuseNode
extends Node2D

@export var fuse_name:       String = "3-fazni osigurač"
@export var rated_current_a: float  = 16.0
@export var blow_time_s:     float  = 0.1

signal fuse_blown(phase: int)
signal fuse_reset()

var _bus_in:      SimNode              = null
var _bus_out:     SimNode              = null
var _fuse:        ThreePhaseFuse       = null
var _bridge:      ThreePhaseFuseBridge = null
var _model:       CircuitModel         = null
var _initialized: bool                 = false

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup_in(source_bus: SimNode, model: CircuitModel) -> void:
	if _initialized: return
	_initialized = true
	_model   = model
	_bus_in  = source_bus
	_bus_out = SimNode.new("%s_out" % fuse_name)
	_fuse    = ThreePhaseFuse.new(_bus_in, _bus_out, rated_current_a, fuse_name)
	model.add_element(_fuse)

	_bridge = ThreePhaseFuseBridge.new()
	_bridge.name = "%s_Bridge" % fuse_name
	add_child(_bridge)
	_bridge.bind(_fuse, model)

	_bridge.blown.connect(func(ph): emit_signal("fuse_blown", ph))
	_bridge.fuse_reset.connect(func(): emit_signal("fuse_reset"))
	_bridge.solved.connect(queue_redraw)

func setup_in_out(bus_in: SimNode, bus_out: SimNode, model: CircuitModel) -> void:
	if _initialized: return
	_initialized = true
	_model   = model
	_bus_in  = bus_in
	_bus_out = bus_out
	_fuse    = ThreePhaseFuse.new(_bus_in, _bus_out, rated_current_a, fuse_name)
	model.add_element(_fuse)

	_bridge = ThreePhaseFuseBridge.new()
	_bridge.name = "%s_Bridge" % fuse_name
	add_child(_bridge)
	_bridge.bind(_fuse, model)

	_bridge.blown.connect(func(ph): emit_signal("fuse_blown", ph))
	_bridge.fuse_reset.connect(func(): emit_signal("fuse_reset"))
	_bridge.solved.connect(queue_redraw)

# ── Bus pristup ───────────────────────────────────────────────────────────────

func get_sim_bus() -> SimNode:
	if _fuse == null: return _bus_in
	# Isti mehanizam kao stari kod — first cable → _bus_in; second → _bus_out
	for elem in _model.elements:
		if (elem is ThreePhaseCable or elem is Cable):
			if elem.node_a() == _bus_in or elem.node_b() == _bus_in:
				return _bus_out
	return _bus_in

# ── Game actions ──────────────────────────────────────────────────────────────

func repair() -> void:
	if _bridge != null: _bridge.interact_repair()

func is_enabled() -> bool:
	return _fuse != null and not _fuse.is_blown()

# ── InfoPanel API ─────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	return _bridge.get_info() if _bridge != null else {"name": fuse_name, "type": "3-fazni osigurač", "rows": []}

# ── Crtanje ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var col: Color
	if _bridge == null:              col = Color(0.5, 0.5, 0.5)
	elif _bridge.vis_damaged:        col = Color(0.9, 0.1, 0.0)
	elif not _bridge.vis_enabled:    col = Color(0.9, 0.1, 0.0)
	else:                            col = Color(0.2, 0.8, 0.2)
	draw_circle(Vector2.ZERO, 8.0, col)

static func row(label: String, value, fmt: String = "") -> Dictionary:
	return ElementBridge.row(label, value, fmt)
