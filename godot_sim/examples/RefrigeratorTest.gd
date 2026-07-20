## Refrigerator.gd
## ════════════════════════════════════════════════════════════════════
##  PRIMER 2 — POTROŠAČ KAO Node3D U SCENI
## ════════════════════════════════════════════════════════════════════
##
##  Ovo je primer kako se jedan game prop (frižider model u sceni)
##  vezuje za simulaciju preko ElementBridge sloja.
##
##  Pridruži ovaj script svom frižider Node3D-u (mesh, animacija, sve).
##  U sceni ti treba:
##
##      MeshInstance3D  "FridgeMesh"      ← vizuelni model
##      OmniLight3D     "InsideLight"     ← gori dok ima napona
##      AudioStreamPlayer3D "Hum"         ← brujanje kompresora
##      Area3D          "InteractZone"    ← igrač pritisne E za toggle
##
##  Skript NE zna ništa o solver-u. Sva komunikacija ide preko
##  ElementBridge signala.

class_name RefrigeratorTest
extends Node3D

# ── Inspector parametri (dizajner ih podešava po prop-u) ────────────
@export var rated_power_w: float   = 150.0
@export var power_factor: float    = 0.85
@export var nominal_voltage: float = 230.0
@export var inrush_factor: float   = 4.0
@export var inrush_duration_s: float = 0.2

# ── Reference na vizuelne elemente unutar scene ─────────────────────
@onready var inside_light: Node = get_node_or_null("InsideLight")
@onready var hum_audio: Node    = get_node_or_null("Hum")

# ── Logika simulacije ───────────────────────────────────────────────
var _bridge: ElementBridge
var _consumer: RatedConsumer

## Pozivamo iz "rodtelja" (npr. House.gd) odmah pošto se prop instancira.
##   bus  : SimNode na koji je frižider zakačen (npr. izlaz osigurača)
##   model: CircuitModel kuće (deli ga sa svim ostalim aparatima)
func plug_into(bus: SimNode, model: CircuitModel) -> void:
        # 1. napravi pure-sim element
        _consumer = RatedConsumer.new(
                bus, rated_power_w, power_factor, name,
                nominal_voltage, true
        )
        _consumer.inrush_factor     = inrush_factor
        _consumer.inrush_duration_s = inrush_duration_s

        # 2. ubaci ga u model
        model.add_element(_consumer)

        # 3. napravi most za scene-tree komunikaciju
        _bridge = ElementBridge.new()
        _bridge.name = "%s_Bridge" % name
        add_child(_bridge)
        _bridge.bind(_consumer, model)

        # 4. pretplati vizuelne reakcije na bridge signale
        _bridge.voltage_changed.connect(_on_voltage_changed)
        _bridge.state_changed.connect(_on_state_changed)
        _bridge.damaged.connect(_on_damaged)

# ── Reakcije na simulaciju ──────────────────────────────────────────

func _on_voltage_changed(magnitude_v: float, _phase_deg: float) -> void:
        # Sijalica unutar frižidera → intenzitet ide sa naponom.
        if inside_light:
                inside_light.light_energy = clampf(magnitude_v / nominal_voltage, 0.0, 1.2)
        # Brujanje kompresora samo dok je radan i ima napona.
        if hum_audio:
                if magnitude_v > nominal_voltage * 0.5 and _consumer.enabled:
                        if not hum_audio.playing: hum_audio.play()
                else:
                        hum_audio.stop()

func _on_state_changed(new_state: String) -> void:
        match new_state:
                Consumer.STATE_NORMAL:
                        modulate_visual(Color.WHITE)
                Consumer.STATE_OFF:
                        modulate_visual(Color(0.6, 0.6, 0.6))
                Consumer.STATE_TRIPPED_UV:
                        modulate_visual(Color(0.4, 0.4, 0.8))   # plavkast = nestala struja
                Consumer.STATE_DAMAGED_OV:
                        modulate_visual(Color(0.3, 0.0, 0.0))   # spaljen

func _on_damaged() -> void:
        # ovde bi pucao particle efekat dima, alarm, itd.
        push_warning("[%s] frižider je pregoreo!" % name)

func modulate_visual(c: Color) -> void:
        var mesh: MeshInstance3D = get_node_or_null("FridgeMesh")
        if mesh and mesh.material_override:
                mesh.material_override.albedo_color = c

# ── Igračeve interakcije ────────────────────────────────────────────
##  Pozovi ovo iz svog interakcijskog sistema (npr. raycast + E key).
func interact() -> void:
        if _bridge: _bridge.interact_toggle()

func repair() -> void:
        if _bridge: _bridge.interact_repair()
