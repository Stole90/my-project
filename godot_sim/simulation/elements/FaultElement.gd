## FaultElement.gd
## Simulation-layer fault injection element for the 5-conductor AC system.
##
## ── Fault types ───────────────────────────────────────────────────────────────
##
##   PHASE_TO_EARTH    — low-impedance shunt from faulted phase to PE.
##   PHASE_TO_NEUTRAL  — shunt from faulted phase to neutral conductor.
##   NEUTRAL_OPEN      — open-circuit neutral between node_a and node_b.
##                       Requires BOTH node_a and node_b (the two ends of the
##                       broken neutral conductor).  Stamps a very high series
##                       impedance on the N row between the two nodes.
##   HIGH_Z_EARTH      — same topology as PHASE_TO_EARTH but high fault R.
##
## ── Ispravka NEUTRAL_OPEN ─────────────────────────────────────────────────────
##
##   Originalna implementacija je stampala admitansu između N i PE na ISTOM busu
##   (što modeluje N-PE kratki spoj, ne prekinutu nulu).
##
##   Ispravno: prekinuta nula = visoka SERIJSKA impedansa između N reda node_a i
##   N reda node_b (dva kraja kabla gde je nulta žila prekinuta).
##   To se stampa kao dvopolni element IZMEĐU dva busa na N redu:
##
##     Y[N_a][N_a] += y_open;   Y[N_b][N_b] += y_open
##     Y[N_a][N_b] -= y_open;   Y[N_b][N_a] -= y_open
##
##   gde je y_open = 1/R_open ≈ 1/1e6 Ω (praktično 0).
##
##   Za NEUTRAL_OPEN, fault_node_b MORA biti postavljen (drugi kraj prekinute nule).
##   Ako je fault_node_b null, element se ne stampa i emituje grešku.
##
## ── Usage ─────────────────────────────────────────────────────────────────────
##
##   # Kvar faze na zemlju (na jednom busu):
##   var f1 := FaultElement.new(bus, FaultElement.PHASE_TO_EARTH, Phase.L1)
##   model.add_fault(f1)
##
##   # Prekinuta nula između dva busa:
##   var f2 := FaultElement.new(bus_a, FaultElement.NEUTRAL_OPEN)
##   f2.fault_node_b = bus_b
##   model.add_fault(f2)

class_name FaultElement
extends CircuitElement

# ── Fault type constants ──────────────────────────────────────────────────────

const PHASE_TO_EARTH:   int = 0
const PHASE_TO_NEUTRAL: int = 1
const NEUTRAL_OPEN:     int = 2   ## Prekinuta nula između node_a i node_b.
const HIGH_Z_EARTH:     int = 3
const PHASE_TO_PHASE:   int = 4
const PHASE_SERIES_SHORT:int = 5  ## Low-impedance series short between same phase on two nodes.

## Visoka otpornost koja modeluje otvoreno kolo [Ω].
const DEFAULT_HIGH_Z_OHM: float = 1e6

# ── Parameters ────────────────────────────────────────────────────────────────

## Primarni bus kvara.
var fault_node: SimNode

## Drugi bus — obavezan SAMO za NEUTRAL_OPEN.
## Predstavlja drugi kraj prekinutog N provodnika.
var fault_node_b: SimNode = null

## Tip kvara.
var fault_type: int = PHASE_TO_EARTH

## Fazni provodnik koji je u kvaru: Phase.L1, L2, ili L3.
var faulted_phase: int = Phase.L1
var faulted_phase_b: int = -1

## Impedansa putanje kvara [Ω].
## Mala vrednost = metalni kvar;  velika = visoko-impedansni kvar.
var fault_impedance: Complex = Complex.new(0.01, 0.0)

# ── Results ───────────────────────────────────────────────────────────────────

var fault_current: Complex = Complex.zero()

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	p_node: SimNode,
	p_type: int           = PHASE_TO_EARTH,
	p_phase: int          = Phase.L1,
	p_phase_b: int        = -1,
	p_impedance_re: float = 0.01,
	p_name: String        = "FaultElement"
) -> void:
	super._init(p_name)
	fault_node      = p_node
	fault_type      = p_type
	faulted_phase   = p_phase
	faulted_phase_b = p_phase_b
	fault_impedance = Complex.new(maxf(p_impedance_re, 1e-9), 0.0)
	terminals       = [[p_node]]

func node_a() -> SimNode:
	return fault_node

# ── Activation API ────────────────────────────────────────────────────────────

func activate() -> void:
	if not enabled:
		enabled = true
		mark_dirty()

