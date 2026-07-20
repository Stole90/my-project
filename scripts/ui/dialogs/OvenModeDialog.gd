# res://scripts/ui/dialogs/OvenModeDialog.gd
## Mode-selector dialog for ThreePhaseOvenNode.
## All UI logic lives in ModeDialog — this class is configuration only.
##
## Signals (inherited from ModeDialog):
##   mode_confirmed(mode_key: String)  — emitted on "Primeni"
##   cancelled()                       — emitted on "Otkaži"
##
## Usage:
##   oven_dialog.mode_confirmed.connect(func(key): oven.apply_params({"cook_mode": key}))
##   oven_dialog.open_for(oven)

class_name OvenModeDialog
extends ModeDialog

func _ready() -> void:
	dialog_title = "Mod pećnice"
	column_widths = [120, 70, 70]
	modes = [
		{ "key": "off",     "label": "Isključena",  "power": "0 W",    "temp": "—"       },
		{ "key": "preheat", "label": "Zagrevanje",  "power": "1200 W", "temp": "180 °C"  },
		{ "key": "bake",    "label": "Pečenje",     "power": "2000 W", "temp": "200 °C"  },
		{ "key": "grill",   "label": "Grill",       "power": "2800 W", "temp": "250 °C"  },
		{ "key": "broil",   "label": "Broil",       "power": "3200 W", "temp": "280 °C"  },
	]
	super._ready()

## Convenience: read current cook mode from oven and open.
func open_for(oven: ThreePhaseOvenNode) -> void:
	var current: String = oven._oven.cook_mode if oven._oven else "off"
	open_with_mode(current)
