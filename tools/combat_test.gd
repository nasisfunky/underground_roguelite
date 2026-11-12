extends Node
## Automatischer Test des Kombo-Baukastens und der Waffen (headless):
## Kette (Reihenfolge, Überspringen, Zurücksetzen), Zustände (gebunden, taumelnd, Lichtmal),
## Reaktionen der Bausteine, Ziehen/Stoßen, Waffenwerte, beidhändiger Griff, Zweithand-Dolch, Menü.
## Aufruf: godot --headless --path . tools/combat_test.tscn

var level: Node
var p: Player
var fails := 0
const C := Vector3(35, 0, -34)  ## Mitte "The Drowned Cistern" (trockener Boden südlich vom Becken)
var _spawned: Array[Node] = []


func _ready() -> void:
	await get_tree().process_frame
	level = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await _phys(10)
	p = level.player
	p.max_health = 100000.0
	p.health = 100000.0

	await _test_chain()
	await _test_states()
	await _test_distance()
	await _test_marks()
	await _test_finishers()
	await _test_real_enemy()
	await _test_weapons()
	await _test_impact()
	await _test_menu()

	print("\n=== COMBAT TEST: %s (%d Fehler) ===" % ["OK" if fails == 0 else "FEHLER", fails])
	get_tree().quit(fails)


# ------------------------------------------------------------------

func _test_chain() -> void:
	_check("Standardkette = Bind, Shove, Lunge, Hook, Kindle", p.combo_chain == ComboModules.DEFAULT_CHAIN, str(p.combo_chain))
	var d := _dummy(Vector3(-6, 0.05, 8.2))
	_reset(Vector3(-6, 0.1, 10.5))
	await _draw_on()
	await _phys(50)
	# Fünf Klicks im Rhythmus: die Bausteine kommen in der Reihenfolge der Kette
	p.combo_chain.assign([&"cut", &"backcut", &"", &"sweep", &"cut"])
	p._chain_idle = 99.0
	var seen: Array[StringName] = []
	var last: ComboModule = null
	for i in 4:
		p._set_stamina(p.max_stamina)
		p.input._attack = 1
		for f in 120:
			await get_tree().physics_frame
			if p._module and p._module != last:
				last = p._module
				seen.append(last.id)
			if p._module and p._module == last and p._swing_t / p.swing_duration > p.combo_window:
				break
	_check("Kette spielt der Reihe nach, leerer Platz übersprungen", seen == [&"cut", &"backcut", &"sweep", &"cut"], str(seen))
	await _phys(130)
	_check("Nach einer Pause beginnt die Kette vorn", p.next_chain_slot() == 0, "nächster Platz %d" % p.next_chain_slot())
	# Waffeneigener Baustein mit falscher Waffe wird übersprungen
	p.combo_chain.assign([&"impale", &"cut", &"", &"", &""])
	_check("Speer-Baustein mit Klinge übersprungen", p.next_chain_slot() == 1, str(p.next_chain_slot()))
	p.set_weapon(&"spear")
	_check("Mit Speer wieder dabei", p.next_chain_slot() == 0, str(p.next_chain_slot()))
	p.set_weapon(&"sword")
	# Ausdauer
	p.combo_chain.assign([&"kindle", &"", &"", &"", &""])
	p._set_stamina(p.max_stamina)
	var before := p.stamina
	p._chain_idle = 99.0
	p.input._attack = 1
	var low := before
	for i in 40:
		await get_tree().physics_frame
		low = minf(low, p.stamina)
	_check("Baustein kostet seine Ausdauer (Kindle 24)", absf((before - low) - 24.0) < 1.0, "%.0f" % (before - low))
	await _phys(80)
	_clear()


func _test_states() -> void:
	var d := _dummy(Vector3(-6, 0.05, 8.2))
	_reset(Vector3(-6, 0.1, 10.5))
	await _draw_on()
	await _phys(50)
	p.combo_chain.assign([&"bind", &"", &"", &"", &""])
	await _run_module()
	_check("Bind: Gegner gebunden", d.has_status(&"bound"), str(d.status.keys()))
	p.combo_chain.assign([&"backcut", &"", &"", &"", &""])
	var hp := d.health
	await _run_module()
	_check("Backcut auf Gebundenen: Wrench (gelöst, taumelt)", not d.has_status(&"bound") and d.has_status(&"reeling"), str(d.status.keys()))
	_check("Wrench macht Zusatzschaden", hp - d.health > 11.0, "%.1f" % (hp - d.health))
	await _phys(130)
	_check("Zustände laufen ab", d.status.is_empty(), str(d.status.keys()))
	# Bind auf Taumelnden: länger gebunden
	d.add_status(&"reeling", 2.0)
	p.combo_chain.assign([&"bind", &"", &"", &"", &""])
	await _run_module()
	_check("Bind auf Taumelnden: Pinned (4 s)", d.has_status(&"bound") and d.status[&"bound"].t > 3.0, str(d.status))
	_clear()


