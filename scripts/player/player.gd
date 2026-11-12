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

enum State { MOVE, ROLL, ABILITY, STAGGER, DEAD, CLIMB, LEDGE_UP, SWIM }

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

@export_group("Sprint")
@export var sprint_speed := 7.0
@export var sprint_cost := 15.0  ## Ausdauer pro Sekunde
@export var sprint_recover := 25.0  ## nach Erschöpfung erst wieder ab dieser Ausdauer

@export_group("Ausrüstung")
@export var sheathe_after := 6.0  ## s ohne Kampf -> Waffe automatisch wegstecken (außer mit Y gezogen)
@export var quick_draw := 1.8  ## Ziehtempo, wenn ein Angriff/Block die Waffe zieht

@export_group("Klettern")
@export var climb_speed := 1.25
@export var climb_cost_move := 10.0  ## Ausdauer pro Sekunde beim Klettern
@export var climb_cost_hold := 3.5  ## Ausdauer pro Sekunde beim Festhalten
@export var climb_wall_dist := 0.36

@export_group("Schwimmen")
@export var swim_speed := 2.3
@export var swim_sprint_speed := 3.4
@export var swim_sprint_cost := 10.0
@export var swim_float_depth := 1.12  ## Wasserlinie über den Füßen beim Schwimmen (Kopf und Schultern draußen)
@export var swim_enter_depth := 1.1
@export var ledge_up_time := 1.05

@export_group("Sturz")
@export var fall_roll_height := 3.2  ## ab dieser Fallhöhe rollt die Figur beim Aufkommen ab

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
## Waffe und Zweithand-Teil (Schild oder Dolch; Licht kommt per X dazu)
var weapon: WeaponDef = WeaponDef.make(&"sword")
var offhand_choice: StringName = &"shield"  ## &"shield", &"dagger" oder &""
## Kombo-Kette: Linksklick spielt die Bausteine der Reihe nach ab (leere Plätze werden übersprungen)
const CHAIN_SLOTS := 5
var combo_chain: Array[StringName] = []
var combo_pool: Array[StringName] = []  ## gefundene Bausteine (Prototyp: alle)
var chain_reset := 1.4  ## s ohne Angriff, bis die Kette wieder vorn beginnt
var _module: ComboModule  ## laufender Baustein (null = Stich auf der mittleren Maustaste)
var _chain_i := 0  ## nächster Platz in der Kette
var _chain_idle := 99.0
var _hit_i := 0  ## nächster Treffer des laufenden Bausteins
var _off_jab_t := -1.0  ## Zweithand-Dolch sticht kurz nach dem Treffer nach
var _chain_pos := -1  ## Platz des laufenden Bausteins (fürs HUD)
var _swing_clip := ""  ## Animationsclip des laufenden Schlags (ggf. eigene Version der Waffe)

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
var _roll_kind: StringName = &"fwd"
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
# Ausrüstung
var weapon_out := false  ## Waffe (und Schild, wenn kein Licht vorgehalten) soll gezogen sein
var light_out := false  ## Licht wird vorgehalten
var _manual_draw := false  ## mit Y gezogen -> kein automatisches Wegstecken
var _since_combat := 99.0
var _light_before := false
# Sprint
var sprinting := false
var _exhausted := false
# Klettern, Hochziehen, Schwimmen, Sturz
var _climb_n := Vector3.BACK
var _climb_lock := 0.0
var _climb_phase := 0.0
var _ledge_from := Vector3.ZERO
var _ledge_to := Vector3.ZERO
var _ledge_edge := Vector3.ZERO
var _push_ledge_t := 0.0
var water_y := NAN  ## Wasseroberfläche an der Spielerposition (NAN = kein Wasser)
var _swim_phase := 0.0
var _water_enter_t := -1.0
var _ripple_t := 0.0
var _air_peak := 0.0
var _landing_roll := false


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
	combo_pool = ComboModules.all_ids()
	combo_chain.assign(ComboModules.DEFAULT_CHAIN)
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
	body.set_weapon(weapon)
	body.set_equipment(weapon_out, _off_wish())


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


## Was die linke Hand halten soll: Licht hat Vorrang, sonst Schild bei gezogener Waffe.
func _off_wish() -> StringName:
	if light_out:
		return &"light"
	if not weapon_out or not weapon.allows_offhand():
		return &""
	return offhand_choice


## Waffe wechseln (Kombo-Menü im Testlevel). Bausteine, die nur mit der alten Waffe gingen, bleiben in der Kette,
## werden aber übersprungen, bis man wieder eine passende Waffe führt.
func set_weapon(weapon_id: StringName) -> void:
	weapon = WeaponDef.make(weapon_id)
	_cancel_swing()
	body.set_weapon(weapon)
	body.set_equipment(weapon_out, _off_wish())


