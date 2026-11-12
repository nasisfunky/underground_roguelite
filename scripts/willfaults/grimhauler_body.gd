class_name GrimhaulerBody
extends Node3D
## Grimhauler: verzerrter Koloss aus Schattenflamme. Stampft schwer, schleift seine Axt mit dem Dorn
## über den Boden (Funken) und schlägt über Kopf zu. Die Schneide glüht vorher weiß-violett auf,
## denn der Schlag lässt sich nicht blocken. Beim Einschlag: Funkenfontäne, Schockwelle, Riss im Boden.
## Animation: Keyframes (data/enemy_anims/grimhauler.json, Animationswerkstatt). Startfassung = die frühere
## prozedurale Bewegung von der Konzeptseite (willfaults3.js, buildGrimhauler), siehe _legacy_pose().
## Automatisch bleiben: Bein-IK zu den Fuß-Keys, Axt sitzt in der Hand, Effekte.

const MODEL := "res://assets/models/willfaults/grimhauler.glb"
const SCALE := 1.95  ## Wurzel-Skalierung des Modells
const HIP_Y := 0.78
const THIGH := 0.38
const SHIN := 0.43
const AXE_S := 0.6
const POLL := Vector3(0, 0.94 * AXE_S, -0.31 * AXE_S)  ## Hammerdorn (Axt-Koordinaten)
const EDGE := Vector3(0, 0.92 * AXE_S, 0.82 * AXE_S)  ## Mitte der Schneide
const EDGE_TOP := Vector3(0, (0.94 + 0.33 * 1.25) * AXE_S, 0.49 * 1.4 * AXE_S)
const EDGE_LOW := Vector3(0, (0.94 - 0.4 * 1.25) * AXE_S, 0.5 * 1.4 * AXE_S)
const CYCLE := 4.8  ## Dauer eines Angriffs
const ARM_R := -0.15  ## Axtarm in Ruhe: hängt so tief, dass der Dorn den Boden erreicht
const STEP_CYCLE := 2.1
const GROUND_SPEED := 2.0 * 0.24 / (0.6 * STEP_CYCLE) * SCALE  ## m/s, passend zur Schrittweite
const IMPACT_T := 1.74  ## s nach Angriffsbeginn: Einschlag (Funken, Schockwelle, Riss)
const JOINTS := ["hips", "chest", "neck", "head", "upR", "foreR", "upL", "foreL"]

var attacking := false
var slam_lean := -0.7  ## Rumpfneigung im Einschlag
var slam_arm := -4.45  ## Armwinkel im Einschlag
var slam_crouch := -0.14
var t := 0.0
var _t0 := 0.0
var _impacted := false
var _shock_t := 9.0

var _m: Dictionary
var root: Node3D
var j: Dictionary
var axe: Node3D
var _edge_mat: StandardMaterial3D
var _edge_light: OmniLight3D
var _drag: CPUParticles3D
var _burst: CPUParticles3D
var _shock: MeshInstance3D
var _shock_mat: StandardMaterial3D
var _crack: MeshInstance3D
var _crack_mat: StandardMaterial3D
var _shards: Array[Node3D] = []
var _shard_base: Array[Vector3] = []
var _track := CreatureAnim.Track.new("grimhauler", 0.25)
var _nodes := {}


func _ready() -> void:
	_m = WillfaultModel.spawn(MODEL, self, {"layers": 7, "thick": 0.026, "rise": 0.07, "scale": SCALE, "hair": 0.3,
		"head_thick": 0.035 * 0.72, "head_rise": 0.07 * 0.72, "glow": 1.3, "dark_gear": true})
	root = _m.root
	j = WillfaultModel.joints(root)
	axe = j["Axe"]
	for k in j:
		if String(k).begins_with("Shard"):
			_shards.append(j[k])
			_shard_base.append((j[k] as Node3D).position)
	# Schneide: eigenes Material, glüht vor dem Schlag auf
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_mat.albedo_color = Color(0.24, 0.14, 0.44)
	for mi: MeshInstance3D in (j["Edge"] as Node).find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _edge_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edge_light = OmniLight3D.new()
	_edge_light.light_color = Color(0.65, 0.48, 1.0)
	_edge_light.omni_range = 2.2 * AXE_S * SCALE
	_edge_light.position = Vector3(0, 0.9, 0.6)
	axe.add_child(_edge_light)
	_build_fx()
	for n in JOINTS:
		_nodes[n] = j[n]
	_nodes["hips_pos"] = j["hips"]
	CreatureAnim.ensure("grimhauler", _bake_sample)
	_pose(0.0)


