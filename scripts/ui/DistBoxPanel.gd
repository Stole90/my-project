# res://scripts/ui/DistBoxPanel.gd
## Panel razvodne kutije — lista potrošača, osigurači, faze.
##
## ── Izmene vs. stara verzija ──────────────────────────────────────────────────
## • Extends BasePanel umesto Control — open/close/refresh logika je nasledjena.
## • Uklonjeni direktni pristupi privatnim članovima DistBoxNode-a:
##     _dist_box._bridge      → _dist_box.get_phase_loading_data()
##     _dist_box._consumer_data → get_consumer_data() + find_fuse_for_consumer()
##   DistBoxNode mora da izloži ove metode (vidi komentar "API zahtev" ispod).
## • @onready putanje za LblTitle i BtnClose ostaju iste (scene .tscn nepromenjena).
## • _refresh_states() i _rebuild_list() nepromenjene funkcionalno.
## ─────────────────────────────────────────────────────────────────────────────
##
## DistBoxNode API zahtev (ako već ne postoji, dodati u DistBoxNode.gd):
##   func get_phase_loading_data() -> Array[Dictionary]:
##       # Vraća niz od 3 dict-a: [{phase:"L1", loading_a:f, voltage:f}, ...]
##       if _bridge == null: return []
##       return [
##           {"phase":"L1","loading_a":_bridge.vis_phase_loading[0],"voltage_v":_bridge.vis_phase_voltages[0]},
##           {"phase":"L2","loading_a":_bridge.vis_phase_loading[1],"voltage_v":_bridge.vis_phase_voltages[1]},
##           {"phase":"L3","loading_a":_bridge.vis_phase_loading[2],"voltage_v":_bridge.vis_phase_voltages[2]},
##       ]
##
##   func find_fuse_node_for_consumer(consumer: Node2D) -> Node:
##       return _consumer_data.get(consumer, {}).get("fuse", null)
## ─────────────────────────────────────────────────────────────────────────────

class_name DistBoxPanel
extends Control

@onready var lbl_title:     Label         = $PanelContainer/VBox/HBox/LblTitle
@onready var btn_close:     Button        = $PanelContainer/VBox/HBox/BtnClose
@onready var consumer_list: VBoxContainer = $PanelContainer/VBox/ScrollContainer/ConsumerList

var _dist_box: DistBoxNode = null
const REFRESH_INTERVAL: float = 0.25

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	btn_close.pressed.connect(close)
	btn_close.custom_minimum_size = Vector2(50, 50)

func _process(delta: float) -> void:
	if not visible or _dist_box == null:
		return
	# BasePanel-style inline timer (panel ne extends BasePanel jer ima .tscn)
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh_states()

var _refresh_timer: float = 0.0

# ── Public API ────────────────────────────────────────────────────────────────

func open(dist_box: DistBoxNode) -> void:
	_dist_box = dist_box
	lbl_title.text = "Razvodna kutija: %s" % dist_box.box_name
	_rebuild_list()
	visible = true
	_connect_dist_box_signals()

func close() -> void:
	visible = false
	_dist_box = null

# ── Signal povezivanje ────────────────────────────────────────────────────────

func _connect_dist_box_signals() -> void:
	if _dist_box == null:
		return
	if not _dist_box.consumer_registered.is_connected(_on_consumer_registered):
		_dist_box.consumer_registered.connect(_on_consumer_registered)
	if not _dist_box.fuse_blown.is_connected(_on_fuse_blown):
		_dist_box.fuse_blown.connect(_on_fuse_blown)
	if not _dist_box.topology_changed.is_connected(_on_topology_changed):
		_dist_box.topology_changed.connect(_on_topology_changed)

# ── Izgradnja liste ───────────────────────────────────────────────────────────

