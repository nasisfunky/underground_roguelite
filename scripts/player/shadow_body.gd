class_name ShadowBody
extends Node3D
## Prozedurales Schattenwesen: dünne, spitz zulaufende Gliedmaßen, leuchtende Augen,
## Kapuze/Helm, Schal und Stoffbahnen. Komplett aus Low-Poly-Grundformen gebaut.
##
## Animation ist prozedural:
##  - Beine: Vorwärtskinematik mit Schrittzyklus
##  - Arme: 2-Knochen-IK auf Schwertgriff und Schild
##  - Angriffe: Keyframes für Schwertposition/-richtung im Brustraum
## Dadurch kann der Oberkörper zuschlagen, während die Beine weiterlaufen (Auto-Angriff wie in WoW).
## Der Controller setzt pro Tick die Eingangswerte unten und ruft tick(delta) auf.

enum Headgear { HOOD, HORNED_HELM, WIDE_HAT }

# --- Aussehen ---
var cloth_color := Color(0.16, 0.30, 0.30)
var scarf_color := Color(0.30, 0.17, 0.38)
var trim_color := Color(0.42, 0.62, 0.60)
var eye_color := LowPoly.EYE_YELLOW
var headgear: Headgear = Headgear.HOOD
var has_shield := true
var weapon_length := 0.78

# --- Eingänge vom Controller (pro Tick setzen) ---
var speed := 0.0  ## horizontale Geschwindigkeit in m/s
var run_speed_ref := 6.5
var local_move := Vector2.ZERO  ## Laufrichtung relativ zum Körper (x rechts, y vorwärts)
var on_floor := true
var vertical_velocity := 0.0
var action: StringName = &""  ## "", swing, roll, block, stagger, dead
var action_t := 0.0  ## normierte Zeit der Aktion 0..1
var swing_index := 0  ## welcher Schwung (0,1 = Auto-Angriff, 2 = schwerer Hieb)
var block_amount := 0.0  ## 0..1, Schild-Anheben

# --- Interne Knoten ---
var rig: Node3D
var hips: Node3D
var chest: Node3D
var head: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var sword: Node3D
var shield: Node3D
var arm_up_l: Node3D
var arm_lo_l: Node3D
var arm_up_r: Node3D
var arm_lo_r: Node3D
var scarf_tail: Node3D
var tabard_front: Node3D
var tabard_back: Node3D
var eye_mat: StandardMaterial3D

# Proportionen (müssen zu tools/blender/build_shade.py passen)
const UPPER_ARM := 0.24
const LOWER_ARM := 0.28
const THIGH := 0.32
const SHIN := 0.36
const RIG_Y := 0.45  ## Drehpunkt für Rolle/Sturz
const HIPS_Y := 0.21  ## Hüfte relativ zum Rig -> 0,66 m über dem Boden
const CHEST_Y := 0.04
const HEAD_Y := 0.62
const SHOULDER_L := Vector3(-0.21, 0.43, 0.02)
const SHOULDER_R := Vector3(0.21, 0.43, 0.02)
## Posen wurden für die alten, längeren Arme geschrieben -> hier auf die neue Reichweite skaliert
const POSE_SCALE := 0.8

var _phase := 0.0
var _time := 0.0
var _meshes: Array[MeshInstance3D] = []
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
# geglättete Posenwerte
var _sw_grip := Vector3(0.27, -0.32, -0.18)
var _sw_dir := Vector3(0.15, -0.35, -1).normalized()
var _sw_flat := Vector3.RIGHT
var _twist := 0.0
var _lean := 0.0
var _hips_drop := 0.0
var _lower_yaw := 0.0
var _trail: SwordTrail
var _overrides: Dictionary = {}


const PARTS_PATH := "res://assets/models/shade_parts.glb"


