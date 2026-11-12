class_name Splinterkin
extends Enemy
## Splinterkin: kleiner Rudel-Willfault. Ein zersplitterter Schatten auf vier Nadelbeinen mit einer Krone
## aus Splittern und drei kalt-violetten Augen. Wie alle Willfaults vom Licht angezogen: Ohne Beute
## umkreist das Rudel die nächste Lichtquelle, sonst die Laterne des Spielers.
## Kampf: Das Rudel kreist auf Abstand, immer nur EINER greift an (Angriffsrecht wird weitergereicht).
## Der Angreifer duckt sich sichtbar (Augen glühen auf) und springt dann geradeaus. Wer seitlich ausweicht
## oder rollt, bekommt ein kurzes Fenster, in dem der Splinterkin nach der Landung wehrlos ist.

signal respawn_requested(kin: Splinterkin)

enum S { LURK, HUNT, WINDUP, LEAP, RECOVER, STAGGER, DEAD, KNOCKDOWN }

const VIOLET := Color(0.72, 0.52, 1.0)
const LEG_UP := 0.3
const LEG_LO := 0.36
const BODY_Y := 0.42
const KNOCKDOWN_TIME := 1.6
const FOOT_CHANNELS := ["foot_fl", "foot_fr", "foot_bl", "foot_br"]
## Ruhepunkte der Füße (Körper-Raum): vorn links, vorn rechts, hinten links, hinten rechts
const RESTS := [Vector3(-0.36, 0, -0.38), Vector3(0.36, 0, -0.38), Vector3(-0.34, 0, 0.36), Vector3(0.34, 0, 0.36)]
const MOVE_REF := 3.0  ## m/s, bei dem der Schrittzyklus "move" in seiner Dauer läuft
const DEATH_TIME := 1.0

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
var _time := 0.0
var _gait := 0.0  ## Schrittzyklus 0..1
var _move_dir := 0.0  ## Laufrichtung relativ zur Blickrichtung (rad)
var _move_len := 0.3
var _idle_len := 2.732
var _rng := RandomNumberGenerator.new()
var _track := CreatureAnim.Track.new("splinterkin", 0.12)
var _preview_action := ""
var _preview_k := 0.0
var puppet := false  ## Animationswerkstatt: keine KI, Haltung wird von außen gesetzt (preview)


func _ready() -> void:
	display_name = "Splinterkin"
	max_health = 24.0
	max_poise = 8.0
	target_height = 0.95
	radius = 0.34
	body_height = 0.8
	stagger_resist = 1.25  # leicht: Treffer werfen es länger aus dem Tritt
	super._ready()
	_rng.randomize()
	CreatureAnim.ensure("splinterkin", Splinterkin.default_pose)
	_move_len = CreatureAnim.action_info("splinterkin", "move")[3]
	_idle_len = CreatureAnim.action_info("splinterkin", "idle")[3]
	_time = _rng.randf() * 10.0
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
	for i in 4:
		var up := Node3D.new()
		_vis.add_child(up)
		_add(LowPoly.prism(0.024, 0.016, LEG_UP, 4), black, up, Vector3(0, -LEG_UP * 0.5, 0), Vector3.ZERO, Vector3.ONE, hem[0])
		var lo := Node3D.new()
		_vis.add_child(lo)
		_add(LowPoly.prism(0.017, 0.0, LEG_LO, 4), black, lo, Vector3(0, -LEG_LO * 0.5, 0), Vector3.ZERO, Vector3.ONE, hem[0])
		_legs.append({"anchor": anchors[i], "rest": RESTS[i], "up": up, "lo": lo})


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
	if puppet:
		return
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
				info.stagger = 0.3  # leichter Sprungbiss: kurze Unterbrechung
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
		S.KNOCKDOWN:
			if state_t >= KNOCKDOWN_TIME:
				_release_token()
				_cooldown = _rng.randf_range(0.6, 1.2)
				_set_state(S.HUNT)
		S.STAGGER:
			if state_t >= _stagger_len:
				_release_token()
				_cooldown = _rng.randf_range(0.8, 1.6)
				_set_state(S.HUNT)
		S.DEAD:
			if state_t > 4.0:
				respawn_requested.emit(self)
				queue_free()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var accel := 30.0 if state != S.LEAP else 80.0
	hv = hv.move_toward(desired + _knock, accel * delta)
	_knock = _knock.move_toward(Vector3.ZERO, 14.0 * delta)
	hv = _forced_velocity(hv, delta)
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


