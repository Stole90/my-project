# res://scripts/ui/base/BasePanel.gd
## Reusable base for all floating UI panels.
## Subclass this for any panel that needs open / close / periodic-refresh.
##
## Usage:
##   class_name MyPanel extends BasePanel
##   func _build_content(container: VBoxContainer) -> void:
##       # build your widgets here
##   func _on_refresh() -> void:
##       # called every refresh_interval while visible

class_name BasePanel
extends PanelContainer

## Emitted when the panel is closed (via close() or an internal ✕ button).
signal panel_closed()

# ── Timing ────────────────────────────────────────────────────────────────────

## Seconds between _on_refresh() calls while visible.
## 0.1 matches the 10 Hz simulation solve rate.
@export var refresh_interval: float = 0.1

var _refresh_timer: float = 0.0

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_theme_constant_override("margin_left",   12)
	margin.add_theme_constant_override("margin_right",  12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_build_content(vbox)

## Override: build widgets into `container` once.
func _build_content(_container: VBoxContainer) -> void:
	pass

## Override: update displayed values; called every refresh_interval while visible.
func _on_refresh() -> void:
	pass

# ── Open / Close API ──────────────────────────────────────────────────────────

func open() -> void:
	visible = true
	_refresh_timer = 0.0
	_on_refresh()

func close() -> void:
	visible = false
	emit_signal("panel_closed")

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer >= refresh_interval:
		_refresh_timer = 0.0
		_on_refresh()
