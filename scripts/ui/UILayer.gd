# res://scripts/ui/UILayer.gd
## UILayer — script za CanvasLayer čvor $UI u world.tscn.
##
## ── Odgovornost ──────────────────────────────────────────────────────────────
## • Poseduje sve UI panele kao decu CanvasLayer-a.
## • Registruje context akcije u InfoPanel umesto hardkodiranih tipova.
## • Prihvata "sim" signale iz world.gd i prosleđuje ih pravim panelima.
## • Emituje "sim akcije" nazad prema world.gd (repair, delete, faze, kvarovi…).
## • world.gd sada radi SAMO sa CircuitModel, nodovima i kablovima.
##   Sve što se tiče UI-a delegira UILayer-u.
##
## ── Kako world.gd koristi UILayer ────────────────────────────────────────────
##   @onready var ui: UILayer = $UI
##
##   # Selekcija:
##   ui.show_node(hit)          # ili ui.show_cable(cn)
##   ui.hide_selection()        # na deselect
##   ui.set_diag_target(hit)    # za DiagnosticHUD
##
##   # Slušaj sim akcije:
##   ui.repair_requested.connect(_on_repair)
##   ui.delete_node_requested.connect(_on_delete)
##   ui.delete_cable_requested.connect(_on_delete_cable)
##   ui.open_dist_box_requested.connect(_on_open_dist_box)
##   ui.edit_cable_requested.connect(_on_edit_cable)
##   ui.edit_node_requested.connect(_on_edit_node)
##   ui.phase_change_requested.connect(_on_phase_change_requested)
##   ui.cable_params_confirmed.connect(_on_cable_params_confirmed)
##   ui.cable_inspector_cancelled.connect(_on_cable_inspector_cancelled)
##   ui.inject_fault_requested.connect(_on_inject_fault)
##   ui.clear_faults_requested.connect(_on_clear_faults)
##
## ── Kako dodati novi context akciju za novi tip ───────────────────────────────
##   U _register_context_actions() dodaj jedan poziv:
##     _info_panel.register_context_action(
##         &"moj_mod", "Otvori mod...",
##         func(n: Node2D) -> bool: return n is MojTipNode)
##   Dodaj handler u _on_context_action().
## ─────────────────────────────────────────────────────────────────────────────

extends CanvasLayer

# ── Signali prema world.gd (sim akcije) ───────────────────────────────────────
signal repair_requested(node: Node2D)
signal delete_node_requested(node: Node2D)
signal delete_cable_requested(cn: Node2D)
signal open_dist_box_requested(dist_box: DistBoxNode)
signal edit_cable_requested(cn: Node2D)
signal edit_node_requested(node: Node2D)
signal phase_change_requested(node: Node2D, new_phase: int)
signal cable_params_confirmed(params: Dictionary)
signal cable_inspector_cancelled()
signal inject_fault_requested(target: Node2D, fault_type: int, phase: int, phase_b: int, cross_node: bool)
signal clear_faults_requested(target: Node2D)

# ── Paneli (deca ovog CanvasLayer-a u sceni) ──────────────────────────────────
@onready var _info_panel:    InfoPanel              = $InfoPanel
@onready var _dist_box_panel: DistBoxPanel          = $DistBoxPanel
@onready var _cable_inspector: CableInspectorDialog = $CableInspectorDialog
@onready var _app_inspector:   ApplianceInspectorDialog = $ApplianceInspectorDialog
@onready var _diag_hud:        DiagnosticHUD        = $DiagnosticHUD

# Mode dijalozi — po jedan po tipu uređaja
@onready var _oven_dialog:   OvenModeDialog         = $OvenModeDialog
@onready var _boiler_dialog: BoilerModeDialog       = $BoilerModeDialog
@onready var _fridge_dialog: RefrigeratorModeDialog = $RefrigeratorModeDialog

# ── Diagnostic refresh timer ──────────────────────────────────────────────────
const _DIAG_INTERVAL: float = 0.1
var _diag_timer: float = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_connect_info_panel()
	_connect_cable_inspector()
	_connect_app_inspector()
	_connect_mode_dialogs()
	_connect_diag_hud()
	_register_context_actions()

