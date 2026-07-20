# godot_sim — Phase 0 Architecture

Stabilna, modularna osnova elektro-simulacije za Godot 4 / GDScript open-world projekat.
Izgrađena nad postojećim AC steady-state Y-bus rešavačem, ali tako da se sutra može proširiti
na 3-fazni sistem, transijente, kvarove, faktor snage i open-world bridge — bez velikog refaktora.

---

## 1. Izveštaj — šta je bilo, šta je promenjeno, šta je zadržano

### Šta je bilo u projektu (analiza)

Postojeći kod je solidna implementacija **AC steady-state Y-bus rešavača** (varijanta MNA bez
branch-current proširenja):

| Fajl                  | Uloga                                                                |
| --------------------- | -------------------------------------------------------------------- |
| `Complex.gd`          | Aritmetika kompleksnih brojeva (puna, dobra)                         |
| `SimNode.gd`          | Električni čvor + UUID + napon kao Complex                           |
| `Source.gd`           | Idealan naponski izvor (slack bus)                                   |
| `Cable.gd`            | Otpornost ρ·L/S, max struja, overload flag                           |
| `Load.gd`             | Apstraktni potrošač + state machine (NORMAL/OFF/TRIPPED_UV/DAMAGED_OV) |
| `RatedLoad.gd`        | Potrošač iz P i pf                                                   |
| `InductiveLoad.gd`    | Potrošač iz R i L (mH)                                               |
| `CapacitiveLoad.gd`   | Potrošač iz R i C (µF)                                               |
| `ConstantPowerLoad.gd`| P = const (računa Z iz stvarnog napona)                              |
| `Network.gd`          | Sklapa Y matricu, Gaussovo eliminisanje s pivotiranjem, signali       |
| `Example.gd`          | Demo (source → cable → cable → 2 loada)                              |

#### Šta radi dobro
- Ispravan algoritam: Y-bus + slack-row substitucija + parcijalno pivotiranje.
- Edge-triggered Godot signali (`solved`, `cable_overloaded`, `load_tripped`, `load_damaged`).
- "Ground floor" `G_FLOOR = 1e-9` na svim ne-source čvorovima — sprečava singularnu matricu kad su delovi mreže izolovani.
- Dirty flag na nivou mreže — ne računa svaki frame.
- Health-check na potrošačima (under/overvoltage state machine).
- Aktivna/reaktivna snaga, faktor snage — tačno preko `V·I*`.

#### Šta nije valjalo / ograničenja
1. **Sve hardkodovano** (`OMEGA = 2π·50` na 4 mesta, `nominal*0.85`/`*1.10`, `230 V`, `INF`…). Otežava promenu frekvencije/standarda i otežava 3-fazni rad.
2. **Nema apstraktne `CircuitElement` baze** — `Cable`, `Load` i `Source` ne dele zajednički interfejs (`stamp()`, `update_state()`). Solver mora da zna konkretne tipove.
3. **`Network.gd` je monolit** (456 linija). Topologija + stamping + Gauss + KCL + signali + print sve u jednom — ne može se zameniti solver bez prepisivanja.
4. **Dirty flag samo na nivou mreže.** Element-level dirty ne postoji — promena `cable.enabled = false` zahteva ručno `network.mark_dirty()`. Lako se zaboravi.
5. **Mrtva grana koda** u `solve()` (zakomentarisan blok ispod "Load currents").
6. **Nema bridge sloja** — Game (Node3D) i Simulation (RefCounted) bi se direktno mešali.
7. **Nema priprema za transijente** — kapacitor i induktor su samo statične impedanse, bez `v_prev` / `i_prev`.
8. **Nema 3-fazne strukture** — `voltage` je jedan `Complex`, ne mapa po fazi.
9. **Nedostaju igri-bitni elementi**: `Fuse`, `Pole`, `DistributionBox`, `Resistor` (bez nameplate), `CurrentSource`.
10. **Mali bug**: u `Source._init` izvor sam upisuje napon u čvor — ako dva izvora gađaju isti čvor, drugi tiho prepisuje prvi (validate ne hvata).

