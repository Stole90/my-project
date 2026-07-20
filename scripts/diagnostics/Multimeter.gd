## Multimeter.gd
## Full electrical measurement — voltage, current, power, resistance, and more.
##
## Voltage extraction priority:
##   "Napon" → "Napon L1/L2/L3" (averaged, all three stored) →
##   "LV napon" → "HV napon" → "Napon izl."
##
## Current extraction priority:
##   "Struja" → "Struja L1/L2/L3" → "LV struja" → "HV struja"
##
## Power extraction: "Snaga", "Uk. snaga", "Izl. snaga", "Uk. aktivna"
##
## All additional parameters (resistance, thermal, tap, PE, etc.) are
## extracted when present so the HUD can display them.

class_name Multimeter
extends DiagnosticTool

func _init() -> void:
    tool_name = "Multimeter"
    tool_icon  = "multimeter"

func can_measure(target: Node2D) -> bool:
    return target != null and target.has_method("get_info")

func measure(target: Node2D) -> Dictionary:
    if not can_measure(target):
        return {}

    var info: Dictionary = target.call("get_info")

    # ── Voltage ────────────────────────────────────────────────────────────
    var voltage: Variant    = "---"
    var voltages_3ph: Array = []
    if has_row(info, "Napon"):
        voltage = get_row_value(info, "Napon")
    elif has_row(info, "Napon L1"):
        voltages_3ph = [
            _f(get_row_value(info, "Napon L1", 0.0)),
            _f(get_row_value(info, "Napon L2", 0.0)),
            _f(get_row_value(info, "Napon L3", 0.0)),
        ]
        voltage = (voltages_3ph[0] + voltages_3ph[1] + voltages_3ph[2]) / 3.0
    elif has_row(info, "LV napon"):
        voltage = get_row_value(info, "LV napon")
    elif has_row(info, "HV napon"):
        voltage = get_row_value(info, "HV napon")
    elif has_row(info, "Napon izl."):
        voltage = get_row_value(info, "Napon izl.")

    # ── Current ────────────────────────────────────────────────────────────
    var current: Variant    = "---"
    var currents_3ph: Array = []
    if has_row(info, "Struja"):
        current = get_row_value(info, "Struja")
    elif has_row(info, "Struja L1"):
        currents_3ph = [
            _f(get_row_value(info, "Struja L1", 0.0)),
            _f(get_row_value(info, "Struja L2", 0.0)),
            _f(get_row_value(info, "Struja L3", 0.0)),
        ]
        current = (currents_3ph[0] + currents_3ph[1] + currents_3ph[2]) / 3.0
    elif has_row(info, "LV struja"):
        current = get_row_value(info, "LV struja")
    elif has_row(info, "HV struja"):
        current = get_row_value(info, "HV struja")

    # ── Power ──────────────────────────────────────────────────────────────
    # "Uk. aktivna" is in kW, not W — handled separately as total_power_kw.
    var power: Variant      = "---"
    var power_label: String = ""
    for lbl in ["Snaga", "Uk. snaga", "Izl. snaga"]:
        if has_row(info, lbl):
            power       = get_row_value(info, lbl)
            power_label = lbl
            break

    # ── State ──────────────────────────────────────────────────────────────
    var state: Variant = get_row_value(info, "Stanje",
                             get_row_value(info, "⚠ Stanje", "?"))

    var result: Dictionary = {
        "tool":        tool_name,
        "target_name": info.get("name", target.name),
        "target_type": info.get("type", "?"),
        "voltage_v":   voltage,
        "current_a":   current,
        "power_w":     power,
        "power_label": power_label,
        "state":       state,
    }

    if voltages_3ph.size() == 3:
        result["voltages_3ph"] = voltages_3ph
    if currents_3ph.size() == 3:
        result["currents_3ph"] = currents_3ph

    # ── Extra: voltage drop ────────────────────────────────────────────────
    if has_row(info, "Pad nap."):
        result["voltage_drop_v"] = get_row_value(info, "Pad nap.")

    # ── Extra: resistance (single-phase cable) ────────────────────────────
    if has_row(info, "Otpor (T)"):
        result["resistance_ohm"]      = get_row_value(info, "Otpor (T)")
        result["resistance_cold_ohm"] = get_row_value(info, "Otpor (20°)")

    # ── Extra: loading % ──────────────────────────────────────────────────
    if has_row(info, "Opterećenje"):
        result["load_percent"] = get_row_value(info, "Opterećenje")

    # ── Extra: dissipation ────────────────────────────────────────────────
    if has_row(info, "Disipacija"):
        result["dissipation_w"] = get_row_value(info, "Disipacija")

    # ── Extra: temperature ────────────────────────────────────────────────
    for lbl in ["Temperatura", "Temp. pećnice"]:
        if has_row(info, lbl):
            result["temperature_c"] = get_row_value(info, lbl)
            break

    # ── Extra: fuse-specific ──────────────────────────────────────────────
    if has_row(info, "Term. energ."):
        result["thermal_energy_pct"] = get_row_value(info, "Term. energ.")
    if has_row(info, "Nom. struja"):
        result["rated_current_a"] = get_row_value(info, "Nom. struja")
    elif has_row(info, "Maks. struja"):
        result["rated_current_a"] = get_row_value(info, "Maks. struja")

    # ── Extra: power factor ───────────────────────────────────────────────
    if has_row(info, "Faktor snage"):
        result["power_factor"] = get_row_value(info, "Faktor snage")

    # ── Extra: transformer ────────────────────────────────────────────────
    if has_row(info, "Efikasnost"):
        result["efficiency"] = get_row_value(info, "Efikasnost")
    if has_row(info, "Tap"):
        result["tap_position"] = get_row_value(info, "Tap")
    if has_row(info, "Reg. nap."):
        result["voltage_regulation"] = get_row_value(info, "Reg. nap.")
    if has_row(info, "Gubici"):
        result["losses"] = get_row_value(info, "Gubici")
    if has_row(info, "HV napon"):
        result["voltage_hv"] = get_row_value(info, "HV napon")
    if has_row(info, "LV napon"):
        result["voltage_lv"] = get_row_value(info, "LV napon")
    if has_row(info, "HV struja"):
        result["current_hv"] = get_row_value(info, "HV struja")
    if has_row(info, "LV struja"):
        result["current_lv"] = get_row_value(info, "LV struja")

    # ── Extra: source (neutral / PE) ──────────────────────────────────────
    if has_row(info, "Nulti prov."):
        result["neutral_status"] = get_row_value(info, "Nulti prov.")
    if has_row(info, "PE provodnik"):
        result["pe_status"] = get_row_value(info, "PE provodnik")
    if has_row(info, "Uk. aktivna"):
        result["total_power_kw"] = get_row_value(info, "Uk. aktivna")

    # ── Extra: oven ───────────────────────────────────────────────────────
    if has_row(info, "Mod"):
        result["cook_mode"] = get_row_value(info, "Mod")
    if has_row(info, "Ciljana temp."):
        result["target_temp_c"] = get_row_value(info, "Ciljana temp.")
    if has_row(info, "Napredak"):
        result["temp_progress_pct"] = get_row_value(info, "Napredak")

    # ── Extra: cable geometry ─────────────────────────────────────────────
    if has_row(info, "Dužina"):
        result["length_m"] = get_row_value(info, "Dužina")
    if has_row(info, "Presek"):
        result["cross_mm2"] = get_row_value(info, "Presek")

    # ── Fault detection ───────────────────────────────────────────────────
    var state_str: String = str(state).to_lower()
    result["fault_detected"] = (
        state_str.contains("pregoreo")  or
        state_str.contains("oštećen")   or
        state_str.contains("preoptere") or
        state_str.contains("pregrejan") or
        state_str.contains("kvar")      or
        state_str.contains("pao")       or
        state_str.contains("faulted")   or
        state_str.contains("damaged")
    )

    return result

static func _f(v: Variant) -> float:
    if v is float: return v
    if v is int:   return float(v)
    return 0.0
