## ConsumerBridge.gd
## Typed bridge za Consumer i RatedConsumer elemente.
## Koristi se u: Refrigerator.gd i svim BaseAppliance podklasama
## koje imaju RatedConsumer kao sim element.
##
## vis_state prati Consumer.STATE_* konstante.

class_name ConsumerBridge
extends ElementBridge

var vis_power_w:  float  = 0.0
var vis_pf:       float  = 1.0

func _sync_visual_state() -> void:
	super._sync_visual_state()
	var c: Consumer = element as Consumer
	if c == null: return

	vis_damaged    = c.is_damaged()
	vis_enabled    = c.enabled
	vis_current_a  = c.current.magnitude() if c.current != null else 0.0
	vis_state      = c.state
	vis_power_w    = c.active_power()

	var ph: int = c.assigned_phase
	var n: SimNode = c.node()
	if n != null:
		var v: Complex = n.get_voltage(ph)
		vis_voltage_v = 0.0 if v == null else v.magnitude()

func get_info() -> Dictionary:
	var c: Consumer = element as Consumer
	if c == null: return { "name": "potrošač", "type": "Potrošač", "rows": [] }

	var rc: RatedConsumer = element as RatedConsumer

	var rows: Array = []
	if rc != null:
		rows.append(row("Nom. snaga",   rc.power_w,         "%.0f W"))
		rows.append(row("Faktor snage", rc.rated_pf,        "%.2f"))
		rows.append(row("Nom. napon",   rc.nominal_voltage, "%.0f V"))
	rows.append(row("Napon",    vis_voltage_v,  "%.2f V"))
	rows.append(row("Struja",   vis_current_a,  "%.2f A"))
	rows.append(row("Snaga",    vis_power_w,    "%.1f W"))
	rows.append(row("Stanje",   vis_state))

	return {
		"name":    c.element_name,
		"type":    "Potrošač",
		"enabled": c.enabled,
		"rows":    rows,
	}

func interact_repair() -> void:
	var c: Consumer = element as Consumer
	if c == null: return
	c.repair()
	if model != null: model.mark_dirty()

func interact_toggle() -> void:
	var c: Consumer = element as Consumer
	if c == null: return
	if c.enabled: c.disable()
	else: c.enable()
	if model != null: model.mark_dirty()
