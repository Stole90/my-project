## TemperatureFactor.gd
## Calculates the K1 ambient temperature correction factor for cable ampacity.
##
## This factor adjusts the cable's current-carrying capacity based on the difference
## between actual ambient/soil temperature and the standard reference temperature.
## Formula: K = sqrt((Tmax - Tactual) / (Tmax - Tref))
##
## Under normal conditions, higher temperatures reduce allowable current. If the
## surrounding temperature exceeds the maximum rating of the insulation, the factor
## is clamped to a safe minimum of 0.05 to reflect lack of current capability.

class_name TemperatureFactor
extends RefCounted

## Maximum continuous operating temperature for standard insulation types [°C].
const TMAX_MAP := {
	"pvc": 70.0,
	"xlpe": 90.0,
	"epr": 90.0
}

## Computes the K1 temperature correction factor.
## Returns 1.0 as a safe fallback if conditions are mathematically invalid.
static func compute(installation: CableInstallationModel, electrical: CableElectricalModel) -> float:
	var ins_key := electrical.insulation_type.to_lower()
	var tmax := 70.0
	
	if TMAX_MAP.has(ins_key):
		tmax = TMAX_MAP[ins_key]
	else:
		push_warning("Unknown insulation type '" + electrical.insulation_type + "' in TemperatureFactor. Defaulting Tmax to 70°C (PVC).")
		tmax = 70.0

	var is_buried := installation.is_buried()
	var tactual := installation.soil_temperature_c if is_buried else installation.ambient_c
	
	var method := InstallationMethodDB.get_method(installation.installation_method)
	var tref := method.reference_soil_c if is_buried else method.reference_ambient_c
	
	var denominator := tmax - tref
	if denominator <= 0.0:
		push_warning("Invalid temperature layout: Tmax (" + str(tmax) + "°C) <= Tref (" + str(tref) + "°C). Returning 1.0 fallback.")
		return 1.0
	
	var numerator := tmax - tactual
	var ratio := numerator / denominator
	
	if ratio <= 0.0:
		push_warning("Ambient/soil temperature (" + str(tactual) + "°C) meets or exceeds insulation limit (" + str(tmax) + "°C). Returning minimum correction of 0.05.")
		return 0.05
	
	return sqrt(ratio)