func build() -> void:
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 1, 1, 0.75)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var parts := ModelParts.load_parts(PARTS_PATH)
	eye_mat = LowPoly.mat(eye_color, 2.6).duplicate()
	# Materialnamen aus Blender -> Farben dieser Figur
	_overrides = {
		"Cloth": LowPoly.mat(cloth_color),
		"ClothDark": LowPoly.mat(cloth_color.darkened(0.45)),
		"Trim": LowPoly.mat(trim_color),
		"Scarf": LowPoly.mat(scarf_color),
		"Eye": eye_mat,
		"Gem": LowPoly.mat(LowPoly.CYAN, 3.0),
		"Void": LowPoly.unshaded(Color(0.008, 0.008, 0.012)),
	}

	rig = Node3D.new()
	rig.name = "Rig"
	rig.position.y = RIG_Y
	add_child(rig)

	hips = Node3D.new()
	hips.position.y = HIPS_Y
	rig.add_child(hips)
	_part(parts, "Pelvis", hips)

	tabard_front = Node3D.new()
	tabard_front.position = Vector3(0, 0.08, -0.12)
	hips.add_child(tabard_front)
	_part(parts, "TabardFront", tabard_front)
	tabard_back = Node3D.new()
	tabard_back.position = Vector3(0, 0.08, 0.12)
	hips.add_child(tabard_back)
	_part(parts, "TabardBack", tabard_back)

	hip_l = _joint(hips, Vector3(-0.085, 0, 0))
	_part(parts, "ThighL", hip_l)
	knee_l = _joint(hip_l, Vector3(0, -THIGH, 0))
	_part(parts, "ShinL", knee_l)
	hip_r = _joint(hips, Vector3(0.085, 0, 0))
	_part(parts, "ThighR", hip_r)
	knee_r = _joint(hip_r, Vector3(0, -THIGH, 0))
	_part(parts, "ShinR", knee_r)

	chest = _joint(hips, Vector3(0, CHEST_Y, 0))
	_part(parts, "Torso", chest)
	_part(parts, "Mantle", chest)
	_part(parts, "Scarf", chest)
	scarf_tail = _joint(chest, Vector3(0.08, 0.52, 0.17))
	_part(parts, "ScarfTail", scarf_tail)

	head = _joint(chest, Vector3(0, HEAD_Y, 0))
	_part(parts, "Head", head)
	_part(parts, "Eyes", head)
	match headgear:
		Headgear.HOOD:
			_part(parts, "Hood", head)
		Headgear.HORNED_HELM:
			_part(parts, "HornedHelm", head)
		Headgear.WIDE_HAT:
			_part(parts, "WideHat", head).position.y = 0.08
	var glow := OmniLight3D.new()
	glow.light_color = eye_color
	glow.light_energy = 0.35
	glow.omni_range = 0.7
	glow.position = Vector3(0, 0, -0.35)
	head.add_child(glow)

	# Arme hängen direkt an diesem Knoten und werden per IK gesetzt
	arm_up_l = _joint(self, Vector3.ZERO)
	_part(parts, "UpperArmL", arm_up_l)
	arm_lo_l = _joint(self, Vector3.ZERO)
	_part(parts, "ForearmL", arm_lo_l)
	arm_up_r = _joint(self, Vector3.ZERO)
	_part(parts, "UpperArmR", arm_up_r)
	arm_lo_r = _joint(self, Vector3.ZERO)
	_part(parts, "ForearmR", arm_lo_r)

	sword = _joint(chest, Vector3.ZERO)
	_part(parts, "Sword", sword).scale = Vector3.ONE * (weapon_length / 0.78)
	if has_shield:
		shield = _joint(chest, Vector3.ZERO)
		_part(parts, "Shield", shield)

	_trail = SwordTrail.new()
	add_child(_trail)


