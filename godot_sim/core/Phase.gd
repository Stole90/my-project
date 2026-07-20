## Phase.gd
## Three-phase support primitive — 5-conductor AC system.
##
## Single-phase elements use [Phase.L1] (or [Phase.NEUTRAL] for return).
## Three-phase elements use [L1, L2, L3] or [L1, L2, L3, NEUTRAL].
## Full 5-conductor elements also include PE (protective earth).
##
## A "terminal" of a three-phase element therefore is NOT a single SimNode
## but a small array of SimNodes — one per phase.  This file centralises
## the conventions so individual elements stay short and readable.

class_name Phase
extends RefCounted

enum {
	L1      = 0,
	L2      = 1,
	L3      = 2,
	NEUTRAL = 3,
	PE      = 4,
}

const NAMES: Array = ["L1", "L2", "L3", "N", "PE"]

## Default reference angle (radians) for a balanced 3-phase source.
## Only L1/L2/L3 have meaningful angles; N and PE return 0.
static func reference_angle_rad(phase_id: int) -> float:
	if phase_id < 0 or phase_id >= SimConstants.PHASE_ANGLE_RAD.size():
		return 0.0
	return SimConstants.PHASE_ANGLE_RAD[phase_id]

static func name_of(phase_id: int) -> String:
	if phase_id < 0 or phase_id >= NAMES.size():
		return "?"
	return NAMES[phase_id]

## All five conductor indices — used when iterating the full 5N matrix.
static func all_conductors() -> Array:
	return [L1, L2, L3, NEUTRAL, PE]

## The three line conductors only.
static func line_conductors() -> Array:
	return [L1, L2, L3]
