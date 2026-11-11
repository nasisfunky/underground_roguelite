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
## Splitter-Laterne ("Shard Lantern") am linken Hüftgurt: eigenes Licht, kein Ausrüstungsplatz
var has_lantern := false
var lantern_color := Color(1.0, 0.80, 0.52)
var lantern_energy := 1.7
var lantern_range := 8.5

# --- Eingänge vom Controller (pro Tick setzen) ---
var speed := 0.0  ## horizontale Geschwindigkeit in m/s
var run_speed_ref := 4.8
var local_move := Vector2.ZERO  ## Laufrichtung relativ zum Körper (x rechts, y vorwärts)
var on_floor := true
var vertical_velocity := 0.0
var action: StringName = &""  ## "", swing, roll, block, stagger, dead
var action_t := 0.0  ## normierte Zeit der Aktion 0..1
var swing_index := 0  ## welcher Schwung (0,1 = Auto-Angriff, 2 = schwerer Hieb)
var block_amount := 0.0  ## 0..1, Schild-Anheben
var combat := 0.0  ## 0..1, Kampfhaltung (Ziel in Reichweite): Schild und Waffe erhoben
var snap := false  ## Werkstatt: Federn springen sofort auf ihr Ziel (exakte Pose, kein Nachschwingen)
var swing_sample: Array = []  ## letzte ausgewertete Schwung-Pose (für die Werkstatt)
var look_target: Variant = null  ## Weltposition, zu der der Kopf schaut (oder null)

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
var lantern: Node3D  ## Pendel-Knoten (hängt an der Hüfte)
var lantern_light: OmniLight3D
var _lantern_core: MeshInstance3D
var _sp_lan_x: Spring
var _sp_lan_z: Spring

# Proportionen (müssen zu tools/blender/build_shade.py passen)
const UPPER_ARM := 0.29
const LOWER_ARM := 0.33
const THIGH := 0.38
const SHIN := 0.43
const LANTERN_LAYER := 1 << 9  ## Render-Ebene 10: Laternen-Meshes
const RIG_Y := 0.45  ## Drehpunkt für Rolle/Sturz
const HIPS_Y := 0.36  ## Hüfte relativ zum Rig -> 0,81 m (Spitzen berühren im Stand den Boden)
const CHEST_Y := 0.04
const HEAD_Y := 0.64
const SHOULDER_L := Vector3(-0.21, 0.43, 0.02)
const SHOULDER_R := Vector3(0.21, 0.43, 0.02)
## Posen wurden für die alten, längeren Arme geschrieben -> hier auf die neue Reichweite skaliert
const POSE_SCALE := 0.92
## Kampfhaltung (Brust-Koordinaten, umgerechnet in Posen-Koordinaten)
var GUARD_GRIP := _unscale(Vector3(0.30, 0.12, -0.32))
var GUARD_DIR := Vector3(-0.12, 0.55, -0.85)
var GUARD_SHIELD := _unscale(Vector3(-0.2, 0.2, -0.4))
var GUARD_SHIELD_FRONT := Vector3(0.18, 0.05, -1.0)
const ROLL_SPIN := 0.7  ## Anteil der Rolle, in dem gedreht wird; danach Aufrichten
const ROLL_PIVOT := 0.88  ## Drehpunkt der Rolle: Körpermitte (Hüfte + 0.1 m)

var _phase := 0.0
var _time := 0.0
var _meshes: Array[MeshInstance3D] = []
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
# geglättete Posenwerte
var _springs_ready := false
var _sp_grip: Spring
var _sp_dir: Spring
var _sp_flat: Spring
var _sp_shield: Spring
var _sp_shield_dir: Spring
var _sp_lean: Spring
var _sp_bank: Spring
var _sp_twist: Spring
var _sp_drop: Spring
var _sp_lower: Spring
var _sp_head: Spring
var _sp_moving: Spring
var _sp_air: Spring
var _sp_rig_x: Spring
var _sp_rig_y: Spring
var _sp_pivot: Spring
var _sp_combat: Spring
var _glue := 0.0
var _sp_scarf: Spring
var _sp_tab_f: Spring
var _sp_tab_b: Spring
var _prev_speed := 0.0
var _prev_yaw := 0.0
var _prev_vy := 0.0
var _was_floor := true
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
			_part(parts, "WideHat", head).position.y = 0.064
	var glow := OmniLight3D.new()
	glow.light_color = eye_color
	glow.light_energy = 0.35
	glow.omni_range = 0.7
	glow.position = Vector3(0, 0, -0.28)
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

	if has_lantern:
		_build_lantern()


