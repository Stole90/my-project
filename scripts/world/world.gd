# res://scripts/world.gd  — posle refaktorisanja UI sloja
#
# ── Šta je uklonjeno ──────────────────────────────────────────────────────────
# • @onready ref-ovi za sve UI panele (info_panel, cable_inspector, app_inspector,
#   dist_box_panel, diagnostic_hud, oven/boiler/refrigerator_mode_dialog).
#   Svi su prešli u UILayer.gd ($UI script).
# • Direktni signal connects za sve UI signale — UILayer ih sada wira interno.
# • _on_open_oven_mode / _on_open_boiler_mode / _on_open_refrigerator_mode handlers.
# • diagnostic_hud.refresh() poziv iz _process.
# • _click_on_ui() — prešlo u UILayer.is_point_over_ui().
# • _diag_timer i _DIAG_INTERVAL — prešlo u UILayer._process.
#
# ── Šta je dodato ─────────────────────────────────────────────────────────────
# • Jedan @onready var ui: UILayer = $UI
# • ui.show_node() / ui.show_cable() / ui.hide_selection() / ui.set_diag_target()
# • Slušanje UI signala iz UILayer-a umesto direktnih panel signala.
# ─────────────────────────────────────────────────────────────────────────────

extends Node2D

# ── Jedini UI ref koji world.gd treba ─────────────────────────────────────────
@onready var ui: CanvasLayer = $UI

# ── Sim-side refs (nepromenjeno) ──────────────────────────────────────────────
@onready var cable_manager:      CableManager     = $CableManager
@onready var selection_manager:  SelectionManager = $SelectionManager
@onready var fault_manager_node: FaultManagerNode = $FaultManagerNode
@onready var btn_add_cable:      Button           = $UI/btnAddCable

var model: CircuitModel
var _appliances:  Array[BaseAppliance] = []
var _grid_nodes:  Array[Node2D]        = []
var _cable_nodes: Array[CableNode]     = []
var _selected_cable:     Node2D        = null
var _selected_appliance: BaseAppliance = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	model = CircuitModel.new("world")
	model.solver = ThreePhaseYBusSolver.new()
	CircuitWorld.add_model(model)

	fault_manager_node.set_model(model)

	_register_grid_nodes()
	_register_existing_appliances()

	# ── Sim dugmad ────────────────────────────────────────────────────────────
	btn_add_cable.pressed.connect(_on_btn_add_cable)

	# ── UI signali iz UILayer-a ───────────────────────────────────────────────
	ui.repair_requested.connect(_on_repair)
	ui.delete_node_requested.connect(_on_delete)
	ui.delete_cable_requested.connect(_on_delete_cable)
	ui.open_dist_box_requested.connect(_on_open_dist_box)
	ui.edit_cable_requested.connect(_on_edit_cable)
	ui.edit_node_requested.connect(_on_edit_node)
	ui.phase_change_requested.connect(_on_phase_change_requested)
	ui.cable_params_confirmed.connect(_on_cable_params_confirmed)
	ui.cable_inspector_cancelled.connect(_on_cable_inspector_cancelled)
	ui.inject_fault_requested.connect(_on_inject_fault)
	ui.clear_faults_requested.connect(_on_clear_faults)
	# Fazni UI zahteva world.gd logiku za graph traversal
	ui.phase_ui_refresh_requested.connect(_on_phase_ui_refresh)

	for app: BaseAppliance in _appliances:
		app.plug_into_isolated(model)

	_register_existing_cables()
	selection_manager.element_deselected.connect(_on_deselected)
	cable_manager.cable_created.connect(_on_cable_created)
	cable_manager.three_phase_cable_created.connect(_on_three_phase_cable_created)
