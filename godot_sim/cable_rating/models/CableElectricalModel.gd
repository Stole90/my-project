## CableElectricalModel.gd
## Configuration resource holding the electrical properties of a cable.
##
## This resource describes only the physical/electrical characteristics of the
## conductor and insulation, independent of where or how the cable is installed.
## It is designed to be saved as a .tres asset, configured via the Inspector,
## and shared between Cable instances.

class_name CableElectricalModel
extends Resource

## Conductor material: "copper" or "aluminium".
@export var material: String = "copper"

## Insulation material type: "pvc", "xlpe", or "epr" (future-ready for alternative limits).
@export var insulation_type: String = "pvc"

## Cross-sectional area of the conductor in square millimetres [mm²].
@export var cross_mm2: float = 4.0

## Total physical length of the cable in metres [m].
@export var length_m: float = 10.0

## Number of physical cores/conductors inside the cable (future-ready).
@export var num_cores: int = 1

## Conductor DC resistance in ohms [Ω]. If set to 0.0, the actual resistance
## will be derived elsewhere using material resistivity, length, and cross-section.
@export var conductor_resistance_ohm: float = 0.0

## Conductor reactance in ohms [Ω] at the network frequency (future-ready).
@export var conductor_reactance_ohm: float = 0.0