func set_attacking(on: bool) -> void:
	if on != attacking:
		attacking = on
		_t0 = t
		_impacted = false


func tick(delta: float) -> void:
	t += delta
	_pose(delta)


## Animationswerkstatt: Haltung der Aktion ("walk"/"attack") zur normierten Zeit k zeigen.
func preview(action: String, k: float, delta: float) -> void:
	_track.fade_len = 0.0
	attacking = action == "attack"
	_t0 = 0.0
	t = k * (CYCLE if attacking else STEP_CYCLE)
	if attacking and k * CYCLE < 1.74:
		_impacted = false
	_pose(delta)


func _process(_delta: float) -> void:
	var o := get_global_transform_interpolated().origin
	for m: ShaderMaterial in _m.hem_mats:
		m.set_shader_parameter("origin", o)


func _build_fx() -> void:
	var spark := StandardMaterial3D.new()
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark.vertex_color_use_as_albedo = true
	spark.albedo_color = Color(1.0, 0.92, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = spark
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 1.0))
	ramp.set_color(1, Color(0.45, 0.25, 0.9, 0.0))
	# Funken am schleifenden Dorn
	_drag = CPUParticles3D.new()
	_drag.mesh = quad
	_drag.amount = 40
	_drag.lifetime = 0.5
	_drag.local_coords = false
	_drag.direction = Vector3(0, 1, 0.6)
	_drag.spread = 35.0
	_drag.initial_velocity_min = 0.5
	_drag.initial_velocity_max = 1.4
	_drag.gravity = Vector3(0, -4.5, 0)
	_drag.scale_amount_min = 0.6
	_drag.scale_amount_max = 1.2
	_drag.color_ramp = ramp
	add_child(_drag)
	# Fontäne beim Einschlag
	_burst = CPUParticles3D.new()
	_burst.mesh = quad
	_burst.amount = 80
	_burst.lifetime = 0.9
	_burst.one_shot = true
	_burst.emitting = false
	_burst.explosiveness = 1.0
	_burst.local_coords = false
	_burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_burst.emission_sphere_radius = 0.2
	_burst.direction = Vector3.UP
	_burst.spread = 70.0
	_burst.initial_velocity_min = 1.5
	_burst.initial_velocity_max = 4.0
	_burst.gravity = Vector3(0, -6.0, 0)
	_burst.scale_amount_min = 0.8
	_burst.scale_amount_max = 1.8
	_burst.color_ramp = ramp
	add_child(_burst)
	# Schockwelle: flacher Ring
	_shock_mat = StandardMaterial3D.new()
	_shock_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shock_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shock_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shock_mat.albedo_color = Color(0.7, 0.55, 1.0, 0.0)
	_shock = MeshInstance3D.new()
	_shock.mesh = _ring_mesh(0.86, 1.0, 64)
	_shock.material_override = _shock_mat
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_shock)
	# Riss im Boden
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_mat.albedo_color = Color(0, 0, 0, 0)
	_crack = MeshInstance3D.new()
	_crack.mesh = _crack_mesh()
	_crack.material_override = _crack_mat
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_crack)


static func _ring_mesh(r0: float, r1: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p := [Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a0) * r1, 0, sin(a0) * r1), Vector3(cos(a1) * r1, 0, sin(a1) * r1), Vector3(cos(a1) * r0, 0, sin(a1) * r0)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(p[k])
	return st.commit()


## Sternförmiger Riss: dunkle, gezackte Fläche
static func _crack_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 14
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n
		var r := (0.55 + rng.randf() * 0.35) if i % 2 == 0 else (0.12 + rng.randf() * 0.08)
		pts.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for i in n:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[(i + 1) % n])
		st.add_vertex(pts[i])
	return st.commit()


