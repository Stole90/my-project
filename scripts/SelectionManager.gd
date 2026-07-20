# res://scripts/SelectionManager.gd
class_name SelectionManager
extends Node

signal element_selected(appliance: BaseAppliance)
signal element_deselected

var selected: BaseAppliance = null

# Poziva World kad aparat bude kliknut
func select(appliance: BaseAppliance) -> void:
    if selected == appliance:
        return
    selected = appliance
    emit_signal("element_selected", appliance)

# Poziva World kad se klikne na prazan prostor
func deselect() -> void:
    if selected == null:
        return
    selected = null
    emit_signal("element_deselected")

func has_selection() -> bool:
    return selected != null
