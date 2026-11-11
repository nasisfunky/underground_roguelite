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
var weapon_length := 0.95

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

const UPPER_ARM := 0.30
const LOWER_ARM := 0.36
const THIGH := 0.44
const SHIN := 0.53
const SHOULDER_L := Vector3(-0.19, 0.47, 0.02)
const SHOULDER_R := Vector3(0.19, 0.47, 0.02)

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


func build() -> void:
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 1, 1, 0.75)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var skin := LowPoly.mat(LowPoly.SHADOW_SKIN, 0.0, 0.6)
	var cloth := LowPoly.mat(cloth_color)
	var scarf := LowPoly.mat(scarf_color)
	var trim := LowPoly.mat(trim_color)
	eye_mat = LowPoly.mat(eye_color, 2.6).duplicate()

	rig = Node3D.new()
	rig.name = "Rig"
	rig.position.y = 0.62
	add_child(rig)

	hips = Node3D.new()
	hips.position.y = 0.35
	rig.add_child(hips)

	# Becken + Gürtel
	_add(LowPoly.prism(0.12, 0.13, 0.16, 5), skin, hips, Vector3(0, 0.02, 0))
	var belt := _add(LowPoly.prism(0.155, 0.15, 0.08, 6), LowPoly.mat(Color(0.06, 0.06, 0.07)), hips, Vector3(0, 0.07, 0))
	belt.scale = Vector3(1, 1, 0.8)

	# Stoffbahnen vorne/hinten (Tabard) – schwingen mit
	tabard_front = Node3D.new()
	tabard_front.position = Vector3(0, 0.08, -0.11)
	hips.add_child(tabard_front)
	_add(LowPoly.box(Vector3(0.17, 0.5, 0.025)), cloth, tabard_front, Vector3(0, -0.28, 0))
	_add(LowPoly.box(Vector3(0.18, 0.04, 0.03)), trim, tabard_front, Vector3(0, -0.49, 0))
	tabard_back = Node3D.new()
	tabard_back.position = Vector3(0, 0.08, 0.11)
	hips.add_child(tabard_back)
	_add(LowPoly.box(Vector3(0.26, 0.62, 0.025)), cloth, tabard_back, Vector3(0, -0.31, 0))

	# Beine: dünn, laufen in eine Spitze aus
	hip_l = _make_leg(Vector3(-0.085, 0, 0), skin, trim)
	hip_r = _make_leg(Vector3(0.085, 0, 0), skin, trim)
	knee_l = hip_l.get_child(hip_l.get_child_count() - 1)
	knee_r = hip_r.get_child(hip_r.get_child_count() - 1)

	# Oberkörper
	chest = Node3D.new()
	chest.position.y = 0.06
	hips.add_child(chest)
	var torso := _add(LowPoly.prism(0.10, 0.18, 0.50, 5), skin, chest, Vector3(0, 0.26, 0))
	torso.scale = Vector3(1, 1, 0.72)
	# Umhang über den Schultern
	var mantle := _add(LowPoly.prism(0.25, 0.14, 0.22, 6), cloth, chest, Vector3(0, 0.42, 0.01))
	mantle.scale = Vector3(1, 1, 0.8)
	_add(LowPoly.prism(0.255, 0.245, 0.035, 6), trim, chest, Vector3(0, 0.31, 0.01)).scale = Vector3(1, 1, 0.8)
	# Schal (dick gewickelt, verdeckt den unteren Teil des Gesichts)
	var s1 := _add(LowPoly.prism(0.20, 0.16, 0.16, 6), scarf, chest, Vector3(0, 0.56, -0.01))
	s1.rotation.x = 0.12
	var s2 := _add(LowPoly.prism(0.17, 0.15, 0.10, 6), scarf, chest, Vector3(0.01, 0.66, -0.02))
	s2.rotation = Vector3(-0.15, 0.4, 0.08)
	scarf_tail = Node3D.new()
	scarf_tail.position = Vector3(0.06, 0.6, 0.13)
	chest.add_child(scarf_tail)
	_add(LowPoly.box(Vector3(0.09, 0.42, 0.025)), scarf, scarf_tail, Vector3(0, -0.2, 0))

	# Kopf
	head = Node3D.new()
	head.position.y = 0.74
	chest.add_child(head)
	_add(LowPoly.rock(0.13, 7, 6, 4, 0.05), skin, head)
	_build_headgear(cloth, trim, skin)
	# Dunkles "Gesicht" und gelbe Augen
	var face := _add(LowPoly.box(Vector3(0.19, 0.12, 0.02)), LowPoly.unshaded(Color(0.01, 0.01, 0.015)), head, Vector3(0, 0.0, -0.13))
	face.rotation.x = -0.1
	for side in [-1.0, 1.0]:
		var eye := _add(LowPoly.box(Vector3(0.062, 0.022, 0.012)), eye_mat, head, Vector3(0.048 * side, 0.005, -0.145))
		eye.rotation.z = 0.32 * side  # innen tiefer -> entschlossener Blick
	var glow := OmniLight3D.new()
	glow.light_color = eye_color
	glow.light_energy = 0.35
	glow.omni_range = 0.7
	glow.position = Vector3(0, 0, -0.3)
	head.add_child(glow)

	# Arme (werden per IK gesetzt, hängen direkt an diesem Knoten)
	arm_up_l = _make_segment(UPPER_ARM, 0.042, 0.034, skin)
	arm_lo_l = _make_segment(LOWER_ARM, 0.034, 0.0, skin)
	arm_up_r = _make_segment(UPPER_ARM, 0.042, 0.034, skin)
	arm_lo_r = _make_segment(LOWER_ARM, 0.034, 0.0, skin)
	# Armwickel
	for seg in [arm_lo_l, arm_lo_r]:
		_add(LowPoly.prism(0.045, 0.042, 0.1, 5), trim, seg, Vector3(0, -0.1, 0))

	# Schwert
	sword = Node3D.new()
	chest.add_child(sword)
	var steel := LowPoly.mat(Color(0.62, 0.70, 0.70), 0.0, 0.35)
	_add(LowPoly.blade(weapon_length, 0.075, 0.02), steel, sword)
	_add(LowPoly.box(Vector3(0.03, 0.2, 0.035)), LowPoly.mat(Color(0.12, 0.13, 0.14)), sword, Vector3(0, 0, -0.04))
	_add(LowPoly.prism(0.018, 0.016, 0.16, 5), LowPoly.mat(Color(0.18, 0.1, 0.06)), sword, Vector3(0, 0, 0.06)).rotation.x = PI / 2
	_add(LowPoly.rock(0.03, 3, 5, 3, 0.1), trim, sword, Vector3(0, 0, 0.15))

	# Schild
	if has_shield:
		shield = Node3D.new()
		chest.add_child(shield)
		var disc := _add(LowPoly.prism(0.26, 0.26, 0.05, 8), LowPoly.mat(Color(0.22, 0.36, 0.36), 0.0, 0.5), shield, Vector3(0, 0, -0.03))
		disc.rotation.x = PI / 2
		var ring := _add(LowPoly.prism(0.19, 0.19, 0.055, 8), LowPoly.mat(Color(0.48, 0.70, 0.68)), shield, Vector3(0, 0, -0.035))
		ring.rotation.x = PI / 2
		var boss := _add(LowPoly.prism(0.11, 0.11, 0.06, 8), LowPoly.mat(Color(0.18, 0.28, 0.29)), shield, Vector3(0, 0, -0.04))
		boss.rotation.x = PI / 2
		var gem := _add(LowPoly.prism(0.05, 0.0, 0.05, 4), LowPoly.mat(LowPoly.CYAN, 3.0), shield, Vector3(0, 0, -0.08))
		gem.rotation.x = -PI / 2

	_trail = SwordTrail.new()
	add_child(_trail)


