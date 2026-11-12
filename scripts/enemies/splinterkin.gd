class_name Splinterkin
extends Enemy
## Splinterkin: kleiner Rudel-Willfault. Ein zersplitterter Schatten auf vier Nadelbeinen mit einer Krone
## aus Splittern und drei kalt-violetten Augen. Wie alle Willfaults vom Licht angezogen: Ohne Beute
## umkreist das Rudel die nächste Lichtquelle, sonst die Laterne des Spielers.
## Kampf: Das Rudel kreist auf Abstand, immer nur EINER greift an (Angriffsrecht wird weitergereicht).
## Der Angreifer duckt sich sichtbar (Augen glühen auf) und springt dann geradeaus. Wer seitlich ausweicht
## oder rollt, bekommt ein kurzes Fenster, in dem der Splinterkin nach der Landung wehrlos ist.

signal respawn_requested(kin: Splinterkin)

enum S { LURK, HUNT, WINDUP, LEAP, RECOVER, STAGGER, DEAD }

const VIOLET := Color(0.72, 0.52, 1.0)
const LEG_UP := 0.3
const LEG_LO := 0.36
const BODY_Y := 0.42
const STEP_TIME := 0.13

@export var move_speed := 4.3
@export var aggro_range := 13.0
@export var orbit_radius := 3.1
@export var windup_time := 0.6
@export var leap_time := 0.32
@export var recover_time := 0.85
@export var damage := 8.0

## Wer gerade angreifen darf (pro Szene): nie zwei Sprünge gleichzeitig
static var _token: Splinterkin = null

var state: S = S.LURK
var state_t := 0.0
var facing_yaw := 0.0
var pack_angle := 0.0  ## eigener Platz im Kreis ums Licht
var _player: Node3D
var _cooldown := 1.5
var _stagger_len := 0.5
var _leap_dir := Vector3.FORWARD
var _leap_v := 9.0
var _hitbox: Hitbox
var _pivot: Node3D

# Aussehen
var _vis: Node3D
var _torso: Node3D
var _eye_mat: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var _flash_t := 0.0
var _hem_mats: Array[ShaderMaterial] = []
var _legs: Array[Dictionary] = []
var _gait_flip := false
var _time := 0.0
var _crouch := 0.0
var _hop := 0.0
var _lean := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	display_name = "Splinterkin"
	max_health = 24.0
	max_poise = 8.0
	target_height = 0.95
	radius = 0.34
	body_height = 0.8
	super._ready()
	_rng.randomize()
	facing_yaw = rotation.y
	rotation = Vector3.ZERO
	_build_visual()
	_pivot = Node3D.new()
	add_child(_pivot)
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.8, 1.0)
	_hitbox = Hitbox.new(Game.LAYER_PLAYER_HURTBOX, box, Vector3(0, 0.5, -0.55))
	_pivot.add_child(_hitbox)
	_cooldown = _rng.randf_range(1.0, 2.5)


# ------------------------------------------------------------------
# Aussehen
# ------------------------------------------------------------------