## Aktion und ihre normierte Zeit (Keyframes aus data/enemy_anims/splinterkin.json).
func anim_action() -> String:
	match state:
		S.WINDUP: return "windup"
		S.LEAP: return "leap"
		S.RECOVER: return "recover"
		S.STAGGER: return "stagger"
		S.DEAD: return "death"
		S.KNOCKDOWN: return "knockdown"
	return "move"


func anim_time() -> float:
	match state:
		S.WINDUP: return state_t / windup_time
		S.LEAP: return state_t / leap_time
		S.RECOVER: return state_t / recover_time
		S.STAGGER: return state_t / _stagger_len
		S.DEAD: return state_t / DEATH_TIME
		S.KNOCKDOWN: return state_t / KNOCKDOWN_TIME
	return _gait


## Animationswerkstatt: Haltung der Aktion zur normierten Zeit k zeigen (puppet = true, ohne Überblenden).
func preview(action: String, k: float, delta: float) -> void:
	_preview_action = action
	_preview_k = k
	_track.fade_len = 0.0
	_animate(delta)


func _set_state(s: S) -> void:
	state = s
	state_t = 0.0


# ------------------------------------------------------------------
# Animation: komplett aus Keyframes (Rumpf, Füße); Beine per IK zu den Füßen
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
	var hv := Vector3(velocity.x, 0, velocity.z)
	var p: Dictionary
	var moving := 0.0
	if puppet:
		var act := _preview_action if _preview_action != "" else "idle"
		p = _track.pose(act, _preview_k, delta)
		moving = 1.0 if act == "move" else 0.0
		_move_dir = 0.0
	elif state in [S.LURK, S.HUNT]:
		# Stehen <-> Laufen nach Tempo mischen; der Schrittzyklus läuft mit der Geschwindigkeit
		var spd := hv.length()
		moving = clampf(spd / 1.0, 0.0, 1.0)
		moving = moving * moving * (3.0 - 2.0 * moving)
		_gait = fposmod(_gait + delta * spd / MOVE_REF / _move_len, 1.0)
		var local := hv.rotated(Vector3.UP, -facing_yaw)
		if spd > 0.3:
			_move_dir = lerp_angle(_move_dir, atan2(-local.x, -local.z), 1.0 - exp(-10.0 * delta))
		var idle := CreatureAnim.sample("splinterkin", "idle", fposmod(_time / _idle_len, 1.0))
		var run := CreatureAnim.sample("splinterkin", "move", _gait)
		p = _track.push("loco", CreatureAnim.blend(idle, run, moving), delta)
	else:
		p = _track.pose(anim_action(), anim_time(), delta)
	if p.is_empty():
		return
	_torso.position = p.get("torso_pos", Vector3(0, BODY_Y, 0))
	_torso.quaternion = p.get("torso", Quaternion.IDENTITY)
	_update_legs(p, moving)
	if state == S.DEAD and not puppet:
		var shrink := maxf(0.0, state_t - DEATH_TIME * 0.6)
		_vis.scale = Vector3.ONE * maxf(0.01, 1.0 - shrink * 0.7)
		_vis.position.y = -0.15 * shrink


## Füße aus den Keys (Körper-Raum); beim Laufen dreht sich der Schritt in die Laufrichtung.
func _update_legs(p: Dictionary, moving: float) -> void:
	var xf := _vis.global_transform
	var turn := Basis(Vector3.UP, _move_dir * moving)
	for i in 4:
		var l: Dictionary = _legs[i]
		var foot: Vector3 = p.get(FOOT_CHANNELS[i], l.rest)
		if moving > 0.0:
			var rest: Vector3 = l.rest
			var off := foot - rest
			foot = rest + turn * Vector3(off.x, 0.0, off.z) + Vector3(0, off.y, 0)
		var hip: Vector3 = _torso.global_transform * (l.anchor as Vector3)
		var out := (xf.basis * Vector3(signf(l.rest.x), 0, 0)).normalized()
		_solve_leg(l.up, l.lo, hip, xf * foot, out * 0.6 + Vector3.UP * 2.0)


# ------------------------------------------------------------------
# Startfassung (vor der Umstellung prozedural; hier als Formeln, daraus werden die Keys gebacken)
# ------------------------------------------------------------------

static func _rest_pose(y: float, pitch: float, roll: float, crouch: float, lift: float) -> Dictionary:
	var d := {"torso": Quaternion.from_euler(Vector3(pitch, 0.0, roll)), "torso_pos": Vector3(0, y, 0)}
	for i in 4:
		var f: Vector3 = (RESTS[i] as Vector3) * (1.0 - 0.25 * crouch)
		f.y = lift
		d[FOOT_CHANNELS[i]] = f
	return d