func _test_distance() -> void:
	var d := _dummy(Vector3(-6, 0.05, 8.2))
	_reset(Vector3(-6, 0.1, 10.5))
	await _draw_on()
	await _phys(50)
	p.combo_chain.assign([&"shove", &"", &"", &"", &""])
	var d0 := _flat(d)
	await _run_module()
	await _phys(30)
	_check("Shove stößt ~3 m weg", _flat(d) - d0 > 2.2, "%.1f m -> %.1f m" % [d0, _flat(d)])
	# Throw: gebunden + Shove
	d.global_position = p.global_position + p.forward() * 2.2
	d.reset_physics_interpolation()
	await _phys(2)
	d.add_status(&"bound", 3.0)
	d0 = _flat(d)
	await _run_module()
	await _phys(40)
	_check("Shove auf Gebundenen: Throw (weiter, taumelt lange)", _flat(d) - d0 > 4.0 and d.has_status(&"reeling"), "%.1f m -> %.1f m" % [d0, _flat(d)])
	# Hook aus 6 m
	d.status.clear()
	d.global_position = p.global_position + p.forward() * 6.0
	d.reset_physics_interpolation()
	await _phys(3)
	p.combo_chain.assign([&"hook", &"", &"", &"", &""])
	await _run_module()
	await _phys(20)
	_check("Hook zieht aus 6 m heran", _flat(d) < 2.4, "%.1f m" % _flat(d))
	_check("Hook von weit: Snap (taumelt)", d.has_status(&"reeling"), str(d.status.keys()))
	_clear()


func _test_marks() -> void:
	var d := _dummy(Vector3(-6, 0.05, 8.2))
	_reset(Vector3(-6, 0.1, 10.5))
	await _draw_on()
	await _phys(50)
	p.combo_chain.assign([&"lunge", &"", &"", &"", &""])
	await _run_module()
	_check("Lunge setzt ein Lichtmal", d.status_stacks(&"marked") == 1, str(d.status))
	# Verfolgung: Ziel 5 m entfernt
	d.status.clear()
	d.global_position = p.global_position + p.forward() * 5.2
	d.reset_physics_interpolation()
	await _phys(3)
	var start := p.global_position
	await _run_module()
	var moved := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	_check("Lunge auf Entfernte: Pursuit (springt hinterher)", moved > 1.2, "%.1f m" % moved)
	_check("Pursuit: zwei Lichtmale", d.status_stacks(&"marked") == 2, str(d.status))
	# Sweep verteilt das Mal auf andere
	var d2 := _dummy(Vector3(0, 0, 0))
	d.global_position = p.global_position + p.forward() * 2.2
	d2.global_position = d.global_position + Vector3(1.3, 0, 0.3)
	d.reset_physics_interpolation()
	d2.reset_physics_interpolation()
	await _phys(3)
	p.combo_chain.assign([&"sweep", &"", &"", &"", &""])
	await _run_module()
	_check("Sweep: beide taumeln", d.has_status(&"reeling") and d2.has_status(&"reeling"), "%s / %s" % [d.status.keys(), d2.status.keys()])
	_check("Sweep: Lichtmal springt über", d2.status_stacks(&"marked") >= 1, str(d2.status))
	_clear()


