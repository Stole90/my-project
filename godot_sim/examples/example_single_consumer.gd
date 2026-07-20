## example_single_consumer.gd
## ════════════════════════════════════════════════════════════════════
##  PRIMER 1 — HEADLESS (čista simulacija, BEZ scene tree-a)
## ════════════════════════════════════════════════════════════════════
##
##  Pokazuje minimalan put kako da:
##    1. napraviš čvorove (SimNode),
##    2. kačiš element po element (izvor → kabl → osigurač → potrošač),
##    3. okineš solve,
##    4. čitaš rezultate (napon, struja, snaga, stanje),
##    5. menjaš stanje u runtime-u (gasiš potrošač, kvariš kabl…) i
##       pokrećeš re-solve preko dirty flag-a.
##
##  POKRETANJE:
##    Bilo gde u svom Godot 4 projektu:
##      const Ex = preload("res://godot_sim/examples/example_single_consumer.gd")
##      func _ready() -> void:
##          Ex.run()
##
##  Output ide u Godot konzolu — nema UI-ja, nema scene.

extends RefCounted

static func run() -> void:
        print("\n" + "═".repeat(64))
        print("  PRIMER 1 — Frižider zakačen na trafostanicu preko kabla")
        print("═".repeat(64))

        # ── Korak 1: ČVOROVI ────────────────────────────────────────────
        # Svaki čvor je jedna električna tačka u mreži ("bus").
        # Daj im čitljiva imena — javljaju se u logovima.
        var grid_bus  := SimNode.new("trafo_bus")    # 230 V slack bus
        var house_bus := SimNode.new("kuca_bus")     # ulaz u kuću

        # ── Korak 2: IZVOR (slack) ─────────────────────────────────────
        # Idealan AC izvor 230 V @ 0°. Definiše referentni napon mreže.
        var grid_src := VoltageSource.new(grid_bus, 230.0, 0.0, "trafo")

        # ── Korak 3: KABL od trafostanice do kuće ──────────────────────
        # 80 m bakrenog kabla, presek 4 mm², dozvoljena struja 32 A.
        var feeder := Cable.new(
                grid_bus, house_bus,
                80.0,        # length [m]
                4.0,         # cross section [mm²]
                "copper",    # material → R/m iz SimConstants
                32.0,        # max current [A]
                "feeder_kabl"
        )

        # ── Korak 4: OSIGURAČ na ulazu u kuću ──────────────────────────
        # Resettable (auto-reset prekidač) na 16 A.
        var bus_after_fuse := SimNode.new("posle_osiguraca")
        var fuse := Fuse.new(house_bus, bus_after_fuse, 16.0, true, "B16_breaker")

        # ── Korak 5: POTROŠAČ (frižider) ───────────────────────────────
        # Frižider:  ~150 W radne snage,  pf = 0.85  (induktivni, motor),
        # nominalni napon 230 V, tolerancija ±10 % (default iz SimConstants).
        # Inrush: kompresor pri startu vuče 4× struju ~200 ms.
        var fridge := RatedConsumer.new(
                bus_after_fuse,
                150.0,       # P [W]
                0.85,        # power factor
                "frizider",
                230.0,       # nominalni napon
                true         # induktivni (cosφ < 1)
        )
        fridge.inrush_factor     = 4.0
        fridge.inrush_duration_s = 0.2

        # ── Korak 6: SLAGANJE U MODEL ──────────────────────────────────
        # CircuitModel = topologija + dirty flag + signali.
        # Solver (YBus default) ne menjamo — radi steady-state AC.
        var model := CircuitModel.new("kuca_1")
        model.add_element(grid_src)
        model.add_element(feeder)
        model.add_element(fuse)
        model.add_element(fridge)

        # Pretplata na signale — game layer bi inače reagovao ovde.
        model.solved.connect(func(ms: float) -> void:
                print("  ⚙  solved za %.3f ms" % ms))
        model.cable_overloaded.connect(func(c) -> void:
                print("  🔥 KABL preopterećen: %s" % c.element_name))
        model.consumer_tripped.connect(func(c) -> void:
                print("  ⚠  POTROŠAČ trip (UV): %s" % c.element_name))
        model.consumer_damaged.connect(func(c) -> void:
                print("  💥 POTROŠAČ uništen (OV): %s" % c.element_name))
        model.fuse_blew.connect(func(f) -> void:
                print("  ⚡ OSIGURAČ pregoreo: %s" % f.element_name))

        # ── Korak 7: PRVI SOLVE ────────────────────────────────────────
        model.solve()
        _print_status("Početno stanje", model, fridge, feeder)

        # ── Korak 8: GAŠENJE FRIŽIDERA ─────────────────────────────────
        # disable() automatski markira element kao dirty.
        # solve_if_dirty() vidi promenu i ponovo računa.
        print("\n  → Igrač gasi frižider (prekidač na zidu)")
        fridge.disable()
        model.solve_if_dirty()
        _print_status("Posle gašenja", model, fridge, feeder)

        # ── Korak 9: PALJENJE NAZAD ────────────────────────────────────
        print("\n  → Igrač pali frižider — pokreće se inrush window")
        fridge.enable()
        model.solve_if_dirty()
        _print_status("Posle paljenja (inrush aktivan)", model, fridge, feeder)

        # ── Korak 10: KVAR NA KABLU ────────────────────────────────────
        print("\n  → Drvo palo na vod — kabl pukao")
        feeder.damage()
        model.solve_if_dirty()
        _print_status("Posle kvara", model, fridge, feeder)
        # Frižider je pao u TRIPPED_UV jer mu je napon ~0.

        # ── Korak 11: POPRAVKA ─────────────────────────────────────────
        print("\n  → Ekipa popravlja kabl")
        feeder.repair()
        # Frižider je sam ušao u TRIPPED_UV (auto-recovery), pa solve treba
        # da ga vrati u NORMAL kad napon poraste.
        model.solve_if_dirty()
        _print_status("Posle popravke", model, fridge, feeder)

        # ── Korak 12: NEMA PROMENE → solve_if_dirty se preskače ────────
        var ran: bool = model.solve_if_dirty()
        print("\n  Re-solve bez promene → izvršio se? %s  (očekivano: false)" % str(ran))

        # ── Detaljan pregled mreže ─────────────────────────────────────
        print("")
        NetworkPrinter.print_model(model)

# ── Pomoćni printer ──────────────────────────────────────────────────
static func _print_status(title: String, model: CircuitModel, c: Consumer, k: Cable) -> void:
        print("\n  ── %s ──" % title)
        print("    napon na frižideru   : %.2f V" % model.get_node_voltage(c.node()))
        print("    struja kroz frižider : %.3f A" % model.get_element_current(c))
        print("    aktivna snaga        : %.2f W" % c.active_power())
        print("    reaktivna snaga      : %.2f VAr" % c.reactive_power())
        print("    faktor snage         : %.3f" % c.power_factor())
        print("    stanje (state)       : %s" % c.state)
        print("    enabled?             : %s" % str(c.enabled))
        print("    kabl opterećenje     : %.1f %%" % k.loading_percent())
