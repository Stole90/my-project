## FaultManager.gd
## Simulation-layer fault injection and tracking.
##
## Three fault types:
##   OPEN_CIRCUIT    — element.disable(), current drops to zero.
##   HIGH_RESISTANCE — Cable.ageing_factor *= magnitude (corroded/damaged).
##   SHORT_CIRCUIT   — near-zero-R Cable injected across the element's terminals.
##
## Both intentional and random faults share the same FaultRecord type.
## The game-layer FaultManagerNode drives tick_random() every physics frame.
##
## Usage (simulation layer):
##   var fm := FaultManager.new()
##   var rec := fm.apply_fault(my_cable, FaultManager.FaultType.OPEN_CIRCUIT, 1.0, model)
##   fm.clear_fault(rec, model)
##
## Usage (random):
##   fm.enable_random_faults(cable, 0.005, FaultManager.FaultType.HIGH_RESISTANCE, 50.0)
##   # then call fm.tick_random(delta, model) every frame

class_name FaultManager
extends RefCounted

# ── Fault types ───────────────────────────────────────────────────────

enum FaultType {
		OPEN_CIRCUIT,      ## Disable the element — no current flows.
		HIGH_RESISTANCE,   ## Multiply Cable.ageing_factor by magnitude.
		SHORT_CIRCUIT,     ## Inject near-zero-R branch across the element's terminals.
}

# ── FaultRecord ───────────────────────────────────────────────────────

## Represents one active (or cleared) fault instance.
class FaultRecord extends RefCounted:
		var element:    CircuitElement
		var fault_type: int            ## FaultType value
		var magnitude:  float          ## HIGH_RESISTANCE multiplier; 1.0 for others
		var is_random:  bool
		var active:     bool = true

		## Optional phase index (Phase.L1 / L2 / L3) for per-phase faults.
		var phase: int = -1
		var phase_b: int = -1

		## Pre-fault state snapshot for clean restore.
		var _saved_enabled: bool
		var _saved_ageing:  float      ## Cable.ageing_factor backup

		## Injected element for SHORT_CIRCUIT (Cable or FaultElement).
		var _short_cable: CircuitElement = null

		func _init(
				p_element:   CircuitElement,
				p_type:      int,
				p_magnitude: float,
				p_random:    bool,
				p_phase:     int = -1,
				p_phase_b:   int = -1
		) -> void:
				element    = p_element
				fault_type = p_type
				magnitude  = p_magnitude
				is_random  = p_random
				phase      = p_phase
				phase_b    = p_phase_b
				_saved_enabled = p_element.enabled
				if p_element is Cable:
						_saved_ageing = (p_element as Cable).ageing_factor
				else:
						_saved_ageing = 1.0

# ── Signals ───────────────────────────────────────────────────────────

signal fault_applied(record: FaultRecord)
signal fault_cleared(record: FaultRecord)
signal random_fault_triggered(record: FaultRecord)

# ── State ─────────────────────────────────────────────────────────────

## Active fault records keyed by element.id → Array[FaultRecord].
var _faults: Dictionary = {}

## Random-fault configuration per element.id.
var _rnd_prob:      Dictionary = {}   # element_id -> float (events/sec)
var _rnd_type:      Dictionary = {}   # element_id -> FaultType
var _rnd_magnitude: Dictionary = {}   # element_id -> float
var _rnd_accum:     Dictionary = {}   # element_id -> float (accumulator)

# ── Apply / Clear ─────────────────────────────────────────────────────