func _build_visual() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	_flash_mat = ShadowBody.hit_flash_material()
	var black := ShadowBody.skin_material()
	_eye_mat = LowPoly.mat(VIOLET, 3.0).duplicate()
	var hem: Array = FrayedOutfit.hem_chain({"heat": Hollowed.HEM_HEAT, "hot": Hollowed.HEM_HOT}, 5, false)
	_hem_mats.assign(hem[1])

	_torso = Node3D.new()
	_torso.position.y = BODY_Y
	_vis.add_child(_torso)
	# Rumpf: gestreckter, kantiger Schattenklumpen, hinten spitz
	var core := LowPoly.rock(0.2, _rng.randi(), 7, 4, 0.3)
	_add(core, black, _torso, Vector3.ZERO, Vector3(0.12, 0.0, 0.0), Vector3(1.0, 0.72, 1.45), hem[0])
	var tail := LowPoly.prism(0.08, 0.0, 0.26, 5)
	_add(tail, black, _torso, Vector3(0, 0.03, 0.32), Vector3(PI / 2 - 0.25, 0, 0), Vector3.ONE, hem[0])
	# Krone aus Splittern, nach hinten oben gefächert
	for i in 7:
		var t := (float(i) / 6.0) * 2.0 - 1.0
		var h := _rng.randf_range(0.2, 0.36) * (1.0 - absf(t) * 0.35)
		var sh := LowPoly.crystal(h, 0.035)
		var rot := Vector3(-0.5 - _rng.randf_range(0.0, 0.35), 0.0, -t * 0.75)
		_add(sh, black, _torso, Vector3(t * 0.1, 0.1, -0.02 + absf(t) * 0.05), rot, Vector3.ONE, hem[0])
		var tip := LowPoly.mesh_instance(LowPoly.crystal(h * 0.3, 0.012), _eye_mat, _torso, Vector3(t * 0.1, 0.1, -0.02 + absf(t) * 0.05))
		tip.rotation = rot
		tip.position += Basis.from_euler(rot) * Vector3(0, h * 0.72, 0)
	# drei Augen im Dreieck vorne
	for e in [Vector3(-0.06, 0.05, -0.27), Vector3(0.06, 0.05, -0.27), Vector3(0.0, 0.11, -0.25)]:
		var eye := LowPoly.mesh_instance(LowPoly.prism(0.022, 0.0, 0.03, 4), _eye_mat, _torso, e)
		eye.rotation.x = -PI / 2
	var glow := OmniLight3D.new()
	glow.light_color = VIOLET
	glow.light_energy = 0.3
	glow.omni_range = 0.9
	glow.position = Vector3(0, 0.08, -0.4)
	_torso.add_child(glow)
	# vier Nadelbeine (vorn links, vorn rechts, hinten links, hinten rechts)
	var anchors := [Vector3(-0.13, -0.02, -0.14), Vector3(0.13, -0.02, -0.14), Vector3(-0.13, -0.02, 0.16), Vector3(0.13, -0.02, 0.16)]
	var rests := [Vector3(-0.36, 0, -0.38), Vector3(0.36, 0, -0.38), Vector3(-0.34, 0, 0.36), Vector3(0.34, 0, 0.36)]
	for i in 4:
		var up := Node3D.new()
		_vis.add_child(up)
		_add(LowPoly.prism(0.024, 0.016, LEG_UP, 4), black, up, Vector3(0, -LEG_UP * 0.5, 0), Vector3.ZERO, Vector3.ONE, hem[0])
		var lo := Node3D.new()
		_vis.add_child(lo)
		_add(LowPoly.prism(0.017, 0.0, LEG_LO, 4), black, lo, Vector3(0, -LEG_LO * 0.5, 0), Vector3.ZERO, Vector3.ONE, hem[0])
		_legs.append({"anchor": anchors[i], "rest": rests[i], "up": up, "lo": lo, "foot": Vector3.ZERO, "from": Vector3.ZERO, "to": Vector3.ZERO, "t": 1.0, "init": false})


func _add(mesh: Mesh, mat: Material, parent: Node3D, pos: Vector3, rot: Vector3, scl: Vector3, hem_mat: Material) -> MeshInstance3D:
	var mi := LowPoly.mesh_instance(mesh, mat, parent, pos)
	mi.rotation = rot
	mi.scale = scl
	_meshes.append(mi)
	# Flammensaum in Willfault-Violett (dieselben Hüllen wie bei den Shades)
	var hm := LowPoly.mesh_instance(mesh, hem_mat, parent, pos)
	hm.rotation = rot
	hm.scale = scl
	hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------