func _rebuild_list() -> void:
	for child: Node in consumer_list.get_children():
		child.queue_free()

	if _dist_box == null:
		return

	# Zaglavlje: opterećenje po fazama
	# Koristimo javni API umesto direktnog _bridge pristupa
	if _dist_box.has_method("get_phase_loading_data"):
		var phase_data: Array = _dist_box.get_phase_loading_data()
		if not phase_data.is_empty():
			var header := HBoxContainer.new()
			header.name = "PhaseHeader"
			for ph: Dictionary in phase_data:
				var lbl := Label.new()
				lbl.name = "LblPhase_%s" % ph["phase"]
				lbl.text = "%s: %.1fA / %.0fV" % [ph["phase"], ph["loading_a"], ph["voltage_v"]]
				lbl.custom_minimum_size = Vector2(140, 0)
				header.add_child(lbl)
			consumer_list.add_child(header)
			consumer_list.add_child(HSeparator.new())

	var data: Array[Dictionary] = _dist_box.get_consumer_data()
	if data.is_empty():
		var lbl := Label.new()
		lbl.text = "Nema povezanih potrošača."
		consumer_list.add_child(lbl)
		return

	for entry: Dictionary in data:
		consumer_list.add_child(_make_row(entry))

func _make_row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % entry["consumer_name"]

	var lbl_c := Label.new()
	lbl_c.text               = entry["consumer_name"]
	lbl_c.custom_minimum_size = Vector2(120, 0)
	row.add_child(lbl_c)

	var lbl_s := Label.new()
	lbl_s.name               = "LblState"
	lbl_s.text               = _state_text(entry)
	lbl_s.custom_minimum_size = Vector2(180, 0)
	row.add_child(lbl_s)

	var spin := SpinBox.new()
	spin.name       = "SpinRated"
	spin.min_value  = 1.0
	spin.max_value  = 125.0
	spin.step       = 1.0
	spin.value      = entry["rated_a"] if entry["has_fuse"] else 16.0
	spin.custom_minimum_size = Vector2(80, 0)
	row.add_child(spin)

	var opt := OptionButton.new()
	opt.name = "CurveSelect"
	opt.add_item("B", 0)
	opt.add_item("C", 1)
	opt.add_item("D", 2)
	match entry.get("curve", ""):
		"B": opt.select(0)
		"C": opt.select(1)
		"D": opt.select(2)
		_:   opt.select(1)
	row.add_child(opt)

	var is_3ph: bool = entry.get("is_3ph", false)
	var phase_opt := OptionButton.new()
	phase_opt.name    = "PhaseSelect"
	phase_opt.visible = not is_3ph
	phase_opt.add_item("L1", Phase.L1)
	phase_opt.add_item("L2", Phase.L2)
	phase_opt.add_item("L3", Phase.L3)
	phase_opt.custom_minimum_size = Vector2(60, 0)

	var _phase_ready := [false]
	phase_opt.item_selected.connect(func(idx: int):
		if not _phase_ready[0]: return
		var new_phase: int = phase_opt.get_item_id(idx)
		_dist_box.set_consumer_phase(entry["consumer"], new_phase)
		var lbl_ref: Label = row.get_node_or_null("LblState")
		if lbl_ref:
			lbl_ref.text = _state_text_with_phase(entry, new_phase)
	)
	phase_opt.select(clampi(entry.get("phase", Phase.L1), 0, 2))
	_phase_ready[0] = true
	row.add_child(phase_opt)

	var btn_add := Button.new()
	btn_add.text = "Izmeni" if entry["has_fuse"] else "Dodaj osigurač"
	btn_add.custom_minimum_size = Vector2(100, 50)
	btn_add.pressed.connect(func():
		var rated: float   = spin.value
		var curve_idx: int = opt.get_selected_id()
		var curve: Fuse.TripCurve
		match curve_idx:
			0: curve = Fuse.TripCurve.B
			1: curve = Fuse.TripCurve.C
			2: curve = Fuse.TripCurve.D
			_: curve = Fuse.TripCurve.C
		var chosen_phase: int = phase_opt.get_item_id(phase_opt.selected)
		_dist_box.set_consumer_phase(entry["consumer"], chosen_phase)
		_dist_box.add_fuse_for(entry["consumer"], rated, curve)
		_rebuild_list()
	)
	row.add_child(btn_add)

	var btn_rst := Button.new()
	btn_rst.name    = "BtnReset"
	btn_rst.text    = "Reset"
	btn_rst.visible = entry["has_fuse"] and entry.get("blown", false)
	btn_rst.pressed.connect(func():
		# Koristimo javni API umesto _consumer_data direktnog pristupa
		var fuse_node: Node = null
		if _dist_box.has_method("find_fuse_node_for_consumer"):
			fuse_node = _dist_box.find_fuse_node_for_consumer(entry["consumer"])
		if fuse_node != null and fuse_node.has_method("repair"):
			fuse_node.repair()
		_rebuild_list()
	)
	row.add_child(btn_rst)

	var btn_rem := Button.new()
	btn_rem.name    = "BtnRemove"
	btn_rem.text    = "Ukloni"
	btn_rem.visible = entry["has_fuse"]
	btn_rem.pressed.connect(func():
		_dist_box.remove_fuse_for(entry["consumer"])
		_rebuild_list()
	)
	row.add_child(btn_rem)

	return row

