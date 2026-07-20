## CircuitModel.gd
## Pure simulation-layer container for one electrical network.
##
## Responsibilities:
##   - Hold the topology: nodes + every CircuitElement.
##   - Maintain the dirty flag (topology / state changed → re-solve).
##   - Delegate the actual numerical work to a CircuitSolver.
##   - Emit Godot signals on solve completion and game-relevant events
##     (overload, fuse-blow, consumer trip / damage).
##
## DOES NOT depend on any Node3D, scene tree, or rendering.  Can be
## instantiated and run head-less in tests.
##
## Usage:
##   var model := CircuitModel.new("town_grid")
##   model.add_element(source)
##   model.add_element(cable)
##   model.add_element(consumer)
##   model.solve_if_dirty()

class_name CircuitModel
extends RefCounted

# ── Signals (Game / Bridge layer hooks) ─────────────────────────────
signal solved(solve_time_ms: float)
signal solve_failed(errors: Array)
signal cable_overloaded(cable)
signal cable_overheated(cable)
signal cable_thermal_damage(cable)
signal socket_overloaded(socket)
signal socket_overheated(socket)
signal socket_thermal_damage(socket)
signal transformer_overloaded(xfmr)
signal transformer_overheated(xfmr)
signal transformer_thermal_damage(xfmr)
signal consumer_tripped(consumer)
signal consumer_damaged(consumer)
signal three_phase_consumer_tripped(consumer, phase: int)
signal three_phase_consumer_damaged(consumer, phase: int)
signal fuse_blew(fuse)

# ── State ───────────────────────────────────────────────────────────
var network_name: String

var nodes: Array        = []     # Array[SimNode]
var elements: Array     = []     # Array[CircuitElement]
var sources: Array      = []     # subset (VoltageSource + ThreePhaseVoltageSource), kept for solver convenience

# ── Typed element caches ─────────────────────────────────────────────
# Maintained by add_element / remove_element.
# Use these for fast type-specific iteration instead of iterating
# `elements` with repeated `is` checks on every element.
var _cables:             Array = []   # Cable
var _three_phase_cables: Array = []   # ThreePhaseCable
var _consumers:          Array = []   # Consumer (RatedConsumer, ConstantPowerConsumer, …)
var _three_ph_consumers: Array = []   # ThreePhaseConsumer
var _fuses:              Array = []   # Fuse
var _sockets:            Array = []   # Socket
var _three_ph_sockets:   Array = []   # ThreePhaseSocket
var _transformers:       Array = []   # Transformer
var _three_ph_xfmrs:     Array = []   # ThreePhaseTransformer

var dirty: bool         = true
var last_solved_ok: bool = false

# Only ThreePhaseYBusSolver is instantiated — single-phase solver removed.
var solver: CircuitSolver = ThreePhaseYBusSolver.new()

# Time-step (used only by transient solver)
var dt: float = 0.0

# Optional grounding system (GroundingSystem).
# When set, ThreePhaseYBusSolver stamps it automatically during each solve.
var grounding_system: GroundingSystem = null

# Active FaultElement instances — tracked separately for add/remove API.
var _fault_elements: Array = []  # Array[FaultElement]

# Snapshot of fault states from the previous solve (edge-triggered signals).
var _prev_overloaded: Dictionary       = {}
var _prev_overheated: Dictionary       = {}
var _prev_consumer_state: Dictionary   = {}
var _prev_fuse_blown: Dictionary       = {}
## Per-element, per-phase state snapshot for ThreePhaseConsumer.
## Key: element.id + ":" + str(phase), Value: state String
var _prev_3ph_consumer_state: Dictionary = {}

# Default ambient temperature broadcast to all cables when the
# game layer calls step_thermal() without specifying one.
var ambient_c: float = SimConstants.DEFAULT_AMBIENT_C

func _init(p_name: String = "network") -> void:
	network_name = p_name

# ── Topology API ────────────────────────────────────────────────────

func add_element(elem: CircuitElement) -> void:
	if elements.has(elem):
		return
	elements.append(elem)
	for n in elem.iter_nodes():
		_register_node(n)
	if elem.is_slack_source():
		if not sources.has(elem):
			sources.append(elem)
	_add_to_typed_cache(elem)
	_refresh_node_registry()
	mark_dirty()

