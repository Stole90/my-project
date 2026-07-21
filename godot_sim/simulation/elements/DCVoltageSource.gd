## DCVoltageSource.gd
## Ideal DC voltage source.  Sets a real (angle = 0) constant voltage on a bus.
##
## ── Usage ────────────────────────────────────────────────────────────────────
##
##   var bat_bus := SimNode.new("battery_bus")
##   var bat     := DCVoltageSource.new(bat_bus, 48.0)   # 48 V DC
##   model.add_element(bat)
##
## ── Implementation note ───────────────────────────────────────────────────────
##
##   DC is modelled as a 0 Hz phasor: V = V_dc ∠ 0°.
##   Phase is always Phase.L1 (positive rail).
##   Phase.NEUTRAL / GND is set to 0 V (reference rail).
##
## ── Polarity ─────────────────────────────────────────────────────────────────
##
##   Positive voltage_v → L1 is the positive rail.
##   Setting a negative value reverses polarity without separate API.

class_name DCVoltageSource
extends CircuitElement

# ── Configuration ─────────────────────────────────────────────────────────────

## DC voltage [V].  May be negative to indicate reversed polarity.
var voltage_v: float

# ── Constructor ───────────────────────────────────────────────────────────────

func _init(
	bus_node: SimNode,
	p_voltage_v: float  = 12.0,
	p_name:      String = ""
) -> void:
	super._init(p_name)
	terminals  = [[bus_node]]
	voltage_v  = p_voltage_v
	_stamp()

func bus_node() -> SimNode:
	return terminals[0][0]

# ── Voltage API ───────────────────────────────────────────────────────────────

## Phasor representation of the DC voltage (imaginary part is always 0).
func voltage_phasor() -> Complex:
	return Complex.new(voltage_v, 0.0)

## Change voltage and re-stamp.
func set_voltage(v: float) -> void:
	voltage_v = v
	_stamp()
	mark_dirty()

## Stamp onto bus.
func _stamp() -> void:
	bus_node().set_voltage(Phase.L1, voltage_phasor())
	bus_node().set_voltage(Phase.NEUTRAL, Complex.zero())
	bus_node().set_voltage(Phase.PE, Complex.zero())

# ── Solver interface ──────────────────────────────────────────────────────────

func is_slack_source() -> bool:
	return true

func slack_node_phases() -> Array:
	return [
		[bus_node(), Phase.L1],
		[bus_node(), Phase.NEUTRAL],
		[bus_node(), Phase.PE],
	]

func stamp_ybus(_Y: Array, _I_inj: Array, _node_idx: Dictionary, _source_nodes: Array) -> void:
	pass

func stamp_ybus_3ph(_Y: Array, _I_inj: Array, _np_idx: Dictionary, _src_np: Dictionary) -> void:
	pass

func update_state_3ph(_dt: float = 0.0) -> void:
	current = currents_by_phase.get(Phase.L1, Complex.zero())

# ── Power queries ─────────────────────────────────────────────────────────────

func apparent_power() -> Complex:
	var v: Complex = bus_node().get_voltage(Phase.L1)
	var i: Complex = currents_by_phase.get(Phase.L1, null)
	if v == null or i == null:
		return null
	return v.mul(i.conjugate())

## DC power delivered [W].  (Reactive power is always 0 for DC.)
func active_power() -> float:
	var s: Complex = apparent_power()
	return 0.0 if s == null else s.re

func _to_string() -> String:
	return "DCVoltageSource('%s', %.2fV DC)" % [element_name, voltage_v]