## Zweithand wählen: &"shield", &"dagger" oder &"" (frei -> Vielseitig-Waffen beidhändig).
func set_offhand(item: StringName) -> void:
	offhand_choice = item
	_cancel_swing()
	body.set_equipment(weapon_out, _off_wish())


func set_chain_slot(i: int, module_id: StringName) -> void:
	while combo_chain.size() < CHAIN_SLOTS:
		combo_chain.append(&"")
	combo_chain[i] = module_id
	_chain_i = 0


## Platz des Bausteins, der beim nächsten Klick kommt (-1 = Kette leer).
func next_chain_slot() -> int:
	var start := _chain_i if _chain_idle < chain_reset or _swing_t >= 0.0 else 0
	for k in CHAIN_SLOTS:
		var i := (start + k) % CHAIN_SLOTS
		if i < combo_chain.size() and combo_chain[i] != &"" and ComboModules.usable(combo_chain[i], weapon):
			return i
	return -1


func current_chain_slot() -> int:
	return _chain_pos if _swing_t >= 0.0 and _module else -1


func _apply_equipment() -> void:
	body.want_weapon = weapon_out
	body.want_off = _off_wish()


## Waffe ziehen, weil gekämpft wird (Angriff, Block, Fähigkeit). Bleibt nicht dauerhaft gezogen.
func _ensure_drawn() -> void:
	_since_combat = 0.0
	if not weapon_out:
		weapon_out = true
		_manual_draw = false
		body.draw_speed = quick_draw
		_apply_equipment()


## Alles sofort wegstecken (Klettern, Schwimmen). Das Licht kommt danach wieder, falls es vorgehalten war.
func _stow_all_now() -> void:
	_light_before = light_out or _light_before
	weapon_out = false
	light_out = false
	_manual_draw = false
	_blocking = false
	_cancel_swing()
	body.set_equipment(false, &"")


func _restore_light() -> void:
	if _light_before:
		light_out = true
		_light_before = false
		_apply_equipment()


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
	water_y = WaterVolume.surface_at(get_tree(), global_position)
	if state in [State.MOVE, State.ROLL, State.STAGGER] and not is_nan(water_y) and water_y - global_position.y > swim_enter_depth:
		_enter_swim()

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
		State.CLIMB:
			_state_climb(delta)
		State.LEDGE_UP:
			_state_ledge_up(delta)
		State.SWIM:
			_state_swim(delta)

	if state != State.LEDGE_UP:
		_apply_gravity(delta)
		var was_air := not is_on_floor()
		var fall_speed := velocity.y
		move_and_slide()
		if was_air and is_on_floor():
			var drop := _air_peak - global_position.y
			if fall_speed < -6.0:
				FX.dust(self, global_position, 6, clampf(-fall_speed / 12.0, 0.6, 1.4))
				if cam:
					cam.add_trauma(clampf(-fall_speed / 60.0, 0.0, 0.25))
			if drop >= fall_roll_height and state == State.MOVE:
				_start_landing_roll()
	if is_on_floor() or state in [State.CLIMB, State.SWIM, State.LEDGE_UP]:
		_air_peak = global_position.y
	else:
		_air_peak = maxf(_air_peak, global_position.y)

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
	if input.consume_draw():
		_toggle_weapon()
	if input.consume_light():
		_toggle_light()
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
		_chain_idle += delta
	if _off_jab_t >= 0.0:
		_off_jab_t -= delta
		if _off_jab_t < 0.0:
			_offhand_jab()
	for a in abilities:
		if a:
			a.cooldown_left = maxf(a.cooldown_left - delta, 0.0)
	_block_released_t += delta
	_climb_lock = maxf(_climb_lock - delta, 0.0)
	# Automatisch wegstecken, wenn eine Weile nicht gekämpft wurde
	var fighting := _swing_t >= 0.0 or _blocking or state == State.ABILITY or state == State.STAGGER or _nearby != null
	_since_combat = 0.0 if fighting else _since_combat + delta
	if weapon_out and not _manual_draw and _since_combat > sheathe_after and state == State.MOVE:
		weapon_out = false
		body.draw_speed = 1.0
		_apply_equipment()
	if body.weapon_ready() and (body.off_item == &"" or body.off_p >= 2.0):
		body.draw_speed = 1.0
	# Ausdauer
	if _stamina_wait > 0.0:
		_stamina_wait -= delta
	elif state in [State.MOVE, State.SWIM] and stamina < max_stamina and not sprinting:
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
func _desired_direction(delta: float, allow_turn := true, turn_rate := -1.0) -> Vector3:
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
		var tr := turn_rate if turn_rate > 0.0 else (turn_sharpness * (0.65 if sprinting else 1.0))
		facing_yaw = lerp_angle(facing_yaw, want, 1.0 - exp(-tr * delta))
	return dir


