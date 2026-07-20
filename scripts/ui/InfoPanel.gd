# res://scripts/ui/InfoPanel.gd
## Info panel — prikazuje podatke selektovanog node-a ili kabla.
##
## ── Šta se promenilo vs. stara verzija ───────────────────────────────────────
## • Uklonjeni hardkodirani `is Boiler`, `is ThreePhaseOvenNode`, `is Refrigerator`.
## • Dodat generički Context Action sistem:
##     register_context_action(id, label, condition)
##   Svaki tip u world.gd/UILayer registruje sopstvena dugmad;
##   InfoPanel ne zna ništa o sim tipovima.
## • @onready putanje ostaju iste (scene .tscn se ne menja).
## • _process timer/refresh logika nepromenjena.
## ─────────────────────────────────────────────────────────────────────────────

class_name InfoPanel
extends PanelContainer

# ── Scene node refs (postavljene u .tscn) ─────────────────────────────────────
@onready var lbl_name:       Label         = $VBox/lblName
@onready var lbl_type:       Label         = $VBox/lblType
@onready var rows_container: VBoxContainer = $VBox/RowsContainer
@onready var btn_repair:     Button        = $VBox/btnRepair
@onready var btn_delete:     Button        = $VBox/btnDelete
@onready var btn_open_panel: Button        = $VBox/btnOpenPanel
@onready var btn_toggle:     Button        = $VBox/btnToggle
@onready var btn_edit:       Button        = $VBox/btnEdit

# ── Signals — sim akcije (world.gd/UILayer ih sluša) ─────────────────────────
signal repair_pressed(node: Node2D)
signal delete_pressed(node: Node2D)
signal delete_cable_pressed(cn: Node2D)
signal open_dist_box_pressed(dist_box: DistBoxNode)
signal edit_cable_pressed(cn: Node2D)
signal edit_node_pressed(node: Node2D)
signal phase_change_requested(node: Node2D, new_phase: int)

## Emituje se kad korisnik klikne registrovano context dugme.
## action_id odgovara id-u koji je prosleđen u register_context_action().
signal context_action_requested(action_id: StringName, node: Node2D)

# ── Context Action sistem ─────────────────────────────────────────────────────
## Svaka stavka: { id: StringName, label: String, condition: Callable }
## condition(node: Node2D) -> bool  — da li se dugme prikazuje za dati node
var _context_actions: Array[Dictionary] = []
var _context_buttons: Array[Button]     = []

# ── Interna stanja ────────────────────────────────────────────────────────────
var _current_node:  Node2D = null
var _current_cable: Node2D = null

# Keširani label nodeovi za brzi refresh bez rekreacije
var _value_labels: Array[Label] = []

# Fazni selektor (dodat proceduralno u _ready)
var _phase_option:     OptionButton
var _phase_lock_label: Label

const _PHASE_VALUES: Array[int]    = [Phase.L1, Phase.L2, Phase.L3]
const _PHASE_LABELS: Array[String] = ["L1", "L2", "L3"]

const _REFRESH_INTERVAL: float = 0.1
var _refresh_timer: float = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	btn_repair.pressed.connect(_on_repair)
	btn_delete.pressed.connect(_on_delete)
	btn_open_panel.pressed.connect(_on_open_panel)
	btn_toggle.pressed.connect(_on_toggle)
	btn_edit.pressed.connect(_on_edit)

	# Fazni selektor
	var phase_row := HBoxContainer.new()
	var phase_lbl := Label.new()
	phase_lbl.text = "Faza:"
	phase_lbl.custom_minimum_size.x = 120
	phase_row.add_child(phase_lbl)

	_phase_option = OptionButton.new()
	for lbl: String in _PHASE_LABELS:
		_phase_option.add_item(lbl)
	phase_row.add_child(_phase_option)
	$VBox.add_child(phase_row)
	_phase_option.item_selected.connect(_on_phase_selected)
	_phase_option.visible = false

	_phase_lock_label = Label.new()
	_phase_lock_label.visible = false
	$VBox.add_child(_phase_lock_label)

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer < _REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_refresh_rows()

# ── Context Action API (UILayer/world.gd poziva ovo pri startu) ───────────────

## Registruj dugme koje se prikazuje u InfoPanel-u kad je node selektovan.
##
## id:        jedinstveni ključ, emituje se u context_action_requested
## label:     tekst dugmeta
## condition: Callable(node: Node2D) -> bool — kad treba prikazati dugme
##
## Primer (u UILayer._ready):
##   info_panel.register_context_action(
##       &"oven_mode", "Mod pećnice...",
##       func(n): return n is ThreePhaseOvenNode)
func register_context_action(id: StringName, label: String, condition: Callable) -> void:
	_context_actions.append({ "id": id, "label": label, "condition": condition })
	var btn := Button.new()
	btn.text = label
	btn.visible = false
	btn.pressed.connect(func(): _on_context_action(id))
	$VBox.add_child(btn)
	_context_buttons.append(btn)

# ── Glavni entry pointovi ─────────────────────────────────────────────────────

