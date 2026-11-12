extends Node
## Automatischer Spieltest (headless): prüft Laufen, Springen, Rollen, Angriffe per Klick,
## Fähigkeiten, Blocken und Gegner-Treffer. Aufruf: godot --headless --path . tools/smoke_test.tscn

var level: Node
var p: Player
var fails := 0


func _ready() -> void:
	await get_tree().process_frame
	level = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await _phys(10)
	p = level.player

	# --- Laufen ---
	var start := p.global_position
	Input.action_press("move_forward")
	await _phys(60)
	Input.action_release("move_forward")
	var moved := start.distance_to(p.global_position)
	_check("Laufen ~4,2 m in 1 s (mit Anlauf)", moved > 3.8 and moved < 4.8, "%.2f m" % moved)
	await _phys(30)

	# --- Springen ---
	var y0 := p.global_position.y
	var peak := y0
	Input.action_press("jump")
	p.input._jump_pressed = true
	for i in 50:
		await get_tree().physics_frame
		peak = maxf(peak, p.global_position.y)
	Input.action_release("jump")
	_check("Sprunghöhe ~1,35 m (gehalten)", peak - y0 > 1.15 and peak - y0 < 1.5, "%.2f m" % (peak - y0))
	await _phys(20)
	# kurzer Sprung (sofort losgelassen) -> niedriger
	y0 = p.global_position.y
	peak = y0
	p.input._jump_pressed = true
	for i in 50:
		await get_tree().physics_frame
		peak = maxf(peak, p.global_position.y)
	_check("Kurzer Sprung niedriger", peak - y0 < 0.75 and peak - y0 > 0.3, "%.2f m" % (peak - y0))
	await _phys(20)

	# --- Rolle ---
	start = p.global_position
	var st0 := p.stamina
	p.input._roll_pressed = true
	await _phys(2)
	_check("Rolle startet, unverwundbar", p.state == Player.State.ROLL and p.is_invulnerable(), str(p.state))
	await _phys(55)
	var rd := start.distance_to(p.global_position)
	_check("Rollweite ~3,8 m", rd > 3.3 and rd < 4.4, "%.2f m" % rd)
	_check("Rolle kostet Ausdauer", p.stamina < st0, "%.0f -> %.0f" % [st0, p.stamina])
	await _phys(90)
	_check("Ausdauer lädt nach", p.stamina > 95.0, "%.0f" % p.stamina)

	# --- Angriffe per Klick an Trainingspuppe ---
	_teleport(Vector3(0, 0.1, -33.3), 0.0)
	await _phys(20)
	var dummy: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is TrainingDummy and e.global_position.distance_to(p.global_position) < 4.0:
			dummy = e
	var hits := [0]
	dummy.health_changed.connect(func(_c, _m): hits[0] += 1)
	await _phys(20)
	_check("Ohne Klick kein Angriff", hits[0] == 0, "%d Treffer" % hits[0])
	var st_before := p.stamina
	p.input._attack = 1
	await _phys(3)
	_check("Linksklick startet Hieb", p._swing_t >= 0.0 and p._swing_index == 0, "Clip %d" % p._swing_index)
	_check("Hieb kostet Ausdauer", p.stamina < st_before, "%.0f -> %.0f" % [st_before, p.stamina])
	await _phys(30)
	p.input._attack = 1  # früh geklickt -> wird vorgemerkt und schließt als Rückhand an
	var combo_seen := false
	for i in 90:
		await get_tree().physics_frame
		if p._swing_index == 1 and p._swing_t >= 0.0:
			combo_seen = true
	_check("Kombo: zweiter Klick wird zur Rückhand", combo_seen, "")
	await _phys(60)
	_check("Hiebe treffen die Puppe", hits[0] >= 2, "%d Treffer" % hits[0])
	var hp_before: float = dummy.health
	p.input._attack = 2
	await _phys(3)
	_check("Mittlere Maustaste startet Stich", p._swing_index == 3, "Clip %d" % p._swing_index)
	await _phys(80)
	_check("Stich trifft stärker", hp_before - dummy.health > p.swing_damage * 1.2, "%.1f Schaden" % (hp_before - dummy.health))
	await _phys(40)

	# --- Fähigkeit 1 ---
	hits[0] = 0
	p.input._ability = 1
	await _phys(3)
	_check("Fähigkeit 1 startet", p.state == Player.State.ABILITY, str(p.state))
	await _phys(80)
	_check("Schwerer Hieb trifft", hits[0] >= 1, "%d" % hits[0])
	_check("Abklingzeit läuft", p.abilities[0].cooldown_left > 3.0, "%.1f" % p.abilities[0].cooldown_left)
	p.input._ability = 1
	await _phys(5)
	_check("Fähigkeit auf Abklingzeit startet nicht", p.state != Player.State.ABILITY, str(p.state))
	await _phys(30)

	# --- Gegner greift an ---
	var hol: Hollowed = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Hollowed:
			hol = e
			break
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e is Hollowed or e is Splinterkin) and e != hol:
			e.queue_free()
	_teleport(hol.global_position + Vector3(0, 0.2, 3.0), 0.0)
	var hp0 := p.health
	await _phys(240)
	_check("Hollowed trifft ungeschützten Spieler", p.health < hp0, "%.0f -> %.0f" % [hp0, p.health])
	_check("Spieler schlägt nicht von selbst", hol.health >= hol.max_health, "%.0f" % hol.health)

	# --- Blocken ---
	await _phys(60)
	hp0 = p.health
	var blocked := [0]
	Input.action_press("block")
	for i in 300:
		# Spieler schaut mit der Kamera zum Gegner (Deckung zeigt in Kamerarichtung)
		var to := hol.global_position - p.global_position
		p.cam.yaw = atan2(-to.x, -to.z)
		await get_tree().physics_frame
		if p.stamina < 99.0:
			blocked[0] = 1
	Input.action_release("block")
	_check("Blocken hält Schaden ab (nur Ausdauer)", p.health >= hp0 - 0.1 and blocked[0] == 1, "HP %.0f -> %.0f" % [hp0, p.health])

	# --- Rolle taucht nicht sichtbar in den Boden ---
	_teleport(Vector3(0, 0.1, 8.0), 0.0)
	await _phys(30)
	var floor_y := p.global_position.y
	var lowest := 99.0
	p.input._roll_pressed = true
	for i in 55:
		await get_tree().physics_frame
		for mi in p.body._meshes:
			if not mi.is_visible_in_tree():
				continue
			var xf: Transform3D = mi.global_transform
			for v in mi.mesh.get_faces():
				lowest = minf(lowest, (xf * v).y)
	_check("Rolle: Körper bleibt am Boden (max. 10 cm Eintauchen)", lowest > floor_y - 0.1, "%.2f m unter Boden" % (floor_y - lowest))

	# --- Schwünge: Klinge bleibt außerhalb des eigenen Körpers ---
	for cult in FrayedOutfit.CULTURES:
		var dummy_body := ShadowBody.new()
		dummy_body.outfit = cult
		add_child(dummy_body)
		dummy_body.build()
		for idx in [0, 1, 2]:
			var worst := _blade_through_body(dummy_body, idx)
			_check("%s, Schwung %d: Klinge nicht durch den Körper" % [cult, idx], worst < 0.03, "%.2f m tief bei t=%.2f" % [worst, _worst_t])
		dummy_body.queue_free()
	# Alle Keyframes: Schwertgriff und Schild in Armreichweite (sonst reißt die Hand von der Waffe ab)
	var reach := ShadowBody.UPPER_ARM + ShadowBody.LOWER_ARM + 0.02
	for cn in AnimLibrary.CLIPS:
		var far := 0.0
		for k in AnimLibrary.clip(cn).keys:
			far = maxf(far, (k.grip as Vector3).distance_to(ShadowBody.SHOULDER_R))
			far = maxf(far, (k.shield as Vector3).distance_to(ShadowBody.SHOULDER_L))
		_check("Animation %s: Hände in Reichweite" % cn, far <= reach, "max %.2f m (Arm %.2f m)" % [far, reach])

	# --- Durchgänge zwischen den Räumen sind begehbar ---
	for seg in [["Durchgang Halle -> Training Yard", Vector3(1.8, 0.1, -9.0), -17.0],
			["Durchgang Training Yard -> Rampe", Vector3(1.8, 0.1, -42.0), -49.0],
			["Durchgang Rampe -> Sealed Hall", Vector3(1.8, -1.5, -55.0), -61.0]]:
		_teleport(seg[1], 0.0)
		await _phys(5)
		Input.action_press("move_forward")
		await _phys(150)
		Input.action_release("move_forward")
		_check(seg[0], p.global_position.z < seg[2], "z %.1f" % p.global_position.z)

	# --- Kein Z-Fighting im Level (übereinanderliegende Flächen flackern) ---
	var t0 := Time.get_ticks_msec()
	var zf := ZFight.scan(level.get_node("Geometry"))
	zf.sort_custom(func(x, y): return x.area > y.area)
	for i in mini(zf.size(), 25):
		print("      z-fight: %s  <->  %s  %.3f m²  bei %s" % [zf[i].a, zf[i].b, zf[i].area, (zf[i].at as Vector3).snapped(Vector3.ONE * 0.1)])
	_check("Kein Z-Fighting im Level", zf.is_empty(), "%d Paare, Scan %d ms" % [zf.size(), Time.get_ticks_msec() - t0])

	# --- Kulturen wechseln (F2): Figur wird neu gebaut, Stoff simuliert ohne Ausreißer ---
	_teleport(Vector3(0, 0.1, 8.0), 0.0)
	for cult in FrayedOutfit.CULTURES:
		p.set_culture(cult)
		Input.action_press("move_forward")
		await _phys(40)
		Input.action_release("move_forward")
		p.input._roll_pressed = true
		await _phys(60)
		var cl: FrayedCloth = p.body.cloth
		var stretch := 0.0
		for c in cl.ca.size():
			if cl.ck[c] >= 1.0:
				stretch = maxf(stretch, cl.p[cl.ca[c]].distance_to(cl.p[cl.cb[c]]) / maxf(cl.cr[c], 1e-4))
		_check("Kultur %s: Figur, Waffe und Stoff da" % cult, p.body.outfit == cult and p.body.sword.get_child_count() > 0 and cl.p.size() > 50, "%d Stoffpunkte" % cl.p.size())
		_check("Kultur %s: Stoff dehnt sich nach Rolle kaum" % cult, stretch < 1.8, "max x%.2f" % stretch)
	p.set_culture("kiln")
	await _phys(5)

	# --- Splinterkin-Rudel: kreist, immer nur einer springt, Sprung trifft ---
	_teleport(Vector3(0, 0.1, 6.0), 0.0)
	var pack: Array[Splinterkin] = []
	for i in 3:
		var k := Splinterkin.new()
		k.position = Vector3(-3.0 + i * 3.0, 0.1, 1.0)
		k.pack_angle = TAU * i / 3.0
		level.add_child(k)
		pack.append(k)
	hp0 = p.health
	var max_attackers := 0
	var leaps := 0
	var was_leaping := {}
	for i in 600:
		await get_tree().physics_frame
		var n := 0
		for k in pack:
			if k.state in [Splinterkin.S.WINDUP, Splinterkin.S.LEAP]:
				n += 1
			if k.state == Splinterkin.S.LEAP and not was_leaping.get(k, false):
				leaps += 1
			was_leaping[k] = k.state == Splinterkin.S.LEAP
		max_attackers = maxi(max_attackers, n)
	_check("Splinterkin: Rudel springt an", leaps >= 2, "%d Sprünge in 10 s" % leaps)
	_check("Splinterkin: immer nur einer greift an", max_attackers <= 1, "max %d gleichzeitig" % max_attackers)
	_check("Splinterkin: Sprung trifft", p.health < hp0, "%.0f -> %.0f" % [hp0, p.health])
	var info := DamageInfo.new()
	info.amount = 30.0
	info.source = p
	pack[0].receive_hit(info)
	await _phys(2)
	_check("Splinterkin: stirbt nach 30 Schaden", pack[0].is_dead(), "%.0f HP" % pack[0].health)

	print("\n=== SMOKE TEST: %s (%d Fehler) ===" % ["OK" if fails == 0 else "FEHLER", fails])
	get_tree().quit(fails)


var _worst_t := 0.0

## Wie tief steckt die Klinge maximal im Rumpf/Kopf (in Brust-Koordinaten, vereinfachte Körperform)?
func _blade_through_body(b: ShadowBody, idx: int) -> float:
	b.combat = 1.0
	for i in 60:
		b.action = &""
		b.tick(1.0 / 60.0)
	var worst := 0.0
	_worst_t = 0.0
	var steps := 90
	for i in steps + 1:
		b.action = &"swing"
		b.swing_index = idx
		b.action_t = float(i) / steps
		b.tick(1.0 / 60.0)
		var d := b.blade_clip_depth()
		if d > worst:
			worst = d
			_worst_t = b.action_t
	b.combat = 0.0
	return worst


func _teleport(pos: Vector3, yaw: float) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.facing_yaw = yaw
	p.cam.yaw = yaw
	p.reset_physics_interpolation()


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s  (%s)" % ["OK  " if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
