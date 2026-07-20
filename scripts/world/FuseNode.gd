## FuseNode.gd (refaktorisan)
## Vizuelni node za osigurač.
## Sim logika i stanje → FuseBridge.
## Termalni tick (tick_thermal) ostaje ovde jer zahteva _process().

class_name FuseNode
extends Node2D

@export var rated_current_a: float     = 16.0
@export var resettable: bool           = true
@export var fuse_name: String          = "osigurac"
@export var curve: Fuse.TripCurve      = Fuse.TripCurve.C

signal fuse_blown(fuse_node: FuseNode)
signal fuse_reset(fuse_node: FuseNode)

var _bus_in:  SimNode         = null
var _bus_out: SimNode         = null
var _fuse:    Fuse            = null
var _bridge:  FuseBridge      = null
var _model:   CircuitModel    = null

# ── Setup ─────────────────────────────────────────────────────────────────────

## Standardni setup — kreira novi _bus_out.
func setup_in(bus_in: SimNode, model: CircuitModel) -> void:
    _bus_in  = bus_in
    _bus_out = SimNode.new("%s_out" % fuse_name)
    _model   = model
    _fuse    = Fuse.new(_bus_in, _bus_out, rated_current_a, resettable, fuse_name, curve)
    model.add_element(_fuse)

    _bridge = FuseBridge.new()
    _bridge.name = "%s_Bridge" % fuse_name
    add_child(_bridge)
    _bridge.bind(_fuse, model)

    _bridge.blown.connect(_on_bridge_blown)
    _bridge.fuse_reset.connect(func(): emit_signal("fuse_reset", self))

    set_process(true)

## DistBox setup — koristi postojeći consumer_in_bus kao _bus_out,
## tako da potrošač koji je već plugovan na taj bus automatski dobija struju.
func setup_in_out(bus_in: SimNode, bus_out: SimNode, model: CircuitModel) -> void:
    _bus_in  = bus_in
    _bus_out = bus_out
    _model   = model
    _fuse    = Fuse.new(_bus_in, _bus_out, rated_current_a, resettable, fuse_name, curve)
    model.add_element(_fuse)

    _bridge = FuseBridge.new()
    _bridge.name = "%s_Bridge" % fuse_name
    add_child(_bridge)
    _bridge.bind(_fuse, model)

    _bridge.blown.connect(_on_bridge_blown)
    _bridge.fuse_reset.connect(func(): emit_signal("fuse_reset", self))

    set_process(true)

func _process(delta: float) -> void:
    if _fuse == null or not _fuse.is_closed():
        return
    # tick_thermal ostaje ovde jer zahteva frame delta
    if _fuse.tick_thermal(delta):
        emit_signal("fuse_blown", self)

func _on_bridge_blown() -> void:
    emit_signal("fuse_blown", self)

# ── Bus pristup ───────────────────────────────────────────────────────────────

func get_output_bus() -> SimNode: return _bus_out
func get_sim_bus() -> SimNode:    return _bus_out
func get_input_bus() -> SimNode:  return _bus_in

## Za InfoPanel prikaz izabrane faze (relevantno samo za monofazne DistBox grane —
## sama promena ide preko DistBoxNode.set_consumer_phase(), ne direktno ovde).
func get_assigned_phase() -> int:
    if _fuse != null and _fuse.get("assigned_phase") != null:
        return _fuse.assigned_phase
    return Phase.L1

# ── Interakcije ───────────────────────────────────────────────────────────────

func interact() -> void:
    if _bridge == null: return
    if _fuse != null and _fuse.blown:
        _bridge.interact_repair()
    else:
        _bridge.interact_toggle()

func reset_fuse() -> void:
    if _bridge != null: _bridge.interact_repair()

func repair() -> void:
    reset_fuse()

# ── InfoPanel API ─────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
    return _bridge.get_info() if _bridge != null else { "name": fuse_name, "type": "Osigurač", "rows": [] }

static func row(label: String, value, fmt: String = "") -> Dictionary:
    return ElementBridge.row(label, value, fmt)
