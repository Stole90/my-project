## SoilTypeDB.gd
## Simple database of soil types and their corresponding thermal resistivities.
##
## This class translates descriptive soil labels into physical thermal resistivity parameters
## expressed in Kelvin-metres per Watt [K·m/W]. These values are used in the calculation
## of the soil correction factor (K3) for buried cables.

class_name SoilTypeDB
extends RefCounted

## Dictionary mapping soil types to thermal resistivity [K·m/W].
## NOTE: These values are standard approximations and should be validated for specific field layouts.
const RESISTIVITY_MAP := {
	"normal": 1.0,      # Standard mixed soil with average moisture content
	"sand": 2.5,        # Dry sand (highly resistive due to air pockets between grains)
	"clay": 1.2,        # Clay soil, moderate water retention
	"wet": 0.7,         # Saturated/wet soil (highly conductive due to water content)
	"dry": 2.0,         # Dry generic soil, depleted of moisture
	"rock": 1.5         # Solid or fractured rock layers
}

## Returns the thermal resistivity in K·m/W for the specified soil type.
## If the soil type is unrecognized, logs a warning and falls back to "normal" soil (1.0 K·m/W).
static func get_resistivity(soil_type: String) -> float:
	var key := soil_type.to_lower()
	if RESISTIVITY_MAP.has(key):
		return RESISTIVITY_MAP[key]
	
	push_warning("Unknown soil type: '" + soil_type + "'. Falling back to 'normal' soil.")
	return RESISTIVITY_MAP["normal"]

## Returns an array of all supported soil type keys.
static func all_types() -> Array[String]:
	return ["normal", "sand", "clay", "wet", "dry", "rock"]