func _process(delta: float) -> void:
	if _diag_hud.visible:
		_diag_timer += delta
		if _diag_timer >= _DIAG_INTERVAL:
			_diag_timer = 0.0
			_diag_hud.refresh()

# ── Public API (poziva world.gd) ──────────────────────────────────────────────

## Prikaži info panel za kliknut node, osvezi fazni UI.
func show_node(node: Node2D) -> void:
	_info_panel.show_for_any(node)
	_refresh_phase_ui_external(node)

## Prikaži info panel za selektovan kabl.
func show_cable(cn: Node2D) -> void:
	_info_panel.show_for_cable(cn)

## Sakrij info panel (na deselect).
func hide_selection() -> void:
	_info_panel.hide_panel()

## Postavi target za DiagnosticHUD.
func set_diag_target(node: Node2D) -> void:
	_diag_hud.set_target(node)

## Ukloni target iz DiagnosticHUD-a.
func clear_diag_target() -> void:
	_diag_hud.clear_target()

## Otvori CableInspector u ADD modu (klik "Dodaj kabl").
func open_cable_add() -> void:
	_cable_inspector.open_add_mode()

## Prosledi ažurirani node InfoPanel-u posle edit potvrde.
func refresh_node_display(node: Node2D) -> void:
	_info_panel.show_for_any(node)

## Prosledi stanje faznog selektora (poziva world.gd/UILayer interne metode).
## world.gd treba da pozove ovu metodu i prosledi rezultat svog _resolve_phase_authority().
func set_phase_control_state(is_visible: bool, editable: bool, note: String = "") -> void:
	_info_panel.set_phase_control_state(is_visible, editable, note)

## Otvori DistBoxPanel.
func open_dist_box(dist_box: DistBoxNode) -> void:
	_dist_box_panel.open(dist_box)
	_info_panel.hide_panel()

## Proverava da li je dati screen_pos iznad bilo kog vidljivog UI child-a.
func is_point_over_ui(screen_pos: Vector2) -> bool:
	for child: Node in get_children():
		if child is Control and child.visible:
			if (child as Control).get_global_rect().has_point(screen_pos):
				return true
	return false

# ── Context akcije — dodavati ovde bez menjanja InfoPanel.gd ─────────────────

## Registruje sva context dugmad za poznate tipove uređaja.
## Da dodaš novu akciju: jedan poziv register_context_action + jedan handler u _on_context_action.
func _register_context_actions() -> void:
	_info_panel.register_context_action(
		&"oven_mode", "Mod pećnice...",
		func(n: Node2D) -> bool: return n is ThreePhaseOvenNode)

	_info_panel.register_context_action(
		&"boiler_mode", "Mod bojlera...",
		func(n: Node2D) -> bool: return n is Boiler)

	_info_panel.register_context_action(
		&"fridge_mode", "Mod frižidera...",
		func(n: Node2D) -> bool: return n is Refrigerator)

	# ── Primer kako dodati novi tip u budućnosti ──────────────────────────────
	# _info_panel.register_context_action(
	#     &"oscilloscope", "Osciloskop...",
	#     func(n: Node2D) -> bool: return n is OscilloscopeNode)

func _on_context_action(action_id: StringName, node: Node2D) -> void:
	match action_id:
		&"oven_mode":
			_oven_dialog.open_for(node as ThreePhaseOvenNode)
			_info_panel.hide_panel()
		&"boiler_mode":
			_boiler_dialog.open_for(node as Boiler)
			_info_panel.hide_panel()
		&"fridge_mode":
			_fridge_dialog.open_for(node as Refrigerator)
			_info_panel.hide_panel()
		# &"oscilloscope":
		#     _oscilloscope_panel.open_for(node)

# ── Signal wiring ─────────────────────────────────────────────────────────────

