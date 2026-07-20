## CapacitiveConsumer.gd
## Consumer specified by physical R [Ω] and C [µF].
## Z = R + j·X_C   where X_C = -1 / (ωC).  Equivalent to legacy CapacitiveLoad.

class_name CapacitiveConsumer
extends Consumer

var resistance_ohm: float
var capacitance_uf: float

func _init(
	node: SimNode,
	p_resistance_ohm: float,
	p_capacitance_uf: float,
	p_name: String = "",
	p_nominal_v: float = SimConstants.NOMINAL_V
) -> void:
	super._init(node, p_name)
	resistance_ohm  = p_resistance_ohm
	capacitance_uf  = p_capacitance_uf
	nominal_voltage = p_nominal_v
	min_voltage     = nominal_voltage * SimConstants.UNDERVOLTAGE_PU
	max_voltage     = nominal_voltage * SimConstants.OVERVOLTAGE_PU
	if p_resistance_ohm < 0.0:
		push_error("CapacitiveConsumer: R must be ≥ 0")
	if p_capacitance_uf <= 0.0:
		push_error("CapacitiveConsumer: C must be > 0")

func impedance() -> Complex:
	var X_C: float = -1.0 / (SimConstants.OMEGA * capacitance_uf * 1e-6)
	return Complex.new(resistance_ohm, X_C)

func load_type() -> String:
	return "capacitive"