### Šta je zadržano nepromenjeno
- `Complex.gd` — netaknut, samo premešten u `core/`.
- Cela matematika Y-bus rešavača (ground-floor shunt, Gauss s pivotiranjem, slack substitucija) — **identičan algoritam**, samo izvučen u zaseban `YBusSolver`.
- State machine potrošača (NORMAL / OFF / TRIPPED_UV / DAMAGED_OV) — premešten na `Consumer`.
- Sve formule impedansi (RatedLoad, InductiveLoad, CapacitiveLoad, ConstantPowerLoad) — netaknute, samo nasleđuju `Consumer` umesto `Load`.

### Šta je promenjeno
- **Uveden 3-slojni sklop** (Simulation / Interface / Game).
- **`CircuitElement` baza** sa `stamp_ybus()`, `stamp_transient()`, `update_state()`, `supports_transient()`.
- **`CircuitModel`** zamenjuje `Network` — drži samo topologiju i emituje signale, NE računa.
- **`CircuitSolver` interfejs**, sa dve implementacije: `YBusSolver` (Phase 0) i `TransientSolver` (skeleton + radi za pasivne RLC).
- **`SimNode` proširen** na više faza (`voltages_by_phase`), uz backward-compat getter `voltage` koji vraća L1.
- **Element-level dirty flag** — promena bilo kog elementa automatski okida re-solve.
- **Hardkodovane vrednosti centralizovane** u `SimConstants.gd` i `Phase.gd`.
- **Preimenovanja**: `Source` → `VoltageSource`, `Load` → `Consumer`, `*Load` → `*Consumer` (kraće, jasnije, ne sudara se sa Godot `Load`).
- **Legacy adapter** (`legacy_adapter/Network.gd` + `aliases.gd`) — stari kod nastavlja da radi bez izmene.

### Šta NIJE implementirano (svesno — pripremljeno za sledeće faze)
| Funkcija | Status |
| --- | --- |
| 3-fazni Y-bus solver (3 zasebne ili spojena 3N×3N matrica) | API spreman (`Phase`, `voltages_by_phase`, `phase_count()`), solver radi samo L1 |
| Newton iteracija za nelinearne elemente | nije |
| Adaptivni Δt za transijente | nije |
| Inrush companion model za motore | `inrush_factor` + `inrush_duration_s` polja stoje, koristi ih Y-bus stamping |
| Generator sa ograničenom snagom (`TYPE_GENERATOR`) | enum + polja postoje, solver ga tretira kao slack |
| Šum/varijabilni izvor (`TYPE_NOISY`) | enum + polja postoje, nema noise injekcije po koraku |
| Long-line shunt kapacitivnost | `Cable.reactance_per_m` postoji, šant ne |
| Serijalizacija mreže (save/load) | nije, ali `id`/`element_name` postoje |

---

## 2. Struktura fajlova

```
godot_sim/
├── README.md                          ← ovaj izveštaj
├── core/
│   ├── Complex.gd                     ← preserved
│   ├── SimConstants.gd                ← ω, defaults, voltage envelope
│   └── Phase.gd                       ← L1 / L2 / L3 / NEUTRAL
│
├── simulation/                        ← BEZ Godot UI/scene zavisnosti
│   ├── SimNode.gd                     ← multi-phase ready bus
│   ├── CircuitModel.gd                ← topology + dirty + signals
│   ├── solver/
│   │   ├── CircuitSolver.gd           ← apstraktna baza + Gauss helper
│   │   ├── YBusSolver.gd              ← steady-state AC (Phase 0)
│   │   └── TransientSolver.gd         ← backward-Euler skeleton
│   └── elements/
│       ├── CircuitElement.gd          ← apstraktna baza
│       ├── Resistor.gd
│       ├── Capacitor.gd               ← transient-ready
│       ├── Inductor.gd                ← transient-ready
│       ├── VoltageSource.gd           ← idealni / Thevenin / generator / noisy (skeleton)
│       ├── CurrentSource.gd
│       ├── Cable.gd                   ← R + opciono X po metru, damaged/aging
│       ├── Consumer.gd                ← state machine + inrush + health-check
│       ├── RatedConsumer.gd           ← P, pf
│       ├── InductiveConsumer.gd       ← R, L (mH)
│       ├── CapacitiveConsumer.gd      ← R, C (µF)
│       ├── ConstantPowerConsumer.gd   ← P = const, Z iz stvarnog napona
│       ├── Fuse.gd                    ← auto-blow + reset/replace
│       ├── Pole.gd                    ← agregat: bus + lista kablova
│       └── DistributionBox.gd         ← agregat: bus + lista osigurača
│
├── interface/                         ← BRIDGE: Sim ↔ Game
│   ├── ElementBridge.gd               ← Node3D wrapper za bilo koji element
│   └── CircuitWorld.gd                ← Node, vozi solve_if_dirty() svakog frame-a
│
├── debug/
│   ├── NetworkPrinter.gd              ← lepo printanje
│   └── headless_test.gd               ← jedan entry-point, bez UI
│
├── tests/
│   ├── test_basic.gd                  ← rekonstrukcija originalnog Example
│   ├── test_dirty.gd                  ← provera dirty propagacije
│   └── test_fuse_trip.gd              ← osigurač pregori → load se izoluje
│
└── legacy_adapter/
	├── Network.gd                     ← stara API površina nad CircuitModel
	└── aliases.gd                     ← Source/Load/RatedLoad/... = novi nazivi
```

