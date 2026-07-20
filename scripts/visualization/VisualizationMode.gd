## VisualizationMode.gd
## Abstract base class for all visualization modes.
##
## A mode is responsible for mapping simulation data (current, voltage,
## temperature, power…) to colors. It never touches the solver, model,
## or any sim element directly — it reads only the cached `vis_*` fields
## on bridges and the public properties on sim elements exposed by the node.
##
## To add a new mode:
##   1. Extend VisualizationMode.
##   2. Override the methods you need (at minimum get_cable_color / get_3ph_cable_colors).
##   3. Register the instance in VisualizationManager._build_modes().
##   4. Done — no other files need to change.

class_name VisualizationMode
extends RefCounted

## Human-readable identifier shown in UI (e.g. "Normalan prikaz").
var display_name: String = "Mode"

## Machine-readable key used by VisualizationManager.set_mode().
var mode_id: StringName = &""

# ── Cable colors ─────────────────────────────────────────────────────────────

## Return the single color to use for the whole single-phase cable line.
## `cable_node` is a CableNode; read bridge and sim_cable from it.
func get_cable_color(_cable_node: Node2D) -> Color:
	return Color(0.5, 0.5, 0.5)

## Return per-wire colors for a three-phase cable: [L1, L2, L3] (+ N if has_neutral).
## `cable_node` is a ThreePhaseCableNode.
func get_3ph_cable_colors(_cable_node: Node2D, num_lines: int) -> Array[Color]:
	var result: Array[Color] = []
	for _i in num_lines:
		result.append(Color(0.5, 0.5, 0.5))
	return result

# ── Node (component) tint ────────────────────────────────────────────────────

## Optional: return a modulate color for non-cable visual nodes
## (appliances, fuses, sources, etc.).  Return Color.WHITE to leave untouched.
## Default implementation always returns WHITE so base node _draw() runs as-is.
func get_node_modulate(_node: Node2D) -> Color:
	return Color.WHITE

# ── Helpers (shared across modes) ────────────────────────────────────────────

## Linear gradient: 0.0 → cold, 1.0 → hot (blue → green → yellow → red).
static func heat_gradient(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.33:
		return Color(0.0, 0.4, 1.0).lerp(Color(0.1, 0.9, 0.1), t / 0.33)
	elif t < 0.66:
		return Color(0.1, 0.9, 0.1).lerp(Color(1.0, 0.85, 0.0), (t - 0.33) / 0.33)
	else:
		return Color(1.0, 0.85, 0.0).lerp(Color(1.0, 0.05, 0.0), (t - 0.66) / 0.34)

## Ramp: 0.0 → green, 1.0 → red (simple two-stop gradient).
static func green_red(t: float) -> Color:
	return Color(0.1, 0.9, 0.1).lerp(Color(1.0, 0.1, 0.0), clampf(t, 0.0, 1.0))

## Ramp: 0.0 → green, 0.5 → orange, 1.0 → red (three-stop).
static func load_gradient(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return Color(0.1, 0.9, 0.1).lerp(Color(1.0, 0.55, 0.0), t * 2.0)
	else:
		return Color(1.0, 0.55, 0.0).lerp(Color(1.0, 0.05, 0.0), (t - 0.5) * 2.0)

## Safe float read from an Object property — returns default on null or missing field.
static func safe_float(obj: Object, prop: StringName, default_val: float = 0.0) -> float:
	if obj == null:
		return default_val
	var v = obj.get(prop)
	if v == null:
		return default_val
	return float(v)
