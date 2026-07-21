## CableRatingCalculator.gd
## Orchestrator and core engine of the SRPS IEC 60364-5-52 Cable Rating System.
##
## This calculator acts as the sole processing point combining base current-carrying capacities
## with all five independent correction factors (K1 to K5).
##
## ── SOLID & Architectural Constraints ─────────────────────────────────────────
##   - ZERO knowledge of UI, views, themes, or presentation layers.
##   - ZERO knowledge of Godot Node/scene classes (inherits strictly from RefCounted).
##   - ZERO dependencies on game loops or frame rates.
##   - This is the ONLY place in the application where base currents and the five factors are composed.

class_name CableRatingCalculator
extends RefCounted

static var _default_table_cache: IecAmpacityTable = null

## Core rating calculation.
## Takes electrical and installation parameters, looks up baseline ampacity in the provided (or default) table,
## computes environmental and physical adjustment factors, and returns a compiled CableRatingResult.
static func calculate(electrical: CableElectricalModel, installation: CableInstallationModel, ampacity_table: IecAmpacityTable = null) -> CableRatingResult:
	var result := CableRatingResult.new()
	
	# 1. Resolve ampacity table (lazy-initialize and cache standard tables if none provided)
	if ampacity_table == null:
		if _default_table_cache == null:
			_default_table_cache = IecAmpacityTable.default_table()
		ampacity_table = _default_table_cache
		
	# 2. Look up baseline rating (Iz)
	var lookup := ampacity_table.get_base_current(
		installation.installation_method,
		electrical.material,
		electrical.insulation_type,
		electrical.cross_mm2
	)
	
	result.iz_base = lookup.value
	
	if not lookup.found:
		result.notes.append(
			"No ampacity data for method=" + installation.installation_method + 
			" material=" + electrical.material + 
			" insulation=" + electrical.insulation_type + 
			" cross=" + str(electrical.cross_mm2) + "mm² — using nearest fallback of 0A"
		)
		result.iz_final = 0.0
		result.is_valid = false
		return result
		
	if lookup.interpolated:
		result.notes.append(
			"Base current was linearly interpolated for a non-standard cross-section of " + 
			str(electrical.cross_mm2) + " mm²."
		)
		
	# 3. Compute and assign all 5 independent correction factors
	result.k1_temperature = TemperatureFactor.compute(installation, electrical)
	result.k2_grouping = GroupingFactor.compute(installation, electrical)
	result.k3_soil = SoilFactor.compute(installation, electrical)
	result.k4_harmonic = HarmonicFactor.compute(installation, electrical)
	result.k5_installation = InstallationFactor.compute(installation, electrical)
	
	# 4. Calculate final corrected ampacity (Iz_final = Iz_base * K1 * K2 * K3 * K4 * K5)
	result.iz_final = result.iz_base * result.total_correction_factor()
	result.is_valid = true
	
	return result
