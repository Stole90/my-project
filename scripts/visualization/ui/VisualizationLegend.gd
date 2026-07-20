## VisualizationLegend.gd
## Draws a color-scale legend for the active visualization mode.
## Place next to or below the VisualizationModeSelector in the HUD.
##
## The legend redraws itself whenever the mode changes.
## Each mode exposes its scale entries via get_legend_entries() — if a mode
## does not override that method this panel shows nothing (Normal mode hides it).

class_name VisualizationLegend
extends Control

## Width of the gradient swatch in pixels.
@export var swatch_width:  int = 160
## Height of the gradient swatch.
@export var swatch_height: int = 16
## Space between entries.
@export var row_gap:       int = 4

var _font: Font = null

func _ready() -> void:
    _font = ThemeDB.fallback_font
    custom_minimum_size = Vector2(swatch_width + 80, 0)

    #if Engine.has_singleton("VisualizationManager"):
    VisualizationManager.mode_changed.connect(_on_mode_changed)

    queue_redraw()

func _on_mode_changed(_id: StringName) -> void:
    queue_redraw()

func _draw() -> void:
    #if not Engine.has_singleton("VisualizationManager"):
        #return

    var mode_id: StringName = VisualizationManager.get_active_mode_id()

    # Only show legend for overlay modes — Normal mode needs no legend
    # because the existing InfoPanel already shows raw values.
    if mode_id == &"normal":
        return

    match mode_id:
        &"current":       _draw_gradient_legend("Iskorištenost struje", _current_stops())
        &"thermal":       _draw_gradient_legend("Temperatura", _thermal_stops())
        &"voltage_drop":  _draw_gradient_legend("Pad napona", _vdrop_stops())
        &"power_loss":    _draw_gradient_legend("Gubici (I²R)", _ploss_stops())

# ── Gradient drawing ──────────────────────────────────────────────────────────

func _draw_gradient_legend(title: String, stops: Array) -> void:
    ## stops: Array of [float_position_0_to_1, Color, String_label]
    ## The swatch is drawn as a sequence of filled rectangles blended between stops.

    var y: int = 2
    # Title
    draw_string(_font, Vector2(0, y + 12), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
    y += 18

    # Gradient swatch
    var segments: int = swatch_width
    for px in segments:
        var t: float = float(px) / float(segments - 1)
        var col: Color = _eval_stops(stops, t)
        draw_line(Vector2(px, y), Vector2(px, y + swatch_height), col, 1.0)

    # Min / max labels
    if stops.size() >= 2:
        var label_min: String = stops[0][2]
        var label_max: String = stops[stops.size() - 1][2]
        draw_string(_font, Vector2(0, y + swatch_height + 13),
            label_min, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.85, 0.85))
        draw_string(_font, Vector2(swatch_width - 60, y + swatch_height + 13),
            label_max, HORIZONTAL_ALIGNMENT_RIGHT, -1, 11, Color(0.85, 0.85, 0.85))
        custom_minimum_size.y = float(y + swatch_height + 28)

static func _eval_stops(stops: Array, t: float) -> Color:
    if stops.is_empty():
        return Color.WHITE
    if t <= float(stops[0][0]):
        return stops[0][1]
    if t >= float(stops[stops.size() - 1][0]):
        return stops[stops.size() - 1][1]
    for i in range(stops.size() - 1):
        var t0: float = float(stops[i][0])
        var t1: float = float(stops[i + 1][0])
        if t >= t0 and t <= t1:
            var f: float = (t - t0) / maxf(t1 - t0, 0.0001)
            return stops[i][1].lerp(stops[i + 1][1], f)
    return Color.WHITE

# ── Stop definitions (must match the actual mode color functions) ─────────────

static func _current_stops() -> Array:
    return [
        [0.00, Color(0.1, 0.3, 0.9),  "0 %"],
        [0.50, Color(0.1, 0.9, 0.1),  "50 %"],
        [0.80, Color(1.0, 0.85, 0.0), "80 %"],
        [1.00, Color(1.0, 0.0, 0.0),  "100 %+"],
    ]

static func _thermal_stops() -> Array:
    return [
        [0.00, Color(0.45, 0.55, 0.75), "≤25 °C"],
        [0.33, Color(0.1, 0.9, 0.1),    "45 °C"],
        [0.66, Color(1.0, 0.85, 0.0),   "70 °C"],
        [1.00, Color(1.0, 0.05, 0.0),   "≥90 °C"],
    ]

static func _vdrop_stops() -> Array:
    return [
        [0.000, Color(0.1, 0.9, 0.1),  "0 %"],
        [0.030, Color(1.0, 0.85, 0.0), "3 %"],
        [0.050, Color(1.0, 0.45, 0.0), "5 %"],
        [0.100, Color(1.0, 0.0, 0.0),  "≥10 %"],
    ]

static func _ploss_stops() -> Array:
    return [
        [0.00, Color(0.1, 0.9, 0.1),  "0 W"],
        [0.20, Color(1.0, 0.85, 0.0), "50 W"],
        [0.60, Color(1.0, 0.45, 0.0), "200 W"],
        [1.00, Color(1.0, 0.0, 0.0),  "≥500 W"],
    ]