static func default_pose(action: String, k: float) -> Dictionary:
	var ss := func(x: float) -> float:
		x = clampf(x, 0.0, 1.0)
		return x * x * (3.0 - 2.0 * x)
	match action:
		"idle":
			return _rest_pose(BODY_Y + sin(k * TAU) * 0.008, 0.0, 0.0, 0.0, 0.0)
		"move":
			# Diagonalpaare im Wechsel: Standphase schiebt den Fuß nach hinten, Schwungphase hebt ihn vor
			var dur: float = CreatureAnim.action_info("splinterkin", "move")[3]
			var stride := MOVE_REF * dur * 0.5
			var d := _rest_pose(BODY_Y - 0.012 * cos(2.0 * TAU * k), MOVE_REF * 0.06, 0.0, 0.0, 0.0)
			for i in 4:
				var u := fposmod(k + (0.0 if i in [0, 3] else 0.5), 1.0)
				var z: float
				var y := 0.0
				if u < 0.5:
					z = lerpf(-stride * 0.5, stride * 0.5, u / 0.5)
				else:
					var s: float = ss.call((u - 0.5) / 0.5)
					z = lerpf(stride * 0.5, -stride * 0.5, s)
					y = 0.09 * sin(PI * (u - 0.5) / 0.5)
				var f: Vector3 = d[FOOT_CHANNELS[i]]
				d[FOOT_CHANNELS[i]] = Vector3(f.x, y, f.z - 0.2 + z)
			return d
		"windup":
			var c: float = ss.call(k)
			return _rest_pose(BODY_Y - 0.18 * c, 0.2 * c, 0.0, c, 0.0)
		"leap":
			var hop := sin(k * PI)
			var c := exp(-3.84 * k)
			return _rest_pose(BODY_Y - 0.18 * c + 0.32 * hop, -0.25 * hop, 0.0, c, 0.15 * clampf((hop - 0.1) / 0.5, 0.0, 1.0))
		"recover":
			var c := 0.5 * (1.0 - ss.call(k)) * (1.0 - exp(-10.2 * k))
			return _rest_pose(BODY_Y - 0.18 * c, 0.0, 0.0, c, 0.0)
		"stagger":
			var env: float = ss.call(k / 0.15) * (1.0 - ss.call((k - 0.75) / 0.25))
			var c := 0.3 * env
			return _rest_pose(BODY_Y - 0.18 * c, 0.0, sin(k * 0.6 * 40.0) * 0.12 * (1.0 - k), c, 0.0)
		"knockdown":
			# hochgeschleudert, landet auf dem Rücken (Bauch nach oben), zappelt, rappelt sich auf
			var hop := sin(clampf(k / 0.3, 0.0, 1.0) * PI) * 0.8
			var c := 0.8 * (1.0 - ss.call((k - 0.65) / 0.35))
			var tip: float = ss.call(k / 0.25) * (1.0 - ss.call((k - 0.7) / 0.25))
			return _rest_pose(BODY_Y - 0.18 * c + 0.32 * hop, -0.25 * hop + 1.9 * tip, sin(k * 1.6 * 30.0) * 0.1 * tip, c,
				0.15 * clampf((hop - 0.1) / 0.5, 0.0, 1.0) + 0.12 * tip)
		"death":
			var c := 1.0 - exp(-12.0 * k)
			return _rest_pose(BODY_Y - 0.18 * c, 0.0, 0.0, c, 0.15 * (1.0 - exp(-10.0 * k)))
	return _rest_pose(BODY_Y, 0.0, 0.0, 0.0, 0.0)


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

func _on_hit(info: DamageInfo, dir: Vector3) -> void:
	_flash_t = 0.08
	for m in _meshes:
		m.material_overlay = _flash_mat
	if state == S.LURK:
		_player = Game.nearest_player(global_position, 40.0)
		_set_state(S.HUNT)
	if state in [S.DEAD, S.KNOCKDOWN]:
		return
	var r := hit_reaction(info, state in [S.WINDUP, S.LEAP])
	if r < 0.0:
		_hitbox.deactivate()
		_eye_mat.emission_energy_multiplier = 3.0
		_knock = dir * maxf(info.knockback, 5.0)
		_set_state(S.KNOCKDOWN)
	elif r > 0.0 and not (state == S.STAGGER and _stagger_len - state_t > r):
		_hitbox.deactivate()
		_eye_mat.emission_energy_multiplier = 3.0
		_stagger_len = r
		_set_state(S.STAGGER)


func hold(duration: float) -> void:
	if state == S.DEAD:
		return
	_hitbox.deactivate()
	_eye_mat.emission_energy_multiplier = 3.0
	_stagger_len = duration
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