func _state_move(delta: float) -> void:
	state_t += delta
	var dir := _desired_direction(delta)

	# Blocken (halten): zieht Waffe und Schild; geblockt wird erst, wenn sie in der Hand sind
	var want_block: bool = input != null and input.block_held and is_on_floor() and _swing_t < 0.0
	if want_block:
		_ensure_drawn()
		var shield_coming: bool = body.has_shield and body.want_off == &"shield"
		want_block = body.shield_ready() if shield_coming else body.weapon_ready()
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

	# Sprint (Shift halten): kostet Ausdauer; leer -> erst nach etwas Erholung wieder
	if _exhausted and stamina >= sprint_recover:
		_exhausted = false
	var want_sprint: bool = input != null and input.sprint_held and dir.length() > 0.3 and not _blocking and _swing_t < 0.0
	sprinting = want_sprint and not _exhausted and stamina > 0.0 and (is_on_floor() or sprinting)
	if sprinting and is_on_floor():
		_set_stamina(stamina - sprint_cost * delta)
		_stamina_wait = stamina_delay
		if stamina <= 0.0:
			_exhausted = true
			sprinting = false

	var spd := sprint_speed if sprinting else run_speed
	if _blocking:
		spd *= block_speed_mult
	# im flachen Wasser waten
	if not is_nan(water_y):
		var wade := clampf((water_y - global_position.y - 0.3) / 0.8, 0.0, 1.0)
		spd *= lerpf(1.0, 0.55, wade)
	var want_vel := dir * spd
	if _swing_t >= 0.0:
		want_vel = dir * spd * attack_move_mult + forward() * _lunge_speed()
		if _module:
			want_vel += _module.extra_velocity(self, _swing_t / swing_duration)
	_horizontal_move(want_vel, delta)

	# Klettern: gegen eine Kletterfläche laufen (Gitter, Flechten)
	if dir.length() > 0.3 and _swing_t < 0.0 and _try_start_climb(dir):
		return

	# Aktionen
	if _buffer == &"jump" and _coyote > 0.0:
		_consume_buffer(&"jump")
		_do_jump()
	elif _buffer == &"roll" and stamina > 0.0 and (is_on_floor() or _coyote > 0.0):
		_consume_buffer(&"roll")
		_start_roll(dir)
	elif _buffer == &"ability":
		var ab: Ability = abilities[_buffer_ability - 1] if _buffer_ability >= 1 and _buffer_ability <= 9 else null
		if ab and ab.needs_shield and (light_out or not body.has_shield):
			_consume_buffer(&"ability")
			FX.number(self, global_position + Vector3.UP * 2.1, "Needs a shield", Color(0.9, 0.8, 0.6))
		elif ab and ab.needs_shield and not body.shield_ready():
			_ensure_drawn()
			_buffer_t = maxf(_buffer_t, 0.1)
		elif body.weapon_ready():
			_try_ability(_buffer_ability)
		else:
			_ensure_drawn()
			_buffer_t = maxf(_buffer_t, 0.1)  # vorgemerkt lassen, bis die Waffe in der Hand ist
	elif _queued_attack > 0 and state == State.MOVE and is_on_floor():
		if not body.weapon_ready():
			_ensure_drawn()
			_queued_t = maxf(_queued_t, 0.1)
		elif _can_start_attack():
			_start_attack(_queued_attack)

	# Variable Sprunghöhe
	if _jumping and velocity.y > jump_cut_speed and input and not input.jump_held:
		velocity.y = jump_cut_speed
		_jumping = false


## Y: Waffe ziehen (bleibt dann gezogen) oder wegstecken.
func _toggle_weapon() -> void:
	if state in [State.CLIMB, State.SWIM, State.LEDGE_UP, State.DEAD]:
		return
	if weapon_out:
		weapon_out = false
		_manual_draw = false
		_blocking = false
		_cancel_swing()
	else:
		weapon_out = true
		_manual_draw = true
		_since_combat = 0.0
	body.draw_speed = 1.0
	_apply_equipment()


## X: Licht vorhalten oder wegstecken. Weggesteckt nimmt die linke Hand wieder den Schild (bei gezogener Waffe).
func _toggle_light() -> void:
	if state in [State.CLIMB, State.SWIM, State.LEDGE_UP, State.DEAD] or not body.has_light_item():
		return
	light_out = not light_out
	_light_before = false
	_blocking = false
	body.draw_speed = 1.0
	_apply_equipment()


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
	if state in [State.CLIMB, State.SWIM]:
		return
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

