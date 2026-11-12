class_name Hollowed
extends Enemy
## Hollowed: humanoider Willfault. Behält die Form des Shades, aus dessen zerbrochenem Willen er entstand,
## samt Resten seiner Ausrüstung (Kultur zufällig). Zersplitterter Schatten mit kalt-violetten Augen.
## Duellgegner: verfolgt den nächsten Spieler, holt deutlich sichtbar aus
## (Augen glühen auf, Waffe hoch), schlägt zu und ist danach kurz verwundbar.
## Gut zum Testen von Blocken, Parieren und Rollen.

signal respawn_requested(hollowed: Hollowed)

const CLIP := "hollowed_strike"  ## eigene Angriffsanimation (Animationswerkstatt)
const STAGGER_CLIP := "hollowed_stagger"  ## Taumeln (auf die Taumeldauer gestreckt)
const DEATH_CLIP := "hollowed_death"  ## Tod, letzte Haltung bleibt stehen
const VIOLET := Color(0.72, 0.52, 1.0)
const HEM_HEAT := "#1c0b3d"
const HEM_HOT := "#9f6bff"

enum S { IDLE, CHASE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD }

@export var move_speed := 3.0
@export var aggro_range := 14.0
@export var attack_range := 2.3
@export var windup_time := 0.85
@export var strike_time := 0.2
@export var recover_time := 0.9
@export var damage := 18.0

var state: S = S.IDLE
var state_t := 0.0
var facing_yaw := 0.0
var body: ShadowBody
var _pivot: Node3D
var _hitbox: Hitbox
var _cooldown := 1.0
var _stagger_len := 0.5
var _poise_regen_wait := 0.0
var _strafe_sign := 1.0
var _player: Node3D