func deactivate() -> void:
	if enabled:
		enabled       = false
		fault_current = Complex.zero()
		mark_dirty()

func set_impedance(z: Complex) -> void:
	fault_impedance = Complex.new(maxf(z.re, 1e-9), z.im)
	mark_dirty()

# ── Solver stamps ─────────────────────────────────────────────────────────────

func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _source_np: Dictionary) -> void:
	if not enabled:
		return

	match fault_type:
		PHASE_TO_EARTH:
			# Shunt: faulted_phase → PE (na istom busu)
			_stamp_shunt_same_node(Y, np_idx, fault_node, faulted_phase, Phase.PE, fault_impedance)

		PHASE_TO_PHASE:
			# L-L fault. If a second node is provided, stamp a series connection
			# between fault_node[phase] and fault_node_b[phase_b]. Otherwise stamp
			# a same-bus shunt between the two phases.
			if faulted_phase_b < 0:
				push_error("FaultElement PHASE_TO_PHASE: second phase not set on '%s'" % element_name)
				return
			if fault_node_b != null:
				_stamp_series_between_nodes_phpair(Y, np_idx, fault_node, fault_node_b, faulted_phase, faulted_phase_b, fault_impedance)
			else:
				_stamp_shunt_same_node(Y, np_idx, fault_node, faulted_phase, faulted_phase_b, fault_impedance)

		PHASE_TO_NEUTRAL:
			# Shunt: faulted_phase → N (na istom busu)
			_stamp_shunt_same_node(Y, np_idx, fault_node, faulted_phase, Phase.NEUTRAL, fault_impedance)

		NEUTRAL_OPEN:
			# Serijska visoka impedansa između N reda node_a i N reda node_b.
			# Modeluje prekinut N provodnik između dva čvora.
			if fault_node_b == null:
				push_error("FaultElement NEUTRAL_OPEN: fault_node_b nije postavljen na '%s'" % element_name)
				return
			var z_open: Complex = Complex.new(DEFAULT_HIGH_Z_OHM, 0.0)
			_stamp_series_between_nodes(Y, np_idx, fault_node, fault_node_b, Phase.NEUTRAL, z_open)

		HIGH_Z_EARTH:
			# High-impedance connection to PE on the same bus. If no explicit
			# fault_impedance provided, use DEFAULT_HIGH_Z_OHM.
			var z: Complex = fault_impedance
			if z.re < 1.0:
				z = Complex.new(DEFAULT_HIGH_Z_OHM, 0.0)
			_stamp_shunt_same_node(Y, np_idx, fault_node, faulted_phase, Phase.PE, z)

		PHASE_SERIES_SHORT:
			# Series low-impedance between the SAME phase on two nodes.
			if fault_node_b == null:
				push_error("FaultElement PHASE_SERIES_SHORT: fault_node_b nije postavljen na '%s'" % element_name)
				return
			_stamp_series_between_nodes(Y, np_idx, fault_node, fault_node_b, faulted_phase, fault_impedance)

## Shunt između dve faze NA ISTOM busu (za L-E i L-N kvarove).
func _stamp_shunt_same_node(
	Y: Array,
	np_idx: Dictionary,
	node: SimNode,
	ph_a: int,
	ph_b: int,
	z: Complex
) -> void:
	var row_a: int = np_idx.get(node.id + ":" + str(ph_a), -1)
	var row_b: int = np_idx.get(node.id + ":" + str(ph_b), -1)
	if row_a < 0 or row_b < 0:
		return
	var y: Complex = z.reciprocal()
	Y[row_a][row_a].add_inplace(y)
	Y[row_b][row_b].add_inplace(y)
	Y[row_a][row_b].sub_inplace(y)
	Y[row_b][row_a].sub_inplace(y)

## Serijska impedansa između iste faze NA DVA BUSA (za prekinut provodnik).
## Ovo je standardni dvopolni stamp između node_a[ph] i node_b[ph].
func _stamp_series_between_nodes(
	Y: Array,
	np_idx: Dictionary,
	na: SimNode,
	nb: SimNode,
	ph: int,
	z: Complex
) -> void:
	var row_a: int = np_idx.get(na.id + ":" + str(ph), -1)
	var row_b: int = np_idx.get(nb.id + ":" + str(ph), -1)
	if row_a < 0 or row_b < 0:
		return
	var y: Complex = z.reciprocal()
	Y[row_a][row_a].add_inplace(y)
	Y[row_b][row_b].add_inplace(y)
	Y[row_a][row_b].sub_inplace(y)
	Y[row_b][row_a].sub_inplace(y)

