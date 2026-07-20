## ThreePhaseFuseBridge.gd
## Typed bridge za ThreePhaseFuse element.
## Koristi se u: ThreePhaseFuseNode.gd

class_name ThreePhaseFuseBridge
extends ElementBridge

signal blown(phase: int)
signal fuse_reset()

var vis_blown_phases: Dictionary = { Phase.L1: false, Phase.L2: false, Phase.L3: false }
var vis_currents_a:   Dictionary = { Phase.L1: 0.0, Phase.L2: 0.0, Phase.L3: 0.0 }
var _prev_blown:      Dictionary = { Phase.L1: false, Phase.L2: false, Phase.L3: false }

func _sync_visual_state() -> void:
	super._sync_visual_state()
	var f: ThreePhaseFuse = element as ThreePhaseFuse
	if f == null: return
	vis_enabled = not f.is_blown()
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		vis_blown_phases[ph] = f.blown_phases.get(ph, false)
		var ic: Complex = f.currents_by_phase.get(ph, null)
		vis_currents_a[ph] = 0.0 if ic == null else ic.magnitude()

func _emit_changed_signals() -> void:
	super._emit_changed_signals()
	var f: ThreePhaseFuse = element as ThreePhaseFuse
	if f == null: return
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		if vis_blown_phases[ph] and not _prev_blown[ph]:
			emit_signal("blown", ph)
		_prev_blown[ph] = vis_blown_phases[ph]

func get_info() -> Dictionary:
	var f: ThreePhaseFuse = element as ThreePhaseFuse
	if f == null: return { "name": "3-fazni osigurač", "type": "3-fazni osigurač", "rows": [] }

	var rows: Array = []
	for ph in [Phase.L1, Phase.L2, Phase.L3]:
		var lbl: String = ["L1", "L2", "L3"][ph]
		rows.append(row("Struja %s" % lbl, vis_currents_a[ph],           "%.2f A"))
		rows.append(row("Stanje %s" % lbl, "PREGOREO" if vis_blown_phases[ph] else "ok"))
	rows.append(row("Nom. struja", f.rated_current_a, "%.0f A"))

	return {
		"name":    f.element_name,
		"type":    "3-fazni osigurač",
		"enabled": not f.is_blown(),
		"rows":    rows,
	}

func interact_repair() -> void:
	var f: ThreePhaseFuse = element as ThreePhaseFuse
	if f == null: return
	f.repair()
	if model != null: model.mark_dirty()
	emit_signal("fuse_reset")