## Höhe eines Axtpunkts L über dem Boden bei Winkel phi (Hand in Höhe h)
static func _y_at(h: float, l: Vector3, ph: float) -> float:
	return h - l.y * cos(ph) + l.z * sin(ph)


static func _solve(h: float, l: Vector3, lo: float, hi: float, target: float) -> float:
	var a := lo
	var b := hi
	var fa := _y_at(h, l, a) - target
	for i in 24:
		var m := (a + b) * 0.5
		var fm := _y_at(h, l, m) - target
		if (fm > 0.0) == (fa > 0.0):
			a = m
		else:
			b = m
	return (a + b) * 0.5


static func _min_y(h: float, ph: float) -> float:
	return minf(minf(_y_at(h, POLL, ph), _y_at(h, EDGE, ph)), minf(_y_at(h, EDGE_TOP, ph), _y_at(h, EDGE_LOW, ph)))


## Größter Winkel zwischen safe und target, bei dem kein Axtpunkt unter dem Boden liegt
static func _floor_clamp(h: float, safe: float, target: float) -> float:
	var a := safe
	var b := target
	for i in 20:
		var m := (a + b) * 0.5
		if _min_y(h, m) >= 0.01:
			a = m
		else:
			b = m
	return a


func _leg_ik(s: String, target: Vector3) -> void:
	var thigh: Node3D = j["thigh" + s]
	var shin: Node3D = j["shin" + s]
	var tw := root.global_transform * target
	var parent := thigh.get_parent() as Node3D
	var tl := parent.global_transform.affine_inverse() * tw
	var d := tl - thigh.position
	var l := clampf(d.length(), absf(THIGH - SHIN) + 0.01, (THIGH + SHIN) * 0.9995)
	var dir := d.normalized()
	var ang := acos(clampf((THIGH * THIGH + l * l - SHIN * SHIN) / (2.0 * THIGH * l), -1.0, 1.0))
	var fwd := Vector3(0, 0, -1)
	var perp := (fwd - dir * fwd.dot(dir)).normalized()
	var knee_dir := (dir * cos(ang) + perp * sin(ang)).normalized()
	thigh.quaternion = Quaternion(Vector3.DOWN, knee_dir)
	var sp := shin.get_parent() as Node3D
	var inv := sp.global_transform.affine_inverse()
	var sd := (inv * tw - inv * shin.global_position).normalized()
	shin.quaternion = Quaternion(Vector3.DOWN, sd)


func _bake_sample(action: String, k: float) -> Dictionary:
	if action == "attack":
		return _legacy_pose(true, k * CYCLE, k * CYCLE)
	return _legacy_pose(false, k * STEP_CYCLE, -1.0)


