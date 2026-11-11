class_name Player
extends CharacterBody3D
## Spieler-Controller.
##
## Aufbau für Koop: Die Simulation liest nur `input` (PlayerInput) und `camera_yaw()`.
## Für Mitspieler über Netzwerk wird später nur die Eingabequelle ausgetauscht,
## Kamera und HUD gibt es nur für den lokalen Spieler.
##
## Game-Feel-Bausteine (Werte unten, alle im Inspector justierbar):
##  - Input-Buffer: Rollen/Springen/Fähigkeiten werden ~0,15 s vorgemerkt
##  - Coyote Time + variable Sprunghöhe + stärkere Fallgravitation
##  - Rolle: sofortige Unverwundbarkeit, Geschwindigkeit vorne stark, hinten weich
##  - Auto-Angriff als Oberkörper-Overlay: Laufen wird nie blockiert
##  - Hitstop, Screenshake, Funken und Zahlen bei Treffern

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal died
signal ability_used(slot: int)

enum State { MOVE, ROLL, ABILITY, STAGGER, DEAD }

@export var peer_id := 1
@export var is_local := true

@export_group("Laufen")
@export var run_speed := 4.8
@export var backpedal_mult := 0.6
@export var block_speed_mult := 0.5
@export var ground_accel := 20.0
@export var ground_decel := 24.0
@export var air_accel := 18.0
@export var turn_sharpness := 8.0

@export_group("Springen")
@export var jump_height := 1.35
@export var gravity_up := 25.0
@export var gravity_down := 44.0
@export var jump_cut_speed := 4.5  ## Steiggeschwindigkeit beim frühen Loslassen (kurzer Hüpfer)
@export var max_fall := 32.0
@export var coyote_time := 0.1
@export var buffer_time := 0.15

@export_group("Rolle")
@export var roll_duration := 0.85
@export var roll_distance := 3.8
@export var roll_iframes := 0.45
@export var roll_cancel_at := 0.68
@export var roll_cost := 22.0

@export_group("Blocken")
@export var parry_window := 0.16
@export var block_arc_deg := 75.0
@export var block_stamina_per_damage := 1.4

@export_group("Angriff")
@export var swing_duration := 0.95  # wird aus dem Clip gelesen
@export var swing_hit_at := 0.44  # normierte Zeit des Treffers (aus dem Clip)
@export var melee_range := 2.4
@export var swing_damage := 9.0
@export var swing_arc_deg := 80.0
@export var swing_cost := 14.0  # Ausdauer pro Hieb
@export var combo_window := 0.68  # ab hier (normiert) schließt ein vorgemerkter Hieb direkt an
@export var combo_reset := 0.45  # s nach Hiebende, bis die Kombo wieder mit der Vorhand beginnt
@export var attack_buffer_time := 0.5  # so lange vor dem Kombofenster darf schon geklickt werden
@export var attack_move_mult := 0.2  # Laufen während eines Hiebs (gewichtig: fast stehen)
@export var swing_lunge := 1.6  # m/s Vorwärtsschub kurz vor dem Treffer
@export var thrust_damage_mult := 1.5
@export var thrust_reach_bonus := 0.8
@export var thrust_arc_deg := 28.0
@export var thrust_cost := 20.0
@export var thrust_lunge := 3.2

@export_group("Werte")
@export var max_health := 100.0
@export var max_stamina := 100.0
@export var stamina_regen := 48.0
@export var stamina_delay := 0.55

var input: PlayerInput
var cam: PlayerCamera
var body: ShadowBody
## Herkunft der Spielfigur (Ausrüstung im Stil ihrer Kaverne)
var culture := "kiln"
var abilities: Array = []  # 9 Plätze, Ability oder null

var state: State = State.MOVE
var state_t := 0.0
var facing_yaw := 0.0
var health := 100.0
var stamina := 100.0
var checkpoint := Transform3D.IDENTITY