func _ready() -> void:
	display_name = "Hollowed"
	max_health = 70.0
	max_poise = 22.0
	target_height = 1.95
	super._ready()
	facing_yaw = rotation.y
	rotation = Vector3.ZERO
	body = ShadowBody.new()
	body.outfit = FrayedOutfit.CULTURES.pick_random()
	body.willfault = true
	body.hem_layers = 4
	body.head_layers = 12
	body.hem_heat = HEM_HEAT
	body.hem_hot = HEM_HOT
	body.eye_color = VIOLET
	body.has_shield = false
	body.run_speed_ref = 3.4
	body.build()
	body.scale = Vector3.ONE * 1.08
	add_child(body)
	body._trail.color = Color(0.62, 0.42, 1.0)
	_pivot = Node3D.new()
	add_child(_pivot)
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.6, 2.0)
	_hitbox = Hitbox.new(Game.LAYER_PLAYER_HURTBOX, box, Vector3(0, 1.0, -1.1))
	_pivot.add_child(_hitbox)
	_strafe_sign = 1.0 if randf() > 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if hitstop > 0.0:
		hitstop -= delta
		body.tick(0.0)
		return
	state_t += delta
	_cooldown -= delta
	_poise_regen_wait -= delta
	if _poise_regen_wait <= 0.0:
		poise = minf(poise + 15.0 * delta, max_poise)

	var desired := Vector3.ZERO
	match state:
		S.IDLE:
			_player = Game.nearest_player(global_position, aggro_range)
			if _player:
				_set_state(S.CHASE)
		S.CHASE:
			_player = Game.nearest_player(global_position, aggro_range * 1.6)
			if not _player:
				_set_state(S.IDLE)
			else:
				var to := _flat_to(_player)
				var dist := to.length()
				_turn_toward(to, 8.0, delta)
				if dist > attack_range * 0.85:
					desired = to.normalized() * move_speed
				elif _cooldown > 0.0:
					# auf Abstand umkreisen, statt dumm stehen zu bleiben
					var side := to.normalized().cross(Vector3.UP) * _strafe_sign
					desired = side * move_speed * 0.45
					if dist < attack_range * 0.6:
						desired -= to.normalized() * move_speed * 0.5
				if dist <= attack_range and _cooldown <= 0.0:
					_set_state(S.WINDUP)
		S.WINDUP:
			if _player and state_t < windup_time * 0.75:
				_turn_toward(_flat_to(_player), 10.0, delta)  # spätes Nachführen, dann festgelegt
			desired = -_forward() * 0.6  # leichtes Zurücklehnen
			body.set_eye_intensity(lerpf(2.6, 12.0, state_t / windup_time))
			if state_t >= windup_time:
				_set_state(S.STRIKE)
				var info := DamageInfo.new()
				info.amount = damage
				info.source = self
				info.knockback = 5.0
				info.hitstop = 0.08
				info.shake = 0.4
				_hitbox.activate(info)
		S.STRIKE:
			desired = _forward() * 7.0
			if state_t >= strike_time:
				_hitbox.deactivate()
				body.set_eye_intensity(2.6)
				_set_state(S.RECOVER)
		S.RECOVER:
			if state_t >= recover_time:
				_cooldown = randf_range(0.9, 1.8)
				_set_state(S.CHASE)
		S.STAGGER:
			if state_t >= _stagger_len:
				_cooldown = randf_range(0.4, 1.0)
				_set_state(S.CHASE)
		S.DEAD:
			if state_t > 3.5:
				body.position.y -= delta * 0.6  # versinkt im Boden
			if state_t > 5.5:
				respawn_requested.emit(self)
				queue_free()

	# Geschwindigkeit: gewünschte Bewegung + abklingender Rückstoß
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(desired + _knock, 40.0 * delta)
	_knock = _knock.move_toward(Vector3.ZERO, 18.0 * delta)
	hv = _forced_velocity(hv, delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	_pivot.rotation.y = facing_yaw
	_animate(delta)


func _animate(delta: float) -> void:
	body.rotation.y = facing_yaw
	var hv := Vector3(velocity.x, 0, velocity.z)
	body.speed = hv.length() if state in [S.CHASE, S.IDLE] else 0.0
	var local := hv.rotated(Vector3.UP, -facing_yaw)
	body.local_move = Vector2(local.x, -local.z) / move_speed
	body.on_floor = true
	body.combat = 1.0 if _player and state != S.DEAD and _player.global_position.distance_to(global_position) < 7.0 else 0.0
	body.look_target = (_player.global_position + Vector3.UP * 1.4) if _player and state != S.DEAD else null
	var tr: Vector2 = AnimLibrary.clip(CLIP).trail  # Ausholen | Schlag | Erholen, in der Werkstatt einstellbar
	body.swing_clip = CLIP
	match state:
		S.WINDUP:
			body.action = &"swing"
			body.action_t = tr.x * (state_t / windup_time)
		S.STRIKE:
			body.action = &"swing"
			body.action_t = tr.x + (tr.y - tr.x) * (state_t / strike_time)
		S.RECOVER:
			body.action = &"swing"
			body.action_t = tr.y + (1.0 - tr.y) * (state_t / recover_time)
		S.STAGGER:
			body.action = &"swing"
			body.swing_clip = STAGGER_CLIP
			body.action_t = minf(state_t / _stagger_len, 1.0)
		S.DEAD:
			body.action = &"swing"
			body.swing_clip = DEATH_CLIP
			body.action_t = minf(state_t / AnimLibrary.clip(DEATH_CLIP).duration, 1.0)
		_:
			body.action = &""
	body.tick(delta)


func _flat_to(n: Node3D) -> Vector3:
	var to := n.global_position - global_position
	to.y = 0.0
	return to


func _forward() -> Vector3:
	return Vector3(-sin(facing_yaw), 0, -cos(facing_yaw))


func _turn_toward(dir: Vector3, sharpness: float, delta: float) -> void:
	if dir.length_squared() < 0.001:
		return
	facing_yaw = lerp_angle(facing_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-sharpness * delta))


func _set_state(s: S) -> void:
	state = s
	state_t = 0.0


func _stagger(duration: float) -> void:
	_hitbox.deactivate()
	body.set_eye_intensity(2.6)
	_stagger_len = duration
	poise = max_poise
	_set_state(S.STAGGER)


func _on_hit(_info: DamageInfo, _dir: Vector3) -> void:
	body.flash(0.09)
	_poise_regen_wait = 2.0
	if state == S.IDLE:
		_player = Game.nearest_player(global_position, 40.0)
		_set_state(S.CHASE)
	if poise <= 0.0 and state != S.DEAD and not (state == S.STAGGER and _stagger_len - state_t > 0.55):
		_stagger(0.55)


func hold(duration: float) -> void:
	if state != S.DEAD:
		_stagger(duration)


func on_parried(_by: Node3D) -> void:
	_stagger(1.4)
	FX.number(self, target_point(), "Staggered", Color(0.6, 0.95, 1.0))


func _on_death() -> void:
	_hitbox.deactivate()
	body.set_eye_intensity(0.0)
	remove_from_group("targetable")
	remove_from_group("enemies")
	collision_layer = 0
	for c in get_children():
		if c is Hurtbox:
			c.collision_layer = 0
	_set_state(S.DEAD)
