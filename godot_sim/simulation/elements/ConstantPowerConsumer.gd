## ConstantPowerConsumer.gd
## Consumer that maintains constant active power regardless of voltage.
## Models switching power supplies, inverters, modern electronics.
## At each solve, impedance is recomputed from the actual node voltage:
##     Z = V_actual² / (P / pf)

class_name ConstantPowerConsumer
extends Consumer

var power_w: float
var rated_pf: float
var inductive: bool

func _init(
	node: SimNode,
	p_power_w: float,
	p_pf: float = 1.0,
	p_name: String = "",
	p_nominal_v: float = SimConstants.NOMINAL_V,
	p_inductive: bool = false
) -> void:
	super._init(node, p_name)
	power_w         = p_power_w
	rated_pf        = clampf(p_pf, 1e-6, 1.0)
	nominal_voltage = p_nominal_v
	inductive       = p_inductive
	min_voltage     = nominal_voltage * SimConstants.UNDERVOLTAGE_PU
	max_voltage     = nominal_voltage * SimConstants.OVERVOLTAGE_PU
	if p_power_w <= 0.0:
		push_error("ConstantPowerConsumer: power_w must be > 0")

func impedance() -> Complex:
	var V: float = node().voltage_magnitude() if node().voltage != null else nominal_voltage
	if V < 1.0:
		V = nominal_voltage
	var S_mag: float = power_w / rated_pf
	var Z_mag: float = (V * V) / S_mag
	var phi: float   = acos(rated_pf)
	var R: float     = Z_mag * cos(phi)
	var X: float     = Z_mag * sin(phi)
	if not inductive:
		X = 0.0
	return Complex.new(R, X)

func load_type() -> String:
	return "constant_power"