## Kleine Käfiglaterne mit leuchtendem Kristallsplitter, an einem kurzen Riemen.
func _build_lantern() -> void:
	var metal := LowPoly.mat(Color(0.09, 0.08, 0.07), 0.0, 0.6)
	var strap := LowPoly.mat(cloth_color.darkened(0.55))
	var hook := _joint(hips, Vector3(-0.2, 0.03, 0.05))
	hook.rotation.y = 0.35
	LowPoly.mesh_instance(LowPoly.box(Vector3(0.05, 0.1, 0.07)), strap, hook)  # Gurtschlaufe
	lantern = _joint(hook, Vector3(0, -0.04, 0))
	var ring := LowPoly.mesh_instance(LowPoly.prism(0.018, 0.018, 0.06, 4), metal, lantern, Vector3(0, -0.03, 0))
	ring.rotation.z = PI / 2
	var top := LowPoly.mesh_instance(LowPoly.prism(0.075, 0.02, 0.045, 6), metal, lantern, Vector3(0, -0.08, 0))
	top.rotation.y = PI / 6
	var bottom := LowPoly.mesh_instance(LowPoly.prism(0.06, 0.075, 0.035, 6), metal, lantern, Vector3(0, -0.235, 0))
	bottom.rotation.y = PI / 6
	for k in 6:  # Käfigstreben
		var a := TAU * k / 6.0
		LowPoly.mesh_instance(LowPoly.box(Vector3(0.012, 0.13, 0.012)), metal, lantern, Vector3(cos(a) * 0.068, -0.155, sin(a) * 0.068))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(lantern_color.r, lantern_color.g, lantern_color.b, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = lantern_color
	glass.emission_energy_multiplier = 0.25
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pane := LowPoly.mesh_instance(LowPoly.prism(0.062, 0.062, 0.12, 6), glass, lantern, Vector3(0, -0.155, 0))
	pane.rotation.y = PI / 6
	_lantern_core = LowPoly.mesh_instance(LowPoly.crystal(0.11, 0.028), LowPoly.mat(lantern_color, 2.2), lantern, Vector3(0, -0.21, 0))
	for n in lantern.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(n as MeshInstance3D).layers = LANTERN_LAYER  # vom eigenen Licht nicht angestrahlt (sonst überstrahlt)
	for n in hook.get_children():
		if n is MeshInstance3D:
			(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(n as MeshInstance3D).layers = LANTERN_LAYER

	lantern_light = OmniLight3D.new()
	lantern_light.name = "LanternLight"
	lantern_light.light_color = lantern_color
	lantern_light.light_energy = lantern_energy
	lantern_light.omni_range = lantern_range
	lantern_light.omni_attenuation = 1.6  # fällt zum Rand hin deutlich ab: nah hell, weiter weg nur Ahnung
	lantern_light.shadow_enabled = true
	lantern_light.shadow_bias = 0.08
	lantern_light.shadow_normal_bias = 1.5
	lantern_light.shadow_blur = 1.5
	lantern_light.light_volumetric_fog_energy = 0.02
	lantern_light.light_cull_mask = ~LANTERN_LAYER & 0xFFFFF
	lantern_light.add_to_group("light_sources")
	add_child(lantern_light)
	_sp_lan_x = Spring.new(1.3, 0.28, 1.0, 0.0)
	_sp_lan_z = Spring.new(1.3, 0.28, 1.0, 0.0)


func _update_lantern(delta: float, s: float, accel: float, yaw_rate: float) -> void:
	if lantern == null:
		return
	# Pendel: hängt immer nach unten, schwingt bei Beschleunigung, Drehung und Schritten nach
	var hip_basis: Basis = (lantern.get_parent() as Node3D).global_basis.orthonormalized()
	var down_local: Vector3 = hip_basis.inverse() * Vector3.DOWN
	var hang_x := atan2(-down_local.z, -down_local.y)  # Gegenrotation zur Körperneigung
	var hang_z := atan2(down_local.x, -down_local.y)
	var step := sin(_phase * 2.0) * 0.07 * minf(s, 1.0)
	var tx := clampf(hang_x - accel * 0.035 - s * 0.12 + step, -1.3, 1.3)
	var tz := clampf(hang_z - yaw_rate * 0.05 + cos(_phase) * 0.06 * minf(s, 1.0), -1.2, 1.2)
	lantern.rotation = Vector3(_u(_sp_lan_x, delta, tx), 0.0, _u(_sp_lan_z, delta, tz))
	# Licht sitzt ruhig neben der Laterne (etwas außen, damit das eigene Bein kaum Schatten wirft)
	var core := _lantern_core.global_position
	var out := global_basis.x * -0.3 + Vector3.UP * 0.2
	lantern_light.global_position = core + out
	# leichtes, lebendiges Flackern des Splitters
	var flick := 1.0 + sin(_time * 7.3) * 0.025 + sin(_time * 12.9 + 1.3) * 0.02
	lantern_light.light_energy = lantern_energy * flick


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

func _init_springs() -> void:
	# Hand/Waffe: reagiert flott, schwingt minimal nach
	_sp_grip = Spring.new(3.0, 0.8, 1.1, _scale_pose(Vector3(0.27, -0.30, -0.16)))
	_sp_dir = Spring.new(3.0, 0.8, 1.1, Vector3(0.12, -0.32, -1.0).normalized())
	_sp_flat = Spring.new(3.0, 0.9, 1.0, Vector3.RIGHT)
	_sp_shield = Spring.new(3.5, 0.75, 1.0, _scale_pose(Vector3(-0.28, -0.18, -0.12)))
	_sp_shield_dir = Spring.new(3.5, 0.8, 1.0, Vector3(-0.5, 0.0, -0.85).normalized())
	# Rumpf: etwas träger, leichtes Nachwippen
	_sp_lean = Spring.new(1.8, 0.6, 0.6, 0.0)
	_sp_bank = Spring.new(1.5, 0.7, 1.0, 0.0)
	_sp_twist = Spring.new(3.5, 0.7, 1.2, 0.0)
	_sp_drop = Spring.new(2.4, 0.5, 1.0, 0.0)
	_sp_lower = Spring.new(2.2, 0.9, 1.0, 0.0)
	_sp_head = Spring.new(1.8, 0.85, 1.0, Vector2.ZERO)
	_sp_moving = Spring.new(1.8, 1.0, 1.0, 0.0)
	_sp_air = Spring.new(4.0, 0.9, 1.0, 0.0)
	_sp_rig_x = Spring.new(2.4, 0.85, 1.0, 0.0)
	_sp_rig_y = Spring.new(3.0, 0.7, 1.0, RIG_Y)
	_sp_pivot = Spring.new(5.0, 1.0, 1.0, RIG_Y)
	_sp_combat = Spring.new(1.6, 1.0, 1.0, 0.0)  # Kampfhaltung baut sich in ~0,4 s auf
	# Stoff: weich und schwingend
	_sp_scarf = Spring.new(1.6, 0.3, 1.0, 0.3)
	_sp_tab_f = Spring.new(2.4, 0.35, 1.0, 0.0)
	_sp_tab_b = Spring.new(2.0, 0.3, 1.0, 0.0)
	_springs_ready = true


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if not _springs_ready:
		_init_springs()
	_time += delta
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for m in _meshes:
				m.material_overlay = null

	# --- Bewegungsdaten ableiten: Beschleunigung, Drehrate, Landung ---
	var accel := (speed - _prev_speed) / delta
	_prev_speed = speed
	var yaw := global_rotation.y
	var yaw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	if on_floor and not _was_floor and _prev_vy < -3.0:
		# Landung: Hüfte federt ein
		_sp_drop.kick(clampf(-_prev_vy * 0.06, 0.0, 0.9))
		_sp_lean.kick(-0.8)
	_was_floor = on_floor
	_prev_vy = vertical_velocity

	var s := clampf(speed / run_speed_ref, 0.0, 1.3)
	# stufenloser Übergang Stand <-> Laufen <-> Luft
	var w_move: float = clampf(_u(_sp_moving, delta, 1.0 if (s > 0.04 and on_floor) else 0.0), 0.0, 1.2)
	var w_air: float = clampf(_u(_sp_air, delta, 0.0 if on_floor else 1.0), 0.0, 1.0)

	# --- Schrittzyklus: Schrittlänge wächst mit Tempo, Beinausschlag passt zur Schrittlänge (kein Gleiten) ---
	var backwards := local_move.y < -0.1
	var dir_sign := -1.0 if backwards else 1.0
	var stride := lerpf(1.25, 2.5, clampf(s, 0.0, 1.0))  # Meter pro Doppelschritt: wenige, lange Schritte
	_phase += delta * speed / stride * TAU * dir_sign
	var leg_len := THIGH + SHIN
	var amp := asin(clampf(stride * 0.25 / leg_len, 0.0, 0.9)) * 1.05 * w_move
	var target_lower := 0.0
	if s > 0.05 and on_floor and local_move.length() > 0.1:
		var lm := local_move * dir_sign
		target_lower = clampf(atan2(-lm.x, lm.y), -1.0, 1.0)
	var lower_yaw: float = _u(_sp_lower, delta, target_lower)

	# Laufpose
	var run_hl := sin(_phase) * amp
	var run_hr := sin(_phase + PI) * amp
	var lift := minf(s, 1.0) * w_move
	var run_kl := -(0.1 + 1.3 * maxf(0.0, cos(_phase)) * lift)
	var run_kr := -(0.1 + 1.3 * maxf(0.0, cos(_phase + PI)) * lift)
	var bob := (-0.05 * s + 0.06 * s * absf(cos(_phase))) * w_move  # deutliches Absenken pro Schritt = Gewicht
	# Stand-Pose (Kampfhaltung, leichtes Atmen)
	var breathe := sin(_time * 2.0)
	var cw: float = clampf(_u(_sp_combat, delta, combat), 0.0, 1.0)
	# Kampfstand: linkes Bein vor, rechtes zurück, tiefer in den Knien
	var idle_hl := lerpf(0.16, 0.34, cw)
	var idle_hr := lerpf(-0.2, -0.3, cw)
	var idle_kl := lerpf(-0.28, -0.55, cw)
	var idle_kr := lerpf(-0.16, -0.42, cw)
	var wm := clampf(w_move, 0.0, 1.0)
	var hl := Vector3(lerpf(idle_hl, run_hl, wm), 0.0, lerpf(-0.05, 0.0, wm))
	var hr := Vector3(lerpf(idle_hr, run_hr, wm), 0.0, lerpf(0.05, 0.0, wm))
	var kl := lerpf(idle_kl, run_kl, wm)
	var kr := lerpf(idle_kr, run_kr, wm)
	var hips_y := lerpf(-0.03 - 0.035 * cw + breathe * (0.006 + 0.006 * cw), bob, wm)
	# Luft-Pose überblenden
	var rising := clampf(vertical_velocity / 6.0, -1.0, 1.0)
	hl.x = lerpf(hl.x, 0.6 + 0.3 * rising, w_air)
	hr.x = lerpf(hr.x, -0.25 + 0.15 * rising, w_air)
	kl = lerpf(kl, -1.15 - 0.3 * rising, w_air)
	kr = lerpf(kr, -0.5, w_air)

	# Rumpf: vorlehnen mit Tempo und beim Beschleunigen, in Kurven neigen
	var lean := -0.06 - 0.1 * cw - 0.16 * minf(s, 1.0) * wm - clampf(accel * 0.012, -0.25, 0.25) - 0.08 * w_air
	var bank := clampf(-yaw_rate * speed * 0.012, -0.3, 0.3)
	var twist := 0.0
	var hips_drop := 0.0
	var rig_x := 0.0
	var rig_y := RIG_Y
	var rig_direct := false
	var pivot := RIG_Y  # Drehpunkt (Höhe) für rig_x
	var rig_scale := 1.0
	var head_tuck := 0.0
	var ground_glue := false

	# --- Waffe / Schild Grundposen ---
	var grip := Vector3(0.27, -0.30, -0.16).lerp(Vector3(0.30, -0.34, 0.02), minf(s, 1.0) * wm)
	var sdir := Vector3(0.12, -0.32, -1.0).lerp(Vector3(0.25, -0.75, 0.55), minf(s, 1.0) * wm)
	var sflat := Vector3(1, 0, 0)
	grip.z += sin(_phase) * 0.07 * minf(s, 1.0) * wm
	grip.y += breathe * 0.006 * (1.0 - wm)
	var sh_pos := Vector3(-0.28, -0.18, -0.12)
	var sh_front := Vector3(-0.5, 0.0, -0.85)
	sh_pos.z += sin(_phase + PI) * 0.05 * minf(s, 1.0) * wm
	# Kampfhaltung: Schild vor der Brust, Klinge schräg nach vorn oben gerichtet
	if cw > 0.0:
		var bob_g := Vector3(0, sin(_phase * 2.0) * 0.015 * wm + breathe * 0.008, 0)
		grip = grip.lerp(GUARD_GRIP + bob_g, cw)
		sdir = sdir.lerp(GUARD_DIR, cw)
		sflat = sflat.lerp(Vector3(1, 0, 0.3), cw)
		sh_pos = sh_pos.lerp(GUARD_SHIELD + bob_g, cw)
		sh_front = sh_front.lerp(GUARD_SHIELD_FRONT, cw)
	var hand_f := 3.0  # Federfrequenz der Hände (niedrig = träge, schwer)

	match action:
		&"swing":
			var k := _swing_pose(swing_index, action_t, [grip, sdir, sflat, sh_pos, sh_front])
			swing_sample = k
			grip = k[0]
			sdir = k[1]
			sflat = k[2]
			twist = k[3]
			lean += k[4]
			hips_drop = k[5]
			hand_f = 7.5  # Schwung: Gewicht, aber trifft noch klar
			sh_pos = k[7]
			sh_front = k[8]
			_trail.emitting = action_t > k[6].x and action_t < k[6].y
		&"roll":
			# Rolle bis ROLL_SPIN, danach schweres Aufrichten aus der Hocke
			var e := _ease_roll(action_t)
			rig_x = -TAU * e
			rig_direct = true
			pivot = ROLL_PIVOT
			var u := clampf(action_t / ROLL_SPIN, 0.0, 1.0)
			var tuck := sin(u * PI)
			ground_glue = true  # Höhe ergibt sich aus Bodenkontakt (siehe unten)
			rig_scale = 1.0 - 0.2 * tuck  # zusammenrollen -> kein Eintauchen in den Boden
			lean = lerpf(lean, -1.0, tuck)
			head_tuck = 0.5 * tuck
			# Hocke: setzt gegen Ende der Drehung ein (Füße greifen), klingt beim Aufrichten aus
			var k_in := clampf((action_t - 0.45) / (ROLL_SPIN - 0.45), 0.0, 1.0)
			var k_out := clampf((action_t - ROLL_SPIN) / (1.0 - ROLL_SPIN), 0.0, 1.0)
			var kneel := k_in * k_in * (3.0 - 2.0 * k_in) * (0.5 + 0.5 * cos(k_out * PI))
			if kneel > 0.0:
				# tiefe Hocke: ein Bein vorn, eins hinten, Füße bleiben über dem Boden
				hips_drop = 0.08 * kneel
				lean = lerpf(lean, -0.35, kneel)
				kl = lerpf(kl, -1.6, kneel)
				kr = lerpf(kr, -1.4, kneel)
				hl.x = lerpf(hl.x, 1.0, kneel)
				hr.x = lerpf(hr.x, -0.3, kneel)
			hl.x = lerpf(hl.x, 1.5, tuck)
			hr.x = lerpf(hr.x, 1.3, tuck)
			kl = lerpf(kl, -2.3, tuck)
			kr = lerpf(kr, -2.2, tuck)
			# Klinge zeigt zur Seite (parallel zur Drehachse) -> sticht nie in den Boden
			var wb := clampf(action_t * 12.0, 0.0, 1.0) * (1.0 - smoothstep(0.82, 1.0, action_t))
			grip = grip.lerp(Vector3(0.3, 0.02, -0.08), wb)
			sdir = sdir.lerp(Vector3(1.0, -0.05, 0.12), wb)
			sflat = Vector3(0, 1, 0)
			sh_pos = sh_pos.lerp(Vector3(-0.3, 0.06, -0.04), wb)
			sh_front = sh_front.lerp(Vector3(-1.0, 0.0, -0.1), wb)
			hand_f = 7.0  # Waffe schnell anlegen, sonst sticht sie beim Abtauchen in den Boden
		&"bash":
			var w := sin(clampf(action_t * 2.2, 0.0, 1.0) * PI)
			sh_pos = Vector3(-0.04, 0.04, -0.40 - 0.22 * w)
			sh_front = Vector3(0.1, 0.1, -1.0)
			grip = Vector3(0.36, -0.15, 0.12)
			sdir = Vector3(0.3, 0.4, 0.6)
			lean -= 0.3 * w
			twist = 0.35 * w
			hips_drop = 0.08 * w
			hand_f = 6.5
		&"stagger":
			var w := sin(minf(action_t * 1.3, 1.0) * PI)
			lean += 0.45 * w
			twist = 0.25 * w
			kl = -0.5
			kr = -0.4
			grip = Vector3(0.42, -0.1, 0.12)
			sh_pos = Vector3(-0.42, -0.05, 0.05)
			hand_f = 6.0
		&"dead":
			var w := clampf(action_t * 2.2, 0.0, 1.0)
			rig_x = 1.45 * (1.0 - pow(1.0 - w, 3.0))
			rig_direct = true
			rig_y = RIG_Y - 0.3 * w
			kl = -0.6
			kr = -0.3
			grip = Vector3(0.45, -0.3, 0.1)
			sh_pos = Vector3(-0.4, -0.3, 0.0)
	if action != &"swing":
		_trail.emitting = false

	if block_amount > 0.0 and has_shield:
		var b := block_amount * block_amount * (3.0 - 2.0 * block_amount)
		sh_pos = sh_pos.lerp(Vector3(-0.06, 0.06, -0.42), b)
		sh_front = sh_front.lerp(Vector3(0.05, 0.12, -1.0), b)
		if action != &"swing":
			grip = grip.lerp(Vector3(0.32, -0.12, 0.06), b)
			sdir = sdir.lerp(Vector3(0.25, 0.55, -0.45), b)
		lean -= 0.1 * b
		hips_drop += 0.06 * b
		kl -= 0.22 * b * (1.0 - wm)
		kr -= 0.18 * b * (1.0 - wm)
		hand_f = maxf(hand_f, 7.0)

	# --- Federn anwenden ---
	_sp_grip.set_params(hand_f, 0.8, 1.1)
	_sp_dir.set_params(hand_f, 0.8, 1.1)
	_sp_flat.set_params(hand_f, 0.9, 1.0)
	_sp_shield.set_params(maxf(hand_f * 0.85, 3.5), 0.75, 1.0)
	_sp_shield_dir.set_params(maxf(hand_f * 0.85, 3.5), 0.8, 1.0)
	_sp_twist.set_params(hand_f * 0.8, 0.7, 1.2)
	var g: Vector3 = _u(_sp_grip, delta, _scale_pose(grip))
	var d: Vector3 = _u(_sp_dir, delta, sdir.normalized())
	var f: Vector3 = _u(_sp_flat, delta, sflat.normalized())
	var sp: Vector3 = _u(_sp_shield, delta, _scale_pose(sh_pos))
	var sf: Vector3 = _u(_sp_shield_dir, delta, sh_front.normalized())
	var tw: float = _u(_sp_twist, delta, twist)
	var ln: float = _u(_sp_lean, delta, lean)
	var bk: float = _u(_sp_bank, delta, bank)
	var dr: float = _u(_sp_drop, delta, hips_drop)

	# Rolle: direkt gesteuert; danach federt der Körper auf dem kürzesten Weg zurück
	var rx: float
	var ry: float
	if rig_direct:
		_sp_rig_x.reset(rig_x)
		_sp_rig_y.reset(rig_y)
		rx = rig_x
		ry = rig_y
	else:
		if absf(_sp_rig_x.y) > PI:
			_sp_rig_x.reset(wrapf(_sp_rig_x.y, -PI, PI))
		rx = _u(_sp_rig_x, delta, rig_x)
		ry = _u(_sp_rig_y, delta, rig_y)
	var pv: float = _u(_sp_pivot, delta, pivot)
	if rig_direct:
		_sp_pivot.reset(pivot)
		pv = pivot
	# Drehung um einen Punkt in Körperhöhe pv statt um den Rig-Ursprung
	var rb := Basis.from_euler(Vector3(rx, 0.0, bk)).scaled(Vector3.ONE * rig_scale)
	rig.transform = Transform3D(rb, Vector3(0, ry - RIG_Y + pv, 0) + rb * Vector3(0, RIG_Y - pv, 0))
	hips.position.y = HIPS_Y + hips_y - dr
	hips.rotation.y = lower_yaw
	chest.rotation = Vector3(ln, tw - lower_yaw, -bk * 0.5)
	hip_l.rotation = hl
	hip_r.rotation = hr
	knee_l.rotation.x = kl
	knee_r.rotation.x = kr

	# Kopf schaut zum Blickziel (begrenzt), sonst leicht in Laufrichtung
	var look := Vector2.ZERO
	if look_target != null:
		var local_t: Vector3 = chest.global_transform.affine_inverse() * (look_target as Vector3)
		var to := local_t - head.position
		look = Vector2(clampf(atan2(-to.x, -to.z), -0.9, 0.9), clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.4, 0.3))
	var hlook: Vector2 = _u(_sp_head, delta, look)
	head.rotation = Vector3(hlook.y - ln * 0.5 - head_tuck, hlook.x, 0.0)

	# Bodenkontakt: während der Rolle liegt der tiefste Körperpunkt genau auf dem Boden
	# (kein Eintauchen, kein Schweben). Danach klingt der Versatz weich aus.
	if ground_glue:
		_glue = -_lowest_body_point()
	else:
		_glue *= exp(-10.0 * delta)
	if absf(_glue) > 0.0005 or ground_glue:
		rig.position.y += _glue

	# Stoff schwingt mit Trägheit nach
	var cloth_drive := minf(s, 1.2)
	var tf: float = _u(_sp_tab_f, delta, maxf(hl.x, hr.x) * 0.55 + 0.05 - ln * 0.3 + clampf(accel * 0.02, -0.4, 0.4))
	var tb: float = _u(_sp_tab_b, delta, minf(hl.x, hr.x) * 0.55 - 0.05 - 0.3 * cloth_drive - ln * 0.3 + clampf(accel * 0.02, -0.4, 0.4))
	tabard_front.rotation.x = tf
	tabard_back.rotation.x = tb
	var sc: float = _u(_sp_scarf, delta, 0.25 + 0.9 * cloth_drive - vertical_velocity * 0.06 + clampf(accel * 0.03, -0.5, 0.5))
	scarf_tail.rotation = Vector3(sc + sin(_time * 8.0) * 0.08 * cloth_drive, 0.0, bk * 1.5)
	_update_lantern(delta, s, accel, yaw_rate)

	sword.transform = Transform3D(_basis_from(-d.normalized(), f.normalized()), g)
	if has_shield:
		shield.transform = Transform3D(_basis_from(-sf.normalized(), Vector3.UP, true), sp)

	# --- Arm-IK ---
	var cb := chest.global_basis
	# Ellbogen zeigt nach außen-hinten; greift die Hand quer vor den Körper, wandert er nach vorn
	var cross := clampf((0.12 - g.x) / 0.3, 0.0, 1.0)
	var pole_r := Vector3(0.7, -1.0, 0.6).lerp(Vector3(0.35, -0.8, -0.9), cross)
	_solve_arm(arm_up_r, arm_lo_r, chest.global_transform * SHOULDER_R, sword.global_transform * Vector3(0, 0, 0.02), cb * pole_r)
	if has_shield:
		_solve_arm(arm_up_l, arm_lo_l, chest.global_transform * SHOULDER_L, shield.global_transform * Vector3(0, 0, 0.07), cb * Vector3(-0.8, -1.0, 0.4))
	else:
		var swing_l := sin(_phase) * 0.08 * minf(s, 1.0) * wm
		_solve_arm(arm_up_l, arm_lo_l, chest.global_transform * SHOULDER_L, chest.global_transform * Vector3(-0.27, 0.0, -0.05 + swing_l), cb * Vector3(-0.8, -1.0, 0.4))

	if _trail.emitting or _trail.has_points():
		var pts := sword_points()
		_trail.push(pts[0], pts[1], delta)


## Tiefster Punkt des Körpers (ohne Waffe/Schild) relativ zum Boden der Figur.
func _lowest_body_point() -> float:
	var inv := global_transform.affine_inverse()
	var pts: Array[Vector3] = [
		knee_l.global_transform * Vector3(0, -SHIN, 0), knee_r.global_transform * Vector3(0, -SHIN, 0),
		knee_l.global_position, knee_r.global_position,
		head.global_transform * Vector3(0, 0.29, 0.02), head.global_transform * Vector3(0, 0.1, -0.2),
		head.global_transform * Vector3(0, 0.1, 0.2), head.global_transform * Vector3(0, -0.08, -0.18),
		head.global_transform * Vector3(-0.2, 0.04, 0), head.global_transform * Vector3(0.2, 0.04, 0),
		head.global_transform * Vector3(0, 0.2, 0.16), head.global_transform * Vector3(0, 0.2, -0.16),
		chest.global_transform * Vector3(-0.26, 0.42, 0), chest.global_transform * Vector3(0.26, 0.42, 0),
		chest.global_transform * Vector3(0, 0.45, 0.24), chest.global_transform * Vector3(0, 0.3, -0.2),
		hips.global_transform * Vector3(0, -0.08, 0.15), hips.global_transform * Vector3(0, -0.08, -0.15),
	]
	var lo := 99.0
	for pt in pts:
		lo = minf(lo, (inv * pt).y)
	return lo


## Umkehrung von _scale_pose: Brust-Koordinaten -> Posen-Koordinaten
## Eindringtiefe eines Punkts (Brust-Koordinaten) in Rumpf, Umhang, Becken oder Kopf; 0 = außerhalb.
## Vereinfachte Körperform, genutzt vom Smoke-Test und der Animationswerkstatt.
static func clip_depth(p: Vector3) -> float:
	var depth := maxf(0.0, 0.19 - p.distance_to(Vector3(0, 0.66, 0)))
	if p.y > -0.3 and p.y < 0.55:
		var rx := 0.15
		var rz := 0.11
		if p.y > 0.12:
			rx = 0.27
			rz = 0.21
		var e := sqrt(pow(p.x / rx, 2) + pow(p.z / rz, 2))
		if e < 1.0:
			depth = maxf(depth, (1.0 - e) * minf(rx, rz))
	return depth


## Wie tief stecken Klinge und rechter Unterarm gerade im eigenen Körper (Meter)?
func blade_clip_depth() -> float:
	var inv := chest.global_transform.affine_inverse()
	var pts := sword_points()
	var worst := 0.0
	for k in 9:
		worst = maxf(worst, clip_depth(inv * pts[0].lerp(pts[1], 0.15 + 0.85 * k / 8.0)))
	var elbow: Vector3 = inv * arm_lo_r.global_position
	var hand: Vector3 = inv * pts[0]
	for k in 4:
		worst = maxf(worst, clip_depth(elbow.lerp(hand, k / 3.0)))
	return worst


func _u(sp: Spring, delta: float, x: Variant) -> Variant:
	if snap:
		sp.reset(x)
		return x
	return sp.update(delta, x)


func _unscale(v: Vector3) -> Vector3:
	return Vector3(v.x / 0.95, (v.y - 0.43) / POSE_SCALE + 0.47, v.z / POSE_SCALE)


func _scale_pose(v: Vector3) -> Vector3:
	return Vector3(v.x * 0.95, 0.43 + (v.y - 0.47) * POSE_SCALE, v.z * POSE_SCALE)


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
	# kräftiger Absprung, Drehung bis ROLL_SPIN, weich auslaufend
	var u := clampf(t / ROLL_SPIN, 0.0, 1.0)
	return lerpf(u * u * (3.0 - 2.0 * u), 1.0 - pow(1.0 - u, 2.0), 0.5)


## Keyframes eines Schwungs. Liefert [griff, klingenrichtung, flachseite, drehung, vorlage, absenken, trail_fenster]
func _swing_pose(index: int, t: float, base: Array) -> Array:
	# Keyframes kommen aus AnimLibrary (data/anims/*.json, bearbeitbar in der Animationswerkstatt).
	# Erster und letzter Key = aktuelle Grundhaltung -> nahtloser Übergang aus/zurück in die Kampfhaltung.
	var c: Dictionary = AnimLibrary.clip(AnimLibrary.CLIPS[clampi(index, 0, AnimLibrary.CLIPS.size() - 1)])
	var trail_window: Vector2 = c.trail
	# Zeile: [t, Griff, Klingenrichtung, Flachseite, Drehung, Vorlage, Absenken, Schild, Schild-Front]
	var keys: Array = [[0.0, base[0], base[1], base[2], 0.0, 0.0, 0.0, base[3], base[4]]]
	for k in c.keys:
		keys.append([k.t, _unscale(k.grip), k.dir, k.flat, k.twist, k.lean, k.drop, _unscale(k.shield), k.shield_front])
	keys.append([1.0, base[0], base[1], base[2], 0.0, 0.0, 0.0, base[3], base[4]])
	# Catmull-Rom durch die Keyframes: durchgehende Geschwindigkeit, keine Stopps an den Keys
	var i := 0
	while i < keys.size() - 2 and t > keys[i + 1][0]:
		i += 1
	var k0: Array = keys[maxi(i - 1, 0)]
	var k1: Array = keys[i]
	var k2: Array = keys[i + 1]
	var k3: Array = keys[mini(i + 2, keys.size() - 1)]
	var u := clampf((t - k1[0]) / maxf(k2[0] - k1[0], 0.001), 0.0, 1.0)
	var g := _cr(k0[1], k1[1], k2[1], k3[1], u)
	var d := _cr((k0[2] as Vector3).normalized(), (k1[2] as Vector3).normalized(), (k2[2] as Vector3).normalized(), (k3[2] as Vector3).normalized(), u).normalized()
	var f := _cr((k0[3] as Vector3).normalized(), (k1[3] as Vector3).normalized(), (k2[3] as Vector3).normalized(), (k3[3] as Vector3).normalized(), u).normalized()
	var sc := Vector3(_crf(k0[4], k1[4], k2[4], k3[4], u), _crf(k0[5], k1[5], k2[5], k3[5], u), _crf(k0[6], k1[6], k2[6], k3[6], u))
	var shp := _cr(k0[7], k1[7], k2[7], k3[7], u)
	var shf := _cr((k0[8] as Vector3).normalized(), (k1[8] as Vector3).normalized(), (k2[8] as Vector3).normalized(), (k3[8] as Vector3).normalized(), u).normalized()
	return [g, d, f, sc.x, sc.y, sc.z, trail_window, shp, shf]


func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


func _crf(p0: float, p1: float, p2: float, p3: float, u: float) -> float:
	return _cr(Vector3(p0, 0, 0), Vector3(p1, 0, 0), Vector3(p2, 0, 0), Vector3(p3, 0, 0), u).x
