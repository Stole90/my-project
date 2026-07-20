## DistBoxBridge.gd (v3)
##
## Fix P1/P3 — struja 0 u info panelu za consumere BEZ osigurača:
##   Prethodno: fn == null → continue → consumer doprinosi 0 struji.
##   Sada: kad fn == null čitamo struju direktno iz consumer node-a
##   (via _bridge.vis_current_a ili _consumer.current).
##
## Fix P1 (stari) — timing:
##   Kad fn != null ali fb == null (bridge još nije inicijalizovan),
##   čitamo direktno f.current_magnitude iz Fuse sim elementa.

class_name DistBoxBridge
extends ElementBridge

var vis_phase_loading:    Array  = [0.0, 0.0, 0.0]  # [L1, L2, L3] A
var vis_v_pe:             float  = 0.0
var vis_v_n:              float  = 0.0
var vis_phase_voltages:   Array  = [0.0, 0.0, 0.0]  # [L1, L2, L3] V
var vis_fuse_blown_count: int    = 0
var vis_unbalance_pct:    float  = 0.0

var _bus: SimNode = null

# Ref na DistBoxNode za direktan pristup _consumer_data
var _dist_box_node: Node = null

# ── Bind ──────────────────────────────────────────────────────────────────────

func bind_with_bus(
		p_element: DistributionBox,
		p_bus: SimNode,
		p_model: CircuitModel,
		p_dist_box_node: Node = null
) -> void:
		_bus           = p_bus
		_dist_box_node = p_dist_box_node
		bind(p_element, p_model)

# ── Sync ──────────────────────────────────────────────────────────────────────

func _sync_visual_state() -> void:
		var db: DistributionBox = element as DistributionBox
		if db == null or _bus == null:
				return

		# Naponi po fazama
		for ph_idx in range(3):
				var ph: int = [Phase.L1, Phase.L2, Phase.L3][ph_idx]
				vis_phase_voltages[ph_idx] = _bus.voltage_magnitude(ph)

		vis_v_pe = _bus.pe_voltage_magnitude()
		vis_v_n  = _bus.neutral_displacement_v()

		# ── Struje po fazama ──────────────────────────────────────────────────────
		vis_phase_loading    = [0.0, 0.0, 0.0]
		vis_fuse_blown_count = 0

		if _dist_box_node != null and _dist_box_node.has_method("get_consumer_data"):
				var cdata: Dictionary = _dist_box_node._consumer_data
				for consumer in cdata:
						var entry: Dictionary = cdata[consumer]
						var fn: Node   = entry.get("fuse", null)
						var phase: int = entry.get("phase", Phase.L1)
						var ph_idx: int = [Phase.L1, Phase.L2, Phase.L3].find(phase)

						if fn == null:
								# Consumer bez osigurača — čitaj direktno
								if ph_idx >= 0:
										vis_phase_loading[ph_idx] += _read_consumer_current(consumer)
								continue

						# ── Trofazni osigurač ─────────────────────────────────────────────
						if fn is ThreePhaseFuseNode:
								var fb3: ThreePhaseFuseBridge = fn.get("_bridge") as ThreePhaseFuseBridge
								if fb3 == null:
										# Bridge još nije init — čitaj iz sim elementa
										var fe: ThreePhaseFuse = fn.get("_fuse") as ThreePhaseFuse
										if fe != null:
												# Svaka faza → njen slot u vis_phase_loading
												for k_idx in range(3):
														var k: int = [Phase.L1, Phase.L2, Phase.L3][k_idx]
														var ic: Complex = fe.currents_by_phase.get(k, null)
														if ic != null:
																vis_phase_loading[k_idx] += ic.magnitude()
								else:
										# vis_currents_a: Dictionary {Phase.L1: float, L2: float, L3: float}
										# Svaka faza → njen slot u vis_phase_loading (ne prosek u jedan slot!)
										for k_idx in range(3):
												var k: int = [Phase.L1, Phase.L2, Phase.L3][k_idx]
												vis_phase_loading[k_idx] += fb3.vis_currents_a.get(k, 0.0)
										# Proveri da li je ijedan pregoreo
										for k in [Phase.L1, Phase.L2, Phase.L3]:
												if fb3.vis_blown_phases.get(k, false):
														vis_fuse_blown_count += 1
														break
								continue

						# ── Monofazni osigurač ────────────────────────────────────────────
						var fb: FuseBridge = fn.get("_bridge") as FuseBridge
						if fb == null:
								if ph_idx >= 0 and fn.get("_fuse") != null:
										vis_phase_loading[ph_idx] += fn.get("_fuse").current_magnitude
								continue

						if ph_idx >= 0:
								vis_phase_loading[ph_idx] += fb.vis_current_mag

						if fb.vis_blown:
								vis_fuse_blown_count += 1
		else:
				# Fallback: staro ponašanje (bez _dist_box_node ref-a)
				for f in db.output_fuses:
						var fuse := f as Fuse
						if fuse == null: continue
						if fuse.blown:
								vis_fuse_blown_count += 1

		# Nebalans napona
		var v_max: float = vis_phase_voltages.max()
		var v_min: float = vis_phase_voltages.min()
		vis_unbalance_pct = 0.0 if v_max < 1.0 else (v_max - v_min) / v_max * 100.0

		# Stanje
		if vis_v_pe > 50.0 or vis_v_n > 20.0:
				vis_state = "kvar"
		elif vis_v_pe > 10.0 or vis_v_n > 5.0 or vis_fuse_blown_count > 0:
				vis_state = "upozorenje"
		else:
				vis_state = "ok"