---

## 3. Glavne klase i njihova uloga

### Simulation Layer (čista logika, nema Godot UI)

| Klasa | Uloga |
| --- | --- |
| **`CircuitElement`** | Apstraktna baza svih elemenata. Definiše ugovor: `stamp_ybus`, `stamp_transient`, `update_state`, `supports_transient`, `terminals`, `enabled`, `dirty`, `iter_nodes()`. |
| **`SimNode`** | Električni čvor. Drži `voltages_by_phase` (Dictionary po fazi). Backward-compat getter `voltage` vraća L1. |
| **`CircuitModel`** | Vlasnik topologije (`elements`, `nodes`, `sources`). Drži dirty flag, delegira numeriku `solver`-u, emituje edge-triggered signale (`solved`, `cable_overloaded`, `consumer_tripped`, `consumer_damaged`, `fuse_blew`). NE računa ništa sam. |
| **`CircuitSolver`** | Apstraktna baza solvera + zajednički Gauss helper i kreatori matrica. |
| **`YBusSolver`** | Identičan algoritam kao stari `Network.solve()`, ali polimorfan: nikad ne ispituje konkretne tipove elemenata, samo zove `stamp_ybus`/`update_state`. **Plug-and-play** za nove elemente. |
| **`TransientSolver`** | Backward-Euler skeleton. Funkcionalan za pasivne RLC mreže (Capacitor i Inductor već imaju companion model). |

### Konkretni elementi

- `Resistor`, `Capacitor`, `Inductor`, `VoltageSource`, `CurrentSource` — generičke MNA primitive.
- `Cable`, `Consumer` (+ 4 podtipa), `Fuse`, `Pole`, `DistributionBox` — game-orijentisani elementi.

### Interface Layer (most ka Godot scene-tree)

| Klasa | Uloga |
| --- | --- |
| **`ElementBridge`** (`Node3D`) | Lepi se na bilo koji vizuelni prop u sceni. `bind(element, model)` → emituje `voltage_changed`, `current_changed`, `state_changed`, `damaged`. Igrački pozivi (`interact_toggle`, `interact_repair`) ne pristupaju modelu direktno. |
| **`CircuitWorld`** (`Node`) | Top-level orchestrator. `_physics_process()` poziva `solve_if_dirty()` za sve registrovane modele. Prebacivanje između steady-state i transient režima jednim flag-om. |

### Debug / test

- `NetworkPrinter` — formatirani print mreže.
- `HeadlessTest.run_all()` — pokreće sve `tests/*.gd` bez ikakve UI.

### Legacy

- `LegacyNetwork` + `aliases.gd` → stari `Source`/`Load`/`Network` nazivi nastavljaju da rade.

---

## 4. Šta je spremno za sledeću fazu

