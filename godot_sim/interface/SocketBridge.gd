## SocketBridge.gd
## Typed bridge za Socket element.
## Koristi se u: SocketAppliance.gd

class_name SocketBridge
extends ElementBridge

var vis_temperature_c: float = 25.0

func _sync_visual_state() -> void:
	super._sync_visual_state()
	var s: Socket = element as Socket
	if s == null: return

	vis_damaged      = s.damaged
	vis_overloaded   = s.is_overloaded
	vis_overheated   = s.is_overheated
	vis_enabled      = s.enabled
	vis_temperature_c = s.temperature_c
	vis_current_a    = s.current.magnitude() if s.current != null else 0.0
	vis_voltage_v    = s.node_load().voltage_magnitude()

	if not s.damaged and not s.is_overheated and not s.is_overloaded:
		vis_state = "ok"
	elif s.damaged:      vis_state = "oštećena"
	elif s.is_overheated: vis_state = "pregrejana"
	elif s.is_overloaded: vis_state = "preopterećena"

func get_info() -> Dictionary:
	var s: Socket = element as Socket
	if s == null: return { "name": "priključnica", "type": "Priključnica", "rows": [] }

	var v_load: float = s.node_load().voltage_magnitude()

	return {
		"name":    s.element_name,
		"type":    "Priključnica",
		"enabled": true,
		"rows": [
			row("Napon",       v_load,                     "%.2f V"),
			row("Struja",      vis_current_a,              "%.2f A"),
			row("Snaga",       s.dissipated_power(),       "%.1f W"),
			row("Nom. struja", s.max_current_a,            "%.0f A"),
			row("Temperatura", vis_temperature_c,          "%.1f °C"),
			row("Materijal",   s.contact_material),
			row("Stanje",      vis_state),
		]
	}

func interact_repair() -> void:
	var s: Socket = element as Socket
	if s == null: return
	s.repair()
	if model != null: model.mark_dirty()
