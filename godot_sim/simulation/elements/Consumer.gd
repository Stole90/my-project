## Consumer.gd
## Abstract base for everything that draws power: appliances, motors,
## constant-power loads, capacitor banks, etc.
##
## Implements the load state-machine and health checking that used to
## live on `Load.gd`.  Subclasses only override impedance() and load_type().
##
## State machine:
##   STATE_NORMAL          — operating within rated envelope
##   STATE_OFF             — manually disabled by player (enable() / disable())
##   STATE_TRIPPED_UV      — auto trip on undervoltage  (recovers automatically)
##   STATE_DAMAGED_OV      — permanent damage on overvoltage  (needs repair())
##
## Multi-phase support:
##   `assigned_phase` selects which phase row this consumer stamps on in the
##   5N ThreePhaseYBusSolver matrix. Default Phase.L1 is backward compatible.
##
## Fix: _apparent_power_complex() now uses assigned_phase voltage, not
##      the hardcoded L1 accessor — so L2/L3 consumers report correct power.

class_name Consumer
extends CircuitElement

const STATE_NORMAL     := "normal"
const STATE_OFF        := "off"
const STATE_TRIPPED_UV := "tripped_undervoltage"
const STATE_DAMAGED_OV := "damaged_overvoltage"

var state: String = STATE_NORMAL

## Which phase conductor this single-phase consumer connects to.
## Phase.L1 (default) = backward compatible; set to L2 or L3 for
## consumers on other phases in the distribution panel.
var assigned_phase: int = Phase.L1

# Voltage envelope
var nominal_voltage: float = SimConstants.NOMINAL_V
var min_voltage: float     = SimConstants.NOMINAL_V * SimConstants.UNDERVOLTAGE_PU
var max_voltage: float     = SimConstants.NOMINAL_V * SimConstants.OVERVOLTAGE_PU

# Inrush model
var inrush_factor: float       = 1.0
var inrush_duration_s: float   = 0.0
var _inrush_remaining_s: float = 0.0

func _init(node: SimNode, p_name: String = "") -> void:
	super._init(p_name)
	terminals = [[node]]

func node() -> SimNode:
	return terminals[0][0]

# ── Subclass interface ──────────────────────────────────────────────

func impedance() -> Complex:
	push_error("Consumer.impedance() not implemented in '%s'" % get_class())
	return Complex.new(1.0, 0.0)

func load_type() -> String:
	return "unknown"

func admittance() -> Complex:
	return impedance().reciprocal()

# ── Solver stamps ───────────────────────────────────────────────────

## Three-phase stamp: uses assigned_phase to select the correct matrix row.
func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _source_np: Dictionary) -> void:
	if not enabled:
		return
	var key: String = node().id + ":" + str(assigned_phase)
	var row: int    = np_idx.get(key, -1)
	if row < 0:
		return
	var y: Complex = admittance()
	if _inrush_remaining_s > 0.0 and inrush_factor > 1.0:
		y = y.scale(inrush_factor)
	Y[row][row].add_inplace(y)

## Three-phase state update: reads voltage from assigned_phase.
func update_state_3ph(dt: float = 0.0) -> void:
	if not enabled or node().get_voltage(assigned_phase) == null:
		current = Complex.zero()
		currents_by_phase[assigned_phase] = Complex.zero()
		return
	var v: Complex = node().get_voltage(assigned_phase)
	current = v.div(impedance())
	if _inrush_remaining_s > 0.0:
		_inrush_remaining_s = max(0.0, _inrush_remaining_s - dt)
		if _inrush_remaining_s == 0.0:
			mark_dirty()
	currents_by_phase[assigned_phase] = current
	check_health()

func stamp_ybus(Y: Array, _I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	if not enabled:
		return
	var i: int = node_idx[node()]
	var y: Complex = admittance()
	if _inrush_remaining_s > 0.0 and inrush_factor > 1.0:
		y = y.scale(inrush_factor)
	Y[i][i].add_inplace(y)

func update_state(_node_voltages: Dictionary, dt: float = 0.0) -> void:
	if not enabled or node().voltage == null:
		current = Complex.zero()
		return
	current = node().voltage.div(impedance())
	if _inrush_remaining_s > 0.0:
		_inrush_remaining_s = max(0.0, _inrush_remaining_s - dt)
		if _inrush_remaining_s == 0.0:
			mark_dirty()
	check_health()

# ── Power query ─────────────────────────────────────────────────────

## Fix: koristi napon assigned_phase, ne hardcoded L1.
## Potrošač na L2 ili L3 sada ispravno računa snagu.
func _apparent_power_complex() -> Complex:
	var v: Complex = node().get_voltage(assigned_phase)   # ← fix
	if v == null or current == null:
		return null
	return v.mul(current.conjugate())

func active_power() -> float:
	var s: Complex = _apparent_power_complex()
	return 0.0 if s == null else s.re

func reactive_power() -> float:
	var s: Complex = _apparent_power_complex()
	return 0.0 if s == null else s.im

func apparent_power() -> float:
	var s: Complex = _apparent_power_complex()
	return 0.0 if s == null else s.magnitude()

func power_factor() -> float:
	var P: float = active_power()
	var S: float = apparent_power()
	return 0.0 if S == 0.0 else abs(P) / S

# ── Game state control ──────────────────────────────────────────────

func disable() -> void:
	enabled = false
	state   = STATE_OFF
	mark_dirty()

func enable() -> void:
	if state == STATE_DAMAGED_OV:
		return
	enabled = true
	if state == STATE_OFF or state == STATE_TRIPPED_UV:
		state = STATE_NORMAL
	if inrush_duration_s > 0.0:
		_inrush_remaining_s = inrush_duration_s
	mark_dirty()

func repair() -> void:
	state   = STATE_NORMAL
	enabled = true
	mark_dirty()

func is_damaged() -> bool: return state == STATE_DAMAGED_OV
func is_tripped() -> bool: return state == STATE_TRIPPED_UV

# ── Health check (called from update_state) ─────────────────────────

func check_health() -> String:
	if state == STATE_DAMAGED_OV or state == STATE_OFF:
		return state
	var v: Complex = node().get_voltage(assigned_phase)
	if v == null:
		return state
	var vmag: float = v.magnitude()
	if vmag > max_voltage:
		state   = STATE_DAMAGED_OV
		enabled = false
		mark_dirty()
	elif vmag < min_voltage and vmag > 1e-3:
		state   = STATE_TRIPPED_UV
		enabled = false
		mark_dirty()
	elif state == STATE_TRIPPED_UV and vmag >= min_voltage:
		state   = STATE_NORMAL
		enabled = true
		mark_dirty()
	return state
