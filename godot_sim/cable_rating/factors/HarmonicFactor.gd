## HarmonicFactor.gd
## Calculates the K4 current harmonics correction factor for cable ampacity.
##
## Under high current harmonics, non-linear loads produce neutral current and skin effects,
## generating additional heat in the conductor. This factor scales the allowable current
## based on Total Harmonic Distortion (THD) or a specified harmonic level.

class_name HarmonicFactor
extends RefCounted

## Computes the harmonic correction factor (K4).
static func compute(installation: CableInstallationModel, electrical: CableElectricalModel) -> float:
	if installation.thd_percent_advanced >= 0.0:
		return HarmonicLevelDB.get_factor_for_thd(installation.thd_percent_advanced)
	else:
		return HarmonicLevelDB.get_factor_for_level(installation.harmonic_level)