var _coyote := 0.0
var _buffer: StringName = &""
var _buffer_ability := 0
var _buffer_t := 0.0
var _jumping := false
var _was_on_floor := true
var _stamina_wait := 0.0
var _roll_dir := Vector3.FORWARD
var _roll_peak := 0.0
var _blocking := false
var _block_t := 0.0
var _block_released_t := 10.0
var _swing_t := -1.0  # <0 = kein Schwung aktiv
var _swing_index := 0  # Clip: 0 Vorhand, 1 Rückhand, 3 Stich
var _swing_kind := 1  # 1 normal, 2 Stich
var _swing_yaw := 0.0  # Angriffsrichtung (Kamera)
var _since_swing := 10.0
var _queued_attack := 0
var _queued_t := 0.0
var _nearby: Node3D  ## nächster Gegner in Kampfnähe (nur für Haltung/Blick, kein Anvisieren)
var _swing_hit_done := false
var _anim_hitstop := 0.0
var _stagger_len := 0.4
var _ability: Ability
var _ability_slot := 0
var _dead_t := 0.0
var _move_local := Vector2.ZERO


func _ready() -> void:
	add_to_group("players")
	collision_layer = Game.LAYER_PLAYERS
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMIES
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(48)
	health = max_health
	stamina = max_stamina
	checkpoint = global_transform
	facing_yaw = rotation.y
	rotation = Vector3.ZERO

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.55
	col.shape = cap
	col.position.y = 0.775
	add_child(col)
	add_child(Hurtbox.new(self, Game.LAYER_PLAYER_HURTBOX, cap, Vector3(0, 0.775, 0)))

	_build_body()

	if is_local:
		input = PlayerInput.new()
		input.name = "Input"
		add_child(input)
		cam = PlayerCamera.new()
		cam.name = "Camera"
		cam.target = self
		cam.input = input
		cam.yaw = facing_yaw
		add_child(cam)

	abilities.resize(9)
	abilities[0] = HeavyStrike.new()
	abilities[1] = ShieldBash.new()
	Game.register_player(self)


## Spielfigur im Frayed-Stil; die Kultur (Ausrüstung) kommt aus Game.culture.
func _build_body() -> void:
	if body:
		body.queue_free()
	body = ShadowBody.new()
	body.name = "Body"
	body.outfit = culture
	body.has_lantern = true
	body.build()
	add_child(body)
	body.rotation.y = facing_yaw


## Kultur wechseln (F2 im Testlevel). Neue Figur, gleiche Werte.
func set_culture(c: String) -> void:
	culture = c
	_build_body()


func _unhandled_input(event: InputEvent) -> void:
	if is_local and event.is_action_pressed("cycle_culture"):
		var i := FrayedOutfit.CULTURES.find(culture)
		set_culture(FrayedOutfit.CULTURES[(i + 1) % FrayedOutfit.CULTURES.size()])
		FX.number(self, global_position + Vector3.UP * 2.1, FrayedOutfit.DISPLAY[culture], Color(0.95, 0.85, 0.6), true)


func _exit_tree() -> void:
	Game.unregister_player(self)


# ------------------------------------------------------------------
# Öffentliche Abfragen
# ------------------------------------------------------------------

func is_dead() -> bool:
	return state == State.DEAD


func get_facing_yaw() -> float:
	return facing_yaw


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func camera_yaw() -> float:
	return cam.yaw if cam else facing_yaw


func forward() -> Vector3:
	return Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))


func is_invulnerable() -> bool:
	return state == State.ROLL and state_t < roll_iframes


func is_blocking() -> bool:
	return _blocking


func swing_progress() -> float:
	return _swing_t / swing_duration if _swing_t >= 0.0 else -1.0


func ability_cooldown(slot: int) -> float:
	var a: Ability = abilities[slot]
	return a.cooldown_left if a else 0.0