func _joint(parent: Node, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parts: Dictionary, part_name: String, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = parts.get(part_name)
	if mi.mesh == null:
		push_warning("Teil fehlt im Modell: " + part_name)
	else:
		ModelParts.apply_overrides(mi, _overrides)
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func flash(duration := 0.09) -> void:
	_flash_t = duration
	for m in _meshes:
		m.material_overlay = _flash_mat


func set_eye_intensity(v: float) -> void:
	eye_mat.emission_energy_multiplier = v


func sword_points() -> Array[Vector3]:
	var base := sword.global_transform * Vector3(0, 0, -0.12)
	var tip := sword.global_transform * Vector3(0, 0, -weapon_length)
	return [base, tip]


# ------------------------------------------------------------------
# Animation
# ------------------------------------------------------------------

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_time += delta
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for m in _meshes:
				m.material_overlay = null

	var s := clampf(speed / run_speed_ref, 0.0, 1.3)
	var moving := s > 0.05 and on_floor

	# --- Schrittzyklus ---
	var backwards := local_move.y < -0.1
	var dir_sign := -1.0 if backwards else 1.0
	_phase += delta * speed / 1.35 * TAU * dir_sign
	# Unterkörper dreht sich in Laufrichtung (Seitwärtslaufen)
	var target_lower := 0.0
	if moving and local_move.length() > 0.1:
		var lm := local_move * dir_sign
		target_lower = clampf(atan2(-lm.x, lm.y), -1.1, 1.1)
	_lower_yaw = lerp_angle(_lower_yaw, target_lower, 1.0 - exp(-12.0 * delta))

	var hl := Vector3.ZERO
	var hr := Vector3.ZERO
	var kl := 0.0
	var kr := 0.0
	var hips_y := 0.0
	var lean := 0.0
	var twist := 0.0
	var rig_rot := Vector3.ZERO
	var rig_y := RIG_Y
	var hips_drop := 0.0

	if on_floor:
		var amp := 0.85 * minf(s, 1.0)
		hl.x = sin(_phase) * amp
		hr.x = sin(_phase + PI) * amp
		kl = -(0.12 + 1.25 * maxf(0.0, cos(_phase)) * minf(s, 1.0))
		kr = -(0.12 + 1.25 * maxf(0.0, cos(_phase + PI)) * minf(s, 1.0))
		hips_y = -0.05 * s + 0.045 * s * absf(cos(_phase))
		lean = -0.2 * minf(s, 1.0)
		if not moving:
			# Idle: leichtes Atmen, Kampfhaltung
			hl = Vector3(0.18, 0, -0.06)
			hr = Vector3(-0.22, 0, 0.06)
			kl = -0.3
			kr = -0.18
			hips_y = -0.04 + sin(_time * 2.2) * 0.008
			lean = -0.06
	else:
		# In der Luft: Beine angezogen, beim Fallen gestreckt
		var rising := clampf(vertical_velocity / 6.0, -1.0, 1.0)
		hl.x = 0.55 + 0.35 * rising
		hr.x = -0.25 + 0.15 * rising
		kl = -1.1 - 0.3 * rising
		kr = -0.5
		lean = -0.12

	# --- Schwert / Schild Grundposen ---
	var grip := Vector3(0.27, -0.30, -0.16)
	var sdir := Vector3(0.12, -0.32, -1.0)
	var sflat := Vector3(1, 0, 0)
	if moving:
		grip = grip.lerp(Vector3(0.30, -0.34, 0.02), minf(s, 1.0))
		sdir = sdir.lerp(Vector3(0.25, -0.75, 0.55), minf(s, 1.0))
		grip.z += sin(_phase) * 0.06 * s
	var sh_pos := Vector3(-0.28, -0.18, -0.12)
	var sh_front := Vector3(-0.5, 0.0, -0.85)
	if moving:
		sh_pos.z += sin(_phase + PI) * 0.05 * s

	var anim_rate := 16.0
	match action:
		&"swing":
			var k := _swing_pose(swing_index, action_t)
			grip = k[0]
			sdir = k[1]
			sflat = k[2]
			twist = k[3]
			lean += k[4]
			hips_drop = k[5]
			anim_rate = 40.0
			_trail.emitting = action_t > k[6].x and action_t < k[6].y
		&"roll":
			var e := _ease_roll(action_t)
			rig_rot.x = -TAU * e
			rig_y = RIG_Y - 0.22 * sin(action_t * PI)
			hl.x = 1.5
			hr.x = 1.3
			kl = -2.3
			kr = -2.2
			grip = Vector3(0.2, -0.05, -0.25)
			sdir = Vector3(0.2, -0.4, 1.0)
			sh_pos = Vector3(-0.2, 0.0, -0.3)
			anim_rate = 30.0
		&"bash":
			var w := sin(clampf(action_t * 2.2, 0.0, 1.0) * PI)
			sh_pos = Vector3(-0.04, 0.04, -0.40 - 0.22 * w)
			sh_front = Vector3(0.1, 0.1, -1.0)
			grip = Vector3(0.36, -0.15, 0.12)
			sdir = Vector3(0.3, 0.4, 0.6)
			lean -= 0.3 * w
			twist = 0.35 * w
			hips_drop = 0.08 * w
			anim_rate = 40.0
		&"stagger":
			var w := sin(minf(action_t * 1.3, 1.0) * PI)
			lean += 0.45 * w
			twist = 0.25 * w
			kl = -0.5
			kr = -0.4
			grip = Vector3(0.42, -0.1, 0.12)
			sh_pos = Vector3(-0.42, -0.05, 0.05)
			anim_rate = 30.0
		&"dead":
			var w := clampf(action_t * 2.2, 0.0, 1.0)
			rig_rot.x = 1.45 * (1.0 - pow(1.0 - w, 3.0))
			rig_y = RIG_Y - 0.32 * w
			kl = -0.6
			kr = -0.3
			grip = Vector3(0.45, -0.3, 0.1)
			sh_pos = Vector3(-0.4, -0.3, 0.0)
	if action != &"swing":
		_trail.emitting = false

	if block_amount > 0.0 and has_shield:
		var b := block_amount
		sh_pos = sh_pos.lerp(Vector3(-0.06, 0.06, -0.42), b)
		sh_front = sh_front.lerp(Vector3(0.05, 0.12, -1.0), b)
		if action != &"swing":
			grip = grip.lerp(Vector3(0.32, -0.12, 0.06), b)
			sdir = sdir.lerp(Vector3(0.25, 0.55, -0.45), b)
		lean -= 0.12 * b
		hips_drop += 0.06 * b
		if not moving:
			kl -= 0.25 * b
			kr -= 0.2 * b

	# --- anwenden (mit Glättung) ---
	grip = _scale_pose(grip)
	sh_pos = _scale_pose(sh_pos)
	var kf := 1.0 - exp(-anim_rate * delta)
	var kb := 1.0 - exp(-18.0 * delta)
	_sw_grip = _sw_grip.lerp(grip, kf)
	_sw_dir = _sw_dir.lerp(sdir.normalized(), kf).normalized()
	_sw_flat = _sw_flat.lerp(sflat.normalized(), kf).normalized()
	_twist = lerpf(_twist, twist, kf)
	_lean = lerpf(_lean, lean, kb)
	_hips_drop = lerpf(_hips_drop, hips_drop, kf)

	rig.rotation = rig_rot if action == &"roll" else rig.rotation.lerp(rig_rot, kb)
	rig.position.y = lerpf(rig.position.y, rig_y, 1.0 - exp(-25.0 * delta))
	hips.position.y = HIPS_Y + hips_y - _hips_drop
	hips.rotation.y = _lower_yaw
	chest.rotation = Vector3(_lean, _twist - _lower_yaw, 0)
	hip_l.rotation = hip_l.rotation.lerp(hl, kb)
	hip_r.rotation = hip_r.rotation.lerp(hr, kb)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, kl, kb)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, kr, kb)

	# Stoff schwingt nach
	tabard_front.rotation.x = maxf(hl.x, hr.x) * 0.6 + 0.05
	tabard_back.rotation.x = minf(hl.x, hr.x) * 0.6 - 0.05 - 0.25 * minf(s, 1.0)
	scarf_tail.rotation.x = lerpf(scarf_tail.rotation.x, 0.25 + 0.9 * minf(s, 1.2) + sin(_time * 9.0) * 0.12 * s - vertical_velocity * 0.05, kb)

	sword.transform = Transform3D(_basis_from(-_sw_dir, _sw_flat), _sw_grip)
	if has_shield:
		shield.position = shield.position.lerp(sh_pos, kf)
		var sb := _basis_from(-sh_front.normalized(), Vector3.UP, true)
		shield.basis = shield.basis.slerp(sb, kf).orthonormalized()

	# --- Arm-IK ---
	var cb := chest.global_basis
	_solve_arm(arm_up_r, arm_lo_r, chest.global_transform * SHOULDER_R, sword.global_transform * Vector3(0, 0, 0.02), cb * Vector3(0.7, -1.0, 0.6))
	if has_shield:
		_solve_arm(arm_up_l, arm_lo_l, chest.global_transform * SHOULDER_L, shield.global_transform * Vector3(0, 0, 0.07), cb * Vector3(-0.8, -1.0, 0.4))
	else:
		_solve_arm(arm_up_l, arm_lo_l, chest.global_transform * SHOULDER_L, chest.global_transform * Vector3(-0.3, -0.05, -0.05), cb * Vector3(-0.8, -1.0, 0.4))

	if _trail.emitting or _trail.has_points():
		var pts := sword_points()
		_trail.push(pts[0], pts[1], delta)


