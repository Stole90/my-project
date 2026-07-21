## GroupingFactor.gd
## Calculates the K2 grouping correction factor for cable ampacity.
##
## Multiple circuits running in close proximity reduce mutual heat dissipation. This factor
## scales down the allowable current based on the number of grouped circuits and their physical arrangement.
##
## NOTE: These values are representative of typical IEC 60364-5-52 tables and should be updated
## with exact SRPS standard figures once localized validation is completed.

class_name GroupingFactor
extends RefCounted

## Dictionary mapping grouping arrangements to their respective circuit-count derating curves.
## Keyed by arrangement: "touching" | "spacing" | "tray" | "conduit" | "bundle"
## Under each arrangement, maps the number of circuits (1 to 9+) to a float factor.
const GROUPING_FACTORS := {
	"touching": {
		1: 1.00,
		2: 0.85,
		3: 0.79,
		4: 0.75,
		5: 0.73,
		6: 0.72,
		7: 0.71,
		8: 0.70,
		9: 0.70
	},
	"bundle": {
		1: 1.00,
		2: 0.80,
		3: 0.70,
		4: 0.65,
		5: 0.60,
		6: 0.57,
		7: 0.54,
		8: 0.52,
		9: 0.50
	},
	"conduit": {
		1: 1.00,
		2: 0.80,
		3: 0.70,
		4: 0.65,
		5: 0.60,
		6: 0.57,
		7: 0.54,
		8: 0.52,
		9: 0.50
	},
	"tray": {
		1: 1.00,
		2: 0.88,
		3: 0.82,
		4: 0.77,
		5: 0.75,
		6: 0.73,
		7: 0.72,
		8: 0.71,
		9: 0.70
	},
	"spacing": {
		1: 1.00,
		2: 0.94,
		3: 0.90,
		4: 0.90,
		5: 0.90,
		6: 0.90,
		7: 0.90,
		8: 0.90,
		9: 0.90
	}
}

## Computes the grouping correction factor (K2).
## Clamps grouped_circuits to [1, 9] (the max key of the reference curves).
## If grouping_arrangement is unrecognized, warns and falls back to "bundle" for safety.
static func compute(installation: CableInstallationModel, electrical: CableElectricalModel) -> float:
	var arrangement := installation.grouping_arrangement.to_lower()
	
	if not GROUPING_FACTORS.has(arrangement):
		push_warning("Unknown grouping arrangement '" + installation.grouping_arrangement + "' in GroupingFactor. Falling back to 'bundle' safety curve.")
		arrangement = "bundle"
		
	var curve: Dictionary = GROUPING_FACTORS[arrangement]
	var circuits := clampi(installation.grouped_circuits, 1, 9)
	
	return curve[circuits]