# ------------------------------------------------------------------
# Hauptschleife
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_read_input(delta)
	_tick_timers(delta)
	_update_nearby()

	match state:
		State.MOVE:
			_state_move(delta)
		State.ROLL:
			_state_roll(delta)
		State.ABILITY:
			_state_ability(delta)
		State.STAGGER:
			_state_stagger(delta)
		State.DEAD:
			_state_dead(delta)

	_apply_gravity(delta)
	var was_air := not is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()
	if was_air and is_on_floor() and fall_speed < -6.0:
		FX.dust(self, global_position, 6, clampf(-fall_speed / 12.0, 0.6, 1.4))
		if cam:
			cam.add_trauma(clampf(-fall_speed / 60.0, 0.0, 0.25))

	if global_position.y < -40.0:
		_respawn()

	_update_swing(delta)
	_update_body(delta)


func _read_input(delta: float) -> void:
	if not input:
		return
	if input.consume_jump():
		_set_buffer(&"jump")
	if input.consume_roll():
		_set_buffer(&"roll")
	var ab := input.consume_ability()
	if ab > 0:
		_set_buffer(&"ability", ab)
	var atk := input.consume_attack()
	if atk > 0:
		_queued_attack = atk
		_queued_t = attack_buffer_time
	if _queued_t > 0.0:
		_queued_t -= delta
		if _queued_t <= 0.0:
			_queued_attack = 0
	if _buffer_t > 0.0:
		_buffer_t -= delta
		if _buffer_t <= 0.0:
			_buffer = &""


func _set_buffer(action: StringName, ability_slot := 0) -> void:
	_buffer = action
	_buffer_ability = ability_slot
	_buffer_t = buffer_time


func _consume_buffer(action: StringName) -> bool:
	if _buffer == action:
		_buffer = &""
		_buffer_t = 0.0
		return true
	return false


func _tick_timers(delta: float) -> void:
	if is_on_floor():
		_coyote = coyote_time
		_jumping = false
	else:
		_coyote -= delta
	if _swing_t < 0.0:
		_since_swing += delta
	for a in abilities:
		if a:
			a.cooldown_left = maxf(a.cooldown_left - delta, 0.0)
	_block_released_t += delta
	# Ausdauer
	if _stamina_wait > 0.0:
		_stamina_wait -= delta
	elif state == State.MOVE and stamina < max_stamina:
		var rate := stamina_regen * (0.35 if _blocking else 1.0)
		_set_stamina(stamina + rate * delta)


func _set_stamina(v: float) -> void:
	var nv := clampf(v, 0.0, max_stamina)
	if nv != stamina:
		stamina = nv
		stamina_changed.emit(stamina, max_stamina)


func _spend_stamina(amount: float) -> void:
	_set_stamina(stamina - amount)
	_stamina_wait = stamina_delay


# ------------------------------------------------------------------
# Bewegung
# ------------------------------------------------------------------

## Gewünschte Laufrichtung in Weltkoordinaten (Länge 0..1). Kümmert sich auch um die Blickrichtung.
func _desired_direction(delta: float, allow_turn := true) -> Vector3:
	if not input:
		return Vector3.ZERO
	var m := input.move
	# Kamera-relativ: W läuft dorthin, wohin die Kamera schaut; der Charakter dreht sich in Laufrichtung.
	var basis_yaw := camera_yaw()
	var dir := Basis(Vector3.UP, basis_yaw) * Vector3(m.x, 0.0, -m.y)
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	if allow_turn and _swing_t < 0.0 and dir.length_squared() > 0.01 and not _blocking:
		var want := atan2(-dir.x, -dir.z)
		facing_yaw = lerp_angle(facing_yaw, want, 1.0 - exp(-turn_sharpness * delta))
	return dir