func _pose(dt: float) -> void:
	var ta := fmod(t - _t0, CYCLE) if attacking else -1.0
	if attacking and ta < 0.05:
		_impacted = false
	var p := _track.pose("attack" if attacking else "walk", ta / CYCLE if attacking else fposmod(t / STEP_CYCLE, 1.0), dt)
	if p.is_empty():
		return
	CreatureAnim.apply(p, _nodes)
	_leg_ik("L", p.get("foot_L", Vector3(-0.17, 0, 0)))
	_leg_ik("R", p.get("foot_R", Vector3(0.17, 0, 0)))
	# Axt sitzt in der rechten Hand, ihre Neigung kommt aus den Keys
	var h2: Vector3 = root.global_transform.affine_inverse() * (j["handR"] as Node3D).global_position
	axe.position = h2
	axe.quaternion = p.get("axe", axe.quaternion)
	var axf := axe.transform
	if attacking and ta >= IMPACT_T and not _impacted:
		_impacted = true
		_shock_t = 0.0
		var edge := axf * EDGE
		_shock.position = Vector3(edge.x, 0.01, edge.z)
		_crack.position = Vector3(edge.x, 0.006, edge.z)
		_crack.rotation.y = randf() * TAU
		_burst.global_position = root.global_transform * Vector3(edge.x, 0.05, edge.z)
		_burst.restart()
	# Glühen der Schneide: Warnung vor dem nicht blockbaren Schlag
	var k_w := WillfaultModel.sm(ta / 1.5) if attacking else 0.0
	var glow_k := clampf(k_w * 1.1, 0.0, 1.0) * (1.0 - WillfaultModel.sm((ta - 1.9) / 0.8)) if attacking else 0.0
	_edge_mat.albedo_color = Color(lerpf(0.24, 0.97, glow_k), lerpf(0.14, 0.92, glow_k), lerpf(0.44, 1.0, glow_k))
	_edge_light.light_energy = 0.15 + 2.5 * glow_k * (1.0 + 0.25 * sin(t * 30.0))
	# Funken am Dorn, wenn er den Boden berührt
	var poll := axf * POLL
	_drag.global_position = root.global_transform * Vector3(poll.x, maxf(poll.y, 0.0) + 0.01, poll.z)
	_drag.emitting = (not attacking or ta > 3.6) and poll.y < 0.06
	# Schockwelle und Riss
	_shock_t += dt
	var sk := _shock_t / 0.7
	_shock_mat.albedo_color.a = 0.9 * (1.0 - sk) if sk < 1.0 else 0.0
	_shock.scale = Vector3.ONE * (0.15 + 1.4 * WillfaultModel.sm(sk))
	_shock.visible = sk < 1.0
	_crack_mat.albedo_color.a = 0.85 * (1.0 - WillfaultModel.sm(_shock_t - 1.0)) if _shock_t < 2.0 else 0.0
	_crack.visible = _shock_t < 2.0
	# Splitter schweben
	for i in _shards.size():
		_shards[i].position = _shard_base[i] + Vector3(0, 0.015 * sin(t * 1.3 + i * 1.7), 0)
		_shards[i].rotation.y = t * 0.4 + i