func remove_element(elem: CircuitElement) -> void:
	if not elements.has(elem):
		return
	elements.erase(elem)
	sources.erase(elem)
	_remove_from_typed_cache(elem)
	_refresh_node_registry()
	mark_dirty()

func _add_to_typed_cache(elem: CircuitElement) -> void:
	if   elem is Cable:                 _cables.append(elem)
	elif elem is ThreePhaseCable:       _three_phase_cables.append(elem)
	elif elem is Consumer:              _consumers.append(elem)
	elif elem is ThreePhaseConsumer:    _three_ph_consumers.append(elem)
	elif elem is Fuse:                  _fuses.append(elem)
	elif elem is Socket:                _sockets.append(elem)
	elif elem is ThreePhaseSocket:      _three_ph_sockets.append(elem)
	elif elem is Transformer:           _transformers.append(elem)
	elif elem is ThreePhaseTransformer: _three_ph_xfmrs.append(elem)

func _remove_from_typed_cache(elem: CircuitElement) -> void:
	_cables.erase(elem)
	_three_phase_cables.erase(elem)
	_consumers.erase(elem)
	_three_ph_consumers.erase(elem)
	_fuses.erase(elem)
	_sockets.erase(elem)
	_three_ph_sockets.erase(elem)
	_transformers.erase(elem)
	_three_ph_xfmrs.erase(elem)

# ── Fault API ───────────────────────────────────────────────────────

## Add a FaultElement to the network and register it as a normal element.
func add_fault(fault: FaultElement) -> void:
	if _fault_elements.has(fault):
		return
	_fault_elements.append(fault)
	add_element(fault)

## Remove a FaultElement from the network and deactivate it.
func remove_fault(fault: FaultElement) -> void:
	_fault_elements.erase(fault)
	fault.deactivate()
	remove_element(fault)

## Remove all active fault elements.
func clear_all_faults() -> void:
	for f in _fault_elements.duplicate():
		remove_fault(f)

## All currently registered fault elements.
func get_faults() -> Array:
	return _fault_elements.duplicate()

func _refresh_node_registry() -> void:
	var next_nodes: Array = []
	for elem in elements:
		if elem == null:
			continue
		for n in elem.iter_nodes():
			if n != null and not next_nodes.has(n):
				next_nodes.append(n)
	nodes = next_nodes

func _register_node(node: SimNode) -> void:
	if node != null and not nodes.has(node):
		nodes.append(node)

func mark_dirty() -> void:
	dirty = true

# ── Solve drivers ───────────────────────────────────────────────────

func solve_if_dirty() -> bool:
	if not dirty:
		for e in elements:
			if e.dirty:
				dirty = true
				break
	if not dirty:
		return false
	solve()
	return true

func solve() -> void:
	var validation_issues: Array = validate()
	if not validation_issues.is_empty():
		last_solved_ok = false
		dirty = true
		emit_signal("solve_failed", validation_issues)
		return

	var result: Dictionary = solver.solve(self)
	last_solved_ok = result.get("ok", false)
	if not last_solved_ok:
		emit_signal("solve_failed", result.get("errors", []))
		return
	var became_dirty_during_solve := dirty
	dirty = false
	for e in elements:
		e.clear_dirty()
	_emit_event_signals()
	emit_signal("solved", result.get("solve_ms", 0.0))
	if became_dirty_during_solve:
		dirty = true

## Run one transient time-step (Δt seconds).  Always solves.
func step_transient(delta_t: float) -> void:
	var prev_solver: CircuitSolver = solver
	if not (solver is TransientSolver):
		solver = TransientSolver.new()
	dt = delta_t
	solve()
	solver = prev_solver
	dt = 0.0