## Rolle. Mit gezogener Waffe zählt die Richtung relativ zur Kamera: zurück = Rückwärtsrolle,
## seitlich = Seitenrolle (Blick bleibt beim Gegner/in Kamerarichtung). Sonst immer vorwärts in Laufrichtung.
func _start_roll(dir: Vector3, kind: StringName = &"", landing := false) -> void:
	if dir.length_squared() < 0.01:
		dir = forward()
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	if kind == &"":
		kind = &"fwd"
		if body.weapon_p >= 1.0 and input and input.move.length() > 0.2:
			var m := input.move
			var ang := rad_to_deg(atan2(m.x, m.y))  # 0 = vorwärts (Kamera), 180 = zurück
			if absf(ang) > 125.0:
				kind = &"back"
			elif absf(ang) > 50.0:
				kind = &"right" if ang > 0.0 else &"left"
	_roll_kind = kind
	_roll_dir = dir
	var dist := roll_distance
	match kind:
		&"back":
			dist = roll_distance * 0.8
		&"left", &"right":
			dist = roll_distance * 0.9
	# Spitzengeschwindigkeit so, dass die Kurve (1 - x²) genau dist zurücklegt
	_roll_peak = dist / (roll_duration * 2.0 / 3.0)
	if not landing:
		_spend_stamina(roll_cost)
	_blocking = false
	sprinting = false
	_cancel_swing()
	_set_state(State.ROLL)
	if kind == &"fwd":
		facing_yaw = atan2(-_roll_dir.x, -_roll_dir.z)
	elif kind == &"back" and landing:
		facing_yaw = atan2(_roll_dir.x, _roll_dir.z)  # Blick zur Wand, Rolle weg davon
	elif not landing:
		facing_yaw = camera_yaw()
	if landing:
		state_t = roll_duration * 0.1  # Abtauchen entfällt: der Sturz ist die Ausholbewegung
		if kind == &"fwd":
			var hv := Vector2(velocity.x, velocity.z).length()
			_roll_peak = maxf(_roll_peak, hv * 1.1)
	collision_mask = Game.LAYER_WORLD  # durch Gegner hindurchrollen
	FX.dust(self, global_position, 5, 0.8)


## Aufkommen nach einem tiefen Sturz: abrollen nach vorn, oder nach hinten, wenn vorn kein Platz ist.
func _start_landing_roll() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var dir := hv.normalized() if hv.length() > 0.8 else forward()
	FX.dust(self, global_position, 10, 1.3)
	if _space_ahead(dir, 2.4):
		_start_roll(dir, &"fwd", true)
	else:
		_start_roll(-dir, &"back", true)
		# nur so weit zurückrollen, wie Platz ist
		var from := global_position + Vector3.UP * 0.5
		var hit := _ray(from, from - dir * 3.2)
		if not hit.is_empty():
			var room := maxf(from.distance_to(hit.position) - 0.45, 0.6)
			_roll_peak = minf(_roll_peak, room / (roll_duration * 0.9 * 2.0 / 3.0))


## Ist in Richtung dir Platz für eine Rolle (keine Wand, Boden vorhanden)?
func _space_ahead(dir: Vector3, dist: float) -> bool:
	var from := global_position + Vector3.UP * 0.5
	if not _ray(from, from + dir * dist).is_empty():
		return false
	var end := global_position + dir * dist * 0.85
	return not _ray(end + Vector3.UP * 0.5, end + Vector3.DOWN * 0.8).is_empty()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.LAYER_WORLD)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


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
# Klettern an Gittern, Flechten u. Ä. (Gruppe "climbable"). Kostet Ausdauer; leer = loslassen.
# ------------------------------------------------------------------

func _climbable_hit(from: Vector3, dir: Vector3, length: float) -> Dictionary:
	var hit := _ray(from, from + dir * length)
	if hit.is_empty() or not (hit.collider as Node).is_in_group("climbable"):
		return {}
	var n: Vector3 = hit.normal
	if absf(n.y) > 0.4:
		return {}
	return hit


func _try_start_climb(dir: Vector3) -> bool:
	if _climb_lock > 0.0 or stamina < 5.0:
		return false
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var hit := _climbable_hit(global_position + Vector3.UP * 1.1, d, 0.75)
	if hit.is_empty():
		return false
	var n: Vector3 = hit.normal
	n = Vector3(n.x, 0.0, n.z).normalized()
	if d.dot(-n) < 0.55:
		return false
	_stow_all_now()
	sprinting = false
	_climb_n = n
	_set_state(State.CLIMB)
	velocity = Vector3.ZERO
	facing_yaw = atan2(n.x, n.z)
	return true


