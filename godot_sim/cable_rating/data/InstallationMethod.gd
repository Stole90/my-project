## InstallationMethod.gd
## Configuration resource describing a single IEC 60364-5-52 reference installation method.
##
## This resource specifies the characteristics of a specific installation method, such as reference temperatures,
## medium types, and reference resistivity values, which are used to look up and scale base ampacities.

class_name InstallationMethod
extends Resource

## The standard code representing the installation method (e.g., "A1", "C", "D2").
@export var method_code: String = "A1"

## Human-readable display name for UI and debugging.
@export var display_name: String = ""

## True if the installation is in free air, on a wall, or in conduits on/in a wall.
@export var is_air_installation: bool = true

## True if the installation places conductors inside a conduit, duct, or trunking.
@export var is_conduit: bool = false

## True if the installation involves directly buried cables or buried ducts.
@export var is_buried: bool = false

## Reference ambient temperature in degrees Celsius [°C] for this method (typically 30°C for air).
@export var reference_ambient_c: float = 30.0

## Reference soil temperature in degrees Celsius [°C] for this method (typically 20°C for ground).
@export var reference_soil_c: float = 20.0

## Reference soil thermal resistivity in Kelvin-metres per Watt [K·m/W] (typically 2.5 K·m/W for IEC ground).
@export var reference_soil_resistivity: float = 2.5

## Descriptive text indicating the cooling conditions of this installation environment.
@export var cooling_description: String = ""