func _scale_pose(v: Vector3) -> Vector3:
	return Vector3(v.x * 0.9, 0.43 + (v.y - 0.47) * POSE_SCALE, v.z * POSE_SCALE)


## Basis mit z = Vorwärts-Achse (lokal -Z zeigt dann in Gegenrichtung von z) und x so nah wie möglich an hint.
func _basis_from(z: Vector3, hint: Vector3, hint_is_up := false) -> Basis:
	z = z.normalized()
	var x: Vector3
	if hint_is_up:
		x = hint.cross(z)
		if x.length_squared() < 1e-6:
			x = Vector3.RIGHT
		x = x.normalized()
	else:
		x = hint - z * hint.dot(z)
		if x.length_squared() < 1e-6:
			x = Vector3.UP.cross(z)
		x = x.normalized()
	var y := z.cross(x)
	return Basis(x, y, z)


## 2-Knochen-IK. Segmente zeigen mit lokal -Y vom Gelenk weg.
func _solve_arm(upper: Node3D, lower: Node3D, shoulder: Vector3, target: Vector3, pole: Vector3) -> void:
	var a := UPPER_ARM
	var b := LOWER_ARM
	var to := target - shoulder
	var d := clampf(to.length(), 0.05, a + b - 0.001)
	var dir := to.normalized() if to.length_squared() > 1e-6 else Vector3.DOWN
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 1e-6:
		perp = Vector3.FORWARD
	perp = perp.normalized()
	var elbow := shoulder + dir * a * cos_a + perp * a * sin_a
	var hand := shoulder + dir * d
	upper.global_transform = Transform3D(_seg_basis(elbow - shoulder, perp), shoulder)
	lower.global_transform = Transform3D(_seg_basis(hand - elbow, perp), elbow)