func _test_finishers() -> void:
	var d := _dummy(Vector3(-6, 0.05, 8.2))
	var n := _dummy(Vector3(-4.6, 0.05, 7.6))
	_reset(Vector3(-6, 0.1, 10.5))
	await _draw_on()
	await _phys(50)
	# Kindle ohne Mal
	p.combo_chain.assign([&"kindle", &"", &"", &"", &""])
	var hp := d.health
	await _run_module()
	var plain := hp - d.health
	await _phys(90)
	d.status.clear()
	d.add_status(&"marked", 6.0, 3)
	hp = d.health
	var hp_n := n.health
	await _run_module()
	var lit := hp - d.health
	_check("Kindle entzündet 3 Male: viel mehr Schaden", lit > plain + 25.0, "%.0f statt %.0f" % [lit, plain])
	_check("Kindle verbraucht die Male", d.status_stacks(&"marked") == 0, str(d.status))
	_check("Aufflammen trifft den Nachbarn", hp_n - n.health > 10.0, "%.0f" % (hp_n - n.health))
	await _phys(130)
	# Sever: gebunden -> Disarm
	d.status.clear()
	d.add_status(&"bound", 3.0)
	p.combo_chain.assign([&"sever", &"", &"", &"", &""])
	hp = d.health
	await _run_module()
	_check("Sever auf Gebundenen: Disarm (+25)", hp - d.health > 33.0 and d.has_status(&"reeling") and not d.has_status(&"bound"), "%.0f, %s" % [hp - d.health, d.status.keys()])
	_clear()


func _test_real_enemy() -> void:
	# Gebundener Hollowed greift nicht an
	var h := Hollowed.new()
	h.position = C + Vector3(-6, 0.05, 8.4)
	level.add_child(h)
	_spawned.append(h)
	_reset(Vector3(-6, 0.1, 10.5))
	await _draw_on()
	await _phys(30)
	p.combo_chain.assign([&"bind", &"", &"", &"", &""])
	await _run_module()
	var attacked := false
	for i in 120:
		await get_tree().physics_frame
		if h.state in [Hollowed.S.WINDUP, Hollowed.S.STRIKE]:
			attacked = true
	_check("Gebundener Hollowed greift 2 s nicht an", h.has_status(&"bound") or not attacked, "Angriff: %s" % attacked)
	_check("Hollowed bleibt gebunden stehen", not attacked, str(h.state))
	_clear()


func _test_weapons() -> void:
	var d := _dummy(Vector3(-6, 0.05, 7.1))  # 3.4 m vor dem Spieler
	_reset(Vector3(-6, 0.1, 10.5))
	await _draw_on()
	await _phys(50)
	p.combo_chain.assign([&"cut", &"", &"", &"", &""])
	# Speer beidhändig reicht weiter als die Klinge
	p.set_offhand(&"")
	p.set_weapon(&"spear")
	await _phys(70)
	_check("Speer ohne Zweithand: beidhändig", p.body.two_hand, "")
	var lh := p.body.hand_position(true)
	var shaft: Vector3 = p.body.sword.global_transform * Vector3(0, 0, p.body.two_hand_offset())
	_check("Linke Hand am Speerschaft", lh.distance_to(shaft) < 0.18, "%.2f m" % lh.distance_to(shaft))
	var hp := d.health
	await _run_module(false)
	_check("Speer trifft auf 3.4 m", d.health < hp, "%.1f" % (hp - d.health))
	p.set_offhand(&"shield")
	await _phys(70)
	_check("Speer mit Schild: einhändig", not p.body.two_hand and p.body.off_item == &"shield", str(p.body.off_item))
	# Dolch reicht nicht so weit
	p.set_weapon(&"dagger")
	await _phys(40)
	hp = d.health
	await _run_module(false)
	_check("Dolch trifft auf 3.4 m nicht", is_equal_approx(d.health, hp), "%.1f" % (hp - d.health))
	# Zweithand-Dolch: sticht nach (zwei Treffer pro Hieb)
	d.global_position = C + Vector3(-6, 0.05, 8.7)
	d.reset_physics_interpolation()
	p.set_offhand(&"dagger")
	await _phys(70)
	_check("Dolch in der Zweithand gezogen", p.body.off_item == &"dagger" and p.body.off_p >= 2.0, "%s %.1f" % [p.body.off_item, p.body.off_p])
	var hits := [0]
	var cb := func(_c, _m): hits[0] += 1
	d.health_changed.connect(cb)
	await _run_module(false)
	await _phys(20)
	d.health_changed.disconnect(cb)
	_check("Zweithand-Dolch sticht nach", hits[0] >= 2, "%d Treffer" % hits[0])
	# Zweihandaxt: keine Zweithand, schwerer, langsamer
	p.set_weapon(&"greataxe")
	await _phys(70)
	_check("Axt: Zweithand leer, beidhändig", p.body.off_item == &"" and p.body.two_hand, str(p.body.off_item))
	lh = p.body.hand_position(true)
	shaft = p.body.sword.global_transform * Vector3(0, 0, p.body.two_hand_offset())
	_check("Linke Hand am Axtstiel", lh.distance_to(shaft) < 0.18, "%.2f m" % lh.distance_to(shaft))
	var m := ComboModules.make(&"cut")
	m.setup(p)
	_check("Axt schlägt langsamer", m.duration > 1.1, "%.2f s" % m.duration)
	hp = d.health
	await _run_module(false)
	_check("Axt trifft härter", hp - d.health > 13.0, "%.1f" % (hp - d.health))
	# Licht mit Zweihänder: Axt wird einhändig geführt
	p.input._light = true
	await _phys(80)
	_check("Axt + Licht: einhändig, Licht in der Hand", p.body.off_item == &"light" and not p.body.two_hand, "%s" % p.body.off_item)
	p.input._light = true
	await _phys(60)
	p.set_weapon(&"sword")
	p.set_offhand(&"shield")
	await _phys(60)
	_check("Zurück zur Klinge mit Schild", p.body.off_item == &"shield", str(p.body.off_item))
	_clear()


