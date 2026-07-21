## ACCurrentSource.gd
## Ideal AC current source between two nodes.
## Replaces and supersedes the original CurrentSource.gd, adding:
##   • set_current() API with mark_dirty()
##   • active_power() / reactive_power() helpers
##   • stamp_ybus_3ph() stub for 3-phase solver compatibility
##   • _to_string()
##
## ── Usage ────────────────────────────────────────────────────────────────────
##
##   # 10 A ∠ 30° injected from node_a into node_b
##   var src := ACCurrentSource.new(node_a, node_b, Complex.from_polar(10.0, deg_to_rad(30.0)))
##   model.add_element(src)
##
## ── Sign convention ───────────────────────────────────────────────────────────
##
##   current_phasor defines the current leaving node_a and entering node_b.

class_name ACCurrentSource
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## Complex current phasor [A].
var current_phasor: Complex

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	node_a: SimNode,
	node_b: SimNode,
	p_current: Complex,
	p_name: String = ""
) -> void:
	super._init(p_name)
	terminals       = [[node_a], [node_b]]
	current_phasor  = p_current

func node_a() -> SimNode: return terminals[0][0]
func node_b() -> SimNode: return terminals[1][0]

# ── Current API ───────────────────────────────────────────────────────────────

## Change the injected current phasor.
func set_current(phasor: Complex) -> void:
	current_phasor = phasor
	mark_dirty()

## Convenience: set by RMS magnitude and angle in degrees.
func set_current_polar(rms: float, deg: float) -> void:
	set_current(Complex.from_polar(rms, deg_to_rad(deg)))

## RMS magnitude [A].
func current_rms() -> float:
	return current_phasor.magnitude()

# ── Solver interface ──────────────────────────────────────────────────────────

func is_slack_source() -> bool:
	return false

func stamp_ybus(_Y: Array, I_inj: Array, node_idx: Dictionary, _source_nodes: Array) -> void:
	var i: int = node_idx[node_a()]
	var j: int = node_idx[node_b()]
	I_inj[i].sub_inplace(current_phasor)   # current leaves node_a
	I_inj[j].add_inplace(current_phasor)   # current enters node_b

func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass   # single-phase stamp is sufficient

func update_state(_node_voltages: Dictionary, _dt: float = 0.0) -> void:
	current = current_phasor.copy()

func update_state_3ph(_dt: float = 0.0) -> void:
	current = current_phasor.copy()

# ── Power queries ─────────────────────────────────────────────────────────────

## Apparent power injected into node_b [VA].
func apparent_power() -> Complex:
	var va: Complex = node_a().get_voltage(Phase.L1)
	var vb: Complex = node_b().get_voltage(Phase.L1)
	if va == null or vb == null:
		return null
	# V_ab drives the current; S = V_ab * I*
	var v_ab: Complex = Complex.new(va.re - vb.re, va.im - vb.im)
	return v_ab.mul(current_phasor.conjugate())

func active_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.re

func reactive_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.im

func _to_string() -> String:
	return "ACCurrentSource('%s', %.3fA ∠%.1f°)" % [
		element_name,
		current_phasor.magnitude(),
		rad_to_deg(atan2(current_phasor.im, current_phasor.re))
	]