## Advance the lumped thermal model of every thermally-modelled element
## by dt seconds.  ThreePhaseConsumer has no thermal model and is skipped.
## Uses typed caches — O(thermal_elements) instead of O(all_elements × 6 checks).
func step_thermal(delta_t: float, p_ambient_c: float = NAN) -> void:
	if delta_t <= 0.0:
		return
	if not is_nan(p_ambient_c):
		ambient_c = p_ambient_c

	for e in _cables:
		var newly_damaged: bool = e.update_thermal(delta_t, ambient_c)
		var prev_oh: bool = _prev_overheated.get(e.id, false)
		if e.is_overheated and not prev_oh:
			emit_signal("cable_overheated", e)
		_prev_overheated[e.id] = e.is_overheated
		if newly_damaged:
			emit_signal("cable_thermal_damage", e)

	for e in _three_phase_cables:
		var newly_damaged: bool = e.update_thermal(delta_t, ambient_c)
		var prev_oh: bool = _prev_overheated.get(e.id, false)
		if e.is_overheated and not prev_oh:
			emit_signal("cable_overheated", e)
		_prev_overheated[e.id] = e.is_overheated
		if newly_damaged:
			emit_signal("cable_thermal_damage", e)

	for e in _sockets:
		var newly_damaged: bool = e.update_thermal(delta_t, ambient_c)
		var prev_oh: bool = _prev_overheated.get(e.id, false)
		if e.is_overheated and not prev_oh:
			emit_signal("socket_overheated", e)
		_prev_overheated[e.id] = e.is_overheated
		if newly_damaged:
			emit_signal("socket_thermal_damage", e)

	for e in _three_ph_sockets:
		var newly_damaged: bool = e.update_thermal(delta_t, ambient_c)
		var prev_oh: bool = _prev_overheated.get(e.id, false)
		if e.is_overheated and not prev_oh:
			emit_signal("socket_overheated", e)
		_prev_overheated[e.id] = e.is_overheated
		if newly_damaged:
			emit_signal("socket_thermal_damage", e)

	for e in _transformers:
		var newly_damaged: bool = e.update_thermal(delta_t, ambient_c)
		var prev_oh: bool = _prev_overheated.get(e.id, false)
		if e.is_overheating and not prev_oh:
			emit_signal("transformer_overheated", e)
		_prev_overheated[e.id] = e.is_overheating
		if newly_damaged:
			emit_signal("transformer_thermal_damage", e)

	for e in _three_ph_xfmrs:
		var newly_damaged: bool = e.update_thermal(delta_t, ambient_c)
		var prev_oh: bool = _prev_overheated.get(e.id, false)
		if e.is_overheating and not prev_oh:
			emit_signal("transformer_overheated", e)
		_prev_overheated[e.id] = e.is_overheating
		if newly_damaged:
			emit_signal("transformer_thermal_damage", e)

# ── Validation ──────────────────────────────────────────────────────

func validate() -> Array:
	var issues: Array = []
	_refresh_node_registry()

	if elements.is_empty():
		issues.append("Network has no elements.")

	if sources.is_empty():
		issues.append("No voltage source found. Add a VoltageSource or ThreePhaseVoltageSource.")

	for elem in elements:
		if elem == null:
			issues.append("Encountered a null element in the network.")
			continue

		if elem.terminals.is_empty():
			issues.append("%s has no terminals defined." % elem.element_name)
			continue

		var term_idx: int = 0
		for term in elem.terminals:
			if term == null:
				issues.append("%s has a null terminal at index %d." % [elem.element_name, term_idx])
				term_idx += 1
				continue
			if term.is_empty():
				issues.append("%s terminal %d is empty." % [elem.element_name, term_idx])
				term_idx += 1
				continue

			var node_idx: int = 0
			for n in term:
				if n == null:
					issues.append("%s terminal %d references a null node." % [elem.element_name, term_idx])
				elif not nodes.has(n):
					issues.append("%s references unregistered node '%s'." % [elem.element_name, n.node_name])
				node_idx += 1
			term_idx += 1

	# NAPOMENA: Floating / nepovezani busevi NISU fatalna greška — solver
	# (ThreePhaseYBusSolver / YBusSolver) ima G_FLOOR shunt na svakom
	# non-source redu baš zato da izolovana "ostrva" ne prave singularnu
	# matricu, već se prosto rešavaju na ~0V. Zato disconnected topologija
	# NE ulazi u `issues` (ne sme blokirati solve celog ostatka mreže).

	return issues

## Ne-blokirajuća dijagnostika: imena buseva koji trenutno nisu dostižni
## ni od jednog izvora (npr. potrošač bez osigurača, appliance bez kabla).
## Koristi za UI upozorenja — NE utiče na solve().
func get_disconnected_nodes() -> Array:
	_refresh_node_registry()
	return _find_disconnected_nodes()

