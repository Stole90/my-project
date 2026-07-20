# Refaktor Bridge sloja — Vodič za migraciju

## Novi fajlovi

| Fajl | Opis |
|---|---|
| `ElementBridge.gd` | Osnovna klasa — sve ostalo nasljeđuje ovo |
| `CableBridge.gd` | Za `Cable` elemente → koristi `CableNode.gd` |
| `ThreePhaseCableBridge.gd` | Za `ThreePhaseCable` → koristi `ThreePhaseCableNode.gd` |
| `FuseBridge.gd` | Za `Fuse` → koristi `FuseNode.gd` |
| `ThreePhaseFuseBridge.gd` | Za `ThreePhaseFuse` → koristi `ThreePhaseFuseNode.gd` |
| `ConsumerBridge.gd` | Za `Consumer` / `RatedConsumer` → koristi `Refrigerator.gd` i sl. |
| `SocketBridge.gd` | Za `Socket` → koristi `SocketAppliance.gd` |
| `TransformerBridge.gd` | Za `Transformer` → koristi `TransformerNode.gd` |
| `ThreePhaseTransformerBridge.gd` | Za `ThreePhaseTransformer` → koristi `ThreePhaseTransformerNode.gd` |

---

## Šta je promenjeno u postojećim fajlovima

### CableNode.gd
- **Uklonjeno**: `_on_model_solved()`, lokalne var (`current_a`, `is_overloaded`, `temperature_c`...)
- **Dodato**: `_bridge: CableBridge`, crtanje čita iz `_bridge.vis_*`
- `get_info()` → delegira na `_bridge.get_info()`

### FuseNode.gd
- **Uklonjeno**: direktno čitanje `_fuse.*` u `get_info()`
- **Zadržano**: `_process()` sa `tick_thermal()` (zahteva frame delta)
- `get_info()` → delegira na `_bridge.get_info()`

### TransformerNode.gd
- **Uklonjeno**: `_on_model_solved`, lokalni `_solved`, ručni signal connect-i ka modelu
- `_draw()` čita iz `_bridge.vis_*`

### BaseAppliance.gd
- `row()` sada delegira na `ElementBridge.row()` — jedna implementacija
- `_bridge` je sada typed `ElementBridge` (podklase mogu koristiti specifičniji tip)

### Refrigerator.gd / SocketAppliance.gd
- Lokalne var (`_last_voltage`, `_last_current`, `_last_state`) → uklonjene
- `get_info()` čita iz `_bridge.vis_*`

---

## Fajlovi koji još čekaju refaktor

Ovi fajlovi nisu refaktorisani (jednako lako kao prethodni):

| Fajl | Bridge koji treba |
|---|---|
| `ThreePhaseCableNode.gd` | `ThreePhaseCableBridge` |
| `ThreePhaseFuseNode.gd` | `ThreePhaseFuseBridge` |
| `ThreePhaseTransformerNode.gd` | `ThreePhaseTransformerBridge` |
| `ThreePhaseSocketAppliance.gd` | `SocketBridge` (ili novi `ThreePhaseSocketBridge`) |
| `ThreePhaseOvenNode.gd` | `ConsumerBridge` ili poseban `ThreePhaseOvenBridge` |
| `PowerSourceNode.gd` | Opcionalno — izvor nema mnogo stanja za pratiti |
| `ThreePhaseSourceNode.gd` | Opcionalno |
| `PoleNode.gd` | Opcionalno — minimalan element |
| `DistBoxNode.gd` | Složeniji, poseban tretman (ima N osigurača) |

---

## Pattern za novi aparat / grid node

```gdscript
# U plug_into() ili setup_in():
_my_element = MySimElement.new(...)
model.add_element(_my_element)

var bridge := ConsumerBridge.new()   # ili odgovarajući typed bridge
bridge.name = "%s_Bridge" % name
add_child(bridge)
bridge.bind(_my_element, model)
_bridge = bridge

# Opcionalno — specifični signali:
bridge.damaged.connect(func(): _on_damaged())
bridge.overloaded.connect(func(v): queue_redraw())

# get_info() — delegiraj ili proširi:
func get_info() -> Dictionary:
    return _bridge.get_info()
```

---

## row() helper — samo jedna kopija

**Staro** — svaki fajl imao svoju kopiju:
```gdscript
# U CableNode.gd, FuseNode.gd, BaseAppliance.gd, DistBoxNode.gd, ...
static func row(label, value, fmt=""): return {"label":..., "value":..., "fmt":...}
```

**Novo** — jedna implementacija u `ElementBridge.gd`:
```gdscript
ElementBridge.row("Napon", 230.0, "%.2f V")
# ili iz podklase:
row("Napon", 230.0, "%.2f V")  # nasleđeno
```

---

## Vizuelni state — šta _draw() čita

```
_bridge.vis_enabled     → bool   — siva boja kada false
_bridge.vis_damaged     → bool   — crvena/tamna boja
_bridge.vis_overloaded  → bool   — narandžasta boja
_bridge.vis_overheated  → bool   — narandžasta boja
_bridge.vis_loading_pct → float  — 0..100, za lerp boje kabla
_bridge.vis_voltage_v   → float  — napon za UI overlay
_bridge.vis_current_a   → float  — struja za UI overlay
_bridge.vis_state       → String — tekstualni opis
```

Podklase dodaju specifična polja (npr. `CableBridge.vis_temperature_c`).