func _build_headgear(cloth: Material, trim: Material, skin: Material) -> void:
	match headgear:
		Headgear.HOOD:
			var hood := _add(LowPoly.prism(0.215, 0.0, 0.40, 5), cloth, head, Vector3(0, 0.08, 0.04))
			hood.rotation = Vector3(-0.32, PI / 5.0, 0)  # Spitze leicht nach hinten
			var rim := _add(LowPoly.prism(0.225, 0.2, 0.05, 5), trim, head, Vector3(0, -0.10, 0.03))
			rim.rotation.y = PI / 5.0
		Headgear.HORNED_HELM:
			var helm := _add(LowPoly.prism(0.17, 0.12, 0.26, 6), LowPoly.mat(Color(0.30, 0.25, 0.20), 0.0, 0.5), head, Vector3(0, 0.08, 0.02))
			helm.rotation.y = PI / 6.0
			for side in [-1.0, 1.0]:
				var horn := _add(LowPoly.prism(0.045, 0.0, 0.32, 4), LowPoly.mat(Color(0.75, 0.68, 0.55)), head, Vector3(0.17 * side, 0.18, 0.02))
				horn.rotation = Vector3(0.0, 0.0, -0.9 * side)
		Headgear.WIDE_HAT:
			_add(LowPoly.prism(0.42, 0.0, 0.22, 8), cloth, head, Vector3(0, 0.16, 0))
			_add(LowPoly.prism(0.15, 0.15, 0.12, 6), skin, head, Vector3(0, 0.04, 0))


func _make_leg(pos: Vector3, skin: Material, trim: Material) -> Node3D:
	var hip := Node3D.new()
	hip.position = pos
	hips.add_child(hip)
	_add(LowPoly.prism(0.035, 0.058, THIGH, 4), skin, hip, Vector3(0, -THIGH * 0.5, 0))
	var knee := Node3D.new()
	knee.position.y = -THIGH
	hip.add_child(knee)
	_add(LowPoly.prism(0.0, 0.04, SHIN, 4), skin, knee, Vector3(0, -SHIN * 0.5, 0))
	_add(LowPoly.prism(0.05, 0.046, 0.12, 5), trim, knee, Vector3(0, -0.12, 0))
	# Knie-Knoten als letztes Kind, damit build() ihn findet
	hip.move_child(knee, hip.get_child_count() - 1)
	return hip


func _make_segment(length: float, r_top: float, r_bottom: float, material: Material) -> Node3D:
	var seg := Node3D.new()
	add_child(seg)
	_add(LowPoly.prism(r_bottom, r_top, length, 4), material, seg, Vector3(0, -length * 0.5, 0))
	return seg


func _add(mesh: Mesh, material: Material, parent: Node, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := LowPoly.mesh_instance(mesh, material, parent, pos)
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
	_phase += delta * speed / 1.75 * TAU * dir_sign
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
	var rig_y := 0.62
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
			rig_y = 0.62 - 0.32 * sin(action_t * PI)
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
			rig_y = 0.62 - 0.45 * w
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
	hips.position.y = 0.35 + hips_y - _hips_drop
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