# _process: bez UI timera — prešlo u UILayer._process ─────────────────────────
# (ako world.gd nema drugog razloga za _process, može se ukloniti potpuno)

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if cable_manager.active:
			cable_manager.exit_cable_mode()
			btn_add_cable.text = "Dodaj kabl"
			get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		return

	# UILayer proverava da li klik pada na UI
	if ui.is_point_over_ui(event.global_position):
		return

	var mouse: Vector2 = get_global_mouse_position()
	var hit: Node2D    = _get_node_at(mouse)

	if hit != null:
		get_viewport().set_input_as_handled()
		if cable_manager.active:
			cable_manager.handle_click(hit, model)
		else:
			_deselect_cable()
			_deselect_appliance()
			if hit is BaseAppliance:
				_select_appliance(hit)
			elif hit is CableNode or hit is ThreePhaseCableNode:
				_select_cable(hit)
			selection_manager.deselect()
			_show_info(hit)
			ui.set_diag_target(hit)
	else:
		if cable_manager.active:
			if cable_manager.is_drawing():
				cable_manager.add_waypoint(mouse)
				get_viewport().set_input_as_handled()
			else:
				cable_manager.exit_cable_mode()
				btn_add_cable.text = "Dodaj kabl"
		else:
			_deselect_cable()
			_deselect_appliance()
			selection_manager.deselect()
			ui.clear_diag_target()

# ── Registracija (nepromenjeno) ───────────────────────────────────────────────

func _register_grid_nodes() -> void:
	for child: Node in get_children():
		if child is SinglePhaseSourceNode:
			child.setup_in(model); _grid_nodes.append(child)
		elif child is ThreePhaseSourceNode:
			child.setup_in(model); _grid_nodes.append(child)
		elif child is PoleNode:
			child.setup_in(model); _grid_nodes.append(child)
		elif child is TransformerNode:
			child.setup_in(model); _grid_nodes.append(child)
		elif child is ThreePhaseTransformerNode:
			child.setup_in(model); _grid_nodes.append(child)
		elif child is DistBoxNode or child is FuseNode:
			_grid_nodes.append(child)
		elif child is ThreePhaseSwitchNode or child is ThreePhaseFuseNode:
			_grid_nodes.append(child)

func _register_existing_appliances() -> void:
	for child: Node in get_children():
		if child is BaseAppliance and not _is_managed_by_grid_node(child):
			_appliances.append(child)

func _is_managed_by_grid_node(node: Node) -> bool:
	var p: Node = node.get_parent()
	return p is DistBoxNode

func _register_existing_cables() -> void:
	for child: Node in get_children():
		if child is CableNode and child.sim_cable == null and (child.node_a != null or child.node_b != null):
			child.setup_from_editor(model)
			if child.sim_cable != null:
				_on_cable_created(child)
		elif child is ThreePhaseCableNode and child.sim_cable == null and (child.node_a != null or child.node_b != null):
			child.setup_from_editor(model)
			if child.sim_cable != null:
				_on_three_phase_cable_created(child)

# ── Selekcija ─────────────────────────────────────────────────────────────────

func _select_cable(cn: Node2D) -> void:
	_deselect_cable()
	selection_manager.deselect()
	_selected_cable = cn
	cn.set_meta("selected", true)
	cn.queue_redraw()
	ui.show_cable(cn)
	ui.set_diag_target(cn)

func _deselect_cable() -> void:
	if _selected_cable != null:
		_selected_cable.set_meta("selected", false)
		_selected_cable.queue_redraw()
		_selected_cable = null

func _select_appliance(app: BaseAppliance) -> void:
	_deselect_appliance()
	selection_manager.select(app)
	_selected_appliance = app
	app.set_meta("selected", true)
	app.queue_redraw()

func _deselect_appliance() -> void:
	if _selected_appliance != null:
		selection_manager.deselect()
		_selected_appliance.set_meta("selected", false)
		_selected_appliance.queue_redraw()
		_selected_appliance = null

# ── Show info — delegira UILayer-u ────────────────────────────────────────────

func _show_info(node: Node2D) -> void:
	ui.show_node(node)
	# Fazni UI refresh se rešava kroz signal phase_ui_refresh_requested → _on_phase_ui_refresh

# ── UILayer signal handleri ───────────────────────────────────────────────────

func _on_deselected() -> void:
	ui.hide_selection()

func _on_cable_created(cn: CableNode) -> void:
	_cable_nodes.append(cn)
	cn.cable_clicked.connect(_on_cable_clicked)
	btn_add_cable.text = "Dodaj kabl"


func _on_cable_clicked(cn: CableNode) -> void:
	_select_cable(cn)

func _on_three_phase_cable_created(cn: ThreePhaseCableNode) -> void:
	cn.cable_clicked.connect(_on_3ph_cable_clicked)
	btn_add_cable.text = "Dodaj kabl"

func _on_3ph_cable_clicked(cn: ThreePhaseCableNode) -> void:
	_select_cable(cn)