func get_diagnostic_report() -> Dictionary:
	var issues: Array = validate()
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"node_count": nodes.size(),
		"element_count": elements.size(),
		"source_count": sources.size(),
		"fault_count": _fault_elements.size(),
		"dirty": dirty,
		"last_solved_ok": last_solved_ok,
	}

func get_state_snapshot() -> Dictionary:
	_refresh_node_registry()

	var node_snapshots: Dictionary = {}
	var phase_ids: Array = [Phase.L1, Phase.L2, Phase.L3, Phase.NEUTRAL, Phase.PE]
	for node in nodes:
		if node == null:
			continue

		var voltage_snapshot: Dictionary = {}
		for phase in phase_ids:
			var v: Complex = node.get_voltage(phase)
			voltage_snapshot[str(phase)] = {
				"magnitude": null if v == null else v.magnitude(),
				"angle_deg": null if v == null else v.phase_deg(),
			}

		node_snapshots[node.id] = {
			"name": node.node_name,
			"voltages": voltage_snapshot,
		}

	var element_snapshots: Dictionary = {}
	for elem in elements:
		if elem == null:
			continue

		var current_mag: float = 0.0 if elem.current == null else elem.current.magnitude()
		var current_angle: float = 0.0 if elem.current == null else elem.current.phase_deg()
		var summary: Dictionary = {
			"name": elem.element_name,
			"class": elem.get_class(),
			"enabled": elem.enabled,
			"dirty": elem.dirty,
			"current": current_mag,
			"current_angle_deg": current_angle,
		}

		if elem is Cable:
			summary["overloaded"] = elem.is_overloaded
			summary["overheated"] = elem.is_overheated
			summary["damaged"] = elem.damaged
		elif elem is Socket:
			summary["overloaded"] = elem.is_overloaded
			summary["overheated"] = elem.is_overheated
			summary["damaged"] = elem.damaged
			summary["plugged_in"] = elem.plugged_in
		elif elem is Transformer:
			summary["overloaded"] = elem.is_overloaded
			summary["overheating"] = elem.is_overheating
			summary["damaged"] = elem.damaged
		elif elem is Consumer:
			summary["state"] = elem.state
			summary["assigned_phase"] = elem.assigned_phase
		elif elem is ThreePhaseConsumer:
			var phase_states: Dictionary = {}
			var phase_currents: Dictionary = {}
			for ph in [Phase.L1, Phase.L2, Phase.L3]:
				phase_states[str(ph)] = elem.phase_state.get(ph, ThreePhaseConsumer.STATE_NORMAL)
				var ph_current: Complex = elem.currents_by_phase.get(ph, Complex.zero())
				phase_currents[str(ph)] = 0.0 if ph_current == null else ph_current.magnitude()
			summary["phase_state"] = phase_states
			summary["phase_currents"] = phase_currents
		elif elem is Fuse:
			summary["blown"] = elem.blown

		element_snapshots[elem.id] = summary

	return {
		"nodes": node_snapshots,
		"elements": element_snapshots,
		"fault_count": _fault_elements.size(),
	}

func _find_disconnected_nodes() -> Array:
	if nodes.is_empty() or elements.is_empty():
		return []

	var reachable_nodes: Array = []
	var pending_nodes: Array = []

	for src in sources:
		if src == null:
			continue
		for n in src.iter_nodes():
			if n != null and not pending_nodes.has(n):
				pending_nodes.append(n)

	if pending_nodes.is_empty():
		return []

	while not pending_nodes.is_empty():
		var current: SimNode = pending_nodes.pop_back()
		if current == null or reachable_nodes.has(current):
			continue
		reachable_nodes.append(current)

		for elem in elements:
			if elem == null:
				continue
			if not elem.iter_nodes().has(current):
				continue
			for n in elem.iter_nodes():
				if n != null and not reachable_nodes.has(n) and not pending_nodes.has(n):
					pending_nodes.append(n)

	var disconnected: Array = []
	for n in nodes:
		if n != null and not reachable_nodes.has(n):
			disconnected.append(n.node_name)
	return disconnected

