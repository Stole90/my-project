# res://scripts/ui/dialogs/BoilerModeDialog.gd
## Mode-selector dialog for Boiler.
## All UI logic lives in ModeDialog — this class is configuration only.
##
## Signals (inherited from ModeDialog):
##   mode_confirmed(mode_key: String)  — emitted on "Primeni"
##   cancelled()                       — emitted on "Otkaži"
##
## Usage:
##   boiler_dialog.mode_confirmed.connect(func(key): boiler.apply_params({"mode": key}))
##   boiler_dialog.open_for(boiler)

class_name BoilerModeDialog
extends ModeDialog

func _ready() -> void:
	dialog_title = "Mod bojlera"
	modes = [
		{ "key": "off",    "label": "Isključen",        "power": "0 W",    "temp": "—"      },
		{ "key": "eco",    "label": "Ekonomičan",        "power": "1000 W", "temp": "45 °C"  },
		{ "key": "normal", "label": "Normalan",          "power": "2000 W", "temp": "60 °C"  },
		{ "key": "boost",  "label": "Brzo zagrevanje",   "power": "3000 W", "temp": "75 °C"  },
	]
	super._ready()

## Convenience: read current mode from Boiler and open.
func open_for(boiler: Boiler) -> void:
	open_with_mode(boiler.current_mode)
