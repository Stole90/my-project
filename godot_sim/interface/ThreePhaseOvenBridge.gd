## ThreePhaseOvenBridge.gd
## Typed bridge za ThreePhaseOven element.
## Koristi se u: ThreePhaseOvenNode.gd
##
## ThreePhaseOven nasljeđuje ThreePhaseConsumer (delta veza).
## Nema damaged/repair u sim klasi — bridge tretira prekoračenje
## max_oven_temp_c kao "damaged" stanje (termalno oštećenje).
##
## vis_state prati mode string, ne Consumer.STATE_* konstante.
##
## Dodatni signali:
##   mode_changed(new_mode)   — cooking mode se promenio
##   target_reached()         — pećnica dostigla ciljnu temperaturu
##   overheated_oven()        — temperatura prešla max_oven_temp_c (kvar)

class_name ThreePhaseOvenBridge
extends ElementBridge

signal mode_changed(new_mode: String)
signal target_reached()
signal overheated_oven()

# ── Vizuelni state ────────────────────────────────────────────────────────────

var vis_cook_mode:    String = ThreePhaseOven.MODE_OFF
var vis_oven_temp_c:  float  = 20.0
var vis_target_temp_c: float = 20.0
var vis_temp_pct:     float  = 0.0
var vis_heating:      bool   = false
var vis_power_w:      float  = 0.0
var vis_currents_a:   Array  = [0.0, 0.0, 0.0]   # [L1, L2, L3]

var _prev_mode:           String = ThreePhaseOven.MODE_OFF
var _prev_target_reached: bool   = false

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
	var o: ThreePhaseOven = element as ThreePhaseOven
	if o == null: return

	vis_enabled      = o.cook_mode != ThreePhaseOven.MODE_OFF
	vis_cook_mode    = o.cook_mode
	vis_oven_temp_c  = o.oven_temp_c
	vis_target_temp_c = o.target_temp_c
	vis_temp_pct     = o.temp_percent()
	vis_heating      = o.is_heating()
	vis_power_w      = o.total_active_power_w()
	vis_state        = o.cook_mode

	# Thermal overload → damaged
	vis_damaged = o.oven_temp_c > o.max_oven_temp_c

	for ph_idx in range(3):
		var ph: int     = [Phase.L1, Phase.L2, Phase.L3][ph_idx]
		var ic: Complex = o.currents_by_phase.get(ph, null)
		vis_currents_a[ph_idx] = 0.0 if ic == null else ic.magnitude()

# ── Edge-triggered signali ────────────────────────────────────────────────────

func _emit_changed_signals() -> void:
	super._emit_changed_signals()

	if vis_cook_mode != _prev_mode:
		emit_signal("mode_changed", vis_cook_mode)
		_prev_mode = vis_cook_mode

	# Target reached: pećnica je dostigla temp i thermostat se zadovoljio
	var o: ThreePhaseOven = element as ThreePhaseOven
	if o != null:
		var at_target: bool = o.thermostat_satisfied and vis_cook_mode != ThreePhaseOven.MODE_OFF
		if at_target and not _prev_target_reached:
			emit_signal("target_reached")
		_prev_target_reached = at_target

		if vis_damaged and not _prev_damaged:
			emit_signal("overheated_oven")

# ── Interakcije ───────────────────────────────────────────────────────────────

## Toggle: OFF ↔ poslednji aktivni mode (ili BAKE ako nije bilo).
func interact_toggle() -> void:
	var o: ThreePhaseOven = element as ThreePhaseOven
	if o == null: return
	if o.cook_mode == ThreePhaseOven.MODE_OFF:
		var last: String = _prev_mode if _prev_mode != ThreePhaseOven.MODE_OFF else ThreePhaseOven.MODE_BAKE
		o.set_mode(last)
	else:
		o.set_mode(ThreePhaseOven.MODE_OFF)
	if model != null: model.mark_dirty()

## Postavi konkretan mode direktno.
func set_mode(mode: String) -> void:
	var o: ThreePhaseOven = element as ThreePhaseOven
	if o == null: return
	o.set_mode(mode)
	if model != null: model.mark_dirty()

## Repair: hlađenje pećnice na ambient (termalni reset). Ne vraća mode.
func interact_repair() -> void:
	var o: ThreePhaseOven = element as ThreePhaseOven
	if o == null: return
	o.set_mode(ThreePhaseOven.MODE_OFF)
	o.oven_temp_c       = o.ambient_temp_c
	o.thermostat_satisfied = false
	if model != null: model.mark_dirty()

# ── Info za InfoPanel ─────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	var o: ThreePhaseOven = element as ThreePhaseOven
	if o == null:
		return {"name": "pećnica", "type": "3-fazna pećnica", "rows": []}

	var bus: SimNode = o.bus_node()
	var rows: Array  = [
		row("Mod",           _mode_label(vis_cook_mode)),
		row("Temp. pećnice", vis_oven_temp_c,          "%.1f °C"),
		row("Ciljana temp.", vis_target_temp_c,         "%.1f °C"),
		row("Napredak",      vis_temp_pct,              "%.0f %%"),
		row("Termostat",     "zadovoljen" if o.thermostat_satisfied else "greje"),
		row("Grejanje",      "DA" if vis_heating else "NE"),
		row("Uk. snaga",     vis_power_w,               "%.0f W"),
		row("─── Struje ───", ""),
		row("Struja L1",     vis_currents_a[0],         "%.2f A"),
		row("Struja L2",     vis_currents_a[1],         "%.2f A"),
		row("Struja L3",     vis_currents_a[2],         "%.2f A"),
		row("─── Naponi ───", ""),
	]
	if bus != null:
		for ph_idx in range(3):
			var ph: int = [Phase.L1, Phase.L2, Phase.L3][ph_idx]
			rows.append(row("Napon %s" % ["L1","L2","L3"][ph_idx],
				bus.voltage_magnitude(ph), "%.1f V"))

	if vis_damaged:
		rows.append(row("⚠ Stanje", "TERMALNI KVAR"))
	else:
		rows.append(row("Stanje", "ok" if vis_cook_mode == ThreePhaseOven.MODE_OFF else "aktivan"))

	return {
		"name":      o.element_name,
		"type":      "3-fazna pećnica",
		"enabled":   vis_enabled,
		"cook_mode": vis_cook_mode,
		"rows":      rows,
	}

# ── Helper ────────────────────────────────────────────────────────────────────

static func _mode_label(mode: String) -> String:
	match mode:
		"off":     return "Isključena"
		"preheat": return "Zagrevanje"
		"bake":    return "Pečenje"
		"grill":   return "Grill"
		"broil":   return "Broil"
	return mode