func _end_climb() -> void:
	_set_state(State.MOVE)
	_restore_light()


func _state_climb(delta: float) -> void:
	state_t += delta
	var n := _climb_n
	var m := input.move if input else Vector2.ZERO
	if m.length() > 1.0:
		m = m.normalized()
	# Abspringen (nach hinten weg) oder loslassen
	if _consume_buffer(&"jump"):
		velocity = n * 3.6 + Vector3.UP * 4.5
		facing_yaw = atan2(-n.x, -n.z)
		_climb_lock = 0.4
		_end_climb()
		return
	if _consume_buffer(&"roll"):
		velocity = n * 1.0
		_climb_lock = 0.6
		_end_climb()
		return
	# Ausdauer
	var moving := m.length() > 0.1
	_set_stamina(stamina - (climb_cost_move if moving else climb_cost_hold) * delta)
	_stamina_wait = stamina_delay
	if stamina <= 0.0:
		FX.number(self, global_position + Vector3.UP * 2.0, "Exhausted", Color(1.0, 0.6, 0.35))
		velocity = n * 1.2
		_climb_lock = 1.2
		_exhausted = true
		_end_climb()
		return
	var fwd := -n
	var right := fwd.cross(Vector3.UP).normalized()
	var chest := global_position + Vector3.UP * 1.1
	var vx := m.x * climb_speed
	var vy := m.y * climb_speed
	# oben: reicht die Kletterfläche noch? Sonst über die Kante hochziehen oder anhalten
	if vy > 0.0 and _climbable_hit(chest + Vector3.UP * 0.5, fwd, 0.8).is_empty():
		vy = 0.0
		if _try_ledge(fwd, global_position.y + 0.6, global_position.y + 2.3):
			return
	# seitlich: nur so weit die Fläche reicht
	if vx != 0.0 and _climbable_hit(chest + right * signf(vx) * 0.38, fwd, 0.8).is_empty():
		vx = 0.0
	# unten: Boden erreicht -> loslassen
	if vy < 0.0 and not _ray(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 0.12).is_empty():
		_end_climb()
		return
	var vel := right * vx + Vector3.UP * vy
	# an der Wand halten (Abstand nachregeln, Wandnormale nachführen)
	var hit := _climbable_hit(chest, fwd, 1.0)
	if hit.is_empty():
		_end_climb()
		return
	var hn: Vector3 = hit.normal
	_climb_n = Vector3(hn.x, 0.0, hn.z).normalized()
	var want: Vector3 = (hit.position as Vector3) + _climb_n * climb_wall_dist
	var err := Vector3(want.x - global_position.x, 0.0, want.z - global_position.z)
	vel += err * 10.0
	velocity = vel
	facing_yaw = lerp_angle(facing_yaw, atan2(_climb_n.x, _climb_n.z), 1.0 - exp(-12.0 * delta))
	_climb_phase += Vector2(vx, vy).length() * delta / 0.5 * PI


## Kante vor dem Spieler suchen (Oberkante zwischen min_y und max_y) und sich hochziehen.
func _try_ledge(fwd: Vector3, min_y: float, max_y: float) -> bool:
	var probe := global_position + fwd * (climb_wall_dist + 0.25)
	var top := _ray(Vector3(probe.x, max_y + 0.3, probe.z), Vector3(probe.x, min_y - 0.1, probe.z))
	if top.is_empty() or (top.normal as Vector3).y < 0.7:
		return false
	var ty: float = (top.position as Vector3).y
	if ty < min_y or ty > max_y:
		return false
	# Platz zum Stehen oben?
	var stand := Vector3(probe.x, ty, probe.z) + fwd * 0.3
	if not _ray(stand + Vector3.UP * 0.2, stand + Vector3.UP * 1.6).is_empty():
		return false
	# Wandlinie: wo genau beginnt die Kante?
	var edge := Vector3(probe.x, ty, probe.z) - fwd * 0.25
	var wall := _ray(global_position + Vector3(0, ty - global_position.y - 0.1, 0), global_position + Vector3(0, ty - global_position.y - 0.1, 0) + fwd * 1.2)
	if not wall.is_empty():
		edge = Vector3((wall.position as Vector3).x, ty, (wall.position as Vector3).z)
	_start_ledge_up(edge, fwd)
	return true


func _start_ledge_up(edge: Vector3, fwd: Vector3) -> void:
	_ledge_from = global_position
	_ledge_edge = edge
	_ledge_to = edge + fwd * 0.45
	_ledge_to.y = edge.y + 0.02
	facing_yaw = atan2(-fwd.x, -fwd.z)
	velocity = Vector3.ZERO
	collision_mask = 0
	_set_state(State.LEDGE_UP)


