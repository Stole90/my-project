## BaseAppliance.gd (refaktorisan)
## Osnovna klasa za sve aparate u igri.
##
## ── Promena u odnosu na staru verziju ────────────────────────────────────────
##   _bridge je sada typed: ConsumerBridge (ili podklasa ElementBridge).
##   Podklase koje koriste Socket / ThreePhaseSocket trebaju koristiti
##   SocketBridge direktno (vidi SocketAppliance.gd).
##   row() helper više ne treba — koristiti ElementBridge.row() ili _bridge.row().

class_name BaseAppliance
extends Node2D

## Bridge tip — podklase mogu promeniti na specifičniji tip.
var _bridge:     ElementBridge = null
var _consumer:   RatedConsumer = null
var _bus:        SimNode       = null
var _supply_bus: SimNode       = null
var _solved:     bool          = false

# ── Plug API ──────────────────────────────────────────────────────────────────

func plug_into_isolated(model: CircuitModel) -> void:
        var isolated_bus := SimNode.new("%s_bus" % name)
        plug_into(isolated_bus, model)

func plug_into(bus: SimNode, _model: CircuitModel) -> void:
        _bus = bus

func get_sim_bus() -> SimNode:
        return _bus

func notify_supply_bus(bus: SimNode) -> void:
        _supply_bus = bus

# ── Napon / pad napona ────────────────────────────────────────────────────────

## Sim element koji nosi .assigned_phase za ovaj appliance. Default je
## _consumer (RatedConsumer). Podklase sa drugačijim elementom — npr.
## SocketAppliance koji koristi _socket umesto _consumer — treba da
## override-uju ovo umesto da diraju _get_assigned_phase()/set_assigned_phase().
func _phase_element() -> Object:
        return _consumer

func _get_assigned_phase() -> int:
        var el: Object = _phase_element()
        if el != null and el.get("assigned_phase") != null:
                return el.assigned_phase
        return Phase.L1

## Javni getter/setter za fazu monofaznog potrošača — koristi InfoPanel
## za prikaz i promenu izbora faze (L1/L2/L3).
func get_assigned_phase() -> int:
        return _get_assigned_phase()

func set_assigned_phase(new_phase: int) -> void:
        var el: Object = _phase_element()
        if el == null:
                return
        el.assigned_phase = new_phase
        el.mark_dirty()

func get_voltage_drop() -> float:
        if not _solved or _bus == null or _supply_bus == null:
                return 0.0
        var ph: int     = _get_assigned_phase()
        var v_supply: float = _supply_bus.voltage_magnitude(ph)
        var v_load: float   = _bus.voltage_magnitude(ph)
        return v_supply - v_load

func get_voltage() -> float:
        if _bus == null: return 0.0
        return _bus.voltage_magnitude(_get_assigned_phase())

# ── Info za InfoPanel ─────────────────────────────────────────────────────────

#func get_info() -> Dictionary:
        #var v := get_voltage()
        #return {
                #"name":           name,
                #"type":           "Aparat",
                #"enabled":        is_enabled(),
                #"rows": [
                        #row("Napon",        "---" if not _solved else "%.2f" % v,                    "%.2f V"),
                        #row("Pad nap.",     "---" if not _solved else get_voltage_drop(),   "%.2f V"),
                        #row("Struja",       "---" if not _solved else 0.0,                  "%.2f A"),
                        #row("Stanje",       "nepovezano" if not _solved else "unknown"),
                #]
        #}

# ── Akcije ────────────────────────────────────────────────────────────────────

func repair() -> void:
        if _bridge: _bridge.interact_repair()

func toggle_power() -> void:
        if _bridge: _bridge.interact_toggle()

func is_enabled() -> bool:
        if _bridge and _bridge.element:
                return _bridge.element.enabled
        return true

func apply_params(_params: Dictionary) -> void:
        pass

## Override and return true in three-phase appliance subclasses
## (ThreePhaseOvenNode, ThreePhaseSocketAppliance, etc.).
## Used by DistBoxNode to decide whether to create a single-phase
## or three-phase fuse for this consumer.
func is_three_phase_appliance() -> bool:
        return false

# ── Utility ───────────────────────────────────────────────────────────────────

## Centralni row() helper — delegira na ElementBridge.
## Svi podovi u igri koriste SAMO ovaj poziv — nema više kopiranja.
static func row(label: String, value, fmt: String = "") -> Dictionary:
        return ElementBridge.row(label, value, fmt)

func _draw() -> void:
    # Proveravamo metadata baš kao što CableNode radi
    if get_meta("selected", false):
        # Definiši kvadrat (Rect2) koji odgovara veličini tvog uređaja. 
        # Ako je slika 64x64, crtamo od centra (-32, -32) sa dimenzijama 64x64.
        var rect = Rect2(-32, -32, 64, 64) 
        
        # Ista boja kao za kablove: Svetlo plava
        var color = Color(0.2, 0.8, 1.0, 0.5) 
        var line_width = 4.0
        
        # false znači da ne popunjavamo unutrašnjost (samo ivice)
        draw_rect(rect, color, false, line_width)
