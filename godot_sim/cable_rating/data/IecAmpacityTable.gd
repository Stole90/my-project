## IecAmpacityTable.gd
## Configuration resource storing the base current-carrying capacity (ampacity) tables.
##
## This table acts as a key database for looking up the baseline current (Iz) of a cable
## based on its installation method, conductor material, insulation type, and cross-sectional area.
## It is a Resource, allowing it to be edited in the inspector or saved/loaded as a .tres asset.

class_name IecAmpacityTable
extends Resource

## Nested Dictionary structure representing the ampacity lookup table:
## table[method_code (String)][material (String)][insulation_type (String)][cross_mm2_string (String)] = Iz (float, Amperes)
@export var table: Dictionary = {}

## Returns a Dictionary of lookup results: {"value": float, "found": bool, "interpolated": bool}.
##
## If the exact cross-section is missing but the method, material, and insulation exist,
## this function performs linear interpolation between the two nearest tabulated cross-sectional sizes.
## If the combination is completely missing, it returns {"value": 0.0, "found": false, "interpolated": false}.
func get_base_current(method_code: String, material: String, insulation_type: String, cross_mm2: float) -> Dictionary:
	var result := {
		"value": 0.0,
		"found": false,
		"interpolated": false
	}
	
	# 1. Normalize method code to uppercase
	var method_key := method_code.to_upper()
	if not table.has(method_key):
		return result
	var mat_dict: Dictionary = table[method_key]
	
	# 2. Normalize material to lowercase, handling alternative spelling "aluminum"
	var mat_key := material.to_lower()
	if mat_key == "aluminum":
		mat_key = "aluminium"
	if not mat_dict.has(mat_key):
		return result
	var ins_dict: Dictionary = mat_dict[mat_key]
	
	# 3. Normalize insulation type to lowercase, mapping EPR to XLPE performance curves as standard thermosetting equivalent
	var ins_key := insulation_type.to_lower()
	if not ins_dict.has(ins_key):
		if ins_key == "epr" and ins_dict.has("xlpe"):
			ins_key = "xlpe"
		else:
			return result
	var size_dict: Dictionary = ins_dict[ins_key]
	
	# 4. Extract sizes from dictionary keys and convert them to float for robust lookup/interpolation
	var sorted_sizes: Array[float] = []
	var size_to_val: Dictionary = {}
	for k in size_dict.keys():
		var f_size := float(k)
		sorted_sizes.append(f_size)
		size_to_val[f_size] = float(size_dict[k])
	
	if sorted_sizes.is_empty():
		return result
	
	sorted_sizes.sort()
	
	# 5. Check for exact (or extremely close) match
	for f_size in sorted_sizes:
		if abs(f_size - cross_mm2) < 0.01:
			result.value = size_to_val[f_size]
			result.found = true
			result.interpolated = false
			return result
	
	# 6. Check if requested cross-section is out of tabulated bounds (we do not extrapolate)
	if cross_mm2 < sorted_sizes[0] or cross_mm2 > sorted_sizes[-1]:
		return result
	
	# 7. Locate the two nearest tabulated sizes for linear interpolation
	var lower_size: float = sorted_sizes[0]
	var upper_size: float = sorted_sizes[-1]
	for i in range(sorted_sizes.size() - 1):
		if sorted_sizes[i] < cross_mm2 and sorted_sizes[i+1] > cross_mm2:
			lower_size = sorted_sizes[i]
			upper_size = sorted_sizes[i+1]
			break
	
	var lower_val: float = size_to_val[lower_size]
	var upper_val: float = size_to_val[upper_size]
	
	# 8. Apply linear interpolation
	var t := (cross_mm2 - lower_size) / (upper_size - lower_size)
	result.value = lower_val + (upper_val - lower_val) * t
	result.found = true
	result.interpolated = true
	return result