func _test_menu() -> void:
	var hud: HUD = level.hud if "hud" in level else null
	if hud == null:
		for c in level.get_children():
			if c is HUD:
				hud = c
	_check("HUD gefunden", hud != null, "")
	if hud == null:
		return
	var ev := InputEventAction.new()
	ev.action = &"combo_menu"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("C öffnet das Kombo-Menü, Spiel pausiert", hud.combo_menu.visible and get_tree().paused, "")
	hud.combo_menu._on_pool(&"sever")
	hud.combo_menu._on_slot(2)
	_check("Menü: Baustein auf Platz 3 gelegt", p.combo_chain[2] == &"sever", str(p.combo_chain))
	hud.combo_menu._on_weapon(&"spear")
	_check("Menü: Waffe gewechselt", p.weapon.id == &"spear", str(p.weapon.id))
	hud.combo_menu._on_weapon(&"sword")
	hud.combo_menu.close_menu()
	await get_tree().process_frame
	_check("Menü zu: Spiel läuft weiter", not get_tree().paused, "")


# ------------------------------------------------------------------

## Abbrechen, Unterbrechen je Waffe, Umwerfen (Gegner und Spieler).
func _test_impact() -> void:
	_reset(Vector3(-6, 0.1, 10.5))
	p.set_weapon(&"sword")
	p.set_offhand(&"shield")
	await _draw_on()
	await _phys(40)
	# 1) normaler Hieb lässt sich per Rolle abbrechen
	p.combo_chain.assign([&"cut", &"", &"", &"", &""])
	p._chain_idle = 99.0
	p._chain_i = 0
	p._set_stamina(p.max_stamina)
	p.input._attack = 1
	for i in 60:
		await get_tree().physics_frame
		if p._swing_t >= 0.0 and p._swing_t / p.swing_duration > 0.3:
			break
	p.input._roll_pressed = true
	await _phys(4)
	_check("Hieb per Rolle abbrechen", p.state == Player.State.ROLL and p._swing_t < 0.0, str(p.state))
	await _phys(70)
	# 2) Zweihandaxt: ab dem Ausholen festgelegt
	_reset(Vector3(-6, 0.1, 10.5))
	p.set_weapon(&"greataxe")
	p.set_offhand(&"")
	await _phys(60)
	p.combo_chain.assign([&"cleave", &"", &"", &"", &""])
	p._chain_idle = 99.0
	p._chain_i = 0
	p._set_stamina(p.max_stamina)
	p.input._attack = 1
	var m: ComboModule = null
	for i in 90:
		await get_tree().physics_frame
		m = p._module
		if m and p._swing_t / p.swing_duration > m.hits[0] - 0.1:
			break
	p.input._roll_pressed = true
	await _phys(4)
	_check("Axt-Finisher festgelegt: Rolle wartet", p.state == Player.State.MOVE and p._swing_t >= 0.0 and p.swing_committed(), str(p.state))
	var rolled := false
	for i in 90:
		await get_tree().physics_frame
		if p.state == Player.State.ROLL:
			rolled = true
			break
	_check("Rolle kommt nach dem Schlag", rolled, "")
	await _phys(70)
	# 3) Unterbrechung je Waffe am Hollowed
	var h := Hollowed.new()
	h.position = C + Vector3(-6, 0.05, 6.0)
	level.add_child(h)
	_spawned.append(h)
	await _phys(5)
	p.set_weapon(&"dagger")
	p.set_offhand(&"shield")
	await _phys(2)
	h.receive_hit(p.module_info(ComboModules.make(&"cut")))
	var dagger_len := h._stagger_len
	await _phys(60)
	p.set_weapon(&"greataxe")
	p.set_offhand(&"")
	await _phys(2)
	h.receive_hit(p.module_info(ComboModules.make(&"cut")))
	var axe_len := h._stagger_len
	_check("Dolch unterbricht kurz, Axt lange", dagger_len < 0.3 and axe_len > 0.6, "Dolch %.2f s, Axt %.2f s" % [dagger_len, axe_len])
	await _phys(80)
	# ausholender Gegner: Dolchstich hält ihn nicht auf
	p.set_weapon(&"dagger")
	p.set_offhand(&"shield")
	h.poise = h.max_poise
	h._set_state(Hollowed.S.WINDUP)
	h.receive_hit(p.module_info(ComboModules.make(&"cut")))
	_check("Ausholender Hollowed: Dolch unterbricht nicht", h.state == Hollowed.S.WINDUP, str(h.state))
	await _phys(2)
	# Axt-Finisher wirft um
	p.set_weapon(&"greataxe")
	p.set_offhand(&"")
	await _phys(2)
	var heavy := p.module_info(ComboModules.make(&"cleave"))
	h.receive_hit(heavy)
	_check("Axt-Finisher wirft den Hollowed um", heavy.knockdown and h.state == Hollowed.S.KNOCKDOWN, "%s %s" % [heavy.knockdown, h.state])
	await _phys(int(Hollowed.KNOCKDOWN_TIME * 60) + 20)
	_check("Hollowed steht wieder auf", h.state != Hollowed.S.KNOCKDOWN, str(h.state))
	await _clear()
	# 4) Spieler: Unterbrechung je nach Angriff, schwerer Treffer wirft um
	_reset(Vector3(-6, 0.1, 10.5))
	p.set_weapon(&"sword")
	p.set_offhand(&"shield")
	await _phys(30)
	var src := Node3D.new()
	level.add_child(src)
	src.global_position = p.global_position + Vector3(0, 0, -1.5)
	var lens: Array[float] = []
	for st in [0.3, 0.8]:
		var info := DamageInfo.new()
		info.amount = 1.0
		info.source = src
		info.stagger = st
		p.receive_hit(info)
		lens.append(p._stagger_len)
		await _phys(70)
	_check("Spieler: Unterbrechung je nach Angriff", is_equal_approx(lens[0], 0.3) and is_equal_approx(lens[1], 0.8), str(lens))
	var kd := DamageInfo.new()
	kd.amount = 1.0
	kd.source = src
	kd.knockback = 7.0
	kd.knockdown = true
	var z0 := p.global_position.z
	p.receive_hit(kd)
	await _phys(30)
	_check("Spieler umgeworfen und nach hinten geschleudert", p.state == Player.State.KNOCKDOWN and p.global_position.z - z0 > 0.8, "%s, %.1f m" % [p.state, p.global_position.z - z0])
	_check("Am Boden unverwundbar", p.is_invulnerable(), "")
	await _phys(int(Player.KNOCKDOWN_TIME * 60) + 10)
	_check("Spieler steht wieder auf", p.state == Player.State.MOVE, str(p.state))
	src.queue_free()