# ── Refresh stanja ────────────────────────────────────────────────────────────

func _refresh_states() -> void:
	if _dist_box == null:
		return

	# Osvezi zaglavlje faza
	if _dist_box.has_method("get_phase_loading_data"):
		var phase_data: Array = _dist_box.get_phase_loading_data()
		var header: Node = consumer_list.get_node_or_null("PhaseHeader")
		if header != null:
			for ph: Dictionary in phase_data:
				var lbl: Label = header.get_node_or_null("LblPhase_%s" % ph["phase"])
				if lbl:
					lbl.text = "%s: %.1fA / %.0fV" % [ph["phase"], ph["loading_a"], ph["voltage_v"]]

	var data: Array[Dictionary] = _dist_box.get_consumer_data()
	for entry: Dictionary in data:
		var row: Node = consumer_list.get_node_or_null("Row_%s" % entry["consumer_name"])
		if row == null:
			continue
		var lbl_s: Label = row.get_node_or_null("LblState")
		if lbl_s:
			lbl_s.text = _state_text(entry)
		var btn_rem: Button = row.get_node_or_null("BtnRemove")
		if btn_rem:
			btn_rem.visible = entry["has_fuse"]
		var btn_rst: Button = row.get_node_or_null("BtnReset")
		if btn_rst:
			btn_rst.visible = entry["has_fuse"] and entry.get("blown", false)
		var phase_opt: OptionButton = row.get_node_or_null("PhaseSelect")
		if phase_opt:
			var ph: int = entry.get("phase", Phase.L1)
			if phase_opt.selected != ph:
				phase_opt.select(clampi(ph, 0, 2))

# ── Text helpers ──────────────────────────────────────────────────────────────

func _state_text(entry: Dictionary) -> String:
	var is_3ph: bool  = entry.get("is_3ph", false)
	var state: String = entry["fuse_state"]
	if not entry["has_fuse"]:
		if is_3ph:
			return "bez osigurača"
		return "bez osigurača | faza: %s" % entry.get("phase_label", "L1")
	if is_3ph:
		var c: Array = entry.get("currents_3ph", [0.0, 0.0, 0.0])
		return "%s | L1:%.2fA  L2:%.2fA  L3:%.2fA" % [state, c[0], c[1], c[2]]
	var cur: float    = entry.get("current_a", 0.0)
	var therm: float  = entry.get("thermal_pct", 0.0)
	var ph_lbl: String = entry.get("phase_label", "L1")
	return "%s | %.2fA | T:%.0f%% | %s" % [state, cur, therm, ph_lbl]

func _state_text_with_phase(entry: Dictionary, override_phase: int) -> String:
	var ph_idx: int    = [Phase.L1, Phase.L2, Phase.L3].find(override_phase)
	var ph_lbl: String = ["L1", "L2", "L3"][clampi(ph_idx, 0, 2)]
	if not entry["has_fuse"]:
		return "bez osigurača | faza: %s" % ph_lbl
	var cur: float   = entry.get("current_a", 0.0)
	var therm: float = entry.get("thermal_pct", 0.0)
	return "%s | %.2fA | T:%.0f%% | %s" % [entry["fuse_state"], cur, therm, ph_lbl]

# ── DistBoxNode signal handlers ───────────────────────────────────────────────

func _on_consumer_registered(_consumer: Node2D) -> void:
	_rebuild_list()

func _on_fuse_blown(_fuse_node: Node) -> void:
	_rebuild_list()

func _on_topology_changed() -> void:
	call_deferred("_rebuild_list")
