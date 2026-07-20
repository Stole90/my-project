# Primeri — kako se potrošač povezuje sa simulacijom

Tri kompletna, run-able primera. Idu od najprostijeg ka najrealnijem.

---

## Primer 1 — `example_single_consumer.gd`  (HEADLESS, bez scene)

Najjednostavniji put. Sve se dešava u jednom statičkom `run()`.

**Scenario:** trafostanica → 80 m kabla → osigurač 16 A → frižider (150 W, pf=0.85, induktivni).

Pokazuje:
- pravljenje čvorova i elemenata,
- dodavanje u `CircuitModel`,
- pretplatu na sve signale (`solved`, `cable_overloaded`, `consumer_tripped`, `fuse_blew`, …),
- prvi `solve()` i čitanje rezultata,
- runtime promene: `disable()`, `enable()` (sa inrush-om), `damage()`, `repair()`,
- automatski `solve_if_dirty()` short-circuit.

**Kako pokrenuti:**

```gdscript
extends Node
const Example1 = preload("res://godot_sim/examples/example_single_consumer.gd")

func _ready() -> void:
    Example1.run()
```

Sve ide u Output panel. Nikakva scena nije potrebna.

---

## Primer 2 — `Refrigerator.gd`  (Node3D + ElementBridge)

Frižider kao pravi prop u sceni: vizuelno reaguje na simulaciju
(unutrašnja sijalica gori dok ima napon, brujanje kompresora staje
kad nema struje, materijal pocrni ako pregori).

**Šta zna a šta ne zna:**
- ZNA: kako da prikaže sebe i da pošalje "interact" igraču,
- NE ZNA: ništa o solver-u, Y-bus matricama, kompleksnim brojevima.

Sva komunikacija ide preko `ElementBridge`-a, koji emituje Godot signale.

**Hijerarhija scene:**

```
Refrigerator (Node3D, attach Refrigerator.gd)
├── FridgeMesh        (MeshInstance3D)
├── InsideLight       (OmniLight3D)
├── Hum               (AudioStreamPlayer3D)
└── InteractZone      (Area3D + CollisionShape3D)
```

**Inspector parametri:**
- `rated_power_w` (default 150)
- `power_factor`  (default 0.85)
- `inrush_factor` / `inrush_duration_s`

Igrač pritisne E → tvoj interact sistem zove `refrigerator.interact()`.

---

## Primer 3 — `House.gd`  (kompletna kuća sa više aparata)

Sklapa celu kuću kao jedan `CircuitModel`:

```
mreža (230V) → dovod (kabl) → glavni osigurač → razvodna šina
                                                     ├── Refrigerator
                                                     ├── Boiler
                                                     ├── Lamp
                                                     └── …
```

**Konvencija:** svaki child Node3D koji ima metodu `plug_into(bus, model)`
automatski se kači na razvodnu šinu kuće. To znači da nove aparate dodaješ
samo tako što ih instanciraš kao decu kuće — nikakvog koda u House.gd
više ne treba menjati.

```gdscript
# bilo koji aparat treba samo:
func plug_into(bus: SimNode, model: CircuitModel) -> void:
    var c := RatedConsumer.new(bus, ...)
    model.add_element(c)
    var bridge := ElementBridge.new()
    add_child(bridge)
    bridge.bind(c, model)
```

---

## Globalni driver — `CircuitWorld` autoload

Da `solve_if_dirty()` ne moraš ručno da zoveš svakog frame-a, registruj
`CircuitWorld` kao autoload:

1. **Project Settings → Autoload**
   - Path: `res://godot_sim/interface/CircuitWorld.gd`
   - Node Name: `CircuitWorld`
   - Singleton: ✅

2. U `House.gd` (ili bilo gde) samo dodaj svoj model:

   ```gdscript
   CircuitWorld.add_model(model)
   ```

`CircuitWorld._physics_process()` automatski poziva `solve_if_dirty()`
za sve registrovane modele svakog frame-a. Solve se realno izvršava samo
ako se nešto promenilo (zahvaljujući element-level dirty flag-u) — tako da
je u mirnoj kući trošak ~0.

Da pređeš na transient režim (vremenski integrisanje, za inrush /
prelazne pojave): `CircuitWorld.transient_mode = true`.

---

## Sažetak — ko šta radi

| Sloj           | Klasa                       | Odgovornost                                        |
| -------------- | --------------------------- | -------------------------------------------------- |
| **Simulation** | `RatedConsumer`             | čista fizika potrošača (Z, I, P, Q, state)         |
| **Simulation** | `CircuitModel` + `YBusSolver` | topologija, dirty flag, numerika                  |
| **Interface**  | `ElementBridge` (Node3D)    | "prevodi" između elementa i scene tree-a          |
| **Interface**  | `CircuitWorld` (autoload)   | pumpa solve_if_dirty() svaki frame                |
| **Game**       | `Refrigerator.gd` (Node3D)  | mesh, svetlo, zvuk, interakcija sa igračem        |
| **Game**       | `House.gd` (Node3D)         | sklapa topologiju kuće, kači sve aparate na šinu  |
