## TransformerNode.gd (refaktorisan)
## Vizuelni node za monofazni transformator.
## Sim logika i stanje → TransformerBridge.

class_name TransformerNode
extends Node2D

@export var transformer_name:      String = "transformer"
@export var primary_voltage_v:     float  = 11000.0
@export var secondary_voltage_v:   float  = 400.0
@export var rated_power_kva:       float  = 100.0
@export var winding_r_pu:          float  = 0.01
@export var leakage_x_pu:          float  = 0.05
@export var tap_position:          int    = 0

signal transformer_tripped(node: TransformerNode)
signal transformer_repaired(node: TransformerNode)
signal transformer_overloaded(node: TransformerNode)
signal transformer_overheated(node: TransformerNode)

var _primary_bus:   SimNode           = null
var _secondary_bus: SimNode           = null
var _transformer:   Transformer       = null
var _bridge:        TransformerBridge = null
var _model:         CircuitModel      = null
var _initialized:   bool              = false

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup_in(model: CircuitModel) -> void:
    if _initialized: return
    _initialized = true
    _model = model

    _primary_bus   = SimNode.new("%s_hv" % transformer_name)
    _secondary_bus = SimNode.new("%s_lv" % transformer_name)

    var data := TransformerData.new()
    data.primary_voltage           = primary_voltage_v
    data.secondary_voltage         = secondary_voltage_v
    data.rated_power_kva           = rated_power_kva
    data.winding_resistance_pu     = winding_r_pu
    data.leakage_reactance_pu      = leakage_x_pu
    data.tap_position              = tap_position
    data.ambient_temperature_c     = 25.0
    data.max_temperature_c         = 105.0
    data.thermal_capacity_kj_per_k = rated_power_kva * 0.5
    data.cooling_rate_kw_per_k     = 0.05

    _transformer = Transformer.new(_primary_bus, _secondary_bus, data, transformer_name)
    model.add_element(_transformer)

    _bridge = TransformerBridge.new()
    _bridge.name = "%s_Bridge" % transformer_name
    add_child(_bridge)
    _bridge.bind(_transformer, model)

    # Prosleđuj signale ka world.gd
    _bridge.overloaded.connect(func(v): if v: emit_signal("transformer_overloaded", self))
    _bridge.overheated.connect(func(v): if v: emit_signal("transformer_overheated", self))
    _bridge.damaged.connect(func(): emit_signal("transformer_tripped", self))
    _bridge.solved.connect(queue_redraw)

# ── Bus pristup ───────────────────────────────────────────────────────────────

func get_sim_bus() -> SimNode:       return _primary_bus
func get_primary_bus() -> SimNode:   return _primary_bus
func get_secondary_bus() -> SimNode: return _secondary_bus

# ── Game actions ──────────────────────────────────────────────────────────────

func trip() -> void:
    if _bridge != null: _bridge.interact_toggle()
    emit_signal("transformer_tripped", self)

func repair() -> void:
    if _bridge != null: _bridge.interact_repair()
    emit_signal("transformer_repaired", self)
    queue_redraw()

func toggle_power() -> void:
    if _bridge != null: _bridge.interact_toggle()

func adjust_tap(steps: int) -> void:
    if _transformer == null: return
    _transformer.adjust_tap(steps)
    if _model: _model.mark_dirty()

# ── InfoPanel API ─────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
    return _bridge.get_info() if _bridge != null else { "name": transformer_name, "type": "Transformator", "rows": [] }

static func row(label: String, value, fmt: String = "") -> Dictionary:
    return ElementBridge.row(label, value, fmt)

# ── Crtanje ───────────────────────────────────────────────────────────────────

func _draw() -> void:
    if _bridge == null or _transformer == null: return

    var col: Color
    if _bridge.vis_damaged:       col = Color(0.8, 0.1, 0.0)
    elif _bridge.vis_overheated:  col = Color(1.0, 0.4, 0.0)
    elif _bridge.vis_overloaded:  col = Color(1.0, 0.85, 0.0)
    elif not _bridge.vis_enabled: col = Color(0.45, 0.45, 0.45)
    else:                         col = Color(0.2, 0.75, 0.2)

    draw_circle(Vector2(0, 40), 7, col)

    if _bridge.vis_load_pct > 0.0:
        draw_string(ThemeDB.fallback_font, Vector2(-20, 54),
            "%.0f%%" % _bridge.vis_load_pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

    if _bridge.vis_prim_v > 0.0:
        draw_string(ThemeDB.fallback_font, Vector2(-40, -42),
            "HV %.0fV" % _bridge.vis_prim_v, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
        draw_string(ThemeDB.fallback_font, Vector2(-40, -28),
            "LV %.0fV" % _bridge.vis_sec_v, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)

## Sekundarni/izlazni bus ovog node-a daje proizvoljnu fazu — appliance
## povezan direktno ovde sme sam da bira L1/L2/L3.
func is_free_phase_source() -> bool:
        return true
