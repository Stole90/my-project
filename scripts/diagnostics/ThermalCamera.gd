## ThermalCamera.gd
## Non-contact thermal imaging.
##
## Temperature sources (tried in order):
##   "Temperatura"   — cables, transformers, sockets
##   "Temp. pećnice" — 3-phase oven
##   "Term. energ."  — fuses (thermal energy % → proxy temperature)
##
## Extra parameters extracted when present:
##   ambient_c, insulation_limit_c, target_temp_c, temp_progress_pct,
##   thermal_energy_pct, load_percent, dissipation_w

class_name ThermalCamera
extends DiagnosticTool

const BAND_NORMAL: float = 40.0
const BAND_WARM:   float = 65.0
const BAND_HOT:    float = 90.0

func _init() -> void:
    tool_name = "Thermal Camera"
    tool_icon  = "thermal_camera"

func can_measure(target: Node2D) -> bool:
    if target == null or not target.has_method("get_info"):
        return false
    var info: Dictionary = target.call("get_info")
    return (
        has_row(info, "Temperatura")   or
        has_row(info, "Temp. pećnice") or
        has_row(info, "Term. energ.")
    )

func measure(target: Node2D) -> Dictionary:
    if not can_measure(target):
        return {}

    var info: Dictionary = target.call("get_info")
    var tname: String    = info.get("name", target.name)
    var ttype: String    = info.get("type", "?")
    var state_str: String = str(get_row_value(info, "Stanje", "")).to_lower()

    # ── Temperature — try real labels first, then synthesize from fuse energy ──
    var temp: float       = 25.0
    var temp_label: String = ""
    for lbl in ["Temperatura", "Temp. pećnice"]:
        if has_row(info, lbl):
            temp       = _f(get_row_value(info, lbl, 25.0))
            temp_label = lbl
            break

    var therm_pct: Variant = "---"
    if has_row(info, "Term. energ."):
        therm_pct = get_row_value(info, "Term. energ.")
        # No real temp sensor on fuses — derive proxy: 0 % → 25 °C, 100 % → 250 °C
        if temp_label.is_empty():
            temp = 25.0 + _f(therm_pct) * 2.25

    # ── Classification ────────────────────────────────────────────────────
    var level: String
    var level_color: String
    if temp < BAND_NORMAL:
        level = "Normal";   level_color = "green"
    elif temp < BAND_WARM:
        level = "Warm";     level_color = "yellow"
    elif temp < BAND_HOT:
        level = "Hot";      level_color = "orange"
    else:
        level = "Critical"; level_color = "red"

    var fault: bool = (
        temp >= BAND_HOT                  or
        state_str.contains("pregrejan")   or
        state_str.contains("overheating") or
        state_str.contains("kvar")        or
        state_str.contains("damaged")     or
        state_str.contains("faulted")
    )

    var result: Dictionary = {
        "tool":           tool_name,
        "target_name":    tname,
        "target_type":    ttype,
        "temperature_c":  temp,
        "thermal_level":  level,
        "thermal_color":  level_color,
        "fault_detected": fault,
    }

    # Loading %
    if has_row(info, "Opterećenje"):
        result["load_percent"] = get_row_value(info, "Opterećenje")

    # Fuse thermal energy %
    if therm_pct != "---":
        result["thermal_energy_pct"] = therm_pct

    # Ambient temperature
    if has_row(info, "Ambijent"):
        result["ambient_c"] = get_row_value(info, "Ambijent")

    # Insulation temperature limit
    if has_row(info, "Limit izol."):
        result["insulation_limit_c"] = get_row_value(info, "Limit izol.")

    # Heat source power
    if has_row(info, "Disipacija"):
        result["dissipation_w"] = get_row_value(info, "Disipacija")

    # Oven target temperature and heating progress
    if has_row(info, "Ciljana temp."):
        result["target_temp_c"] = get_row_value(info, "Ciljana temp.")
    if has_row(info, "Napredak"):
        result["temp_progress_pct"] = get_row_value(info, "Napredak")
    if has_row(info, "Grejanje"):
        result["heating_active"] = str(get_row_value(info, "Grejanje"))
    if has_row(info, "Mod"):
        result["cook_mode"] = get_row_value(info, "Mod")

    return result

static func _f(v: Variant) -> float:
    if v is float: return v
    if v is int:   return float(v)
    return 0.0
