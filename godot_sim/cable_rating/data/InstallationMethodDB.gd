## InstallationMethodDB.gd
## Centralized database of IEC 60364-5-52 reference installation methods.
##
## This class manages the construction and caching of the standard 10 installation methods (A1 to G).
## It avoids hardcoding in the calculation engines by acting as a single source of truth for method properties.

class_name InstallationMethodDB
extends RefCounted

static var _methods_cache: Dictionary = {}

## Returns the cached InstallationMethod matching the given code.
## If the code is unknown, pushes a warning and returns the default "A1" installation method.
static func get_method(code: String) -> InstallationMethod:
	_ensure_cache_loaded()
	if _methods_cache.has(code):
		return _methods_cache[code]
	
	push_warning("Unknown installation method code: '" + code + "'. Falling back to default 'A1'.")
	return _methods_cache["A1"]

## Returns an array of all standard installation method codes.
static func all_codes() -> Array[String]:
	return ["A1", "A2", "B1", "B2", "C", "D1", "D2", "E", "F", "G"]

## Returns an array of all standard InstallationMethod resources.
static func all_methods() -> Array[InstallationMethod]:
	_ensure_cache_loaded()
	var methods: Array[InstallationMethod] = []
	for code in all_codes():
		methods.append(_methods_cache[code])
	return methods

# Internal helper to initialize the static database of installation methods.
static func _ensure_cache_loaded() -> void:
	if not _methods_cache.is_empty():
		return
	
	for code in all_codes():
		var method := InstallationMethod.new()
		method.method_code = code
		
		match code:
			"A1":
				method.display_name = "Insulated conductors in conduit in thermally insulated wall"
				method.is_air_installation = true
				method.is_conduit = true
				method.is_buried = false
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Extremely restricted cooling inside insulated wall cavity"
			"A2":
				method.display_name = "Multicore cable in conduit in thermally insulated wall"
				method.is_air_installation = true
				method.is_conduit = true
				method.is_buried = false
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Restricted cooling for multicore cable inside insulated wall"
			"B1":
				method.display_name = "Insulated conductors in conduit on a wall"
				method.is_air_installation = true
				method.is_conduit = true
				method.is_buried = false
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Conductors inside conduit, protected from direct air flow"
			"B2":
				method.display_name = "Multicore cable in conduit on a wall"
				method.is_air_installation = true
				method.is_conduit = true
				method.is_buried = false
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Multicore cable in protective surface conduit"
			"C":
				method.display_name = "Directly clipped to a wall / free air"
				method.is_air_installation = true
				method.is_conduit = false
				method.is_buried = false
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Baseline open-air cooling, mounted flush on a wall surface"
			"D1":
				method.display_name = "Buried in ducts in the ground"
				method.is_air_installation = false
				method.is_conduit = true
				method.is_buried = true
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Moderate underground cooling, air gap inside protective duct"
			"D2":
				method.display_name = "Buried directly in the ground"
				method.is_air_installation = false
				method.is_conduit = false
				method.is_buried = true
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Direct contact with soil provides highly effective heat sink"
			"E":
				method.display_name = "Multicore cable in free air"
				method.is_air_installation = true
				method.is_conduit = false
				method.is_buried = false
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Excellent cooling on open trays, ladders, or brackets"
			"F":
				method.display_name = "Single-core cables touching in free air"
				method.is_air_installation = true
				method.is_conduit = false
				method.is_buried = false
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Clipped single-core conductors in close contact with each other"
			"G":
				method.display_name = "Single-core cables spaced in free air"
				method.is_air_installation = true
				method.is_conduit = false
				method.is_buried = false
				method.reference_ambient_c = 30.0
				method.reference_soil_c = 20.0
				method.reference_soil_resistivity = 2.5
				method.cooling_description = "Maximum free-air cooling with physical spacing between conductors"
		
		_methods_cache[code] = method