## Builds and returns a representative seed IecAmpacityTable resource.
##
## This table includes data for copper and aluminium conductors with PVC and XLPE insulations across standard
## cross-sections (1.5 to 120 mm²). It populates methods A1, B1, C, D1 as requested, and also populates methods
## A2, B2, D2, E, F, G using typical IEC-aligned coefficients relative to method C.
##
## NOTE: These are SEED / PLACEHOLDER values approximating SRPS IEC 60364-5-52.
## They should be replaced with exact tables from the official standard when available.
## The architecture isolates these changes completely to this data class.
static func default_table() -> IecAmpacityTable:
	var table_res := IecAmpacityTable.new()
	var t: Dictionary = {}
	
	var sizes := [1.5, 2.5, 4.0, 6.0, 10.0, 16.0, 25.0, 35.0, 50.0, 70.0, 95.0, 120.0]
	
	# Baseline Method C (clipped directly to wall) PVC rows
	var c_cu_pvc_vals := [16.0, 20.0, 25.0, 32.0, 50.0, 63.0, 80.0, 100.0, 125.0, 160.0, 200.0, 230.0]
	var c_al_pvc_vals := [13.0, 16.0, 20.0, 25.0, 40.0, 50.0, 63.0, 80.0, 100.0, 125.0, 160.0, 185.0]
	
	# Map baseline lists to dictionaries keyed by size strings
	var c_cu_pvc: Dictionary = {}
	var c_al_pvc: Dictionary = {}
	for i in range(sizes.size()):
		var size_str := str(sizes[i])
		c_cu_pvc[size_str] = c_cu_pvc_vals[i]
		c_al_pvc[size_str] = c_al_pvc_vals[i]
	
	# Derive XLPE insulation rows from PVC baseline (continuous 90°C rating vs 70°C rating)
	# Ratio: XLPE ≈ 1.18x of PVC as a standard physical heat tolerance improvement
	var xlpe_ratio: float = 1.18
	var c_cu_xlpe: Dictionary = {}
	var c_al_xlpe: Dictionary = {}
	for i in range(sizes.size()):
		var size_str := str(sizes[i])
		c_cu_xlpe[size_str] = round(c_cu_pvc_vals[i] * xlpe_ratio)
		c_al_xlpe[size_str] = round(c_al_pvc_vals[i] * xlpe_ratio)
	
	# Standard derating factors relative to Method C baseline:
	# A1 (conduit in insulated wall): 0.72x
	# A2 (multicore in conduit in insulated wall): 0.68x
	# B1 (insulated conductors in conduit on wall): 0.85x
	# B2 (multicore in conduit on wall): 0.80x
	# C  (direct clipped): 1.0x (Baseline)
	# D1 (buried in ground ducts): 0.80x (includes ground thermal resistance + air gap)
	# D2 (buried directly in ground): 1.10x (direct soil contact provides superior heat-sinking than open-air wall mount)
	# E  (multicore in free air): 1.05x (better convective cooling than surface clipping)
	# F  (single-core touching in free air): 1.10x (improved convective air flow)
	# G  (single-core spaced in free air): 1.25x (maximum cooling separation)
	var method_factors := {
		"A1": 0.72,
		"A2": 0.68,
		"B1": 0.85,
		"B2": 0.80,
		"C": 1.00,
		"D1": 0.80,
		"D2": 1.10,
		"E": 1.05,
		"F": 1.10,
		"G": 1.25
	}
	
	# Build table entries for all methods by scaling Method C baselines
	for method in method_factors.keys():
		var factor: float = method_factors[method]
		var cu_pvc_row: Dictionary = {}
		var al_pvc_row: Dictionary = {}
		var cu_xlpe_row: Dictionary = {}
		var al_xlpe_row: Dictionary = {}
		
		for i in range(sizes.size()):
			var size_str := str(sizes[i])
			# Calculate and round to nearest integer Amperes
			cu_pvc_row[size_str] = round(c_cu_pvc[size_str] * factor)
			al_pvc_row[size_str] = round(c_al_pvc[size_str] * factor)
			cu_xlpe_row[size_str] = round(c_cu_xlpe[size_str] * factor)
			al_xlpe_row[size_str] = round(c_al_xlpe[size_str] * factor)
		
		t[method] = {
			"copper": {
				"pvc": cu_pvc_row,
				"xlpe": cu_xlpe_row
			},
			"aluminium": {
				"pvc": al_pvc_row,
				"xlpe": al_xlpe_row
			}
		}
		
	table_res.table = t
	return table_res