## Frühere prozedurale Bewegung (Startfassung der Keys). Setzt die Gelenke und liefert die Haltung als Kanäle.
func _legacy_pose(att: bool, tt: float, ta: float) -> Dictionary:
	var k_w := WillfaultModel.sm(ta / 1.5) if att else 0.0  # Ausholen
	var k_s := WillfaultModel.ease_in((ta - 1.5) / 0.24) if att else 0.0  # Schlag
	var k_r := WillfaultModel.sm((ta - 2.75) / 1.3) if att else 0.0  # Zurückziehen
	var in_slam := att and ta >= 1.5 and ta < 2.75
	var walk_w := 0.0 if att else 1.0
	# Beine: schwerer Stampfschritt bzw. breiter Stand
	var ph := tt / STEP_CYCLE * TAU
	var stride := 0.24 * walk_w
	var lift := 0.07 * walk_w
	var feet := {}
	for side in [["L", -1.0, 0.0], ["R", 1.0, 0.5]]:
		var s: String = side[0]
		var sx: float = side[1]
		var u := fposmod(tt / STEP_CYCLE + float(side[2]), 1.0)
		var z: float
		var y := 0.0
		if u < 0.6:
			z = lerpf(-stride, stride, u / 0.6)
		else:
			var k := (u - 0.6) / 0.4
			z = lerpf(stride, -stride, WillfaultModel.sm(k))
			y = lift * sin(PI * k)
		if att:
			var stance := Vector3(sx * 0.2, 0, -0.1 if sx < 0.0 else 0.1)
			if s == "L":
				stance.z += -0.16 * WillfaultModel.sm((ta - 1.3) / 0.4) * (1.0 - k_r)
			feet[s] = stance
		else:
			feet[s] = Vector3(sx * 0.17, y, z)
	var stomp := walk_w * (-0.035 * pow(absf(cos(ph)), 6.0))
	var crouch := ((-0.05 * k_w + slam_crouch * k_s) * (1.0 - k_r) + 0.03 * k_w * (1.0 - k_s)) if att else 0.0
	var hips: Node3D = j["hips"]
	hips.position = Vector3(walk_w * 0.03 * sin(ph), HIP_Y - 0.07 + stomp + crouch, 0)
	WillfaultModel.rot(hips, -0.08, walk_w * 0.12 * sin(ph), walk_w * 0.06 * sin(ph))
	var lean := (lerpf(lerpf(-0.36, -0.02, k_w), slam_lean, k_s) * (1.0 - k_r) - 0.36 * k_r) if att else -0.36 + 0.03 * sin(2.0 * ph)
	WillfaultModel.rot(j["chest"], lean, walk_w * -0.16 * sin(ph) + (-0.25 * k_w * (1.0 - k_s) if att else 0.0), walk_w * -0.04 * sin(ph))
	WillfaultModel.rot(j["neck"], (lerpf(0.36, 0.6, k_s) * (1.0 - k_r) + 0.36 * k_r) if att else 0.38, walk_w * 0.1 * sin(tt * 0.4), 0.0)
	# Kopf zuckt in harten Sprüngen
	var tw := floorf(tt * 2.3)
	var twk := fmod(sin(tw * 12.9898) * 43758.5453, 1.0)
	WillfaultModel.rot(j["head"], 0.1 * twk, 0.5 * twk, 0.32 + 0.15 * sin(tw * 3.1))
	# Arme
	var shake := 0.03 * sin(tt * 60.0) * (1.0 - (ta - IMPACT_T) / 0.76) if in_slam and ta > IMPACT_T and ta < 2.5 else 0.0
	var arm_r := ARM_R
	var arm_l := 0.1 + walk_w * 0.32 * sin(ph + PI)
	var z_l := -0.32
	var fore_l := 0.55
	if att:
		arm_r = lerpf(lerpf(ARM_R, -2.75, k_w), slam_arm, k_s)
		arm_r = lerpf(arm_r, ARM_R - TAU, k_r)
		arm_l = lerpf(lerpf(0.1, -2.55, k_w), slam_arm + 0.15, k_s)
		arm_l = lerpf(arm_l, 0.1 - TAU, k_r)
		z_l = lerpf(-0.32, -0.06, WillfaultModel.sm(k_w * 2.0) * (1.0 - k_r))
		fore_l = lerpf(0.55, 0.25, k_w * (1.0 - k_r))
	WillfaultModel.rot(j["upR"], arm_r + shake, 0.0, 0.3 - (0.2 * k_w * (1.0 - k_r) if att else 0.0))
	WillfaultModel.rot(j["foreR"], (0.3 * (1.0 - k_s * 0.7) * (1.0 - k_r) + 0.15 * k_r) if att else 0.15, 0.0, 0.0)
	WillfaultModel.rot(j["upL"], arm_l + shake, 0.0, z_l)
	WillfaultModel.rot(j["foreL"], fore_l, 0.0, 0.0)
	# Axt an der rechten Hand: Dorn schleift am Boden, im Angriff über Kopf und mit der Schneide in den Boden
	var h2: Vector3 = root.global_transform.affine_inverse() * (j["handR"] as Node3D).global_position
	var phi_d := _solve(h2.y, POLL, 0.2, 1.57, 0.02)
	var phi := phi_d
	if att:
		var phi_i := _solve(h2.y, EDGE, 4.5, 6.2, 0.01)
		phi = lerpf(lerpf(phi_d, 2.95, k_w), phi_i, k_s)
		var phi_back := lerpf(phi, phi_d + TAU, k_r)
		# beim Zurückziehen schleift die Axt über den Boden statt durch ihn hindurch
		phi = phi_back if _min_y(h2.y, phi_back) >= 0.01 else _floor_clamp(h2.y, phi, phi_back)
	var yv := Vector3(0, -cos(phi), sin(phi))
	var zv := Vector3(0, sin(phi), cos(phi))
	axe.quaternion = Basis(yv.cross(zv), yv, zv).get_rotation_quaternion()
	axe.position = h2
	var out := {"hips_pos": hips.position, "axe": axe.quaternion, "foot_L": feet["L"], "foot_R": feet["R"]}
	for n in JOINTS:
		out[n] = (j[n] as Node3D).quaternion
	return out
