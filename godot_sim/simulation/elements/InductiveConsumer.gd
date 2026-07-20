## InductiveConsumer.gd
## Consumer specified by physical R [Ω] and L [mH].  Z = R + jωL.
## Equivalent to the legacy `InductiveLoad`.

class_name InductiveConsumer
extends Consumer

var resistance_ohm: float
var inductance_mh: float

func _init(
	node: SimNode,
	p_resistance_ohm: float,
	p_inductance_mh: float,
	p_name: String = "",
	p_nominal_v: float = SimConstants.NOMINAL_V
) -> void:
	super._init(node, p_name)
	resistance_ohm  = p_resistance_ohm
	inductance_mh   = p_inductance_mh
	nominal_voltage = p_nominal_v
	min_voltage     = nominal_voltage * SimConstants.UNDERVOLTAGE_PU
	max_voltage     = nominal_voltage * SimConstants.OVERVOLTAGE_PU
	if p_resistance_ohm < 0.0:
		push_error("InductiveConsumer: R must be ≥ 0")
	if p_inductance_mh <= 0.0:
		push_error("InductiveConsumer: L must be > 0")

func impedance() -> Complex:
	var X_L: float = SimConstants.OMEGA * inductance_mh * 1e-3
	return Complex.new(resistance_ohm, X_L)

func load_type() -> String:
	return "inductive"