# ── Edge-triggered signal emission ──────────────────────────────────

## Emit edge-triggered game-event signals after each solve.
## Uses typed caches — one pass per element type, no repeated `is` checks.
func _emit_event_signals() -> void:
	for e in _cables:
		var prev: bool = _prev_overloaded.get(e.id, false)
		if e.is_overloaded and not prev:
			emit_signal("cable_overloaded", e)
		_prev_overloaded[e.id] = e.is_overloaded

	for e in _sockets:
		var prev: bool = _prev_overloaded.get(e.id, false)
		if e.is_overloaded and not prev:
			emit_signal("socket_overloaded", e)
		_prev_overloaded[e.id] = e.is_overloaded

	for e in _transformers:
		var prev: bool = _prev_overloaded.get(e.id, false)
		if e.is_overloaded and not prev:
			emit_signal("transformer_overloaded", e)
		_prev_overloaded[e.id] = e.is_overloaded

	for e in _three_ph_xfmrs:
		var prev: bool = _prev_overloaded.get(e.id, false)
		if e.is_overloaded and not prev:
			emit_signal("transformer_overloaded", e)
		_prev_overloaded[e.id] = e.is_overloaded

	for e in _consumers:
		var prev_state: String = _prev_consumer_state.get(e.id, Consumer.STATE_NORMAL)
		if e.state == Consumer.STATE_TRIPPED_UV and prev_state != Consumer.STATE_TRIPPED_UV:
			emit_signal("consumer_tripped", e)
		elif e.state == Consumer.STATE_DAMAGED_OV and prev_state != Consumer.STATE_DAMAGED_OV:
			emit_signal("consumer_damaged", e)
		_prev_consumer_state[e.id] = e.state

	for e in _three_ph_consumers:
		for ph in [Phase.L1, Phase.L2, Phase.L3]:
			var key: String     = e.id + ":" + str(ph)
			var cur_st: String  = e.phase_state.get(ph, ThreePhaseConsumer.STATE_NORMAL)
			var prev_st: String = _prev_3ph_consumer_state.get(key, ThreePhaseConsumer.STATE_NORMAL)
			if cur_st == ThreePhaseConsumer.STATE_TRIPPED_UV and prev_st != ThreePhaseConsumer.STATE_TRIPPED_UV:
				emit_signal("three_phase_consumer_tripped", e, ph)
			elif cur_st == ThreePhaseConsumer.STATE_DAMAGED_OV and prev_st != ThreePhaseConsumer.STATE_DAMAGED_OV:
				emit_signal("three_phase_consumer_damaged", e, ph)
			_prev_3ph_consumer_state[key] = cur_st

	for e in _fuses:
		var prev_b: bool = _prev_fuse_blown.get(e.id, false)
		if e.blown and not prev_b:
			emit_signal("fuse_blew", e)
		_prev_fuse_blown[e.id] = e.blown

# ── Game query helpers ──────────────────────────────────────────────

func get_node_voltage(n: SimNode) -> float:
	return -1.0 if n.voltage == null else n.voltage.magnitude()

func get_element_current(e: CircuitElement) -> float:
	return -1.0 if e.current == null else e.current.magnitude()

# ── Monofazni query helpers ─────────────────────────────────────────

## These helpers now return typed-cache references directly — no iteration needed.
func get_consumers() -> Array:                    return _consumers.duplicate()
func get_cables() -> Array:                       return _cables.duplicate()
func get_sockets() -> Array:                      return _sockets.duplicate()
func get_transformers() -> Array:                 return _transformers.duplicate()
func get_three_phase_consumers() -> Array:        return _three_ph_consumers.duplicate()
func get_three_phase_cables() -> Array:           return _three_phase_cables.duplicate()
func get_three_phase_transformers() -> Array:     return _three_ph_xfmrs.duplicate()

func get_overloaded_cables() -> Array:
	var out: Array = []
	for e in _cables:
		if e.is_overloaded: out.append(e)
	return out

func get_overloaded_sockets() -> Array:
	var out: Array = []
	for e in _sockets:
		if e.is_overloaded: out.append(e)
	return out

func get_overheated_sockets() -> Array:
	var out: Array = []
	for e in _sockets:
		if e.is_overheated: out.append(e)
	return out

