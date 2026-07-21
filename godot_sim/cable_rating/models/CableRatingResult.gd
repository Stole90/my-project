## CableRatingResult.gd
## Data container for the output of a cable rating calculation.
##
## This is a pure data/output container. It holds the intermediate correction factors,
## the base ampacity, the final corrected ampacity, and diagnostic notes about the calculation.
## It contains no rating calculation logic itself except for a helper to compute the combined factor.

class_name CableRatingResult
extends Resource

## Base current ampacity from the standard tables in Amperes [A].
@export var iz_base: float = 0.0

## Temperature correction factor (K1).
@export var k1_temperature: float = 1.0

## Grouping correction factor (K2).
@export var k2_grouping: float = 1.0

## Soil/burial resistivity and depth correction factor (K3).
@export var k3_soil: float = 1.0

## Harmonic current presence correction factor (K4).
@export var k4_harmonic: float = 1.0

## Installation detail and ventilation correction factor (K5).
@export var k5_installation: float = 1.0

## Final continuous current-carrying capacity in Amperes [A] after applying all corrections.
@export var iz_final: float = 0.0

## Flag indicating if the rating calculation completed successfully with valid parameters.
@export var is_valid: bool = false

## List of diagnostic logs, explanations, and warning messages generated during calculation.
@export var notes: Array[String] = []

## Calculates the combined total correction factor from all individual coefficients.
func total_correction_factor() -> float:
	return k1_temperature * k2_grouping * k3_soil * k4_harmonic * k5_installation
