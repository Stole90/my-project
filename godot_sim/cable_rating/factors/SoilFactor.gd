## SoilFactor.gd
## Calculates the K3 soil correction factor for buried cables.
##
## This factor adjusts the cable ampacity for underground installations depending on soil characteristics.
## If the cable is not buried (in free air), this factor is neutral (1.0).
## If buried, the factor is determined by comparing actual soil thermal resistivity to the reference
## resistivity of the installation method.
## Formula: K = sqrt(ReferenceResistivity / max(ActualResistivity, 0.01))

class_name SoilFactor
extends RefCounted

## Computes the soil correction factor (K3).
## Returns 1.0 if the cable is not buried.
static func compute(installation: CableInstallationModel, electrical: CableElectricalModel) -> float:
	# This factor operates exclusively on buried cables
	if not installation.is_buried():
		return 1.0
		
	# Determine actual resistivity, prioritizing advanced manual override
	var resistivity := installation.soil_resistivity_advanced
	if resistivity < 0.0:
		resistivity = SoilTypeDB.get_resistivity(installation.soil_type)
		
	# Look up reference soil resistivity from the installation method
	var method := InstallationMethodDB.get_method(installation.installation_method)
	var reference := method.reference_soil_resistivity
	
	# Apply square root correction formula to scale ampacity based on thermal dissipation performance
	return sqrt(reference / max(resistivity, 0.01))