func get_overloaded_transformers() -> Array:
	var out: Array = []
	for e in _transformers:
		if e.is_overloaded: out.append(e)
	return out

func get_overheated_transformers() -> Array:
	var out: Array = []
	for e in _transformers:
		if e.is_overheating: out.append(e)
	return out

## Trofazni potrošači kod kojih je bar jedna faza u TRIPPED ili DAMAGED stanju.
func get_faulted_three_phase_consumers() -> Array:
	var out: Array = []
	for e in _three_ph_consumers:
		if e.any_phase_faulted(): out.append(e)
	return out

func get_overloaded_three_phase_cables() -> Array:
	var out: Array = []
	for e in _three_phase_cables:
		if e.is_overloaded: out.append(e)
	return out

func get_overloaded_three_phase_transformers() -> Array:
	var out: Array = []
	for e in _three_ph_xfmrs:
		if e.is_overloaded: out.append(e)
	return out

func get_overheated_three_phase_transformers() -> Array:
	var out: Array = []
	for e in _three_ph_xfmrs:
		if e.is_overheating: out.append(e)
	return out

# ── Totals ──────────────────────────────────────────────────────────

## Returns power-flow totals broken down by category.
## Uses typed caches for O(N) iteration without per-element type checks.
## Keys: load_P_w, load_Q_var, cable_loss_w, socket_loss_w, xfmr_loss_w,
##       source_P_w, source_Q_var
func get_totals() -> Dictionary:
	if not last_solved_ok:
		return {}
	var load_p:      float = 0.0
	var load_q:      float = 0.0
	var cable_loss:  float = 0.0
	var socket_loss: float = 0.0
	var xfmr_loss:   float = 0.0
	var src_p:       float = 0.0
	var src_q:       float = 0.0

	for e in _consumers:
		load_p += e.active_power()
		load_q += e.reactive_power()

	for e in _three_ph_consumers:
		if not e.enabled:
			continue
		load_p += e.total_active_power_w()
		if e.connection == ThreePhaseConsumer.CONNECTION_WYE:
			for ph in [Phase.L1, Phase.L2, Phase.L3]:
				load_q += e.apparent_power_phase(ph).im
		else:
			for pair_idx in range(3):
				load_q += e.apparent_power_phase(pair_idx).im

	for e in _cables:
		if not e.enabled or e.current == null:
			continue
		var s: Complex = e.apparent_power()
		if s != null:
			cable_loss += s.re

	for e in _three_phase_cables:
		if not e.enabled:
			continue
		cable_loss += e.losses_kw * 1e3 if e.get("losses_kw") != null else 0.0

	for e in _sockets:
		if not e.enabled or not e.plugged_in or e.current == null:
			continue
		var s: Complex = e.apparent_power()
		if s != null:
			socket_loss += s.re

	for e in _transformers:
		if not e.enabled or e.damaged:
			continue
		xfmr_loss += e.losses_kw * 1e3

	for e in _three_ph_xfmrs:
		if not e.enabled or e.damaged:
			continue
		xfmr_loss += e.losses_kw * 1e3

	for e in sources:
		if e is ThreePhaseVoltageSource:
			src_p += e.active_power_total()
			src_q += e.reactive_power_total()
		elif e is VoltageSource:
			src_p += e.active_power()
			src_q += e.reactive_power()

	return {
		"load_P_w":      load_p,
		"load_Q_var":    load_q,
		"cable_loss_w":  cable_loss,
		"socket_loss_w": socket_loss,
		"xfmr_loss_w":   xfmr_loss,
		"source_P_w":    src_p,
		"source_Q_var":  src_q,
	}

func debug_dump_topology() -> void:
	print("── DEBUG TOPOLOGY ──")
	print("elements: ", elements.size(), "  nodes: ", nodes.size(), "  sources: ", sources.size())
	for src in sources:
		for n in src.iter_nodes():
			print("  SOURCE bus: ", n.node_name, " id=", n.id)
	for e in elements:
		var ids: Array = []
		for n in e.iter_nodes():
			ids.append("%s(id=%s)" % [n.node_name, n.id])
		print("  ELEM ", e.get_class(), " '", e.element_name, "': ", ids)