## Apply a fault to `element`. Returns the FaultRecord.
## Keep the record to call clear_fault() later.
func apply_fault(
		element:   CircuitElement,
		type:      int,
		magnitude: float,
		model:     CircuitModel,
		is_random: bool = false,
		phase:     int  = -1,
		phase_b:   int  = -1
) -> FaultRecord:
		var rec := FaultRecord.new(element, type, magnitude, is_random, phase, phase_b)

		match type:
				FaultType.OPEN_CIRCUIT:
						element.disable()

				FaultType.HIGH_RESISTANCE:
						if not (element is Cable):
								push_warning("FaultManager: HIGH_RESISTANCE only valid for Cable elements — fault not applied.")
								return null
						var c := element as Cable
						c.ageing_factor = maxf(magnitude, 1.0)
						c.mark_dirty()

				FaultType.SHORT_CIRCUIT:
						if element.terminals.size() >= 2:
								var na: SimNode = element.terminals[0][0]
								var nb: SimNode = element.terminals[1][0]
								if rec.phase >= 0 and rec.phase_b >= 0:
										# Inject a phase-to-phase short FaultElement between the two buses
										var fe_pp := FaultElement.new(na, FaultElement.PHASE_TO_PHASE, rec.phase, rec.phase_b, 0.001, "_phase_to_phase_%s" % element.id)
										fe_pp.fault_node_b = nb
										model.add_element(fe_pp)
										rec._short_cable = fe_pp
								elif rec.phase >= 0:
										# Inject a phase-series short using FaultElement when a single phase is specified
										var fe := FaultElement.new(na, FaultElement.PHASE_SERIES_SHORT, rec.phase, rec.phase_b, 0.001, "_phase_short_%s" % element.id)
										fe.fault_node_b = nb
										model.add_element(fe)
										rec._short_cable = fe
								else:
										# Fallback: inject a near-zero single-phase Cable between the two buses
										var sc := Cable.new(na, nb, 0.001, 100.0, "copper", INF,
												"_fault_short_%s" % element.id)
										model.add_element(sc)
										rec._short_cable = sc
						else:
								push_warning("FaultManager: SHORT_CIRCUIT requires element with ≥2 terminals.")

		if not _faults.has(element.id):
				_faults[element.id] = []
		_faults[element.id].append(rec)
		model.mark_dirty()

		emit_signal("fault_applied", rec)
		if is_random:
				emit_signal("random_fault_triggered", rec)

		return rec

## Clear a specific fault record and restore the element's pre-fault state.
func clear_fault(rec: FaultRecord, model: CircuitModel) -> void:
		if not rec.active:
				return
		rec.active = false

		match rec.fault_type:
				FaultType.OPEN_CIRCUIT:
						if rec._saved_enabled:
								rec.element.enable()

				FaultType.HIGH_RESISTANCE:
						if rec.element is Cable:
								(rec.element as Cable).ageing_factor = rec._saved_ageing
								rec.element.mark_dirty()

				FaultType.SHORT_CIRCUIT:
						if rec._short_cable != null:
								model.remove_element(rec._short_cable)
								rec._short_cable = null

		var eid := rec.element.id
		if _faults.has(eid):
				_faults[eid].erase(rec)
				if _faults[eid].is_empty():
						_faults.erase(eid)

		model.mark_dirty()
		emit_signal("fault_cleared", rec)

## Clear all active faults across the entire model.
func clear_all_faults(model: CircuitModel) -> void:
		for eid in _faults.keys().duplicate():
				var recs: Array = _faults.get(eid, []).duplicate()
				for rec in recs:
						clear_fault(rec, model)

## Clear all faults on one specific element.
func clear_faults_for(element: CircuitElement, model: CircuitModel) -> void:
		if not _faults.has(element.id):
				return
		for rec in _faults[element.id].duplicate():
				clear_fault(rec, model)

# ── Random fault configuration ────────────────────────────────────────

## Enable random fault generation for `element`.
## `prob_per_sec` — probability of a fault event per second.
##   0.01 ≈ one fault every ~100 s; 0.001 ≈ every ~1000 s.
## `type`      — which FaultType to inject.
## `magnitude` — only used for HIGH_RESISTANCE (ageing_factor multiplier).
func enable_random_faults(
		element:      CircuitElement,
		prob_per_sec: float,
		type:         int   = FaultType.OPEN_CIRCUIT,
		magnitude:    float = 10.0
) -> void:
		_rnd_prob[element.id]      = prob_per_sec
		_rnd_type[element.id]      = type
		_rnd_magnitude[element.id] = magnitude
		_rnd_accum[element.id]     = 0.0