# Verhalten
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if hitstop > 0.0:
		hitstop -= delta
		return
	state_t += delta
	_cooldown -= delta
	poise = minf(poise + 6.0 * delta, max_poise)
	var desired := Vector3.ZERO
	match state:
		S.LURK:
			# ums nächste Licht schleichen, bis Beute in Reichweite ist
			_player = Game.nearest_player(global_position, aggro_range)
			if _player:
				_set_state(S.HUNT)
			else:
				var light := _nearest_light(14.0)
				if light != Vector3.INF:
					desired = _orbit_velocity(light, 2.2, 0.25) * 0.5
		S.HUNT:
			_player = Game.nearest_player(global_position, aggro_range * 1.5)
			if not _player:
				_release_token()
				_set_state(S.LURK)
			else:
				desired = _orbit_velocity(_player.global_position, orbit_radius, 0.45)
				var to := _flat_to(_player.global_position)
				_turn_toward(to, 9.0, delta)
				var free := _token == null or not is_instance_valid(_token) or _token == self
				if _cooldown <= 0.0 and free and to.length() < orbit_radius + 1.6:
					_token = self
					_set_state(S.WINDUP)
		S.WINDUP:
			# Ducken und Augen aufglühen lassen: deutliches Signal vor dem Sprung
			var to := _flat_to(_player.global_position) if _player else -_forward()
			if state_t < windup_time * 0.7:
				_turn_toward(to, 12.0, delta)
			desired = -to.normalized() * 0.8
			_eye_mat.emission_energy_multiplier = lerpf(3.0, 14.0, state_t / windup_time)
			if state_t >= windup_time:
				_leap_dir = _forward()
				# Sprungweite bis knapp vor das Ziel (festgelegt beim Absprung: seitlich ausweichen hilft)
				var dist := _flat_to(_player.global_position).length() if _player else 2.5
				_leap_v = clampf(dist - 0.3, 1.5, 4.2) / (leap_time * 0.8)
				_set_state(S.LEAP)
				var info := DamageInfo.new()
				info.amount = damage
				info.source = self
				info.knockback = 3.5
				info.hitstop = 0.06
				info.shake = 0.25
				_hitbox.activate(info)
		S.LEAP:
			desired = _leap_dir * _leap_v * (1.0 - 0.4 * state_t / leap_time)
			if state_t >= leap_time:
				_hitbox.deactivate()
				_eye_mat.emission_energy_multiplier = 3.0
				_set_state(S.RECOVER)
		S.RECOVER:
			# nach der Landung kurz wehrlos
			if state_t >= recover_time:
				_release_token()
				_cooldown = _rng.randf_range(1.6, 3.2)
				_set_state(S.HUNT)
		S.STAGGER:
			if state_t >= _stagger_len:
				_release_token()
				_cooldown = _rng.randf_range(0.8, 1.6)
				_set_state(S.HUNT)
		S.DEAD:
			_vis.scale = Vector3.ONE * maxf(0.01, 1.0 - state_t * 0.7)
			_vis.position.y -= delta * 0.15
			if state_t > 4.0:
				respawn_requested.emit(self)
				queue_free()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var accel := 30.0 if state != S.LEAP else 80.0
	hv = hv.move_toward(desired + _knock, accel * delta)
	_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	if state in [S.LURK, S.HUNT] and hv.length() > 0.5 and (not _player or state == S.LURK):
		_turn_toward(hv, 6.0, delta)
	_pivot.rotation.y = facing_yaw
	_animate(delta)


## Geschwindigkeit, um auf einem Kreis um `center` zum eigenen Platz zu laufen (Platz wandert langsam mit).
func _orbit_velocity(center: Vector3, r: float, spin: float) -> Vector3:
	pack_angle += spin * get_physics_process_delta_time()
	var spot := center + Vector3(sin(pack_angle), 0, cos(pack_angle)) * r
	var to := _flat_to(spot)
	var d := to.length()
	if d < 0.15:
		return Vector3.ZERO
	return to / d * move_speed * clampf(d / 1.2, 0.25, 1.0)


func _nearest_light(max_d: float) -> Vector3:
	var best := Vector3.INF
	var best_d := max_d
	for l in get_tree().get_nodes_in_group("light_sources"):
		if l is Node3D and (l as Node3D).is_visible_in_tree():
			var d := (l as Node3D).global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = (l as Node3D).global_position
	return best


func _release_token() -> void:
	if _token == self:
		_token = null


func _flat_to(p: Vector3) -> Vector3:
	var to := p - global_position
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


# ------------------------------------------------------------------
# Animation: Rumpf federt, Beine setzen prozedural paarweise über Kreuz
# ------------------------------------------------------------------

func _animate(delta: float) -> void:
	_time += delta
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for m in _meshes:
				m.material_overlay = null
	var o := global_position
	for m in _hem_mats:
		m.set_shader_parameter("origin", o)
	_vis.rotation.y = facing_yaw
	var crouch_t := 0.0
	var hop_t := 0.0
	match state:
		S.WINDUP:
			crouch_t = smoothstep(0.0, 1.0, state_t / windup_time)
		S.LEAP:
			hop_t = sin(clampf(state_t / leap_time, 0.0, 1.0) * PI)
		S.RECOVER:
			crouch_t = 0.5 * (1.0 - smoothstep(0.0, 1.0, state_t / recover_time))
		S.STAGGER:
			crouch_t = 0.3
		S.DEAD:
			crouch_t = 1.0
	_crouch = lerpf(_crouch, crouch_t, 1.0 - exp(-12.0 * delta))
	_hop = hop_t
	var hv := Vector3(velocity.x, 0, velocity.z)
	var local := hv.rotated(Vector3.UP, -facing_yaw)
	_lean = _lean.lerp(Vector2(local.x, local.z) * 0.06, 1.0 - exp(-8.0 * delta))
	var bob := sin(_time * 14.0) * 0.012 * minf(hv.length() / move_speed, 1.0)
	_torso.position.y = BODY_Y - 0.18 * _crouch + 0.32 * _hop + bob + sin(_time * 2.3) * 0.008
	_torso.rotation = Vector3(-_lean.y - 0.25 * _hop + 0.2 * _crouch * (1.0 if state == S.WINDUP else 0.0), 0.0, _lean.x)
	if state == S.STAGGER:
		_torso.rotation.z += sin(_time * 40.0) * 0.12
	_update_legs(delta, hv)


