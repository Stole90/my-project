## GroundingSystem.gd
## Models the bonding between Neutral and PE conductors at the star point,
## and the PE-to-earth shunt impedance.
##
## ── System types ─────────────────────────────────────────────────────────────
##
##   TN_S : Separate N and PE conductors.  N and PE are bonded (low Z) at
##          the transformer star point only.  PE is connected to earth.
##
##   TN_C : Combined PEN conductor (older wiring).  N-PE bonding impedance
##          is zero; treated identically to TN_S in the matrix.
##
##   IT   : No direct N-to-earth connection.  PE floats relative to N.
##          n_pe_impedance is ignored; only pe_earth_impedance is stamped.
##
## ── Stamp ────────────────────────────────────────────────────────────────────
##
##   1. N-PE bonding (TN systems):
##        Y[N_row][N_row]  += y_n_pe
##        Y[PE_row][PE_row] += y_n_pe
##        Y[N_row][PE_row]  -= y_n_pe
##        Y[PE_row][N_row]  -= y_n_pe
##
##   2. PE-earth shunt (all types):
##        Y[PE_row][PE_row] += y_pe_earth
##
## ── Usage ─────────────────────────────────────────────────────────────────────
##
##   var gs := GroundingSystem.new(star_bus, GroundingSystem.TN_S)
##   model.grounding_system = gs

class_name GroundingSystem
extends RefCounted

# ── System type constants ─────────────────────────────────────────────────────

const TN_S: int = 0   ## Separate N and PE; bonded at transformer star point.
const TN_C: int = 1   ## Combined PEN (N and PE are the same conductor).
const IT:   int = 2   ## Isolated neutral; PE floats — no N-PE bond stamped.

# ── Configuration ─────────────────────────────────────────────────────────────

## The star-point bus where N and PE are bonded.
var star_node: SimNode

## Grounding system type: TN_S, TN_C, or IT.
var system_type: int = TN_S

## Impedance between Neutral and PE conductors at the star point [Ω].
## Typically near zero for TN systems (solid bond).
## Ignored for IT systems.
var n_pe_impedance: Complex = Complex.new(0.001, 0.0)

## Impedance from PE conductor to true earth [Ω].
## Typical values: 0.1–2 Ω for driven rod; very high for IT systems.
var pe_earth_impedance: Complex = Complex.new(0.5, 0.0)

# ── Constructor ───────────────────────────────────────────────────────────────

## Create a grounding system.
##
##   p_star_node       — the SimNode where N and PE are bonded (transformer star)
##   p_type            — TN_S, TN_C, or IT
##   p_n_pe_ohm        — N-PE bonding resistance [Ω]  (default 0.001 Ω)
##   p_pe_earth_ohm    — PE-to-earth resistance  [Ω]  (default 0.5 Ω)
func _init(
	p_star_node: SimNode,
	p_type: int           = TN_S,
	p_n_pe_ohm: float     = 0.001,
	p_pe_earth_ohm: float = 0.5
) -> void:
	star_node        = p_star_node
	system_type      = p_type
	n_pe_impedance   = Complex.new(maxf(p_n_pe_ohm,    1e-9), 0.0)
	pe_earth_impedance = Complex.new(maxf(p_pe_earth_ohm, 1e-9), 0.0)

# ── Stamp ─────────────────────────────────────────────────────────────────────

## Stamp N-PE bonding and PE-earth shunt into the 5N Y-bus matrix.
## Called by ThreePhaseYBusSolver during each solve.
func stamp_ybus_3ph(Y: Array, _I_inj: Array, np_idx: Dictionary, _source_np: Dictionary) -> void:
	if star_node == null:
		return

	var n_key:  String = star_node.id + ":" + str(Phase.NEUTRAL)
	var pe_key: String = star_node.id + ":" + str(Phase.PE)
	var row_n:  int    = np_idx.get(n_key, -1)
	var row_pe: int    = np_idx.get(pe_key, -1)

	# ── 1. N-PE bonding (TN systems only) ─────────────────────────────
	if system_type != IT and row_n >= 0 and row_pe >= 0:
		var y_np: Complex = n_pe_impedance.reciprocal()
		Y[row_n][row_n].add_inplace(y_np)
		Y[row_pe][row_pe].add_inplace(y_np)
		Y[row_n][row_pe].sub_inplace(y_np)
		Y[row_pe][row_n].sub_inplace(y_np)

	# ── 2. PE-earth shunt (all system types) ──────────────────────────
	if row_pe >= 0:
		var y_earth: Complex = pe_earth_impedance.reciprocal()
		Y[row_pe][row_pe].add_inplace(y_earth)

## System type as a human-readable string.
func system_type_name() -> String:
	match system_type:
		TN_S: return "TN-S"
		TN_C: return "TN-C"
		IT:   return "IT"
	return "Unknown"

func _to_string() -> String:
	return "GroundingSystem(%s, N-PE=%.3fΩ, PE-Earth=%.3fΩ)" % [
		system_type_name(),
		n_pe_impedance.re,
		pe_earth_impedance.re,
	]
