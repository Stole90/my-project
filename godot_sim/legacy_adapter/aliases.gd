## legacy_adapter/aliases.gd
## Re-exports old class names so existing code keeps compiling.
##
## Add this to your project as an autoload (or just preload it once)
## to get back: Source, Load, RatedLoad, InductiveLoad, CapacitiveLoad,
## ConstantPowerLoad, Network — all forwarded to the new classes.
##
## This file is purely a typedef bag — do not put logic here.

extends RefCounted

const Source             = preload("res://godot_sim/simulation/elements/VoltageSource.gd")
const Load               = preload("res://godot_sim/simulation/elements/Consumer.gd")
const RatedLoad          = preload("res://godot_sim/simulation/elements/RatedConsumer.gd")
const InductiveLoad      = preload("res://godot_sim/simulation/elements/InductiveConsumer.gd")
const CapacitiveLoad     = preload("res://godot_sim/simulation/elements/CapacitiveConsumer.gd")
const ConstantPowerLoad  = preload("res://godot_sim/simulation/elements/ConstantPowerConsumer.gd")
const Network            = preload("res://godot_sim/legacy_adapter/Network.gd")