# ── Helper: čitaj struju iz consumer node-a ───────────────────────────────────
##
## Pokušava redom:
##   1. consumer._bridge.vis_current_a   — ElementBridge pattern (BaseAppliance itd.)
##   2. consumer._consumer.current       — direktan sim element (monofazni)
##   3. suma vis_currents_a              — trofazni bridge (ThreePhaseOvenBridge itd.)

func _read_consumer_current(consumer: Node) -> float:
		# 1. ElementBridge pattern
		var bridge = consumer.get("_bridge")
		if bridge is ElementBridge:
				var eb := bridge as ElementBridge
				# Za trofazne bridgeve koji imaju vis_currents_a, uzmi srednju vrednost
				var currents = bridge.get("vis_currents_a")
				if currents is Array and currents.size() >= 3:
						var sum: float = 0.0
						for i in range(3):
								sum += float(currents[i])
						return sum / 3.0
				return eb.vis_current_a

		# 2. Direktan sim element — monofazni consumer (BaseAppliance fallback)
		var sim_elem = consumer.get("_consumer")
		if sim_elem != null:
				var ic = sim_elem.get("current")
				if ic is Complex:
						return ic.magnitude()

		return 0.0

# ── Info za InfoPanel ─────────────────────────────────────────────────────────

func get_info() -> Dictionary:
		var db: DistributionBox = element as DistributionBox
		if db == null:
				return {"name": "razvodnik", "type": "Razvodna kutija", "rows": []}

		var rows: Array = []

		if _bus == null:
				rows.append(row("Stanje", "nepovezano"))
		else:
				rows.append(row("─── Naponi ───", ""))
				for ph_idx in range(3):
						rows.append(row(
								"Napon %s" % ["L1","L2","L3"][ph_idx],
								vis_phase_voltages[ph_idx], "%.1f V"
						))

				var n_status: String = "ok (%.1f V)" % vis_v_n if vis_v_n < 5.0 \
						else ("upozorenje (%.1f V)" % vis_v_n if vis_v_n < 20.0 \
						else "KVAR (%.1f V)" % vis_v_n)
				rows.append(row("Nulti prov.", n_status))

				var pe_status: String = "ok (%.1f V)" % vis_v_pe if vis_v_pe < 10.0 \
						else ("upozorenje (%.1f V)" % vis_v_pe if vis_v_pe < 50.0 \
						else "OPASNO (%.1f V)" % vis_v_pe)
				rows.append(row("PE provodnik", pe_status))
				rows.append(row("Nebalans nap.", vis_unbalance_pct, "%.1f %%"))

				rows.append(row("─── Opterećenje ───", ""))
				for ph_idx in range(3):
						rows.append(row(
								"Struja %s" % ["L1","L2","L3"][ph_idx],
								vis_phase_loading[ph_idx], "%.2f A"
						))

		rows.append(row("─── Tabla ───", ""))
		var total: int = db.output_fuses.size() if db else 0
		rows.append(row("Osigurači",  total,                "%d"))
		rows.append(row("Pregoreli",  vis_fuse_blown_count, "%d"))
		rows.append(row("Stanje",     vis_state))

		return {
				"name":  db.element_name,
				"type":  "Razvodna kutija",
				"rows":  rows,
		}

# ── Akcije ────────────────────────────────────────────────────────────────────

func main_breaker_open() -> void:
		var db: DistributionBox = element as DistributionBox
		if db == null: return
		db.main_breaker_open()
		if model != null: model.mark_dirty()

func main_breaker_close() -> void:
		var db: DistributionBox = element as DistributionBox
		if db == null: return
		db.main_breaker_close()
		if model != null: model.mark_dirty()