func _state_move(delta: float) -> void:
	state_t += delta
	var dir := _desired_direction(delta)

	# Blocken (halten)
	var want_block: bool = input != null and input.block_held and is_on_floor() and _swing_t < 0.0
	if want_block and not _blocking:
		_blocking = true
		_block_t = 0.0
	elif not want_block and _blocking:
		_blocking = false
		_block_released_t = 0.0
	if _blocking:
		_block_t += delta
		# Deckung zeigt in Kamerarichtung
		facing_yaw = lerp_angle(facing_yaw, camera_yaw(), 1.0 - exp(-10.0 * delta))

	var spd := run_speed
	if _blocking:
		spd *= block_speed_mult
	var want_vel := dir * spd
	if _swing_t >= 0.0:
		want_vel = dir * spd * attack_move_mult + forward() * _lunge_speed()
	_horizontal_move(want_vel, delta)

	# Aktionen
	if _buffer == &"jump" and _coyote > 0.0:
		_consume_buffer(&"jump")
		_do_jump()
	elif _buffer == &"roll" and stamina > 0.0 and (is_on_floor() or _coyote > 0.0):
		_consume_buffer(&"roll")
		_start_roll(dir)
	elif _buffer == &"ability":
		_try_ability(_buffer_ability)
	elif _queued_attack > 0 and _can_start_attack():
		_start_attack(_queued_attack)

	# Variable Sprunghöhe
	if _jumping and velocity.y > jump_cut_speed and input and not input.jump_held:
		velocity.y = jump_cut_speed
		_jumping = false