## Serijska impedansa između DVE RAZLIČITE FAZE na DVA BUSA.
## Koristi se za cross-node L-L kvar: na primer na L1 bus_a povezano sa L2 bus_b.
func _stamp_series_between_nodes_phpair(
	Y: Array,
	np_idx: Dictionary,
	na: SimNode,
	nb: SimNode,
	ph_a: int,
	ph_b: int,
	z: Complex
) -> void:
	var row_a: int = np_idx.get(na.id + ":" + str(ph_a), -1)
	var row_b: int = np_idx.get(nb.id + ":" + str(ph_b), -1)
	if row_a < 0 or row_b < 0:
		return
	var y: Complex = z.reciprocal()
	Y[row_a][row_a].add_inplace(y)
	Y[row_b][row_b].add_inplace(y)
	Y[row_a][row_b].sub_inplace(y)
	Y[row_b][row_a].sub_inplace(y)

# ── State update ──────────────────────────────────────────────────────────────

func update_state_3ph(_dt: float = 0.0) -> void:
	if not enabled:
		fault_current = Complex.zero()
		current       = Complex.zero()
		return

	match fault_type:
		PHASE_TO_EARTH, HIGH_Z_EARTH:
			var v_ph: Complex = fault_node.get_voltage(faulted_phase)
			var v_pe: Complex = fault_node.get_voltage(Phase.PE)
			fault_current = _calc_fault_current(v_ph, v_pe, fault_impedance)

		PHASE_TO_NEUTRAL:
			var v_ph: Complex = fault_node.get_voltage(faulted_phase)
			var v_n: Complex  = fault_node.get_voltage(Phase.NEUTRAL)
			fault_current = _calc_fault_current(v_ph, v_n, fault_impedance)

		NEUTRAL_OPEN:
			# Struja je praktično nula (otvoreno kolo)
			if fault_node_b != null:
				var v_na: Complex = fault_node.get_voltage(Phase.NEUTRAL)
				var v_nb: Complex = fault_node_b.get_voltage(Phase.NEUTRAL)
				var z_open: Complex = Complex.new(DEFAULT_HIGH_Z_OHM, 0.0)
				fault_current = _calc_fault_current(v_na, v_nb, z_open)
			else:
				fault_current = Complex.zero()

		PHASE_SERIES_SHORT:
			if fault_node_b != null:
				var v_a: Complex = fault_node.get_voltage(faulted_phase)
				var v_b: Complex = fault_node_b.get_voltage(faulted_phase)
				fault_current = _calc_fault_current(v_a, v_b, fault_impedance)
			else:
				fault_current = Complex.zero()

		PHASE_TO_PHASE:
			if faulted_phase_b >= 0:
				var v1: Complex
				var v2: Complex
				if fault_node_b != null:
					v1 = fault_node.get_voltage(faulted_phase)
					v2 = fault_node_b.get_voltage(faulted_phase_b)
				else:
					v1 = fault_node.get_voltage(faulted_phase)
					v2 = fault_node.get_voltage(faulted_phase_b)
				fault_current = _calc_fault_current(v1, v2, fault_impedance)
				# Assign equal & opposite currents to the involved phases
				currents_by_phase[faulted_phase] = fault_current
				currents_by_phase[faulted_phase_b] = fault_current.scale(-1.0)
			else:
				fault_current = Complex.zero()

	current = fault_current
	currents_by_phase[faulted_phase] = fault_current

func _calc_fault_current(v_a: Complex, v_b: Complex, z: Complex) -> Complex:
	if v_a == null: v_a = Complex.zero()
	if v_b == null: v_b = Complex.zero()
	return v_a.sub(v_b).div(z)

func update_state(_nv: Dictionary, _dt: float = 0.0) -> void:
	update_state_3ph(_dt)

# ── Queries ───────────────────────────────────────────────────────────────────

func fault_current_a() -> float:
	return fault_current.magnitude()

func fault_power_w() -> float:
	var i: float = fault_current.magnitude()
	return i * i * fault_impedance.re

static func type_name(t: int) -> String:
	match t:
		PHASE_TO_EARTH:   return "Faza-Zemlja"
		PHASE_TO_NEUTRAL: return "Faza-Nula"
		NEUTRAL_OPEN:     return "Prekinuta nula"
		HIGH_Z_EARTH:     return "Visoko-Z zemlja"
	return "Nepoznat"

func _to_string() -> String:
	return "FaultElement('%s', %s, %s, Zf=%.2fΩ, I=%.1fA)" % [
		element_name,
		type_name(fault_type),
		Phase.name_of(faulted_phase),
		fault_impedance.re,
		fault_current_a(),
	]
