## ClampMeter.gd
## Non-contact current measurement (clamp ammeter).
##
## Handles:
##   Single-phase  — row "Struja"
##   Three-phase   — rows "Struja L1/L2/L3" (and optional "Struja N")
##   Transformer   — rows "HV struja" / "LV struja"
##
## Extra parameters extracted when available:
##   thermal_energy_pct, temperature_c, unbalance_pct, load_percent

class_name ClampMeter
extends DiagnosticTool

func _init() -> void:
	tool_name = "Clamp Meter"
	tool_icon  = "clamp_meter"

func can_measure(target: Node2D) -> bool:
	if target == null or not target.has_method("get_info"):
		return false
	var info: Dictionary = target.call("get_info")
	return (
		has_row(info, "Struja")    or
		has_row(info, "Struja L1") or
		has_row(info, "HV struja")
	)

func measure(target: Node2D) -> Dictionary:
	if not can_measure(target):
		return {}

	var info: Dictionary  = target.call("get_info")
	var tname: String     = info.get("name", target.name)
	var ttype: String     = info.get("type",  "?")
	var state_str: String = str(get_row_value(info, "Stanje", "")).to_lower()
	var max_a: float      = _rated_a(info)

	# ── 3-phase path ─────────────────────────────────────────────────────
	if has_row(info, "Struja L1"):
		var l1: float = _f(get_row_value(info, "Struja L1", 0.0))
		var l2: float = _f(get_row_value(info, "Struja L2", 0.0))
		var l3: float = _f(get_row_value(info, "Struja L3", 0.0))
		var i_n_raw   = get_row_value(info, "Struja N", null)
		var i_avg: float    = (l1 + l2 + l3) / 3.0
		var i_max_ph: float = max(l1, max(l2, l3))

		var unbalance_pct: float = 0.0
		if i_avg > 0.01:
			var dev: float = max(abs(l1 - i_avg), max(abs(l2 - i_avg), abs(l3 - i_avg)))
			unbalance_pct  = dev / i_avg * 100.0

		var loading_3ph: String = "---"
		if max_a > 0.0:
			loading_3ph = "%.1f %%" % (i_max_ph / max_a * 100.0)

		var overloaded_3ph: bool = (
			(max_a > 0.0 and i_max_ph > max_a) or
			state_str.contains("preopterećen") or state_str.contains("overload")
		)

		var res: Dictionary = {
			"tool":          tool_name,
			"target_name":   tname,
			"target_type":   ttype,
			"is_3ph":        true,
			"current_l1":    l1,
			"current_l2":    l2,
			"current_l3":    l3,
			"current_avg":   i_avg,
			"current_max":   i_max_ph,
			"max_current_a": max_a if max_a > 0.0 else "---",
			"loading":       loading_3ph,
			"unbalance_pct": unbalance_pct,
			"overloaded":    overloaded_3ph,
			"fault_detected": overloaded_3ph,
		}
		if i_n_raw != null:
			res["current_n"] = _f(i_n_raw)
		return res

	# ── Transformer path (HV/LV) ─────────────────────────────────────────
	if not has_row(info, "Struja") and has_row(info, "HV struja"):
		var i_hv: float = _f(get_row_value(info, "HV struja", 0.0))
		var i_lv: float = _f(get_row_value(info, "LV struja", 0.0))
		var overloaded_ts: bool = (
			state_str.contains("preopterećen") or state_str.contains("overload")
		)
		return {
			"tool":          tool_name,
			"target_name":   tname,
			"target_type":   ttype,
			"is_3ph":        false,
			"current_hv":    i_hv,
			"current_lv":    i_lv,
			"load_percent":  get_row_value(info, "Opterećenje", "---"),
			"loading":       str(get_row_value(info, "Opterećenje", "---")),
			"max_current_a": "---",
			"overloaded":    overloaded_ts,
			"fault_detected": overloaded_ts,
		}

	# ── Single-phase path ────────────────────────────────────────────────
	var cur_raw  = get_row_value(info, "Struja", "---")
	var current: float = _f(cur_raw)

	var loading: String = "---"
	if max_a > 0.0 and (cur_raw is float or cur_raw is int):
		loading = "%.1f %%" % (current / max_a * 100.0)

	var overloaded: bool = (
		(max_a > 0.0 and current > max_a) or
		state_str.contains("preopterećen") or state_str.contains("overload")
	)

	var res: Dictionary = {
		"tool":          tool_name,
		"target_name":   tname,
		"target_type":   ttype,
		"is_3ph":        false,
		"current_a":     current if (cur_raw is float or cur_raw is int) else "---",
		"max_current_a": max_a if max_a > 0.0 else "---",
		"loading":       loading,
		"overloaded":    overloaded,
		"fault_detected": overloaded,
	}
	# Fuse thermal energy
	var therm = get_row_value(info, "Term. energ.", null)
	if therm != null:
		res["thermal_energy_pct"] = _f(therm)
	# Cable temperature
	var temp = get_row_value(info, "Temperatura", null)
	if temp != null:
		res["temperature_c"] = _f(temp)
	# Loading %
	if has_row(info, "Opterećenje"):
		res["load_percent"] = get_row_value(info, "Opterećenje")
	return res

# ── Helpers ───────────────────────────────────────────────────────────────────

static func _f(v: Variant) -> float:
	if v is float: return v
	if v is int:   return float(v)
	return 0.0

## Returns rated/max current from whichever label the bridge uses.
static func _rated_a(info: Dictionary) -> float:
	var v = DiagnosticTool.get_row_value(info, "Maks. struja",
				DiagnosticTool.get_row_value(info, "Nom. struja", -1.0))
	if v is float: return v
	if v is int:   return float(v)
	return -1.0