func _seg_basis(along: Vector3, side_hint: Vector3) -> Basis:
	var y := -along.normalized()
	var x := side_hint.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


func _ease_roll(t: float) -> float:
	# schnell rein, weich raus
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2.2)


## Keyframes eines Schwungs. Liefert [griff, klingenrichtung, flachseite, drehung, vorlage, absenken, trail_fenster]
func _swing_pose(index: int, t: float) -> Array:
	var keys: Array
	var trail_window := Vector2(0.28, 0.62)
	match index:
		0:  # waagerecht von rechts nach links
			keys = [
				[0.0, Vector3(0.27, -0.30, -0.16), Vector3(0.12, -0.32, -1), Vector3(1, 0, 0), 0.0, 0.0, 0.0],
				[0.30, Vector3(0.44, 0.06, 0.10), Vector3(0.95, 0.2, 0.45), Vector3(0, 1, 0), -0.55, 0.05, 0.03],
				[0.42, Vector3(0.14, -0.02, -0.52), Vector3(0.1, 0.0, -1), Vector3(0, 1, 0), 0.05, -0.12, 0.06],
				[0.56, Vector3(-0.34, -0.10, -0.30), Vector3(-1, -0.12, 0.05), Vector3(0, 1, 0), 0.6, -0.08, 0.06],
				[1.0, Vector3(0.27, -0.30, -0.16), Vector3(0.12, -0.32, -1), Vector3(1, 0, 0), 0.0, 0.0, 0.0],
			]
		1:  # aufsteigender Rückhandschlag von links nach rechts
			keys = [
				[0.0, Vector3(0.27, -0.30, -0.16), Vector3(0.12, -0.32, -1), Vector3(1, 0, 0), 0.0, 0.0, 0.0],
				[0.30, Vector3(-0.28, -0.26, -0.14), Vector3(-0.9, -0.35, -0.3), Vector3(0, 1, 0.3), 0.5, 0.0, 0.04],
				[0.42, Vector3(0.10, -0.06, -0.54), Vector3(0.1, 0.12, -1), Vector3(0, 1, 0.2), 0.0, -0.12, 0.06],
				[0.58, Vector3(0.48, 0.16, -0.06), Vector3(0.9, 0.5, 0.35), Vector3(-0.3, 1, 0), -0.55, -0.05, 0.04],
				[1.0, Vector3(0.27, -0.30, -0.16), Vector3(0.12, -0.32, -1), Vector3(1, 0, 0), 0.0, 0.0, 0.0],
			]
		_:  # schwerer Hieb von oben
			trail_window = Vector2(0.36, 0.66)
			keys = [
				[0.0, Vector3(0.27, -0.30, -0.16), Vector3(0.12, -0.32, -1), Vector3(1, 0, 0), 0.0, 0.0, 0.0],
				[0.36, Vector3(0.12, 0.48, 0.10), Vector3(0.0, 1.0, 0.55), Vector3(1, 0, 0), -0.2, 0.22, 0.0],
				[0.48, Vector3(0.05, 0.02, -0.52), Vector3(0.0, 0.15, -1), Vector3(1, 0, 0), 0.0, -0.3, 0.12],
				[0.62, Vector3(0.03, -0.46, -0.48), Vector3(0.0, -0.8, -0.6), Vector3(1, 0, 0), 0.05, -0.45, 0.2],
				[1.0, Vector3(0.27, -0.30, -0.16), Vector3(0.12, -0.32, -1), Vector3(1, 0, 0), 0.0, 0.0, 0.0],
			]
	var i := 0
	while i < keys.size() - 2 and t > keys[i + 1][0]:
		i += 1
	var k0: Array = keys[i]
	var k1: Array = keys[i + 1]
	var u := clampf((t - k0[0]) / maxf(k1[0] - k0[0], 0.001), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var g: Vector3 = (k0[1] as Vector3).lerp(k1[1], u)
	var d: Vector3 = (k0[2] as Vector3).normalized().slerp((k1[2] as Vector3).normalized(), u)
	var f: Vector3 = (k0[3] as Vector3).normalized().lerp((k1[3] as Vector3).normalized(), u)
	return [g, d, f, lerpf(k0[4], k1[4], u), lerpf(k0[5], k1[5], u), lerpf(k0[6], k1[6], u), trail_window]