func _state_ledge_up(delta: float) -> void:
	state_t += delta
	var t := clampf(state_t / ledge_up_time, 0.0, 1.0)
	var lift_y := maxf(_ledge_from.y, _ledge_edge.y - 0.68)
	var p := _ledge_from
	var a := smoothstep(0.0, 0.45, t)
	p.y = lerpf(_ledge_from.y, lift_y, a)
	var b := smoothstep(0.42, 0.85, t)
	if b > 0.0:
		p = Vector3(lerpf(_ledge_from.x, _ledge_to.x, b), lerpf(lift_y, _ledge_to.y, smoothstep(0.42, 0.75, t)), lerpf(_ledge_from.z, _ledge_to.z, b))
	velocity = (p - global_position) / maxf(delta, 1e-4)
	global_position = p
	if t >= 1.0:
		velocity = Vector3.ZERO
		collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMIES
		_set_state(State.MOVE)
		_restore_light()


# ------------------------------------------------------------------
# Schwimmen (kein Tauchen): Kopf und Schultern bleiben über Wasser.
# ------------------------------------------------------------------

func _enter_swim() -> void:
	var impact := -velocity.y
	if state == State.ROLL:
		_end_roll()
	_stow_all_now()
	sprinting = false
	_set_state(State.SWIM)
	_water_enter_t = 0.0 if impact > 4.0 else -1.0
	_push_ledge_t = 0.0
	var at := Vector3(global_position.x, water_y, global_position.z)
	# Aufprall: das Wasser bremst den Sturz stark ab (sonst schlägt man auf den Grund)
	velocity.y = maxf(velocity.y * 0.35, -7.0)
	velocity.x *= 0.5
	velocity.z *= 0.5
	if impact > 4.0:
		WaterFX.splash(self, at, clampf(impact / 10.0, 0.5, 1.6))
		if cam:
			cam.add_trauma(clampf(impact / 70.0, 0.0, 0.2))
	else:
		WaterFX.ripple(self, at, 1.4, 1.0)


