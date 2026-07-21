## InstallationFactor.gd
## Calculates the K5 installation-specific correction factor.
##
## This factor absorbs miscellaneous environmental parameters that are not accounted for by the base
## ampacity tables or the other four correction factors. It accounts for ventilation cooling,
## placement in proximity to thermal wall insulation, and the material of protective ducts.

class_name InstallationFactor
extends RefCounted

## Dictionary mapping duct types to small physical derating factors.
## NOTE: These values are representative placeholders.
const DUCT_MULTIPLIERS := {
	"none": 1.00,
	"pvc_duct": 0.95,       # PVC ducts restrict radiant cooling slightly
	"steel_duct": 0.92      # Steel ducts introduce high thermal storage but restrict air circulation
}

## Computes the installation detail correction factor (K5).
static func compute(installation: CableInstallationModel, electrical: CableElectricalModel) -> float:
	var factor: float = 1.0
	
	# Apply active ventilation factor (1.0 is neutral/unventilated)
	factor *= installation.ventilation_factor
	
	# Apply 10% penalty (0.90x) if the cable runs through thermal wall insulation
	if installation.has_thermal_insulation:
		factor *= 0.90
		
	# Apply protective duct type modifier
	var duct := installation.duct_type.to_lower()
	if DUCT_MULTIPLIERS.has(duct):
		factor *= DUCT_MULTIPLIERS[duct]
	else:
		push_warning("Unknown duct type '" + installation.duct_type + "' in InstallationFactor. Defaulting duct factor to 1.0.")
		
	return factor