func _horizontal_move(target_vel: Vector3, delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float
	if is_on_floor():
		rate = ground_accel if target_vel.length() > hv.length() * 0.9 else ground_decel
	else:
		rate = air_accel
	hv = hv.move_toward(target_vel, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z


func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		return
	var g := gravity_up if velocity.y > 0.0 else gravity_down
	velocity.y = maxf(velocity.y - g * delta, -max_fall)


func _do_jump() -> void:
	velocity.y = sqrt(2.0 * gravity_up * jump_height)
	_coyote = 0.0
	_jumping = true
	_blocking = false
	_cancel_swing()
	FX.dust(self, global_position, 4, 0.7)


# ------------------------------------------------------------------
# Rolle
# ------------------------------------------------------------------

func _start_roll(dir: Vector3) -> void:
	if dir.length_squared() < 0.01:
		dir = forward()
	_roll_dir = dir.normalized()
	# Spitzengeschwindigkeit so, dass die Kurve (1 - x²) genau roll_distance zurücklegt
	_roll_peak = roll_distance / (roll_duration * 2.0 / 3.0)
	_spend_stamina(roll_cost)
	_blocking = false
	_cancel_swing()
	_set_state(State.ROLL)
	facing_yaw = atan2(-_roll_dir.x, -_roll_dir.z)
	collision_mask = Game.LAYER_WORLD  # durch Gegner hindurchrollen
	FX.dust(self, global_position, 5, 0.8)


func _state_roll(delta: float) -> void:
	state_t += delta
	var x := clampf(state_t / roll_duration, 0.0, 1.0)
	var spd := _roll_peak * (1.0 - x * x)
	velocity.x = _roll_dir.x * spd
	velocity.z = _roll_dir.z * spd
	if state_t >= roll_cancel_at:
		# Ab hier kann alles Vorgemerkte die Rolle abbrechen
		if _buffer == &"roll" and stamina > 0.0 and is_on_floor():
			_consume_buffer(&"roll")
			_start_roll(_desired_direction(delta, false))
			return
		if _buffer == &"jump" and _coyote > 0.0:
			_consume_buffer(&"jump")
			_end_roll()
			_do_jump()
			return
		if _buffer == &"ability":
			_end_roll()
			_try_ability(_buffer_ability)
			return
		if _queued_attack > 0 and stamina > 0.0 and is_on_floor():
			_end_roll()
			_start_attack(_queued_attack)
			return
	if state_t >= roll_duration:
		_end_roll()
		# Schwung in die Laufbewegung mitnehmen
		var d := _desired_direction(delta)
		velocity.x = d.x * run_speed * 0.8
		velocity.z = d.z * run_speed * 0.8


func _end_roll() -> void:
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMIES
	_set_state(State.MOVE)


# ------------------------------------------------------------------
# Angriffe: Linksklick = Hieb (Kombo Vorhand/Rückhand), mittlere Maustaste = Stich, Rechtsklick = Blocken.
# Kein Anvisieren: geschlagen wird in Kamerarichtung, getroffen wird alles im Bogen.
# ------------------------------------------------------------------

func _can_start_attack() -> bool:
	if state != State.MOVE or not is_on_floor() or stamina <= 0.0:
		return false
	if _swing_t < 0.0:
		return true
	return _swing_t / swing_duration >= combo_window


func _start_attack(kind: int) -> void:
	_queued_attack = 0
	_queued_t = 0.0
	_blocking = false
	if kind == 2:
		_swing_index = 3
	elif _swing_t >= 0.0 and _swing_index == 0:
		_swing_index = 1  # Kombo: Rückhand schließt an die Vorhand an
	elif _swing_t < 0.0 and _since_swing < combo_reset and _swing_index == 0:
		_swing_index = 1
	else:
		_swing_index = 0
	_swing_kind = kind
	_swing_t = 0.0
	_swing_hit_done = false
	_since_swing = 0.0
	_spend_stamina(thrust_cost if kind == 2 else swing_cost)
	_swing_yaw = camera_yaw()
	# Dauer und Trefferzeitpunkt kommen aus der Animation (Animationswerkstatt)
	var c: Dictionary = AnimLibrary.clip(AnimLibrary.CLIPS[_swing_index])
	swing_duration = c.duration
	swing_hit_at = c.hit


## Kurzer Vorwärtsschub in den Treffer hinein (Gewicht nach vorn verlagern).
func _lunge_speed() -> float:
	if _swing_t < 0.0:
		return 0.0
	var t := _swing_t / swing_duration
	var a := swing_hit_at - 0.16
	if t < a or t > swing_hit_at + 0.04:
		return 0.0
	var x := (t - a) / 0.2
	return (thrust_lunge if _swing_kind == 2 else swing_lunge) * sin(clampf(x, 0.0, 1.0) * PI)


func _cancel_swing() -> void:
	if _swing_t >= 0.0:
		_swing_t = -1.0
		_since_swing = 10.0


func _update_swing(delta: float) -> void:
	if _swing_t < 0.0:
		return
	if state != State.MOVE:
		_cancel_swing()
		return
	if _anim_hitstop > 0.0:
		return
	_swing_t += delta
	var t := _swing_t / swing_duration
	# in der Ausholphase zur Kamerarichtung drehen, danach ist die Richtung festgelegt
	if t < swing_hit_at:
		facing_yaw = lerp_angle(facing_yaw, _swing_yaw, 1.0 - exp(-16.0 * delta))
	if not _swing_hit_done and t >= swing_hit_at:
		_swing_hit_done = true
		var info := DamageInfo.new()
		info.source = self
		if _swing_kind == 2:
			info.amount = swing_damage * thrust_damage_mult * randf_range(0.95, 1.05)
			info.knockback = 2.2
			info.poise_damage = 14.0
			info.hitstop = 0.08
			info.shake = 0.16
			hit_cone(melee_range + thrust_reach_bonus, thrust_arc_deg, info)
		else:
			info.amount = swing_damage * randf_range(0.9, 1.1)
			info.knockback = 1.5
			info.poise_damage = 8.0
			info.hitstop = 0.06
			info.shake = 0.12
			hit_cone(melee_range + 0.3, swing_arc_deg, info)
	if t >= 1.0:
		_swing_t = -1.0


func _deal_damage(victim: Node, info: DamageInfo) -> int:
	var result: int = victim.receive_hit(info)
	if result == DamageInfo.Result.HIT:
		_anim_hitstop = info.hitstop
		if cam:
			cam.add_trauma(info.shake)
	return result


# ------------------------------------------------------------------
# Fähigkeiten (Tasten 1-9) – überschreiben den Auto-Angriff für ihre Dauer
# ------------------------------------------------------------------

func _try_ability(slot: int) -> void:
	var a: Ability = abilities[slot - 1] if slot >= 1 and slot <= 9 else null
	if a == null:
		_consume_buffer(&"ability")
		return
	if a.cooldown_left > 0.0 or stamina < a.stamina_cost * 0.5:
		# Bleibt im Buffer, falls die Abklingzeit gleich vorbei ist
		return
	_consume_buffer(&"ability")
	_blocking = false
	_cancel_swing()
	_ability = a
	_ability_slot = slot
	a.cooldown_left = a.cooldown
	_spend_stamina(a.stamina_cost)
	_set_state(State.ABILITY)
	if a.snap_to_target:
		facing_yaw = camera_yaw()
	a.start(self)
	ability_used.emit(slot - 1)


func _state_ability(delta: float) -> void:
	if _anim_hitstop > 0.0:
		return
	state_t += delta
	var done := _ability.update(self, state_t, delta)
	# Rolle darf die Fähigkeit nach ihrem Treffer abbrechen
	if state_t >= _ability.cancel_at and _buffer == &"roll" and stamina > 0.0 and is_on_floor():
		_consume_buffer(&"roll")
		_start_roll(_desired_direction(delta, false))
		return
	if done:
		_set_state(State.MOVE)


## Wird von Fähigkeiten genutzt: trifft alle Gegner in einem Kegel vor dem Spieler.
func hit_cone(reach: float, arc_deg: float, info: DamageInfo) -> int:
	var count := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_dead():
			continue
		var to: Vector3 = e.global_position - global_position
		if absf(to.y) > 2.0:
			continue
		to.y = 0.0
		if to.length() > reach + e.radius:
			continue
		if to.length() > 0.5 and rad_to_deg(forward().angle_to(to.normalized())) > arc_deg:
			continue
		if _deal_damage(e, info.duplicate_info()) == DamageInfo.Result.HIT:
			count += 1
	return count


# ------------------------------------------------------------------
# Treffer einstecken
# ------------------------------------------------------------------

func receive_hit(info: DamageInfo) -> int:
	if state == State.DEAD:
		return DamageInfo.Result.IGNORED
	if is_invulnerable():
		FX.number(self, global_position + Vector3.UP * 2.0, "Dodged", Color(0.6, 0.9, 1.0))
		return DamageInfo.Result.DODGED
	var from_dir := Vector3.ZERO
	if info.source:
		from_dir = info.source.global_position - global_position
		from_dir.y = 0.0
		from_dir = from_dir.normalized()
	var in_front := from_dir != Vector3.ZERO and rad_to_deg(forward().angle_to(from_dir)) <= block_arc_deg
	if _blocking and in_front and state == State.MOVE:
		if _block_t <= parry_window and _block_released_t > 0.35:
			# Parade!
			_anim_hitstop = 0.12
			if cam:
				cam.add_trauma(0.35)
			FX.sparks(self, global_position + Vector3.UP * 1.3 + from_dir * 0.5, Color(1.0, 0.95, 0.6), 14, 1.5)
			FX.ring(self, global_position, LowPoly.CYAN, 2.5, 0.35)
			FX.number(self, global_position + Vector3.UP * 2.2, "Parry!", Color(1.0, 0.9, 0.4), true)
			if info.source and info.source.has_method("on_parried"):
				info.source.on_parried(self)
			return DamageInfo.Result.PARRIED
		var cost := info.amount * block_stamina_per_damage
		if stamina >= cost:
			_spend_stamina(cost)
			velocity += -from_dir * info.knockback * 0.6
			_anim_hitstop = 0.06
			body.flash(0.05)
			if cam:
				cam.add_trauma(0.18)
			FX.sparks(self, global_position + Vector3.UP * 1.2 + from_dir * 0.5, Color(0.9, 0.95, 1.0), 6)
			return DamageInfo.Result.BLOCKED
		# Deckung gebrochen
		_spend_stamina(stamina)
		info.amount *= 0.5
		FX.number(self, global_position + Vector3.UP * 2.2, "Guard Broken", Color(1.0, 0.5, 0.3))
		_take_damage(info, from_dir, 0.8)
		return DamageInfo.Result.GUARD_BREAK
	_take_damage(info, from_dir, 0.38)
	return DamageInfo.Result.HIT


func _take_damage(info: DamageInfo, from_dir: Vector3, stagger_len: float) -> void:
	health = maxf(health - info.amount, 0.0)
	health_changed.emit(health, max_health)
	body.flash(0.1)
	_anim_hitstop = info.hitstop
	if cam:
		cam.add_trauma(0.45)
	FX.number(self, global_position + Vector3.UP * 2.0, str(roundi(info.amount)), Color(1.0, 0.3, 0.25))
	_blocking = false
	_cancel_swing()
	velocity.x = -from_dir.x * info.knockback
	velocity.z = -from_dir.z * info.knockback
	if health <= 0.0:
		_set_state(State.DEAD)
		_dead_t = 0.0
		died.emit()
		return
	_stagger_len = stagger_len
	_set_state(State.STAGGER)


func _state_stagger(delta: float) -> void:
	state_t += delta
	_horizontal_move(Vector3.ZERO, delta * 0.4)
	if state_t >= _stagger_len:
		_set_state(State.MOVE)


func _state_dead(delta: float) -> void:
	state_t += delta
	_horizontal_move(Vector3.ZERO, delta)
	if state_t > 2.5:
		_respawn()


func _respawn() -> void:
	global_transform = checkpoint
	facing_yaw = checkpoint.basis.get_euler().y
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	health = max_health
	health_changed.emit(health, max_health)
	_set_stamina(max_stamina)
	_set_state(State.MOVE)
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMIES
	reset_physics_interpolation()
	if cam:
		cam.yaw = facing_yaw
		cam.snap_to_target()


func _set_state(s: State) -> void:
	state = s
	state_t = 0.0


# ------------------------------------------------------------------
# Gegner in der Nähe (kein Anvisieren; nur für Kampfhaltung und Kopfdrehung)
# ------------------------------------------------------------------

func _update_nearby() -> void:
	var best: Node3D = null
	var best_d := melee_range + 3.5
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_dead():
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	_nearby = best


# ------------------------------------------------------------------
# Darstellung
# ------------------------------------------------------------------

func _update_body(delta: float) -> void:
	var anim_delta := delta
	if _anim_hitstop > 0.0:
		_anim_hitstop -= delta
		anim_delta = 0.0
	body.rotation.y = facing_yaw
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	body.speed = hv.length()
	var local := hv.rotated(Vector3.UP, -facing_yaw)
	body.local_move = Vector2(local.x, -local.z) / maxf(run_speed, 0.1)
	body.on_floor = is_on_floor() or state == State.ROLL
	body.vertical_velocity = velocity.y
	body.block_amount = move_toward(body.block_amount, 1.0 if _blocking else 0.0, delta * 9.0)
	# Kampfhaltung, sobald ein anvisiertes Ziel in Reichweite ist
	# Kampfhaltung: Gegner in der Nähe oder gerade im Kampf (Hieb/Deckung)
	var engaged: bool = (_nearby != null and is_instance_valid(_nearby)) or _swing_t >= 0.0 or _since_swing < 1.5
	body.combat = 1.0 if engaged and state != State.DEAD else 0.0
	body.look_target = _nearby.target_point() if _nearby and is_instance_valid(_nearby) else null
	match state:
		State.ROLL:
			body.action = &"roll"
			body.action_t = state_t / roll_duration
		State.STAGGER:
			body.action = &"stagger"
			body.action_t = state_t / _stagger_len
		State.DEAD:
			body.action = &"dead"
			body.action_t = state_t
		State.ABILITY:
			_ability.animate(self, body, state_t)
		_:
			if _swing_t >= 0.0:
				body.action = &"swing"
				body.swing_index = _swing_index
				body.action_t = _swing_t / swing_duration
			else:
				body.action = &""
	body.tick(anim_delta)
