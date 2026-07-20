## FuseBridge.gd
## Typed bridge za Fuse element.
## Koristi se u: FuseNode.gd
##
## Pored standardnih signala, dodaje:
##   blown()   — osigurač je upravo pregoreo
##   reset()   — osigurač je resetovan

class_name FuseBridge
extends ElementBridge

signal blown()
signal fuse_reset()

var vis_blown:        bool  = false
var vis_thermal_pct:  float = 0.0
var vis_current_mag:  float = 0.0

var _prev_blown: bool = false

func _sync_visual_state() -> void:
	super._sync_visual_state()
	var f: Fuse = element as Fuse
	if f == null: return

	vis_enabled     = f.enabled
	vis_blown       = f.blown
	vis_thermal_pct = f.thermal_energy * 100.0
	vis_current_mag = f.current_magnitude
	vis_current_a   = f.current_magnitude

func _emit_changed_signals() -> void:
	super._emit_changed_signals()
	var f: Fuse = element as Fuse
	if f == null: return
	if vis_blown and not _prev_blown:
		emit_signal("blown")
	elif not vis_blown and _prev_blown:
		emit_signal("fuse_reset")
	_prev_blown = vis_blown

func get_info() -> Dictionary:
	var f: Fuse = element as Fuse
	if f == null: return { "name": "osigurač", "type": "Osigurač", "rows": [] }

	var state_str: String
	if f.blown:          state_str = "pregoreo"
	elif not f.enabled:  state_str = "isključen"
	else:                state_str = "ok"

	var v_out: float = 0.0
	if f.terminals.size() > 1 and f.terminals[1].size() > 0:
		var n: SimNode = f.terminals[1][0]
		if n != null: v_out = n.voltage_magnitude()

	return {
		"name": f.element_name,
		"type": "Osigurač %s" % f.curve_name(),
		"rows": [
			row("Nom. struja",   f.rated_current_a,    "%.0f A"),
			row("Kriva",         f.curve_name()),
			row("Struja",        vis_current_mag,       "%.2f A"),
			row("Napon izl.",    v_out,                 "%.2f V"),
			row("Term. energ.",  vis_thermal_pct,       "%.0f %%"),
			row("Resetabilan",   "da" if f.resettable else "ne"),
			row("Stanje",        state_str),
		]
	}

func interact_repair() -> void:
	var f: Fuse = element as Fuse
	if f == null: return
	if f.resettable: f.reset()
	else: f.replace()
	if model != null: model.mark_dirty()
	emit_signal("fuse_reset")
