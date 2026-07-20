## RatedConsumer.gd
## Consumer specified by nameplate active power and power factor.
## Equivalent to the legacy `RatedLoad`.
##
## |S| = P / pf;   |Z| = V_nom² / |S|;   φ = arccos(pf)
## Z   = |Z|·cosφ + j·|Z|·sinφ   (inductive when pf < 1 and inductive=true)

class_name RatedConsumer
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
	p_inductive: bool = true
) -> void:
	super._init(node, p_name)
	power_w         = p_power_w
	rated_pf        = clampf(p_pf, 1e-6, 1.0)
	nominal_voltage = p_nominal_v
	inductive       = p_inductive
	min_voltage     = nominal_voltage * SimConstants.UNDERVOLTAGE_PU
	max_voltage     = nominal_voltage * SimConstants.OVERVOLTAGE_PU
	if p_power_w <= 0.0:
		push_error("RatedConsumer: power_w must be > 0 (got %.2f)" % p_power_w)

func impedance() -> Complex:
	if power_w <= 0.0 or nominal_voltage <= 0.0:
		return Complex.new(1e9, 0.0)
	var S_mag: float = power_w / rated_pf
	var Z_mag: float = (nominal_voltage * nominal_voltage) / S_mag
	var phi: float   = acos(rated_pf)
	var R: float     = Z_mag * cos(phi)
	var X: float     = Z_mag * sin(phi)
	if not inductive:
		X = 0.0
	return Complex.new(R, X)

func load_type() -> String:
	if rated_pf >= 1.0 - 1e-6:
		return "resistive"
	return "inductive" if inductive else "resistive"