✅ **Polimorfan solver** — dodavanje novog elementa = jedan novi fajl koji nasleđuje `CircuitElement` i implementira `stamp_ybus()`. Solver ne treba menjati.
✅ **Element-level dirty** — bilo koja promena (`cable.disable()`, `fuse.blown = true`, `consumer.enable()`) automatski markira element kao prljav, a `solve_if_dirty()` to detektuje.
✅ **Game-Sim odvojenost** — cela `simulation/` može da se pokrene head-less u testovima ili na serveru.
✅ **Pripremljen 3-fazni model** — `Phase` enum, `voltages_by_phase`, `terminals = Array[Array[SimNode]]`. Aktiviranje = nasledjivanje 3-faznog `Cable3P`/`Source3P` sa drugačijim `stamp_ybus()`.
✅ **Pripremljeni transijenti** — `stamp_transient()` već implementiran za R/L/C; `TransientSolver` radi za pasivne RLC.
✅ **Pripremljen inrush** — `Consumer.inrush_factor` i `_inrush_remaining_s` postoje, koristi ih Y-bus stamping; treba samo `enable()` da pokrene window.
✅ **Pripremljeni izvori** — `VoltageSource.source_type` enum (ideal/thevenin/generator/noisy) + polja `internal_resistance_ohm`, `current_limit_a`, `noise_amplitude`. Solver ih trenutno tretira kao ideal slack; switch na različit režim je metoda više.
✅ **Faktor snage** — već radi (kompleksne impedanse u Consumer subklasama).
✅ **Gubici u kablovima** — već radi (`Cable.resistance() = ρ·L/S·age`).

## 5. Šta još NIJE implementirano (ali je pripremljeno)

| Šta | Šta nedostaje da postane funkcionalno |
| --- | --- |
| Pravi 3-fazni solver | Implementirati `ThreePhaseYBusSolver` koji indeksira `(node, phase)` parove → 3N×3N matrica; ostatak arhitekture ne treba menjati. |
| Newton-Raphson za nelinearne elemente | Dodati `iter_solve()` u `CircuitSolver` koji zove `update_state()` u petlji dok se ne konvergira. |
| Generator sa ograničenom snagom | U `YBusSolver`: ako `src.source_type == TYPE_GENERATOR` i `|I_src| > current_limit`, prebaciti taj čvor iz slack u PQ režim i re-solvati. |
| Šumni izvor | Pre svakog solve-a: `src.set_voltage(rms + randf_range(-noise, +noise), …)`. |
| Šant kapacitivnost dugačkih vodova | Dodati `Cable.shunt_capacitance_per_m`, u `stamp_ybus()` šantovati `jωC/2` na oba terminala (PI model). |
| Save/load topologije | Iskoristiti postojeće `id` i `element_name`; serijalizovati `elements` listu u JSON. |
| Open-world LOD | `CircuitWorld` može držati više `CircuitModel`-a; daleki regioni mogu se "smrznuti" tako što se njihov model isključi iz frame loop-a. |

---

## 6. Kompatibilnost sa postojećim kodom

Ako u Godot projektu već imaš kod koji koristi stare nazive (`Source`, `Load`, `RatedLoad`, `Network`), dodaj **jedan red** pri startu:

```gdscript
const Aliases = preload("res://godot_sim/legacy_adapter/aliases.gd")
# ili registruj kao Autoload
```

Onda `var net = LegacyNetwork.new(...)` ili (preko aliasa) `var net = Aliases.Network.new(...)` radi
istom API-jem kao stari `Network` — `add_source`, `add_cable`, `add_load`, `solve_if_dirty`, signali.

Migracija na novi API je opciona i može ići fajl po fajl: zameni `Network` sa `CircuitModel`,
`add_source/add_cable/add_load` sa jednim `add_element`. Sve ostalo radi isto.

---

## 7. Kako pokrenuti testove

1. Kopiraj ceo `godot_sim/` folder u `res://` Godot projekta.
2. U bilo kom `_ready()`:
   ```gdscript
   const HeadlessTest = preload("res://godot_sim/debug/headless_test.gd")
   func _ready() -> void:
	   HeadlessTest.run_all()
   ```
3. F5 → rezultati izlaze u Output panel. Nikakva scena ili UI nije potrebna.
