extends Node
## Automatischer Spieltest (headless): prüft Laufen, Springen, Rollen, Auto-Angriff,
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
	_check("Laufen ~6 m in 1 s", moved > 5.5 and moved < 7.0, "%.2f m" % moved)
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
	await _phys(40)
	var rd := start.distance_to(p.global_position)
	_check("Rollweite ~4,4 m", rd > 3.8 and rd < 5.2, "%.2f m" % rd)
	_check("Rolle kostet Ausdauer", p.stamina < st0, "%.0f -> %.0f" % [st0, p.stamina])
	await _phys(90)
	_check("Ausdauer lädt nach", p.stamina > 95.0, "%.0f" % p.stamina)

	# --- Auto-Angriff an Trainingspuppe ---
	_teleport(Vector3(0, 0.1, -33.3), 0.0)
	await _phys(20)
	var dummy: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is TrainingDummy and e.global_position.distance_to(p.global_position) < 4.0:
			dummy = e
	var hits := [0]
	dummy.health_changed.connect(func(_c, _m): hits[0] += 1)
	_check("Ziel automatisch gewählt", p.target != null, str(p.target))
	p.set_target(dummy)
	await _phys(240)
	_check("Auto-Angriff trifft (~4 Treffer in 4 s)", hits[0] >= 3 and hits[0] <= 6, "%d Treffer" % hits[0])

	# --- Tab-Zielwechsel ---
	var before := p.target
	p.cycle_target()
	_check("Tab wechselt Ziel", p.target != before and p.target != null, str(p.target))
	p.set_target(dummy)

	# --- Fähigkeit 1 ---
	hits[0] = 0
	p.input._ability = 1
	await _phys(3)
	_check("Fähigkeit 1 startet", p.state == Player.State.ABILITY, str(p.state))
	await _phys(60)
	_check("Schwerer Hieb trifft", hits[0] >= 1, "%d" % hits[0])
	_check("Abklingzeit läuft", p.abilities[0].cooldown_left > 3.0, "%.1f" % p.abilities[0].cooldown_left)
	p.input._ability = 1
	await _phys(5)
	_check("Fähigkeit auf Abklingzeit startet nicht", p.state != Player.State.ABILITY, str(p.state))
	await _phys(30)

	# --- Gegner greift an ---
	var husk: Husk = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Husk:
			husk = e
			break
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Husk and e != husk:
			e.queue_free()
	_teleport(husk.global_position + Vector3(0, 0.2, 3.0), 0.0)
	var hp0 := p.health
	await _phys(240)
	_check("Hohlwandler trifft ungeschützten Spieler", p.health < hp0, "%.0f -> %.0f" % [hp0, p.health])
	_check("Spieler schlägt automatisch zurück", husk.health < husk.max_health or husk.is_dead(), "%.0f" % husk.health)

	# --- Blocken ---
	await _phys(60)
	p.set_target(husk)
	hp0 = p.health
	var blocked := [0]
	Input.action_press("block")
	for i in 300:
		await get_tree().physics_frame
		if p.stamina < 99.0:
			blocked[0] = 1
	Input.action_release("block")
	_check("Blocken hält Schaden ab (nur Ausdauer)", p.health >= hp0 - 0.1 and blocked[0] == 1, "HP %.0f -> %.0f" % [hp0, p.health])

	# --- Durchgänge zwischen den Räumen sind begehbar ---
	for seg in [["Durchgang Halle -> Training Yard", Vector3(1.8, 0.1, -9.0), -17.0],
			["Durchgang Training Yard -> Rampe", Vector3(1.8, 0.1, -42.0), -49.0],
			["Durchgang Rampe -> Sealed Hall", Vector3(1.8, -1.5, -55.0), -61.0]]:
		_teleport(seg[1], 0.0)
		await _phys(5)
		Input.action_press("move_forward")
		await _phys(100)
		Input.action_release("move_forward")
		_check(seg[0], p.global_position.z < seg[2], "z %.1f" % p.global_position.z)

	print("\n=== SMOKE TEST: %s (%d Fehler) ===" % ["OK" if fails == 0 else "FEHLER", fails])
	get_tree().quit(fails)


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