func _on_delete_cable(cn: Node2D) -> void:
	if cn is CableNode:
		_cable_nodes.erase(cn)
		if cn.sim_cable:
			model.remove_element(cn.sim_cable)
	elif cn is ThreePhaseCableNode:
		if cn.sim_cable:
			model.remove_element(cn.sim_cable)
	cn.queue_free()
	_selected_cable = null
	ui.hide_selection()

func _on_btn_add_cable() -> void:
	if cable_manager.active:
		cable_manager.exit_cable_mode()
		btn_add_cable.text = "Dodaj kabl"
	else:
		ui.open_cable_add()
		selection_manager.deselect()

func _on_cable_params_confirmed(params: Dictionary) -> void:
	cable_manager.enter_cable_mode_with_params(params)
	btn_add_cable.text = "Otkaži kabl"

func _on_cable_inspector_cancelled() -> void:
	if not cable_manager.active:
		btn_add_cable.text = "Dodaj kabl"

func _on_edit_cable(_cn: Node2D) -> void:
	# CableInspectorDialog.open_edit_mode() poziva UILayer direktno
	# (UILayer ima ref na cable_inspector)
	pass  # UILayer to već radi interno — može biti prazan

func _on_open_dist_box(dist_box: DistBoxNode) -> void:
	ui.open_dist_box(dist_box)

func _on_repair(node: Node2D) -> void:
	if node.has_method("repair"):
		node.repair()

func _on_delete(node: Node2D) -> void:
	if node is BaseAppliance:
		var app: BaseAppliance = node as BaseAppliance
		var owning_box: DistBoxNode = _find_distbox_for(app)
		if owning_box != null:
			owning_box.remove_consumer(app)
		_appliances.erase(app)
		if app._consumer:
			model.remove_element(app._consumer)
	node.queue_free()
	selection_manager.deselect()

func _on_edit_node(_node: Node2D) -> void:
	# UILayer otvara ApplianceInspectorDialog direktno
	pass  # UILayer to već radi interno

# ── Diagnostic / Fault (nepromenjeno funkcionalno) ────────────────────────────

func _on_inject_fault(target: Node2D, fault_type: int, phase: int, phase_b: int, cross_node: bool) -> void:
	var element: CircuitElement = _get_element_from_node(target)
	if element == null:
		push_warning("world.gd: ne mogu naći element za fault injection na '%s'" % target.name)
		return

	var mag: float = 1.0
	# If cross_node requested and target is a cable, inject between its endpoints.
	if cross_node:
		if target is CableNode:
			var cn: CableNode = target as CableNode
			if cn.sim_cable != null:
				# Use the cable element, pass phases along to create cross-node FaultElement
				fault_manager_node.inject_fault(cn.sim_cable, fault_type, mag, phase, phase_b)
				return
		elif target is ThreePhaseCableNode:
			var tcn: ThreePhaseCableNode = target as ThreePhaseCableNode
			if tcn.sim_cable != null:
				fault_manager_node.inject_fault(tcn.sim_cable, fault_type, mag, phase, phase_b)
				return

	# Default: inject on the selected element (same-bus faults or legacy behavior)
	fault_manager_node.inject_fault(element, fault_type, mag, phase, phase_b)

func _on_clear_faults(target: Node2D) -> void:
	var element: CircuitElement = _get_element_from_node(target)
	if element != null:
		fault_manager_node.clear_faults_for(element)

func _get_element_from_node(node: Node2D) -> CircuitElement:
	if node is CableNode:          return (node as CableNode).sim_cable
	if node is ThreePhaseCableNode: return (node as ThreePhaseCableNode).sim_cable
	if node is FuseNode:            return node._fuse
	if node is ThreePhaseFuseNode:  return node._fuse
	if node is TransformerNode:     return node._transformer
	if node is ThreePhaseSwitchNode: return node._switch
	if node is SinglePhaseSourceNode:     return node._source
	if node is BaseAppliance:       return (node as BaseAppliance)._consumer
	return null

# ── Fazna logika (graph traversal ostaje u world.gd — sim logika) ─────────────

## Poziva se kad UILayer emituje phase_ui_refresh_requested.
## world.gd sračuna stanje i vrati ga UILayer-u.
func _on_phase_ui_refresh(node: Node2D) -> void:
	_refresh_phase_ui(node)