func _state_swim(delta: float) -> void:
	state_t += delta
	if is_nan(water_y):
		_set_state(State.MOVE)
		_restore_light()
		return
	if _water_enter_t >= 0.0:
		_water_enter_t += delta
		if _water_enter_t > 0.75:
			_water_enter_t = -1.0
	var dir := _desired_direction(delta, true, 4.0)
	var fast: bool = input != null and input.sprint_held and dir.length() > 0.3 and stamina > 0.0 and not _exhausted
	if _exhausted and stamina >= sprint_recover:
		_exhausted = false
	sprinting = fast
	if fast:
		_set_stamina(stamina - swim_sprint_cost * delta)
		_stamina_wait = stamina_delay
		if stamina <= 0.0:
			_exhausted = true
	var spd := swim_sprint_speed if fast else swim_speed
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(dir * spd, 3.5 * delta)
	if _water_enter_t >= 0.0:
		hv *= exp(-3.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	# Auftrieb: federt zur Schwimmhöhe (nach einem Sprung erst tief rein, dann hoch)
	var target_y := water_y - swim_float_depth + sin(state_t * 2.3) * 0.025
	velocity.y += ((target_y - global_position.y) * 30.0 - velocity.y * 7.5) * delta
	# Schwimmzyklus, Ringwellen
	var sp := hv.length()
	_swim_phase += delta * lerpf(3.0, 6.0 if fast else 5.0, clampf(sp / swim_speed, 0.0, 1.0))
	_ripple_t -= delta
	if _ripple_t <= 0.0:
		_ripple_t = 0.28 if sp > 0.5 else 1.1
		WaterFX.ripple(self, Vector3(global_position.x, water_y, global_position.z), 0.8 + sp * 0.25, 1.0)
	# Rausklettern: gegen eine niedrige Kante schwimmen (oder Springen drücken)
	var at_ledge := false
	if dir.length() > 0.3 or _buffer == &"jump":
		var fwd := dir.normalized() if dir.length() > 0.3 else forward()
		var wall := _ray(Vector3(global_position.x, water_y - 0.15, global_position.z), Vector3(global_position.x, water_y - 0.15, global_position.z) + fwd * 0.75)
		if not wall.is_empty() and absf((wall.normal as Vector3).y) < 0.4:
			at_ledge = true
			_push_ledge_t += delta
			if _push_ledge_t > 0.15 or _consume_buffer(&"jump"):
				var n: Vector3 = wall.normal
				var f := -Vector3(n.x, 0.0, n.z).normalized()
				if _try_ledge(f, water_y - 0.2, water_y + 1.1):
					WaterFX.splash(self, Vector3(global_position.x, water_y, global_position.z), 0.5)
					return
	if not at_ledge:
		_push_ledge_t = 0.0
	_consume_buffer(&"jump")
	# flaches Ufer: wieder laufen
	if is_on_floor() and water_y - global_position.y < swim_enter_depth - 0.12:
		_set_state(State.MOVE)
		_restore_light()


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
	_module = null
	_hit_i = 0
	if kind == 1:
		var slot := next_chain_slot()
		if slot >= 0:
			_start_module(slot)
			return
	combo_window = 0.68
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
	_swing_clip = AnimLibrary.resolve(AnimLibrary.CLIPS[_swing_index], String(weapon.id))
	var c: Dictionary = AnimLibrary.clip(_swing_clip)
	swing_duration = c.duration
	swing_hit_at = c.hit


## Baustein aus der Kette starten.
func _start_module(slot: int) -> void:
	var m := ComboModules.make(combo_chain[slot])
	_module = m
	_chain_pos = slot
	_chain_i = (slot + 1) % CHAIN_SLOTS
	_chain_idle = 0.0
	_swing_kind = 1
	_swing_t = 0.0
	_swing_hit_done = false
	_since_swing = 0.0
	_swing_yaw = camera_yaw()
	m.setup(self)
	swing_duration = m.duration
	swing_hit_at = m.hits[0]
	combo_window = m.window
	_swing_index = maxi(AnimLibrary.CLIPS.find(m.clip), 0)
	_swing_clip = m.clip_for(self)
	_spend_stamina(m.cost * weapon.cost)
	facing_yaw = lerp_angle(facing_yaw, _swing_yaw, 0.5)
	m.begin(self)


## Kurzer Vorwärtsschub in den Treffer hinein (Gewicht nach vorn verlagern).
func _lunge_speed() -> float:
	if _swing_t < 0.0:
		return 0.0
	if _module:
		return _module.move_speed(self, _swing_t / swing_duration)
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
		_module = null


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
	if t < swing_hit_at and not (_module and _module is ComboModules.Slip):
		facing_yaw = lerp_angle(facing_yaw, _swing_yaw, 1.0 - exp(-16.0 * delta))
	if _module:
		while _hit_i < _module.hits.size() and t >= _module.hits[_hit_i]:
			_module.strike(self, _hit_i)
			_hit_i += 1
			if body.off_item == &"dagger" and body.off_p >= 2.0 and _module.body_action == &"swing":
				_off_jab_t = 0.13
				body.off_jab = 1.0
		_swing_hit_done = _hit_i >= _module.hits.size()
	if not _swing_hit_done and t >= swing_hit_at:
		_swing_hit_done = true
		var info := DamageInfo.new()
		info.source = self
		if _swing_kind == 2:
			info.amount = swing_damage * thrust_damage_mult * weapon.eff_damage(body.off_item) * randf_range(0.95, 1.05)
			info.knockback = 2.2
			info.poise_damage = 14.0
			info.hitstop = 0.08
			info.shake = 0.16
			hit_cone(melee_range + thrust_reach_bonus + weapon.eff_reach(body.off_item), thrust_arc_deg, info)
		else:
			info.amount = swing_damage * randf_range(0.9, 1.1)
			info.knockback = 1.5
			info.poise_damage = 8.0
			info.hitstop = 0.06
			info.shake = 0.12
			hit_cone(melee_range + 0.3, swing_arc_deg, info)
	if t >= 1.0:
		_swing_t = -1.0
		_module = null


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


## Gegner im Kegel vor dem Spieler (nach Abstand sortiert). `dir` = Mittelachse (Standard: Blickrichtung).
func targets_in_cone(reach: float, arc_deg: float, only_nearest := false, dir := Vector3.ZERO) -> Array[Enemy]:
	var fwd := forward() if dir == Vector3.ZERO else dir
	var found: Array[Enemy] = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead():
			continue
		var to: Vector3 = e.global_position - global_position
		if absf(to.y) > 2.0:
			continue
		to.y = 0.0
		if to.length() > reach + e.radius:
			continue
		if to.length() > 0.5 and rad_to_deg(fwd.angle_to(to.normalized())) > arc_deg:
			continue
		found.append(e)
	found.sort_custom(func(a: Enemy, b: Enemy): return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	if only_nearest and found.size() > 1:
		found.resize(1)
	return found


## Schadenswerte eines Bausteins mit der aktuellen Waffe.
func module_info(m: ComboModule) -> DamageInfo:
	var info := DamageInfo.new()
	info.source = self
	info.amount = m.damage * weapon.eff_damage(body.off_item) * randf_range(0.92, 1.08)
	info.knockback = m.knockback
	info.poise_damage = m.poise * weapon.poise
	info.hitstop = m.hitstop
	info.shake = m.shake * (1.4 if weapon.grip == &"2h" else 1.0)
	return info


func camera_forward() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, camera_yaw())


func time_since_block() -> float:
	return 0.0 if _blocking else _block_released_t


func face_toward(pos: Vector3) -> void:
	var to := pos - global_position
	if Vector2(to.x, to.z).length() > 0.05:
		facing_yaw = atan2(-to.x, -to.z)
		_swing_yaw = facing_yaw


## Zweithand-Dolch sticht nach: kleiner Zusatztreffer ohne Reaktionen.
func _offhand_jab() -> void:
	var info := DamageInfo.new()
	info.source = self
	info.amount = swing_damage * 0.35 * randf_range(0.9, 1.1)
	info.knockback = 0.3
	info.poise_damage = 3.0
	info.hitstop = 0.03
	info.shake = 0.05
	for e in targets_in_cone(melee_range + 0.1, 60.0):
		_deal_damage(e, info.duplicate_info())


## Schattenranke (Shadow Hook): Flammenstrang von der linken Hand zum Ziel.
func spawn_tendril(to: Vector3, hit: bool) -> void:
	var from := body.hand_position(true)
	var t := Tendril.new()
	get_tree().current_scene.add_child(t)
	t.setup(from, to, hit, self)


## Kurzer Lichtblitz (Kindle).
func flash_light(at: Vector3, color: Color, energy: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 5.0
	get_tree().current_scene.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.45)
	tw.tween_callback(l.queue_free)


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
	if state in [State.CLIMB, State.SWIM, State.LEDGE_UP] and health - info.amount > 0.0:
		# hängt/schwimmt: Schaden ja, aber kein Taumeln (sonst fällt man durch die Kante)
		health = maxf(health - info.amount, 0.0)
		health_changed.emit(health, max_health)
		body.flash(0.1)
		FX.number(self, global_position + Vector3.UP * 2.0, str(roundi(info.amount)), Color(1.0, 0.3, 0.25))
		return
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMIES
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
	body.on_floor = is_on_floor() or state in [State.ROLL, State.CLIMB, State.SWIM, State.LEDGE_UP]
	body.sprint = move_toward(body.sprint, 1.0 if sprinting and state == State.MOVE else 0.0, delta * 4.0)
	body.vertical_velocity = velocity.y
	body.block_amount = move_toward(body.block_amount, 1.0 if _blocking else 0.0, delta * 9.0)
	body.two_hand = weapon.two_handed(body.off_item) and weapon_out
	# Kampfhaltung, sobald ein anvisiertes Ziel in Reichweite ist
	# Kampfhaltung: Gegner in der Nähe oder gerade im Kampf (Hieb/Deckung)
	var engaged: bool = (_nearby != null and is_instance_valid(_nearby)) or _swing_t >= 0.0 or _since_swing < 1.5
	body.combat = 1.0 if engaged and state != State.DEAD else 0.0
	body.look_target = _nearby.target_point() if _nearby and is_instance_valid(_nearby) else null
	match state:
		State.ROLL:
			body.action = &"roll"
			body.roll_kind = _roll_kind
			body.action_t = state_t / roll_duration
		State.CLIMB:
			body.action = &"climb"
			body.climb_phase = _climb_phase
			body.climb_move = input.move if input else Vector2.ZERO
			body.speed = 0.0
		State.LEDGE_UP:
			body.action = &"ledge_up"
			body.ledge_world = _ledge_edge
			body.action_t = state_t / ledge_up_time
			body.speed = 0.0
		State.SWIM:
			body.action = &"water_enter" if _water_enter_t >= 0.0 else &"swim"
			body.action_t = maxf(_water_enter_t, 0.0) / 0.75
			body.swim_phase = _swim_phase
			body.swim_amount = clampf(Vector2(velocity.x, velocity.z).length() / swim_speed, 0.0, 1.0)
			body.speed = 0.0
		State.STAGGER:
			body.action = &"stagger"
			body.action_t = state_t / _stagger_len
		State.DEAD:
			body.action = &"dead"
			body.action_t = state_t
		State.ABILITY:
			_ability.animate(self, body, state_t)
		_:
			if _swing_t >= 0.0 and _module and _module.body_action != &"swing":
				body.action = _module.body_action
				body.action_t = _swing_t / swing_duration
			elif _swing_t >= 0.0:
				body.action = &"swing"
				body.swing_index = _swing_index
				body.swing_clip = _swing_clip
				body.action_t = _swing_t / swing_duration
			else:
				body.action = &""
	body.tick(anim_delta)
