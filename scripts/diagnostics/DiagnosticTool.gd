## DiagnosticTool.gd
## Abstract base class for all diagnostic instruments.
##
## Subclasses override:
##   measure(target)  → Dictionary of readings
##   can_measure(target) → bool
##
## Standard reading keys (use whichever are relevant):
##   tool, target_name, target_type,
##   voltage_v, current_a, resistance_ohm, temperature_c,
##   thermal_level, load_percent, power_w, power_factor,
##   fault_detected, state

class_name DiagnosticTool
extends RefCounted

var tool_name: String = "Tool"
var tool_icon: String = ""

func measure(_target: Node2D) -> Dictionary:
    return {}

func can_measure(_target: Node2D) -> bool:
    return false

func fmt(value: Variant, format_str: String) -> String:
    if value is float or value is int:
        return format_str % float(value)
    return str(value)

## Izvlači vrednost iz rows liste po labeli.
## Vraća default ako label nije pronađen.
static func get_row_value(info: Dictionary, label: String, default = "---") -> Variant:
    var rows: Array = info.get("rows", [])
    for row in rows:
        if row.get("label", "") == label:
            return row.get("value", default)
    return default

## Proverava da li rows lista sadrži dati label.
static func has_row(info: Dictionary, label: String) -> bool:
    var rows: Array = info.get("rows", [])
    for row in rows:
        if row.get("label", "") == label:
            return true
    return false
