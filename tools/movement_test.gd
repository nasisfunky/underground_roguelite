extends Node
## Automatischer Test der Bewegungs-Features (headless):
## Sprint, Rolle auf Alt (vor/zurück/seitlich), Abrollen nach Stürzen, Waffe/Schild ziehen und wegstecken (Y),
## Licht vorhalten (X), natürliche Arme, Klettern mit Ausdauer, Hochziehen, Schwimmen ohne Tauchen,
## Reinspringen, Rausklettern, Raus-Waten. Aufruf: godot --headless --path . tools/movement_test.tscn

var level: Node
var p: Player
var fails := 0
const C := Vector3(35, 0, -34)  ## Mitte "The Drowned Cistern"


func _ready() -> void:
	await get_tree().process_frame
	level = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await _phys(10)
	p = level.player

	await _test_controls()
	await _test_equipment()
	await _test_walk()
	await _test_sprint()
	await _test_rolls()
	await _test_fall_rolls()
	await _test_climb()
	await _test_swim()

	print("\n=== MOVEMENT TEST: %s (%d Fehler) ===" % ["OK" if fails == 0 else "FEHLER", fails])
	get_tree().quit(fails)


# ------------------------------------------------------------------

func _test_controls() -> void:
	var roll_ok := false
	for ev in InputMap.action_get_events("roll"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_ALT and (ev as InputEventKey).location == KEY_LOCATION_LEFT:
			roll_ok = true
	_check("Rolle liegt auf Alt links", roll_ok, "")
	var sprint_ok := false
	for ev in InputMap.action_get_events("sprint"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SHIFT:
			sprint_ok = true
	var shift_rolls := false
	for ev in InputMap.action_get_events("roll"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SHIFT:
			shift_rolls = true
	_check("Shift = Sprint (nicht mehr Rolle)", sprint_ok and not shift_rolls, "")
	var walk_ok := false
	for ev in InputMap.action_get_events("walk"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_CTRL:
			walk_ok = true
	_check("Strg = Gehen", walk_ok, "")
	# echter Tastendruck: Alt links -> Rolle, Y -> ziehen, X -> Licht
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ALT
	e.keycode = KEY_ALT
	e.location = KEY_LOCATION_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	await _phys(2)
	_check("Alt links startet die Rolle", p.state == Player.State.ROLL, str(p.state))
	e.pressed = false
	Input.parse_input_event(e)
	await _phys(70)
	var ey := InputEventKey.new()
	ey.keycode = KEY_Y
	ey.physical_keycode = KEY_Z  # QWERTZ: Y liegt auf der US-Z-Position
	ey.pressed = true
	Input.parse_input_event(ey)
	await _phys(2)
	_check("Taste Y (QWERTZ) zieht die Waffe", p.weapon_out, "")
	ey.pressed = false
	Input.parse_input_event(ey)
	p.input._draw = true
	await _phys(50)


func _test_equipment() -> void:
	_teleport(C + Vector3(-6, 0.1, 11), 0.0)  # weit weg von Gegnern/Puppen (sonst bleibt die Waffe gezogen)
	await _phys(40)
	var b := p.body
	_check("Start: Waffe und Schild weggesteckt", not p.weapon_out and b.weapon_p == 0.0 and b.off_item == &"", "weapon_p %.1f, links '%s'" % [b.weapon_p, b.off_item])
	var grip_hips: Vector3 = b.hips.global_transform.affine_inverse() * b.sword.global_position
	_check("Waffe hängt an der linken Hüfte", grip_hips.x < -0.12 and absf(grip_hips.y) < 0.25, str(grip_hips.snapped(Vector3.ONE * 0.01)))
	var sh_chest: Vector3 = b.chest.global_transform.affine_inverse() * b.shield.global_position
	_check("Schild liegt auf dem Rücken", sh_chest.z > 0.18, str(sh_chest.snapped(Vector3.ONE * 0.01)))
	var hand_r := _hand_chest(b, true)
	_check("Freie Arme hängen locker neben dem Körper", hand_r.y < 0.05 and hand_r.x > 0.15, str(hand_r.snapped(Vector3.ONE * 0.01)))
	# Gehen: Arme schwingen gegengleich zu den Beinen
	Input.action_press("move_forward")
	var hz: Array[float] = []
	var hl: Array[float] = []
	for i in 90:
		await get_tree().physics_frame
		if i > 30:
			hz.append(_hand_chest(b, true).z)
			hl.append(b.hip_l.rotation.x)
	Input.action_release("move_forward")
	var corr := _corr(hz, hl)
	var swing: float = hz.max() - hz.min()
	_check("Gehen: rechter Arm schwingt mit dem linken Bein", corr < -0.6 and swing > 0.1, "Korrelation %.2f, Ausschlag %.2f m" % [corr, swing])
	await _phys(30)

	# Y: ziehen (bleibt gezogen), Y: wegstecken
	p.input._draw = true
	await _phys(45)
	_check("Y zieht Waffe und Schild", b.weapon_ready() and b.shield_ready(), "weapon_p %.1f, %s %.1f" % [b.weapon_p, b.off_item, b.off_p])
	await _phys(30)
	var hand_grip := b.arm_lo_r.global_transform * Vector3(0, -ShadowBody.LOWER_ARM, 0)
	_check("Hand hält den Griff", hand_grip.distance_to(b.sword.global_position) < 0.06, "%.3f m" % hand_grip.distance_to(b.sword.global_position))
	await _phys(int(60 * (p.sheathe_after + 2.0)))
	_check("Mit Y gezogen: bleibt gezogen", b.weapon_ready() and p.weapon_out, "")
	p.input._draw = true
	await _phys(50)
	_check("Y steckt wieder weg", b.weapon_p == 0.0 and b.off_item == &"", "weapon_p %.1f" % b.weapon_p)

	# Angriff aus dem Stand: zieht automatisch, schlägt, steckt nach einer Weile selbst weg
	p.input._attack = 1
	var swung := -1
	for i in 60:
		await get_tree().physics_frame
		if p._swing_t >= 0.0 and swung < 0:
			swung = i
	_check("Angriff zieht die Waffe und schlägt", swung > 0 and swung < 45, "Hieb nach %d Ticks" % swung)
	await _phys(int(60 * (p.sheathe_after + 2.0)))
	_check("Nach Kampfpause automatisch weggesteckt", b.weapon_p == 0.0 and not p.weapon_out, "weapon_p %.1f" % b.weapon_p)

	# X: Licht vorhalten
	var lantern_belt := b.chest.global_transform.affine_inverse() * b.lantern.global_position
	p.input._light = true
	await _phys(50)
	var lan := b.chest.global_transform.affine_inverse() * b.lantern.global_position
	var lamp_w := b.lantern_light.global_position
	var front: float = (lamp_w - p.global_position).dot(p.forward())
	_check("X hält das Licht vor (vor der Brust)", b.light_held() and lan.z < -0.3 and front > 0.25, "Laterne %s (vorher %s), Licht %.2f m vorn" % [lan.snapped(Vector3.ONE * 0.01), lantern_belt.snapped(Vector3.ONE * 0.01), front])
	var hand_l := b.arm_lo_l.global_transform * Vector3(0, -ShadowBody.LOWER_ARM, 0)
	_check("Linke Hand hält die Laterne", hand_l.distance_to(b.lantern.get_parent().global_position) < 0.08, "%.3f m" % hand_l.distance_to(b.lantern.get_parent().global_position))
	p.input._draw = true
	await _phys(50)
	_check("Mit Licht: Y zieht nur die Waffe, kein Schild", b.weapon_ready() and b.off_item == &"light", "links '%s'" % b.off_item)
	p.input._light = true
	await _phys(90)
	_check("X: Licht weg, Schild gezogen", b.shield_ready() and not b.light_held(), "links '%s' %.1f" % [b.off_item, b.off_p])
	var lan2: Vector3 = b.hips.global_transform.affine_inverse() * b.lantern.get_parent().global_position
	_check("Laterne wieder an der rechten Hüfte", lan2.x > 0.12 and lan2.distance_to(ShadowBody.LANTERN_BELT) < 0.05, str(lan2.snapped(Vector3.ONE * 0.01)))
	p.input._draw = true
	await _phys(50)
	# Blocken zieht und blockt erst mit Schild am Arm
	Input.action_press("block")
	await _phys(3)
	_check("Block zieht erst (noch kein Block)", not p.is_blocking() and p.weapon_out, "")
	await _phys(50)
	_check("Block steht, sobald der Schild am Arm ist", p.is_blocking() and b.shield_ready(), "")
	Input.action_release("block")
	p.input._draw = true
	await _phys(50)
	# Glowmire: Licht ist der Laternenstab
	p.set_culture("glowmire")
	await _phys(10)
	p.input._light = true
	await _phys(50)
	var pole_front: float = (p.body.offhand.global_position - p.global_position).dot(p.forward())
	_check("Glowmire: X hält den Laternenstab vor", p.body.light_held() and pole_front > 0.15, "%.2f m vorn" % pole_front)
	p.input._light = true
	await _phys(50)
	var pole_back: float = (p.body.offhand.global_position - p.global_position).dot(p.forward())
	_check("Glowmire: Laternenstab auf dem Rücken", pole_back < -0.1, "%.2f m" % pole_back)
	p.set_culture("kiln")
	await _phys(10)


func _test_walk() -> void:
	_teleport(Vector3(35, 0.1, -21), PI * 0.5)
	await _phys(5)
	Input.action_press("move_forward")
	await _phys(60)
	var jog := p.get_horizontal_speed()
	# echter Tastendruck: Strg (links) halten, dabei W -> weiter gehen (Strg+W darf die Bewegung nicht schlucken)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_CTRL
	e.keycode = KEY_CTRL
	e.location = KEY_LOCATION_LEFT
	e.ctrl_pressed = true
	e.pressed = true
	Input.parse_input_event(e)
	Input.action_release("move_forward")
	var ew := InputEventKey.new()
	ew.physical_keycode = KEY_W
	ew.keycode = KEY_W
	ew.ctrl_pressed = true
	ew.pressed = true
	Input.parse_input_event(ew)
	await _phys(60)
	var v := p.get_horizontal_speed()
	_check("Strg halten = langsam gehen (~2 m/s)", absf(v - p.walk_speed) < 0.2 and p.walking and jog > p.run_speed - 0.2, "%.2f m/s (vorher %.2f)" % [v, jog])
	Input.action_press("sprint")
	await _phys(40)
	v = p.get_horizontal_speed()
	_check("Shift hat Vorrang vor Strg", p.sprinting and v > 6.6, "%.2f m/s" % v)
	Input.action_release("sprint")
	e.pressed = false
	e.ctrl_pressed = false
	Input.parse_input_event(e)
	await _phys(50)
	v = p.get_horizontal_speed()
	_check("Strg loslassen = wieder joggen", not p.walking and absf(v - p.run_speed) < 0.3, "%.2f m/s" % v)
	ew.pressed = false
	ew.ctrl_pressed = false
	Input.parse_input_event(ew)
	await _phys(30)


func _test_sprint() -> void:
	_teleport(Vector3(35, 0.1, -21), PI * 0.5)  # Richtung Westen durch den Gang
	p._set_stamina(100.0)
	await _phys(5)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _phys(80)
	var v := p.get_horizontal_speed()
	_check("Sprint ~7 m/s", v > 6.6 and v < 7.4 and p.sprinting, "%.2f m/s" % v)
	_check("Sprint kostet Ausdauer", p.stamina < 90.0, "%.0f" % p.stamina)
	# um den Raum laufen, bis die Ausdauer leer ist
	var t := 0
	while p.stamina > 0.0 and t < 600:
		p.cam.yaw += 0.02
		await get_tree().physics_frame
		t += 1
	await _phys(40)
	v = p.get_horizontal_speed()
	_check("Ausdauer leer: nur noch laufen", not p.sprinting and v < p.run_speed + 0.2, "%.2f m/s nach %.1f s" % [v, t / 60.0])
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _phys(150)
	_check("Ausdauer lädt nach dem Sprint wieder", p.stamina > 60.0, "%.0f" % p.stamina)


func _test_rolls() -> void:
	# ohne Waffe: immer vorwärts in Laufrichtung (dreht sich um)
	_teleport(C + Vector3(-2, 0.1, 8), 0.0)
	await _phys(30)
	Input.action_press("move_back")
	await _phys(2)
	p.input._roll_pressed = true
	await _phys(3)
	Input.action_release("move_back")
	_check("Ohne Waffe: Rolle zurück = umdrehen und vorwärts", p._roll_kind == &"fwd" and absf(wrapf(p.facing_yaw - PI, -PI, PI)) < 0.3, "%s, Blick %.2f" % [p._roll_kind, p.facing_yaw])
	await _phys(70)
	# mit Waffe: relativ zur Kamera
	p.input._draw = true
	await _phys(50)
	for case in [["move_back", &"back", Vector3(0, 0, 1)], ["move_left", &"left", Vector3(-1, 0, 0)], ["move_right", &"right", Vector3(1, 0, 0)], ["move_forward", &"fwd", Vector3(0, 0, -1)]]:
		_teleport(C + Vector3(-2, 0.1, 8), 0.0)
		await _phys(20)
		var start := p.global_position
		var floor_y := start.y
		Input.action_press(case[0])
		await _phys(2)
		p.input._roll_pressed = true
		await _phys(2)
		Input.action_release(case[0])
		var lowest := 99.0
		var kind := p._roll_kind
		for i in 50:
			await get_tree().physics_frame
			lowest = minf(lowest, _lowest_mesh_y())
		var moved := p.global_position - start
		moved.y = 0.0
		var ok_dir: bool = moved.normalized().dot(case[2]) > 0.85
		var keep_face: bool = case[1] == &"fwd" or absf(wrapf(p.facing_yaw, -PI, PI)) < 0.15
		_check("Mit Waffe: Rolle '%s'" % case[1], kind == case[1] and ok_dir and keep_face, "%s, %.1f m %s, Blick %.2f" % [kind, moved.length(), moved.normalized().snapped(Vector3.ONE * 0.1), p.facing_yaw])
		_check("Rolle '%s' taucht nicht in den Boden" % case[1], lowest > floor_y - 0.1, "%.2f m unter Boden" % (floor_y - lowest))
		await _phys(30)
	p.input._draw = true
	await _phys(50)


func _test_fall_rolls() -> void:
	var tw := C + Vector3(5, 0, -9)  # Gitterturm, Plattform 4,18 m
	# vom Turm nach Osten: Platz vorn -> Vorwärtsrolle
	_teleport(tw + Vector3(1.0, 4.3, 0), -PI * 0.5)
	await _phys(20)
	var seen := await _walk_until_roll("move_forward", 150)
	_check("Sturz 4 m, vorn frei: Abrollen vorwärts", seen == &"fwd", "Rolle '%s'" % seen)
	await _phys(60)
	# nach Norden: die Nordwand steht 2 m vor dem Turm -> Rückwärtsrolle
	_teleport(tw + Vector3(0, 4.3, -2.0), 0.0)
	await _phys(20)
	seen = await _walk_until_roll("move_forward", 150)
	_check("Sturz 4 m, Wand vorn: Abrollen rückwärts", seen == &"back", "Rolle '%s'" % seen)
	await _phys(60)
	# niedriger Absatz (1,9 m auf dem Parcours der ersten Halle): keine Rolle
	_teleport(Vector3(4.6, 2.0, -6.8), 0.0)
	await _phys(20)
	seen = await _walk_until_roll("move_forward", 90)
	_check("Kleiner Absatz (1,9 m): keine Rolle", seen == &"", "Rolle '%s'" % seen)
	await _phys(30)


func _walk_until_roll(action: String, frames: int) -> StringName:
	Input.action_press(action)
	var seen: StringName = &""
	for i in frames:
		await get_tree().physics_frame
		if p.state == Player.State.ROLL:
			seen = p._roll_kind
			break
	Input.action_release(action)
	return seen


func _test_climb() -> void:
	var tw := C + Vector3(5, 0, -9)
	# Gitter an der Südseite des Turms: hochklettern und oben über die Kante ziehen
	_teleport(tw + Vector3(0, 0.1, 3.8), 0.0)
	p._set_stamina(100.0)
	await _phys(10)
	Input.action_press("move_forward")
	var started := false
	for i in 40:
		await get_tree().physics_frame
		if p.state == Player.State.CLIMB:
			started = true
			break
	_check("Gegen das Gitter laufen startet Klettern", started, str(p.state))
	var y0 := p.global_position.y
	var st0 := p.stamina
	await _phys(60)
	_check("Klettern hoch ~1,25 m/s", p.global_position.y - y0 > 1.0 and p.global_position.y - y0 < 1.5, "%.2f m in 1 s" % (p.global_position.y - y0))
	_check("Klettern kostet Ausdauer", st0 - p.stamina > 8.0, "%.0f -> %.0f" % [st0, p.stamina])
	var ledge := false
	for i in 300:
		await get_tree().physics_frame
		if p.state == Player.State.LEDGE_UP:
			ledge = true
		if ledge and p.state == Player.State.MOVE:
			break
	Input.action_release("move_forward")
	await _phys(20)
	_check("Oben über die Kante gezogen, steht auf dem Turm", ledge and p.is_on_floor() and p.global_position.y > 4.0, "y %.2f" % p.global_position.y)

	# Seitlich klettern bis zum Rand der Kletterfläche
	_teleport(tw + Vector3(0, 0.1, 3.8), 0.0)
	await _phys(5)
	Input.action_press("move_forward")
	await _phys(30)
	Input.action_release("move_forward")
	Input.action_press("move_right")
	var x0 := p.global_position.x
	await _phys(150)
	Input.action_release("move_right")
	var dx := p.global_position.x - x0
	_check("Seitlich klettern, stoppt am Gitterrand", p.state == Player.State.CLIMB and dx > 0.8 and p.global_position.x < tw.x + 1.6, "dx %.2f, x %.2f" % [dx, p.global_position.x - tw.x])
	# Springen: von der Wand weg
	p.input._jump_pressed = true
	await _phys(30)
	_check("Sprung von der Wand", p.state != Player.State.CLIMB and p.global_position.z > tw.z + 3.6, "z %.2f" % (p.global_position.z - tw.z))
	await _phys(60)

	# Flechtenturm: 7,5 m, Ausdauer reicht
	var lt := C + Vector3(10, 0, 8)
	_teleport(lt + Vector3(-2.2, 0.1, 0), -PI * 0.5)
	p._set_stamina(100.0)
	await _phys(10)
	Input.action_press("move_forward")
	var top := false
	for i in 600:
		await get_tree().physics_frame
		if p.state == Player.State.MOVE and p.is_on_floor() and p.global_position.y > 7.0:
			top = true
			break
	Input.action_release("move_forward")
	_check("Flechtenturm (7,5 m) mit voller Ausdauer geschafft", top, "y %.2f, Ausdauer %.0f" % [p.global_position.y, p.stamina])

	# Flechtenwand ohne Ende: Ausdauer leer -> Absturz (und Abrollen)
	_teleport(C + Vector3(11.2, 0.1, -13.3), 0.0)
	p._set_stamina(100.0)
	await _phys(10)
	Input.action_press("move_forward")
	var max_y := 0.0
	var fell := false
	var rolled := false
	var st_fall := 100.0
	for i in 1100:
		await get_tree().physics_frame
		max_y = maxf(max_y, p.global_position.y)
		if max_y > 3.0 and p.state == Player.State.MOVE and not p.is_on_floor() and not fell:
			fell = true
			st_fall = p.stamina
		if fell and p.state == Player.State.ROLL:
			rolled = true
		if fell and p.is_on_floor() and p.global_position.y < 0.5:
			break
		if fell:
			Input.action_release("move_forward")
	Input.action_release("move_forward")
	_check("Ausdauer leer: Figur lässt los und fällt", fell and st_fall <= 0.5, "höchster Punkt %.1f m, Ausdauer beim Loslassen %.1f" % [max_y, st_fall])
	_check("Absturz aus großer Höhe wird abgerollt", rolled, "")
	await _phys(80)


func _test_swim() -> void:
	var water_y := -0.4
	# über die Rampe hineinwaten -> schwimmen
	_teleport(C + Vector3(-7, 0.1, 2.0), 0.0)
	await _phys(10)
	Input.action_press("move_forward")
	var swim := false
	var wade_slow := false
	for i in 400:
		await get_tree().physics_frame
		if not is_nan(p.water_y) and p.state == Player.State.MOVE and p.is_on_floor() and p.water_y - p.global_position.y > 0.6:
			wade_slow = wade_slow or p.get_horizontal_speed() < p.run_speed * 0.85
		if p.state == Player.State.SWIM:
			swim = true
			break
	_check("Im flachen Wasser langsamer (waten)", wade_slow, "")
	_check("Tiefes Wasser: schwimmt", swim, str(p.state))
	await _phys(60)
	# kein Tauchen: Kopf über Wasser, Höhe bleibt
	var ys: Array[float] = []
	for i in 150:
		await get_tree().physics_frame
		ys.append(p.global_position.y)
	var head_y := p.body.head.global_position.y
	_check("Kein Tauchen: Kopf über Wasser", head_y > water_y + 0.15 and ys.min() > water_y - p.swim_float_depth - 0.08, "Kopf %.2f m über Wasser" % (head_y - water_y))
	var v := p.get_horizontal_speed()
	_check("Schwimmtempo ~2,3 m/s", v > 1.9 and v < 2.6, "%.2f m/s" % v)
	# weiter nach Norden bis zur Kante -> rausklettern
	var out := false
	var ledge := false
	for i in 600:
		await get_tree().physics_frame
		if p.state == Player.State.LEDGE_UP:
			ledge = true
		if ledge and p.state == Player.State.MOVE:
			out = true
			break
	Input.action_release("move_forward")
	await _phys(20)
	_check("An der Beckenkante rausgeklettert", out and p.is_on_floor() and p.global_position.y > -0.05 and p.global_position.z < C.z - 12.0, "y %.2f z %.2f" % [p.global_position.y, p.global_position.z - C.z])

	# vom Turm ins Becken springen
	var tw := C + Vector3(5, 0, -9)
	_teleport(tw + Vector3(-1.4, 4.3, 0), PI * 0.5)
	await _phys(20)
	Input.action_press("move_forward")
	p.input._jump_pressed = true
	var entered := false
	var splash := false
	var min_y := 99.0
	for i in 120:
		await get_tree().physics_frame
		if p.state == Player.State.SWIM:
			entered = true
			Input.action_release("move_forward")
			if p._water_enter_t >= 0.0:
				splash = true
			min_y = minf(min_y, p.global_position.y)
	Input.action_release("move_forward")
	_check("Sprung ins Becken: Eintauch-Animation", entered and splash, "")
	_check("Taucht kurz ein, nicht bis zum Grund", min_y > -2.7 and min_y < water_y - p.swim_float_depth - 0.05, "tiefster Punkt %.2f" % min_y)
	await _phys(120)
	_check("Treibt wieder an der Oberfläche", absf(p.global_position.y - (water_y - p.swim_float_depth)) < 0.08, "y %.2f" % p.global_position.y)
	# zur Rampe schwimmen und hinauslaufen
	_teleport(C + Vector3(-7, -1.58, -7), PI)
	await _phys(10)
	Input.action_press("move_forward")
	var walked := false
	for i in 600:
		await get_tree().physics_frame
		if p.state == Player.State.MOVE and p.is_on_floor() and p.global_position.y > -0.2:
			walked = true
			break
	Input.action_release("move_forward")
	_check("Über die Rampe aus dem Wasser gelaufen", walked, "y %.2f, Zustand %d" % [p.global_position.y, p.state])


# ------------------------------------------------------------------

func _hand_chest(b: ShadowBody, right: bool) -> Vector3:
	var lo := b.arm_lo_r if right else b.arm_lo_l
	return b.chest.global_transform.affine_inverse() * (lo.global_transform * Vector3(0, -ShadowBody.LOWER_ARM, 0))


func _lowest_mesh_y() -> float:
	var lo := 99.0
	for mi in p.body._meshes:
		if not mi.is_visible_in_tree():
			continue
		var xf: Transform3D = mi.global_transform
		for v in mi.mesh.get_faces():
			lo = minf(lo, (xf * v).y)
	return lo


func _corr(a: Array[float], b: Array[float]) -> float:
	var n := mini(a.size(), b.size())
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-9))


func _teleport(pos: Vector3, yaw: float) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.facing_yaw = yaw
	p.cam.yaw = yaw
	p._set_state(Player.State.MOVE)
	p.collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMIES
	p.reset_physics_interpolation()


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s  (%s)" % ["OK  " if ok else "FAIL", label, detail])
	if not ok:
		fails += 1


func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
