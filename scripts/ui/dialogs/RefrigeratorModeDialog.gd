# res://scripts/ui/dialogs/RefrigeratorModeDialog.gd
## Mode-selector dialog for Refrigerator.
## All UI logic lives in ModeDialog — this class is configuration only.
##
## Signals (inherited from ModeDialog):
##   mode_confirmed(mode_key: String)  — emitted on "Primeni"
##   cancelled()                       — emitted on "Otkaži"
##
## Usage:
##   fridge_dialog.mode_confirmed.connect(func(key): fridge.apply_params({"mode": key}))
##   fridge_dialog.open_for(fridge)

class_name RefrigeratorModeDialog
extends ModeDialog

func _ready() -> void:
	dialog_title = "Mod frižidera"
	modes = [
		{ "key": "off",       "label": "Isključen",     "power": "0 W",   "temp": "—"       },
		{ "key": "eco",       "label": "Eco",            "power": "80 W",  "temp": "8 °C"    },
		{ "key": "normal",    "label": "Normalan",       "power": "150 W", "temp": "4 °C"    },
		{ "key": "fast_cool", "label": "Brzo hlađenje",  "power": "250 W", "temp": "1 °C"    },
		{ "key": "freeze",    "label": "Zamrzavanje",    "power": "350 W", "temp": "-18 °C"  },
	]
	super._ready()

## Convenience: read current mode from Refrigerator and open.
func open_for(fridge: Refrigerator) -> void:
	open_with_mode(fridge.current_mode)