func _update_legs(delta: float, hv: Vector3) -> void:
	var xf := _vis.global_transform
	var flat := Transform3D(Basis(Vector3.UP, facing_yaw), global_position)
	var airborne := _hop > 0.2 or state == S.DEAD
	# Schritt auslösen: Fuß zu weit vom Ruhepunkt -> neu setzen (Diagonalpaare abwechselnd)
	var pair := [0, 3] if not _gait_flip else [1, 2]
	var stepping := false
	for l in _legs:
		if l.t < 1.0:
			stepping = true
	for i in 4:
		var l: Dictionary = _legs[i]
		var target: Vector3 = flat * (l.rest * (1.0 - 0.25 * _crouch)) + hv * 0.12
		target.y = global_position.y
		if not l.init:
			l.foot = target
			l.to = target
			l.init = true
		if l.t < 1.0:
			l.t = minf(l.t + delta / STEP_TIME, 1.0)
			var e: float = l.t * l.t * (3.0 - 2.0 * l.t)
			l.foot = (l.from as Vector3).lerp(l.to, e) + Vector3.UP * sin(l.t * PI) * 0.09
		elif airborne:
			l.foot = (l.foot as Vector3).lerp(target + Vector3.UP * 0.15, 1.0 - exp(-10.0 * delta))
		elif not stepping and i in pair and (l.foot as Vector3).distance_to(target) > 0.22:
			l.from = l.foot
			l.to = target + hv * 0.1
			l.t = 0.0
	if not stepping:
		for i in pair:
			if _legs[i].t < 1.0:
				_gait_flip = not _gait_flip
				break
	for l in _legs:
		var hip: Vector3 = _torso.global_transform * (l.anchor as Vector3)
		var out := (xf.basis * Vector3(signf(l.rest.x), 0, 0)).normalized()
		_solve_leg(l.up, l.lo, hip, l.foot, out * 0.6 + Vector3.UP * 2.0)


func _solve_leg(upper: Node3D, lower: Node3D, hip: Vector3, foot: Vector3, pole: Vector3) -> void:
	var a := LEG_UP
	var b := LEG_LO
	var to := foot - hip
	var d := clampf(to.length(), 0.05, a + b - 0.001)
	var dir := to.normalized() if to.length_squared() > 1e-6 else Vector3.DOWN
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 1e-6:
		perp = Vector3.UP
	perp = perp.normalized()
	var knee := hip + dir * a * cos_a + perp * a * sin_a
	var tip := hip + dir * d
	upper.global_transform = Transform3D(_seg_basis(knee - hip), hip)
	lower.global_transform = Transform3D(_seg_basis(tip - knee), knee)


func _seg_basis(along: Vector3) -> Basis:
	var y := -along.normalized()
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, y, x.cross(y))


# ------------------------------------------------------------------
# Treffer
# ------------------------------------------------------------------

func _on_hit(_info: DamageInfo, _dir: Vector3) -> void:
	_flash_t = 0.08
	for m in _meshes:
		m.material_overlay = _flash_mat
	if state == S.LURK:
		_player = Game.nearest_player(global_position, 40.0)
		_set_state(S.HUNT)
	if poise <= 0.0 and state != S.DEAD:
		_hitbox.deactivate()
		_eye_mat.emission_energy_multiplier = 3.0
		_stagger_len = 0.6
		poise = max_poise
		_set_state(S.STAGGER)


func on_parried(_by: Node3D) -> void:
	_hitbox.deactivate()
	_stagger_len = 1.3
	_set_state(S.STAGGER)
	FX.number(self, target_point(), "Staggered", Color(0.6, 0.95, 1.0))


func _on_death() -> void:
	_hitbox.deactivate()
	_release_token()
	_eye_mat.emission_energy_multiplier = 0.0
	FX.sparks(self, global_position + Vector3.UP * 0.5, VIOLET, 16, 1.3)
	remove_from_group("targetable")
	remove_from_group("enemies")
	collision_layer = 0
	for c in get_children():
		if c is Hurtbox:
			c.collision_layer = 0
	_set_state(S.DEAD)


func _exit_tree() -> void:
	_release_token()