func show_for_any(node: Node2D) -> void:
	_current_cable = null
	_current_node  = node

	if not node.has_method("get_info"):
		hide_panel()
		return

	var info: Dictionary = node.get_info()
	_rebuild(info)

	btn_repair.visible     = node.has_method("repair") and not node.has_method("toggle_power")
	btn_delete.visible     = true
	btn_open_panel.visible = node is DistBoxNode
	if node is DistBoxNode:
		btn_open_panel.text = "Otvori razvodnik"
	btn_toggle.visible = node.has_method("toggle_power")
	if btn_toggle.visible:
		btn_toggle.text = "Isključi" if info.get("enabled", true) else "Uključi"
	btn_edit.visible = node.has_method("apply_params")

	# Prikaži samo dugmad čiji condition prolazi za ovaj node
	for i: int in _context_actions.size():
		var entry: Dictionary = _context_actions[i]
		_context_buttons[i].visible = entry["condition"].call(node)

	_phase_option.visible     = false
	_phase_lock_label.visible = false

	visible = true

func show_for_cable(cn: Node2D) -> void:
	_current_node  = null
	_current_cable = cn
	var info: Dictionary = cn.get_info()
	_rebuild(info)

	btn_repair.visible     = info.get("damaged", false)
	btn_delete.visible     = true
	btn_open_panel.visible = false
	btn_toggle.visible     = false
	btn_edit.visible       = true

	for btn: Button in _context_buttons:
		btn.visible = false

	_phase_option.visible     = false
	_phase_lock_label.visible = false
	visible = true

func hide_panel() -> void:
	_current_node  = null
	_current_cable = null
	visible = false

## Poziva UILayer/world.gd posle show_for_any() za fazni selektor.
func set_phase_control_state(is_visible: bool, editable: bool, note: String = "") -> void:
	_phase_option.visible = is_visible
	_phase_option.disabled = not editable
	_phase_lock_label.visible = is_visible and not editable and not note.is_empty()
	_phase_lock_label.text = note
	if is_visible and _current_node != null and _current_node.has_method("get_assigned_phase"):
		var idx: int = _PHASE_VALUES.find(_current_node.get_assigned_phase())
		_phase_option.select(max(idx, 0))

# ── Rebuild / Refresh ─────────────────────────────────────────────────────────

func _rebuild(info: Dictionary) -> void:
	lbl_name.text = info.get("name", "?")
	lbl_type.text = info.get("type", "?")

	for child: Node in rows_container.get_children():
		child.queue_free()
	_value_labels.clear()

	var rows: Array = info.get("rows", [])
	for row: Dictionary in rows:
		_value_labels.append(_add_row(row.get("label", ""), row.get("value", ""), row.get("fmt", "")))

func _refresh_rows() -> void:
	var node: Node2D = _current_node if _current_node != null else _current_cable
	if node == null or not node.has_method("get_info"):
		return

	var info: Dictionary = node.call("get_info")
	var rows: Array      = info.get("rows", [])

	if rows.size() != _value_labels.size():
		_rebuild(info)
		return

	for i: int in rows.size():
		_value_labels[i].text = _fmt(rows[i].get("value", ""), rows[i].get("fmt", ""))

	if btn_toggle.visible:
		btn_toggle.text = "Isključi" if info.get("enabled", true) else "Uključi"

	if _current_cable != null:
		btn_repair.visible = info.get("damaged", false)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _add_row(label: String, value: Variant, fmt: String) -> Label:
	var hbox := HBoxContainer.new()

	var lbl := Label.new()
	lbl.text = label + ":"
	lbl.custom_minimum_size.x = 120
	hbox.add_child(lbl)

	var val := Label.new()
	val.text = _fmt(value, fmt)
	hbox.add_child(val)

	rows_container.add_child(hbox)
	return val

static func _fmt(val: Variant, fmt_str: String) -> String:
	if fmt_str.is_empty():
		return str(val)
	if val is float or val is int:
		return fmt_str % float(val)
	return str(val)

# ── Dugmad ────────────────────────────────────────────────────────────────────

func _on_repair() -> void:
	if _current_cable != null and _current_cable.sim_cable != null:
		_current_cable.sim_cable.repair()
		show_for_cable(_current_cable)
		emit_signal("repair_pressed", _current_cable)
		return
	if _current_node == null:
		return
	if _current_node.has_method("repair"):
		_current_node.repair()
	emit_signal("repair_pressed", _current_node)

func _on_delete() -> void:
	if _current_node != null:
		emit_signal("delete_pressed", _current_node)
	elif _current_cable != null:
		emit_signal("delete_cable_pressed", _current_cable)

func _on_open_panel() -> void:
	if _current_node is DistBoxNode:
		emit_signal("open_dist_box_pressed", _current_node as DistBoxNode)

func _on_toggle() -> void:
	if _current_node == null or not _current_node.has_method("toggle_power"):
		return
	_current_node.toggle_power()
	var info: Dictionary = _current_node.get_info()
	btn_toggle.text = "Isključi" if info.get("enabled", true) else "Uključi"

func _on_edit() -> void:
	if _current_cable != null:
		emit_signal("edit_cable_pressed", _current_cable)
	elif _current_node != null:
		emit_signal("edit_node_pressed", _current_node)

func _on_context_action(id: StringName) -> void:
	var node: Node2D = _current_node
	if node == null:
		return
	emit_signal("context_action_requested", id, node)

func _on_phase_selected(idx: int) -> void:
	if _current_node == null:
		return
	emit_signal("phase_change_requested", _current_node, _PHASE_VALUES[idx])