## Remove random fault generation for `element`.
func disable_random_faults(element: CircuitElement) -> void:
		_rnd_prob.erase(element.id)
		_rnd_type.erase(element.id)
		_rnd_magnitude.erase(element.id)
		_rnd_accum.erase(element.id)

## Advance random fault timers. Call once per physics frame from FaultManagerNode.
## Only injects a new fault when the element has no active fault of the same type
## and the element is currently healthy (enabled, not already damaged).
func tick_random(dt: float, model: CircuitModel) -> void:
		for eid in _rnd_prob.keys():
				var prob: float = _rnd_prob[eid]
				if prob <= 0.0:
						continue

				_rnd_accum[eid] = _rnd_accum.get(eid, 0.0) + prob * dt
				if _rnd_accum[eid] < 1.0:
						continue
				_rnd_accum[eid] = 0.0

				var target: CircuitElement = _find_element_in_model(eid, model)
				if target == null:
						continue

				# Skip elements that are already faulted, disabled, or damaged.
				if not target.enabled:
						continue
				if target is Cable and (target as Cable).damaged:
						continue
				if target is Transformer and (target as Transformer).damaged:
						continue

				# Don't stack the same fault type.
				if _has_active_type(eid, _rnd_type[eid]):
						continue

				apply_fault(target, _rnd_type[eid], _rnd_magnitude.get(eid, 10.0), model, true)

# ── Query helpers ─────────────────────────────────────────────────────

## Returns a compact diagnostic summary of all active and random faults.
func get_diagnostic_summary() -> Dictionary:
		var active_faults: Array = get_all_active_faults()
		var by_type: Dictionary = {}
		for rec in active_faults:
				var type_name: String = type_to_string(rec.fault_type)
				by_type[type_name] = by_type.get(type_name, 0) + 1

		return {
				"active_faults": active_faults.size(),
				"by_type": by_type,
				"random_faults": _rnd_prob.size(),
		}

## Returns all active FaultRecords for `element`.
func get_faults_for(element: CircuitElement) -> Array:
		return _faults.get(element.id, []).filter(func(r): return r.active)

## True if `element` has at least one active fault.
func has_fault(element: CircuitElement) -> bool:
		var recs: Array = _faults.get(element.id, [])
		for r in recs:
				if r.active:
						return true
		return false

## Returns every active FaultRecord across all elements.
func get_all_active_faults() -> Array:
		var out: Array = []
		for eid in _faults.keys():
				for rec in _faults[eid]:
						if rec.active:
								out.append(rec)
		return out

## Group active faults by phase index. Records with phase == -1 are grouped under "global".
func get_faults_by_phase() -> Dictionary:
		var out: Dictionary = {}
		var active: Array = get_all_active_faults()
		for rec in active:
				var key = rec.phase if rec.phase >= 0 else "global"
				out[key] = out.get(key, [])
				out[key].append(rec)
		return out

## Returns a diagnostic summary keyed by phase and global count.
func get_diagnostic_summary_per_phase() -> Dictionary:
		var by_phase: Dictionary = {}
		var grouped: Dictionary = get_faults_by_phase()
		for k in grouped.keys():
				var label = "global" if k == "global" else str(k)
				by_phase[label] = grouped[k].size()
		return {
				"total_active": get_all_active_faults().size(),
				"by_phase": by_phase,
		}

# ── Helpers ───────────────────────────────────────────────────────────

func _find_element_in_model(eid: String, model: CircuitModel) -> CircuitElement:
		for e in model.elements:
				if e.id == eid:
						return e
		return null

func _has_active_type(eid: String, type: int) -> bool:
		if not _faults.has(eid):
				return false
		for rec in _faults[eid]:
				if rec.active and rec.fault_type == type:
						return true
		return false

# ── Fault type name helper (for UI / logging) ─────────────────────────

static func type_to_string(type: int) -> String:
		match type:
				FaultType.OPEN_CIRCUIT:    return "Open Circuit"
				FaultType.HIGH_RESISTANCE: return "High Resistance"
				FaultType.SHORT_CIRCUIT:   return "Short Circuit"
		return "Unknown"
