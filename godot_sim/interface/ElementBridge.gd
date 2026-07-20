## ElementBridge.gd
## Osnovna klasa bridge sloja — veza između vizuelnog Node-a i
## CircuitElement-a (čista simulaciona logika).
##
## ── Arhitektura ───────────────────────────────────────────────────────────────
##
##   Vizuelni Node (Node2D / Node3D)
##       │  owns
##       ▼
##   ElementBridge  (extends Node, dodat kao child)
##       │  binds
##       ▼
##   CircuitElement (RefCounted, bez scene)
##       │  inside
##       ▼
##   CircuitModel + CircuitSolver
##
## ── Upotreba ─────────────────────────────────────────────────────────────────
##
##   # Kreiranje i bind (u plug_into() ili setup_in()):
##   _bridge = CableBridge.new()
##   add_child(_bridge)
##   _bridge.bind(my_cable, model)
##
##   # Vizuelni node sluša signale:
##   _bridge.state_changed.connect(_on_bridge_state)
##   _bridge.overloaded.connect(func(v): _set_color_overload(v))
##
## ── Nasledjivanje ─────────────────────────────────────────────────────────────
##
##   Podklase override-uju:
##     _sync_visual_state()  — čita polja iz element-a, upisuje u lokalne var
##     get_info() -> Dictionary  — za InfoPanel
##
##   Podklase MOGU override-ovati:
##     interact_toggle() / interact_repair()  — ako element ima drugačiji API
##
## ── Vizuelni state ────────────────────────────────────────────────────────────
##
##   ElementBridge drži mirror vizuelnih stanja koja vizuelni node
##   čita za _draw() — nema direktnog pristupa CircuitElement-u iz _draw().
##   Signali se emituju samo kada se stanje PROMENI (edge-triggered).

class_name ElementBridge
extends Node

# ── Signali ───────────────────────────────────────────────────────────────────

## Emituje se svaki put kada model reši mrežu.
signal solved()

## Napon se promenio na prvom terminalu (primarni, faza L1 ili assigned_phase).
signal voltage_changed(magnitude_v: float, phase_deg: float)

## Struja se promenila kroz element.
signal current_changed(magnitude_a: float)

## Stanje state-machine-a Consumer-a se promenilo (normal/tripped/damaged/off).
signal state_changed(new_state: String)

## Element je oštećen (damaged flag prešao u true).
signal damaged()

## Element je popravljen (damaged flag prešao u false).
signal repaired()

## Stanje overload se promenilo.
signal overloaded(is_overloaded: bool)

## Stanje overheat se promenilo.
signal overheated(is_overheated: bool)

## enabled flag se promenio.
signal enabled_changed(is_enabled: bool)

# ── Veza sa simulacijom ───────────────────────────────────────────────────────

## CircuitElement koji ovaj bridge prati.
var element: CircuitElement = null

## CircuitModel u kome element živi.
var model: CircuitModel = null

# ── Vizuelni mirror state ─────────────────────────────────────────────────────
## Ova polja čitaju vizuelni nodovi za _draw() i UI.
## Uvek konzistentna — update-uju se samo u _sync_visual_state().

var vis_enabled:    bool  = true
var vis_damaged:    bool  = false
var vis_overloaded: bool  = false
var vis_overheated: bool  = false
var vis_voltage_v:  float = 0.0
var vis_current_a:  float = 0.0
var vis_state:      String = ""

# ── Prethodni snapshot za edge detection ──────────────────────────────────────
var _prev_enabled:    bool   = true
var _prev_damaged:    bool   = false
var _prev_overloaded: bool   = false
var _prev_overheated: bool   = false
var _prev_state:      String = ""

# ── Bind ──────────────────────────────────────────────────────────────────────

## Poveži bridge sa elementom i modelom.
## Poziva se jednom, odmah nakon add_child(bridge).
func bind(p_element: CircuitElement, p_model: CircuitModel) -> void:
	element = p_element
	model   = p_model
	if model != null:
		model.solved.connect(_on_model_solved)

## Odveži bridge (npr. pri brisanju elementa).
func unbind() -> void:
	if model != null and model.solved.is_connected(_on_model_solved):
		model.solved.disconnect(_on_model_solved)
	element = null
	model   = null

# ── Interakcije igrača ────────────────────────────────────────────────────────

## Uključi / isključi element.
func interact_toggle() -> void:
	if element == null:
		return
	if element.enabled:
		element.disable()
	else:
		element.enable()
	if model != null:
		model.mark_dirty()

## Popravi element (poziva repair() ako postoji).
func interact_repair() -> void:
	if element == null:
		return
	if element.has_method("repair"):
		element.call("repair")
	if model != null:
		model.mark_dirty()

# ── Info za InfoPanel ─────────────────────────────────────────────────────────

## Override u podklasama za specifičan sadržaj.
func get_info() -> Dictionary:
	return {
		"name":    element.element_name if element != null else "?",
		"type":    "Element",
		"enabled": vis_enabled,
		"rows":    [],
	}

# ── Solve callback ────────────────────────────────────────────────────────────

func _on_model_solved(_ms: float) -> void:
	if element == null:
		return
	_sync_visual_state()
	_emit_changed_signals()
	emit_signal("solved")

# ── Virtuelna metoda za podklase ──────────────────────────────────────────────

## Podklase čitaju iz element-a i upisuju u vis_* polja.
## Poziva se SAMO iz _on_model_solved — ne direktno.
func _sync_visual_state() -> void:
	vis_enabled = element.enabled

	# Napon — primarni terminal, faza L1 (ili assigned_phase ako podklasa override-uje)
	var ph := _get_primary_phase()
	if element.terminals.size() > 0 and element.terminals[0].size() > 0:
		var n: SimNode = element.terminals[0][0]
		if n != null:
			var v: Complex = n.get_voltage(ph)
			if v != null:
				vis_voltage_v = v.magnitude()
			else:
				vis_voltage_v = 0.0

	# Struja
	if element.current != null:
		vis_current_a = element.current.magnitude()
	else:
		vis_current_a = 0.0

# ── Emit edge-triggered signali ───────────────────────────────────────────────

func _emit_changed_signals() -> void:
	if vis_enabled != _prev_enabled:
		emit_signal("enabled_changed", vis_enabled)
		_prev_enabled = vis_enabled

	if vis_damaged != _prev_damaged:
		if vis_damaged:
			emit_signal("damaged")
		else:
			emit_signal("repaired")
		_prev_damaged = vis_damaged

	if vis_overloaded != _prev_overloaded:
		emit_signal("overloaded", vis_overloaded)
		_prev_overloaded = vis_overloaded

	if vis_overheated != _prev_overheated:
		emit_signal("overheated", vis_overheated)
		_prev_overheated = vis_overheated

	if vis_state != _prev_state:
		emit_signal("state_changed", vis_state)
		_prev_state = vis_state

	# voltage / current se emituju uvek (kontinualni signal za UI refresh)
	emit_signal("voltage_changed", vis_voltage_v, 0.0)
	emit_signal("current_changed", vis_current_a)

# ── Helper ────────────────────────────────────────────────────────────────────

## Vraća assigned_phase ako element ima to polje, inače Phase.L1.
func _get_primary_phase() -> int:
	if element != null and element.get("assigned_phase") != null:
		return element.assigned_phase
	return Phase.L1

## Kreira row Dictionary za InfoPanel (centralni helper — nema više kopiranja).
static func row(label: String, value, fmt: String = "") -> Dictionary:
	return { "label": label, "value": value, "fmt": fmt }
