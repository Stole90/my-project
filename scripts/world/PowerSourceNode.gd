## PowerSourceNode.gd (refaktorisan)
## Monofazni source node — interno kreira ThreePhaseVoltageSource (L1).
## enable/disable/repair → SourceBridge.

class_name PowerSourceNode
extends Node2D

@export var voltage_rms:  float  = 230.0
@export var phase_deg:    float  = 0.0
@export var source_name:  String = "mreza"

signal power_cut()
signal power_restored()

var _bus:    SimNode                 = null
var _source: ThreePhaseVoltageSource = null
var _bridge: SourceBridge            = null
var _solved: bool                    = false

func setup_in(model: CircuitModel) -> void:
        _bus    = SimNode.new(source_name)
        _source = ThreePhaseVoltageSource.new(_bus, voltage_rms, phase_deg, 1, source_name)
        model.add_element(_source)

        _bridge = SourceBridge.new()
        _bridge.name = "%s_Bridge" % source_name
        add_child(_bridge)
        _bridge.bind(_source, model)

        _bridge.solved.connect(func(): _solved = true)
        _bridge.power_cut.connect(func(): emit_signal("power_cut"))
        _bridge.power_restored.connect(func(): emit_signal("power_restored"))

func get_sim_bus() -> SimNode: return _bus

# ── Game actions ──────────────────────────────────────────────────────────────

## Isključi napajanje (planski isklop).
func cut_power() -> void:
        if _bridge != null: _bridge.interact_toggle()

## Vrati napajanje.
func restore_power() -> void:
        if _bridge != null: _bridge.interact_repair()

## Toggle isklop/uklop.
func toggle_power() -> void:
        if _bridge != null: _bridge.interact_toggle()

func get_info() -> Dictionary:
        if _bridge == null:
                return {"name": source_name, "type": "Izvor napajanja", "nominal_v": voltage_rms, "rows": []}
        var info: Dictionary = _bridge.get_info()
        info["type"]     = "Izvor napajanja (L1)"
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
                        _source.set_balanced_voltage(voltage_rms, phase_deg)
        queue_redraw()

func _draw() -> void:
        var col: Color
        if _bridge == null or not _bridge.vis_enabled:
                col = Color(0.6, 0.6, 0.6)
        else:
                col = Color(0.15, 0.75, 0.15)
        draw_circle(Vector2.ZERO, 8.0, col)
        draw_circle(Vector2.ZERO, 8.0, Color.WHITE, false, 1.5)