func _connect_info_panel() -> void:
	_info_panel.repair_pressed.connect(
		func(n): emit_signal("repair_requested", n))
	_info_panel.delete_pressed.connect(
		func(n): emit_signal("delete_node_requested", n))
	_info_panel.delete_cable_pressed.connect(
		func(cn): emit_signal("delete_cable_requested", cn))
	_info_panel.open_dist_box_pressed.connect(
		func(db): emit_signal("open_dist_box_requested", db))

	# UILayer direktno otvara dijaloge — world.gd handleri su pass i ne treba ih
	_info_panel.edit_cable_pressed.connect(func(cn: Node2D):
		_cable_inspector.open_edit_mode(cn)
		emit_signal("edit_cable_requested", cn))   # world.gd može da sluša ako mu treba

	_info_panel.edit_node_pressed.connect(func(n: Node2D):
		_app_inspector.open_for(n)
		emit_signal("edit_node_requested", n))     # world.gd može da sluša ako mu treba

	_info_panel.phase_change_requested.connect(
		func(n, ph): emit_signal("phase_change_requested", n, ph))
	_info_panel.context_action_requested.connect(_on_context_action)

func _connect_cable_inspector() -> void:
	_cable_inspector.params_confirmed.connect(
		func(p): emit_signal("cable_params_confirmed", p))
	_cable_inspector.cancelled.connect(
		func(): emit_signal("cable_inspector_cancelled"))
	# Posle edit potvrde CableInspectorDialog je već primenio params na kabl.
	# UILayer osvežava InfoPanel da prikaže nove vrednosti.
	_cable_inspector.edit_confirmed.connect(func(_p: Dictionary):
		var cn: Node2D = _cable_inspector._target_cable
		if cn != null and _info_panel.visible:
			_info_panel.show_for_cable(cn))

func _connect_app_inspector() -> void:
	_app_inspector.edit_confirmed.connect(
		func(node: Node2D): refresh_node_display(node))

func _connect_mode_dialogs() -> void:
	# OvenModeDialog: mode_confirmed nosi cook_mode ključ
	_oven_dialog.mode_confirmed.connect(
		func(_key: String):
			# target je već primenjen u OvenModeDialog.open_for → ModeDialog je
			# generički; primenu radimo ovde da ostanemo bez sim logike u dijalogu.
			# Alternativno: world.gd može da sluša direktno na _oven_dialog ako hoće.
			pass)

	_boiler_dialog.mode_confirmed.connect(func(_key: String): pass)
	_fridge_dialog.mode_confirmed.connect(func(_key: String): pass)

	# ── Napomena ──────────────────────────────────────────────────────────────
	# ModeDialog.mode_confirmed nosi samo key (String).
	# Primena na sim model (boiler.apply_params, oven.apply_params) se može
	# raditi direktno u open_for() (trenutna implementacija u podklasama)
	# ili se može prebaciti ovde da UILayer potpuno kontroliše tok.
	# Obe opcije su ispravne; biraj konzistentno u projektu.

func _connect_diag_hud() -> void:
	_diag_hud.inject_fault_requested.connect(
		func(t, ft, p, pb, cross): emit_signal("inject_fault_requested", t, ft, p, pb, cross))
	_diag_hud.clear_faults_requested.connect(
		func(t): emit_signal("clear_faults_requested", t))

# ── Fazni UI — UILayer pita world.gd ─────────────────────────────────────────
## UILayer ne može sam da uradi _resolve_phase_authority() jer ne poznaje
## strukturu grafa (to je sim logika). Umesto toga, emituje signal prema world.gd
## koji sračuna stanje i pozove nazad set_phase_control_state().
##
## world.gd treba da uradi:
##   ui.phase_ui_refresh_requested.connect(_on_phase_ui_refresh)
##   func _on_phase_ui_refresh(node): _refresh_phase_ui(node); ui.set_phase_control_state(...)

signal phase_ui_refresh_requested(node: Node2D)

func _refresh_phase_ui_external(node: Node2D) -> void:
	emit_signal("phase_ui_refresh_requested", node)
