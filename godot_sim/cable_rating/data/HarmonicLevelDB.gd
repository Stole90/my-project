## HarmonicLevelDB.gd
## Database and converter for current harmonics and Total Harmonic Distortion (THD).
##
## Harmonic currents in the neutral conductor generate extra heat and reduce the cable's
## load capacity. This class provides standard derating factors (K4) based either on discrete
## qualitative level classifications or on continuous THD measurements.

class_name HarmonicLevelDB
extends RefCounted

## Qualitative harmonic level factors matching standard expectations:
## - none: no significant harmonics (1.0)
## - low: THD up to 15% (0.95)
## - medium: THD up to 33% (0.86)
## - high: THD above 33% and up to 45% or more (0.75)
const LEVEL_MAP := {
	"none": 1.0,
	"low": 0.95,
	"medium": 0.86,
	"high": 0.75
}

## Returns the derating factor for a qualitative harmonic level.
## If the level is unknown, pushes a warning and returns 1.0 (no derating).
static func get_factor_for_level(level: String) -> float:
	var key := level.to_lower()
	if LEVEL_MAP.has(key):
		return LEVEL_MAP[key]
	
	push_warning("Unknown harmonic level: '" + level + "'. Falling back to 'none' (1.0).")
	return LEVEL_MAP["none"]

## Returns an interpolated/banded derating factor based on continuous current THD [%].
## Maps closely to the SRPS IEC 60364-5-523 informative guidance:
## - 0% THD = 1.0
## - 15% THD = 0.95
## - 30% THD = 0.86
## - 45%+ THD = 0.75 (clamped)
static func get_factor_for_thd(thd_percent: float) -> float:
	var thd := clampf(thd_percent, 0.0, 100.0)
	
	if thd <= 0.0:
		return 1.0
	elif thd <= 15.0:
		# Interpolate between 0% (1.0) and 15% (0.95)
		return 1.0 - (0.05 * (thd / 15.0))
	elif thd <= 30.0:
		# Interpolate between 15% (0.95) and 30% (0.86)
		var t := (thd - 15.0) / 15.0
		return 0.95 - (0.09 * t)
	elif thd <= 45.0:
		# Interpolate between 30% (0.86) and 45% (0.75)
		var t := (thd - 30.0) / 15.0
		return 0.86 - (0.11 * t)
	else:
		# Standard maximum derating factor for high harmonic distortions
		return 0.75

## Returns an array of all standard harmonic level names.
static func all_levels() -> Array[String]:
	return ["none", "low", "medium", "high"]