func _refresh_phase_ui(node: Node2D) -> void:
	if node is BaseAppliance and not (node as BaseAppliance).is_three_phase_appliance():
		var app: BaseAppliance    = node as BaseAppliance
		var owning_box: DistBoxNode = _find_distbox_for(app)
		if owning_box != null:
			var note_str: String = "Prati fazu osigurača u: %s" % owning_box.box_name
			ui.set_phase_control_state(true, false, note_str)
			return
		var a: Dictionary = _resolve_phase_authority(app)
		var note: String  = ""
		if not a["editable"]:
			note = "Prati fazu osigurača: %s" % (a["locked_to"].name if a["locked_to"] else "?")
		ui.set_phase_control_state(true, a["editable"], note)
	elif node is FuseNode:
		var found: Dictionary = _find_distbox_owning_fuse(node)
		ui.set_phase_control_state(not found.is_empty(), true, "")
	else:
		ui.set_phase_control_state(false, false)

func _on_phase_change_requested(node: Node2D, new_phase: int) -> void:
	var app: BaseAppliance = null
	var box: DistBoxNode   = null
	var via_fuse: bool     = false

	if node is BaseAppliance:
		app = node as BaseAppliance
		box = _find_distbox_for(app)
		if box != null:
			return
	elif node is FuseNode:
		var found: Dictionary = _find_distbox_owning_fuse(node)
		if found.is_empty():
			return
		box      = found["box"]
		app      = found["consumer"]
		via_fuse = true
	else:
		return

	if box != null and via_fuse:
		box.set_consumer_phase(app, new_phase)
	else:
		var authority: Dictionary = _resolve_phase_authority(app)
		if not authority["editable"]:
			return
		var feed: Cable = _find_feed_cable(app.get_sim_bus())
		if feed:
			feed.assigned_phase = new_phase
			feed.mark_dirty()
		app.set_assigned_phase(new_phase)
		model.mark_dirty()

	_show_info(node)

# ── Graph traversal helpers (nepromenjeno) ────────────────────────────────────

func _get_node_at(world_pos: Vector2) -> Node2D:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position             = world_pos
	params.collide_with_areas   = true
	params.collide_with_bodies  = false
	var results: Array = space.intersect_point(params)
	for r: Dictionary in results:
		var parent: Node = r["collider"].get_parent()
		if parent is Node2D and parent.has_method("get_sim_bus"):
			return parent as Node2D
	return null

func _find_owner_of_bus(bus: SimNode) -> Node2D:
	if bus == null: return null
	for n: Node2D in _grid_nodes:
		if n.has_method("get_secondary_bus") and n.get_secondary_bus() == bus: return n
		if n.has_method("get_sim_bus")       and n.get_sim_bus()       == bus: return n
	return null

func _find_feed_cable(bus: SimNode) -> Cable:
	if bus == null: return null
	for cn: CableNode in _cable_nodes:
		if cn.sim_cable != null and (cn.sim_cable.node_a() == bus or cn.sim_cable.node_b() == bus):
			return cn.sim_cable
	return null

func _other_end(cable: Cable, bus: SimNode) -> SimNode:
	return cable.node_b() if cable.node_a() == bus else cable.node_a()

func _find_distbox_for(app: BaseAppliance) -> DistBoxNode:
	for n: Node2D in _grid_nodes:
		if n is DistBoxNode and (n as DistBoxNode).has_consumer(app):
			return n
	return null

func _find_distbox_owning_fuse(fuse_node: Node2D) -> Dictionary:
	for n: Node2D in _grid_nodes:
		if n is DistBoxNode:
			var c: Node2D = (n as DistBoxNode).find_consumer_for_fuse(fuse_node)
			if c != null:
				return {"box": n, "consumer": c}
	return {}

func _resolve_phase_authority(app: BaseAppliance) -> Dictionary:
	var bus: SimNode   = app.get_sim_bus()
	var feed: Cable    = _find_feed_cable(bus)
	if feed == null:
		return {"editable": false, "locked_to": null}
	var upstream: Node2D = _find_owner_of_bus(_other_end(feed, bus))
	if upstream != null and upstream.has_method("is_free_phase_source") and upstream.is_free_phase_source():
		return {"editable": true, "locked_to": null}
	return {"editable": false, "locked_to": upstream}
