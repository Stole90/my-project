## ThreePhaseOvenNode.gd (refaktorisan)
## Sva sim logika i stanje → ThreePhaseOvenBridge.
## Ovaj fajl odgovara SAMO za: set_mode API, apply_params, i get_info delegaciju.

class_name ThreePhaseOvenNode
extends BaseAppliance

@export var oven_name:    String = "Trofazna pećnica"
@export var initial_mode: String = ThreePhaseOven.MODE_OFF

signal target_reached()
signal overheated_oven()

var _oven: ThreePhaseOven = null

func plug_into(bus: SimNode, model: CircuitModel) -> void:
        _bus  = bus
        _oven = ThreePhaseOven.new(bus, name)
        _oven.set_mode(initial_mode)
        model.add_element(_oven)

        var ob := ThreePhaseOvenBridge.new()
        ob.name = "%s_Bridge" % name
        add_child(ob)
        ob.bind(_oven, model)
        _bridge = ob

        ob.solved.connect(func(): _solved = true)
        ob.target_reached.connect(func():  emit_signal("target_reached"))
        ob.overheated_oven.connect(func(): emit_signal("overheated_oven"))

# ── Game actions ──────────────────────────────────────────────────────────────

func set_mode(mode: String) -> void:
        var ob: ThreePhaseOvenBridge = _bridge as ThreePhaseOvenBridge
        if ob != null: ob.set_mode(mode)

func toggle_power() -> void:
        if _bridge != null: _bridge.interact_toggle()

func repair() -> void:
        if _bridge != null: _bridge.interact_repair()

func is_enabled() -> bool:
        var ob: ThreePhaseOvenBridge = _bridge as ThreePhaseOvenBridge
        return ob != null and ob.vis_enabled

func current_mode() -> String:
        var ob: ThreePhaseOvenBridge = _bridge as ThreePhaseOvenBridge
        return ob.vis_cook_mode if ob != null else ThreePhaseOven.MODE_OFF

func oven_temp() -> float:
        var ob: ThreePhaseOvenBridge = _bridge as ThreePhaseOvenBridge
        return ob.vis_oven_temp_c if ob != null else 20.0

# ── InfoPanel API ─────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
        if _bridge == null:
                return {"name": oven_name, "type": "3-fazna pećnica", "enabled": false, "rows": []}
        var info: Dictionary = _bridge.get_info()
        info["name"] = oven_name
        return info

func is_three_phase_appliance() -> bool:
        return true

func apply_params(params: Dictionary) -> void:
        var new_name: String = params.get("appliance_name", "")
        if not new_name.is_empty(): oven_name = new_name
        var mode: String = params.get("cook_mode", "")
        if not mode.is_empty(): set_mode(mode)