func _dummy(local: Vector3) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.position = C + local
	d.rotation.y = 0.0
	level.add_child(d)
	_spawned.append(d)
	return d


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _phys(3)


## Kette auf Anfang, einen Klick ausführen und warten, bis der Baustein fertig ist.
func _run_module(fresh := true) -> void:
	if fresh:
		pass
	p._chain_idle = 99.0
	p._chain_i = 0
	p._set_stamina(p.max_stamina)
	p.input._attack = 1
	for i in 90:
		await get_tree().physics_frame
		if p._swing_t >= 0.0:
			break
	for i in 200:
		await get_tree().physics_frame
		if p._swing_t < 0.0:
			break
	await _phys(4)


func _draw_on() -> void:
	if not p.weapon_out:
		p.input._draw = true
	p._manual_draw = true
	await _phys(2)
	p._manual_draw = true


func _flat(e: Node3D) -> float:
	var to := e.global_position - p.global_position
	return Vector2(to.x, to.z).length()


func _reset(local: Vector3) -> void:
	p.global_position = C + local
	p.velocity = Vector3.ZERO
	p.facing_yaw = 0.0
	p.cam.yaw = 0.0
	p._set_state(Player.State.MOVE)
	p.reset_physics_interpolation()


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s  (%s)" % ["OK  " if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
