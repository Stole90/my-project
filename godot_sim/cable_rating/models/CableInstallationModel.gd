## CableInstallationModel.gd
## Configuration resource holding the installation environment parameters of a cable.
##
## This resource describes how and where the cable is installed. These environmental factors
## (such as ambient temperature, grouping, burial status, and thermal insulation) directly
## dictate the ampacity derating coefficients according to SRPS IEC 60364-5-52.

class_name CableInstallationModel
extends Resource

## Installation method code matching the standard.
## Valid keys are "A1", "A2", "B1", "B2", "C", "D1", "D2", "E", "F", "G" in InstallationMethodDB.
@export var installation_method: String = "A1"

## Ambient air temperature in degrees Celsius [°C] for air installations. Reference is typically 30°C.
@export var ambient_c: float = 30.0

## Soil/ground temperature in degrees Celsius [°C] for buried installations. Reference is typically 20°C.
@export var soil_temperature_c: float = 20.0

## Ground soil classification: "normal", "sand", "clay", "wet", "dry", or "rock" (simple mode).
@export var soil_type: String = "normal"

## Advanced manual override for soil thermal resistivity in Kelvin-metres per Watt [K·m/W].
## If >= 0.0, this value is used directly; if -1.0, the resistivity is derived from soil_type.
@export var soil_resistivity_advanced: float = -1.0

## Number of grouped or touching electrical circuits/multicore cables in the same run.
@export var grouped_circuits: int = 1

## True if the grouped cables/circuits are physically touching each other.
@export var touching: bool = true

## Spacing between cables in millimetres [mm] (relevant for spaced grouping arrangements).
@export var spacing_mm: float = 0.0

## Grouping physical arrangement type: "touching", "spacing", "tray", "conduit", or "bundle".
@export var grouping_arrangement: String = "tray"

## Physical depth at which the cable is buried in metres [m] (future-ready).
@export var installation_depth_m: float = 0.7

## Ventilation cooling factor (future-ready; 1.0 represents neutral/unventilated).
@export var ventilation_factor: float = 1.0

## Harmonic current presence level classification: "none", "low", "medium", or "high" (simple mode).
@export var harmonic_level: String = "none"

## Advanced manual override for Total Harmonic Distortion (THD) of current as a percentage [%].
## If >= 0.0, this value is used directly; if -1.0, the level is derived from harmonic_level.
@export var thd_percent_advanced: float = -1.0

## True if the cable passes through or is surrounded by thermal insulation (e.g. wall insulation).
@export var has_thermal_insulation: bool = false

## Enclosing duct type: "none", "pvc_duct", or "steel_duct".
@export var duct_type: String = "none"

## Helper to determine if the selected installation method constitutes burial.
func is_buried() -> bool:
	return installation_method == "D1" or installation_method == "D2"
