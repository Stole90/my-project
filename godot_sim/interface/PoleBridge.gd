## PoleBridge.gd
## Typed bridge za Pole element.
##
## Pole.collapse() = "disable" (stub pao — svi kablovi oštećeni)
## Pole.restore()  = "repair"  (stub uspravljen — kablovi popravljeni)
##
## Signali:
##   pole_collapsed()   — stub je upravo pao
##   pole_restored()    — stub je uspravljen

class_name PoleBridge
extends ElementBridge

signal pole_collapsed()
signal pole_restored()

var _prev_fallen: bool = false
var vis_fallen:   bool = false
var vis_cable_count: int = 0
var vis_damaged_cable_count: int = 0

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
	var p: Pole = element as Pole
	if p == null: return

	vis_enabled              = not p.fallen
	vis_fallen               = p.fallen
	vis_damaged              = p.fallen
	vis_cable_count          = p.attached_cables.size()
	vis_damaged_cable_count  = 0
	for c in p.attached_cables:
		if (c as Cable).damaged:
			vis_damaged_cable_count += 1

func _emit_changed_signals() -> void:
	super._emit_changed_signals()
	if vis_fallen and not _prev_fallen:
		emit_signal("pole_collapsed")
	elif not vis_fallen and _prev_fallen:
		emit_signal("pole_restored")
	_prev_fallen = vis_fallen

# ── Interakcije ───────────────────────────────────────────────────────────────

## Toggle: ako stoji → obori; ako je pao → uspravi.
func interact_toggle() -> void:
	var p: Pole = element as Pole
	if p == null: return
	if p.fallen: p.restore()
	else:        p.collapse()
	if model != null: model.mark_dirty()

## Repair: uspravi stub i popravi kablove.
func interact_repair() -> void:
	var p: Pole = element as Pole
	if p == null or not p.fallen: return
	p.restore()
	if model != null: model.mark_dirty()

## Eksplicitno obori stub (za storm event, udes...).
func collapse() -> void:
	var p: Pole = element as Pole
	if p == null or p.fallen: return
	p.collapse()
	if model != null: model.mark_dirty()

## Eksplicitno uspravi stub.
func restore() -> void:
	var p: Pole = element as Pole
	if p == null or not p.fallen: return
	p.restore()
	if model != null: model.mark_dirty()

# ── Info ──────────────────────────────────────────────────────────────────────

func get_info() -> Dictionary:
	var p: Pole = element as Pole
	if p == null: return {"name": "stub", "type": "Stub", "rows": []}

	var bus_v: float = p.bus.voltage_magnitude() if p.bus != null else 0.0

	var cable_status: String
	if vis_damaged_cable_count == 0:
		cable_status = "svi ok"
	elif vis_damaged_cable_count == vis_cable_count:
		cable_status = "svi oštećeni"
	else:
		cable_status = "%d/%d oštećeni" % [vis_damaged_cable_count, vis_cable_count]

	return {
		"name":  p.element_name,
		"type":  "Stub",
		"rows": [
			row("Napon",      bus_v,           "%.1f V"),
			row("Kablovi",    vis_cable_count, "%d"),
			row("Stanje kab", cable_status),
			row("Stanje",     "PAO" if p.fallen else "ok"),
		]
	}
