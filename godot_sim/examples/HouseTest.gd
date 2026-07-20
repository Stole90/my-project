## House.gd
## ════════════════════════════════════════════════════════════════════
##  PRIMER 3 — KUĆA SA VIŠE APARATA NA JEDNOM CircuitWorld-u
## ════════════════════════════════════════════════════════════════════
##
##  Sklapa kompletnu kuću:
##     mreža → trafostanica → kabl → glavni osigurač → razvodna kutija
##                                                         ├── frižider
##                                                         ├── bojler
##                                                         └── sijalica
##
##  Stavi ovaj script na rodtelj Node3D ("House") u sceni.
##  CircuitWorld autoload (vidi README) automatski okida solve_if_dirty()
##  svakog physics frame-a.

class_name HouseTest
extends Node3D

@export var grid_voltage_v: float    = 230.0
@export var grid_phase_deg: float    = 0.0
@export var feeder_length_m: float   = 80.0
@export var feeder_cross_mm2: float  = 4.0
@export var main_breaker_a: float    = 25.0

var model: CircuitModel
var grid_bus: SimNode
var house_bus: SimNode
var dist_bus: SimNode

func _ready() -> void:
        # 1. CircuitModel — vlasnik topologije ove kuće
        model = CircuitModel.new(name)

        # 2. Čvorovi
        grid_bus  = SimNode.new("%s_grid"   % name)
        house_bus = SimNode.new("%s_ulaz"   % name)
        dist_bus  = SimNode.new("%s_razvod" % name)

        # 3. Mreža (slack izvor)
        var src := VoltageSource.new(grid_bus, grid_voltage_v, grid_phase_deg, "%s_mreza" % name)
        model.add_element(src)

        # 4. Dovodni kabl
        var feeder := Cable.new(
                grid_bus, house_bus,
                feeder_length_m, feeder_cross_mm2,
                "copper", main_breaker_a + 5.0,
                "%s_dovod" % name
        )
        model.add_element(feeder)

        # 5. Glavni osigurač (resettable breaker)
        var main_breaker := Fuse.new(
                house_bus, dist_bus,
                main_breaker_a, true,
                "%s_glavni_B%d" % [name, int(main_breaker_a)]
        )
        model.add_element(main_breaker)

        # 6. Sve aparate iz scene zakači na razvodnu šinu.
        # Konvencija: svaki potrošač implementira plug_into(bus, model).
        for child in get_children():
                if child.has_method("plug_into"):
                        child.plug_into(dist_bus, model)

        # 7. Registruj model u svetu
        var world: CircuitWorld = get_tree().root.get_node_or_null("CircuitWorld")
        if world:
                world.add_model(model)
        else:
                # Fallback: solve sami
                model.solve()

        # 8. Logging
        model.solved.connect(func(ms: float) -> void:
                print("[%s] solved %.2f ms — totals=%s" % [name, ms, model.get_totals()]))
