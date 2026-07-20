## Pole.gd
## A passive aggregation element representing a utility pole / junction.
##
## Electrically a Pole is just a SimNode wrapper — it does not stamp
## anything into Y.  Its purpose is structural: it owns a node and can
## carry a list of attached cables / fuses / drop-lines for the game
## layer (e.g. show "this pole supplies these houses").
##
## The bridge layer (Game side) connects a Node3D pole prop to the
## logical Pole instance via ElementBridge.

class_name Pole
extends CircuitElement

var bus: SimNode
var attached_cables: Array = []     # Array[Cable]

# Damage state for storms / accidents
var fallen: bool = false

func _init(p_bus: SimNode, p_name: String = "") -> void:
	super._init(p_name)
	bus = p_bus
	terminals = [[bus]]

func attach_cable(c: Cable) -> void:
	if not attached_cables.has(c):
		attached_cables.append(c)

func detach_cable(c: Cable) -> void:
	attached_cables.erase(c)

# When a pole falls, all attached cables are damaged.
func collapse() -> void:
	fallen = true
	for c in attached_cables:
		c.damage()
	mark_dirty()

func restore() -> void:
	fallen = false
	for c in attached_cables:
		c.repair()
	mark_dirty()
