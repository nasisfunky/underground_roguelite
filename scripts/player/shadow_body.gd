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


# --- Aussehen ---
var eye_color := LowPoly.EYE_YELLOW
var has_shield := true
var weapon_length := 0.78
## Splitter-Laterne ("Shard Lantern") am linken Hüftgurt: eigenes Licht, kein Ausrüstungsplatz
var has_lantern := false
var lantern_color := Color(1.0, 0.80, 0.52)
var lantern_energy := 1.7
var lantern_range := 8.5
## Frayed-Stil: Kultur der Ausrüstung ("kiln", "rimefall", "glowmire"); leer = alter Stil (Hohlwandler)
var outfit := ""
var hem_layers := 6  ## Hüllen des Körpersaums
var head_layers := 20  ## Hüllen der Kopfflamme (Frisur)
var hem_heat := ""  ## Glimmfarbe überschreiben (leer = Kultur-Vorgabe)
var hem_hot := ""
## Willfault: zersplitterter Schatten eines gescheiterten Shades. Ohne Stoff, Lücken an den Gelenken,
## schwebende Splitter, zuckende Bewegungen, Ausrüstung teils abgefallen und dunkel.
var willfault := false
var ghost := false  ## Hollow One: heller Geisterschleier statt Schattenflamme, keine Beine, verbrauchte Ausrüstung
var shard_mat: Material  ## Material der schwebenden Splitter (Willfault)

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
## Ausrüstung ziehen/wegstecken. Rechte Hand: Waffe. Linke Hand: Schild, Licht oder nichts.
## Die Figur greift selbst zum Gürtel/Rücken und zieht bzw. steckt weg (weapon_p/off_p laufen 0..2:
## 0 = weggesteckt, 1 = Hand am Griff, 2 = in der Hand).
var want_weapon := true
var want_off: StringName = &"shield"  ## &"shield", &"light" oder &""
var draw_speed := 1.0  ## >1 = schnelles Ziehen (z. B. beim Angriff aus dem Stand)
var weapon_p := 2.0
var off_item: StringName = &""  ## Teil, das die linke Hand gerade hält, greift oder wegsteckt
var off_p := 0.0
var sprint := 0.0  ## 0..1, Sprinthaltung
## Waffe beidhändig führen (Zweihandaxt, Speer ohne Zweithand-Teil): linke Hand greift den Schaft
var two_hand := false
## Zweithand-Dolch sticht nach (1 -> 0, setzt der Controller)
var off_jab := 0.0
## Rolle: Richtung relativ zum Körper ("fwd", "back", "left", "right")
var roll_kind: StringName = &"fwd"
## Klettern: Bewegung an der Wand (x seitlich, y hoch) und Kletterzyklus (rad)
var climb_move := Vector2.ZERO
var climb_phase := 0.0
## Schwimmen: Vortrieb 0..1 und Schwimmzyklus (rad)
var swim_amount := 0.0
var swim_phase := 0.0
## Kante, an der sich die Figur hochzieht (Welt): Rausklettern aus dem Wasser und Klettern über Kanten
var ledge_world := Vector3.ZERO

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
var eye_mat: StandardMaterial3D
var lantern: Node3D  ## Pendel-Knoten (hängt an der Hüfte)
var lantern_light: OmniLight3D
var _lantern_core: MeshInstance3D
var _sp_lan_x: Spring
var _sp_lan_z: Spring

# Proportionen (müssen zu den Frayed-Modellen aus tools/frayed_export passen)
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
const OFFHAND_HOLD := Vector3(-0.25, 0.17, -0.34)  ## Griff des Laternenstabs (Brust-Koordinaten)
const ROLL_SPIN := 0.7  ## Anteil der Rolle, in dem gedreht wird; danach Aufrichten
const ROLL_PIVOT := 0.88  ## Drehpunkt der Rolle: Körpermitte (Hüfte + 0.1 m)

var _phase := 0.0
var _time := 0.0
var _meshes: Array[MeshInstance3D] = []
var _flash_t := 0.0
var _flash_mat: StandardMaterial3D
var _saved_overlays: Array[Material] = []  # Overlays (z. B. stumpfe Willfault-Ausrüstung) vor dem Blitz
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
var _sp_off: Spring
var _sp_off_up: Spring
var _prev_speed := 0.0
var _prev_yaw := 0.0
var _prev_vy := 0.0
var _was_floor := true
var _hips_drop := 0.0
var _lower_yaw := 0.0
var _trail: SwordTrail
var _overrides: Dictionary = {}
# Frayed-Stil
var outfit_info: Dictionary = {}
var cloth: FrayedCloth
var offhand: Node3D  ## Laternenstab (Glowmire) in der linken Hand
var head_light: OmniLight3D
var _hem_mats: Array[ShaderMaterial] = []
var _lantern_offset := Vector3(0.3, 0.2, 0.0)  ## Licht neben der Laterne (Körper-Koordinaten)
var _grip_l := false
var _shards: Array[Node3D] = []
var _twitch := Vector3.ZERO
var _twitch_t := 1.0
var _rng := RandomNumberGenerator.new()
var _light_kind: StringName = &""  ## &"belt" (Laterne am Gürtel) oder &"pole" (Laternenstab, Glowmire)
var _lantern_hook: Node3D  ## Gürtelschlaufe der Laterne (wandert beim Ziehen in die Hand)
var _sp_hz: Spring
var _sp_rest_r: Spring
var _sp_rest_l: Spring
var _light_out := 0.0  ## 0..1, wie weit das Licht gerade vorgehalten ist
var weapon_def: WeaponDef  ## null = Waffe der Kultur
var off_dagger: Node3D  ## Dolch für die linke Hand (statt Schild)
var has_off_dagger := false
var _culture_weapon: Node3D
var _culture_len := 0.78
var _custom_weapon: Node3D
var _two_w := 0.0  ## 0..1, Gewicht des beidhändigen Griffs
## Animationsclip für die Aktion "swing" (leer = AnimLibrary.CLIPS[swing_index]); z. B. "thrust@spear"
var swing_clip := ""
## Kombo-Übergang: wird bei jedem neuen Schlag hochgezählt. Folgt der Schlag direkt auf einen anderen, beginnt
## er in der Haltung, in der der vorige gerade war (statt erst in die Grundhaltung zurückzuspringen).
var swing_serial := 0
var _serial_seen := 0
var _swing_from: Array = []  ## Haltung beim Übergang (wie swing_sample), leer = Grundhaltung
var _swing_from_t := 0.0  ## normierte Zeit, bei der der angeschlossene Schlag einsteigt
var _last_action: StringName = &""
var _swing_via: Array = []  ## Zwischen-Key des Übergangs (führt die Klinge um den Körper herum), leer = direkter Weg
var _via_serial := -1
var knockdown_getup := 0.55  ## Aktion "knockdown": ab hier (normiert) steht die Figur wieder auf
## Werkstatt: Haltung erzwingen (leer = normal). "idle", "walk", "guard" … siehe PoseLibrary
var _body_ofs: Array = []  ## Körper-Zusätze des laufenden Clips (AnimLibrary.BODY_FIELDS)

## Ablagen (Hüft- bzw. Brust-Koordinaten)
const LANTERN_BELT := Vector3(0.21, 0.04, 0.0)  ## rechte Hüfte (links hängt die Waffe)
const LANTERN_HELD := Vector3(-0.12, 0.32, -0.5)  ## vorgehalten, linke Hand (Brust-Koordinaten)
const SHIELD_BACK := Vector3(0.02, 0.2, 0.27)  ## Schild auf dem Rücken (Brust-Koordinaten)
const POLE_BACK := Vector3(0.1, 0.1, 0.27)  ## Laternenstab schräg auf dem Rücken
const SWORD_BELT := Vector3(-0.21, 0.1, -0.12)  ## Griff an der linken Hüfte (Hüft-Koordinaten)


const SKIN_SHADER := preload("res://assets/shaders/shade_skin.gdshader")
const GHOST_SHADER := preload("res://assets/shaders/hollow_ghost.gdshader")
const GHOST_DEPTH_SHADER := preload("res://assets/shaders/hollow_ghost_depth.gdshader")
const WORN_SHADER := preload("res://assets/shaders/worn_gear.gdshader")
const LEG_JOINTS := ["hip_l", "knee_l", "hip_r", "knee_r"]
static var _skin_mat: ShaderMaterial


func build() -> void:
	_flash_mat = hit_flash_material()

	if outfit == "":
		outfit = "kiln"
	_build_frayed()


## Trefferblitz als Overlay: kurzes warmes Aufglimmen, schwach genug, dass der Shade nie weiß wird.
static func hit_flash_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.13, 0.085, 0.06)  # additiv: auf fast schwarz wirkt schon wenig sehr hell
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


## Schattenkörper: fast schwarz und matt, wird im Licht sichtbar heller, brennt aber nie weiß aus.
static func skin_material() -> ShaderMaterial:
	if _skin_mat == null:
		_skin_mat = ShaderMaterial.new()
		_skin_mat.shader = SKIN_SHADER
	return _skin_mat


## Frayed-Stil: schwarzer Körper mit Flammensaum, Ausrüstung der Kultur `outfit`, simulierte Stoffe.
func _build_frayed() -> void:
	_rng.randomize()
	var data := FrayedOutfit.get_outfit(outfit)
	outfit_info = data.info
	var parts: Dictionary = data.parts
	eye_mat = LowPoly.mat(eye_color, 2.6).duplicate()
	eye_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Augen-Dreiecke kommen aus dem Export umgekehrt gewickelt
	_overrides = {"Skin": skin_material(), "Eye": eye_mat}
	if ghost:
		# Augen zeichnet der Hollow One selbst (schwarze Kreise mit weißem Rand)
		var hidden := StandardMaterial3D.new()
		hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hidden.albedo_color = Color(0, 0, 0, 0)
		_overrides["Eye"] = hidden
	var body_hem: Array = FrayedOutfit.hem_chain(outfit_info, hem_layers, false, 1.3, hem_heat, hem_hot)
	var head_hem: Array = FrayedOutfit.hem_chain(outfit_info, head_layers, true, 1.3, hem_heat, hem_hot)
	_hem_mats.assign(body_hem[1] + head_hem[1])
	weapon_length = outfit_info.get("weaponLength", weapon_length)
	var grips: Array = outfit_info.get("gripHands", ["R"])
	_grip_l = grips.has("L")

	rig = Node3D.new()
	rig.name = "Rig"
	rig.position.y = RIG_Y
	add_child(rig)
	hips = _joint(rig, Vector3(0, HIPS_Y, 0))
	hip_l = _joint(hips, Vector3(-0.085, 0, 0))
	knee_l = _joint(hip_l, Vector3(0, -THIGH, 0))
	hip_r = _joint(hips, Vector3(0.085, 0, 0))
	knee_r = _joint(hip_r, Vector3(0, -THIGH, 0))
	chest = _joint(hips, Vector3(0, CHEST_Y, 0))
	head = _joint(chest, Vector3(0, HEAD_Y, 0))
	arm_up_l = _joint(self, Vector3.ZERO)
	arm_lo_l = _joint(self, Vector3.ZERO)
	arm_up_r = _joint(self, Vector3.ZERO)
	arm_lo_r = _joint(self, Vector3.ZERO)
	var joints := {"hips": hips, "chest": chest, "head": head, "hip_l": hip_l, "knee_l": knee_l, "hip_r": hip_r, "knee_r": knee_r,
		"arm_up_l": arm_up_l, "arm_lo_l": arm_lo_l, "arm_up_r": arm_up_r, "arm_lo_r": arm_lo_r}
	for jn in joints:
		if ghost and jn in LEG_JOINTS:
			continue
		var parent: Node3D = joints[jn]
		# Hand, die etwas greift: Unterarm etwas länger, damit die Faust am Griff sitzt
		var grip_scale := Vector3.ONE
		if (jn == "arm_lo_r" and grips.has("R")) or (jn == "arm_lo_l" and grips.has("L")):
			grip_scale = Vector3(1, 1.1, 1)
		var sn: String = "S_" + jn
		if parts.has(sn):
			var mi := _part(parts, sn, parent)
			mi.scale = grip_scale
			if ghost:
				_ghostify(mi)
			elif data.has_hem.get(sn, false):
				var hm := MeshInstance3D.new()
				hm.name = "Hem"
				hm.mesh = parts[sn]
				hm.material_override = body_hem[0]
				hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				hm.scale = grip_scale
				parent.add_child(hm)
		if parts.has("G_" + jn):
			var g := _part(parts, "G_" + jn, parent)
			g.scale = grip_scale
			if willfault:
				# Reste der alten Ausrüstung: manches fehlt, der Rest ist stumpf und dunkel
				if jn in ["arm_up_l", "arm_lo_l", "hip_r"] and _rng.randf() < 0.6:
					g.visible = false
				g.material_overlay = _dim_mat()
			elif ghost:
				# alte Ausrüstung: manches ist verloren, der Rest verschmutzt und angerostet
				if jn in ["arm_up_l", "arm_lo_l"] and _rng.randf() < 0.5:
					g.visible = false
				wear(g, _rng.randf() * 10.0)
		if willfault and jn in ["arm_lo_l", "arm_lo_r", "knee_l", "knee_r"]:
			# Lücke am Gelenk: Teile sitzen ein Stück versetzt
			for c in parent.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).position.y -= 0.035
	if parts.has("HeadHem") and not ghost:
		var hh := MeshInstance3D.new()
		hh.name = "HeadHem"
		hh.mesh = parts["HeadHem"]
		hh.material_override = head_hem[0]
		hh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(hh)
	head_light = OmniLight3D.new()
	head_light.light_color = Color(0.9, 0.9, 1.0) if ghost else Color.html(hem_hot if hem_hot != "" else outfit_info.get("hot", "#ff5464"))
	head_light.light_energy = 0.45
	head_light.omni_range = 1.4
	head_light.position = Vector3(0, 0.2, 0.05)
	head.add_child(head_light)

	sword = _joint(chest, Vector3.ZERO)
	_culture_weapon = _part(parts, "Weapon", sword)
	_culture_len = weapon_length
	if has_shield and parts.has("Shield"):
		shield = _joint(chest, Vector3.ZERO)
		_part(parts, "Shield", shield).position.z = -0.05
	else:
		has_shield = false
	if parts.has("Offhand") and not willfault:
		offhand = _joint(chest, OFFHAND_HOLD)
		var oh := _part(parts, "Offhand", offhand)
		if ghost:
			wear(oh, 5.0)
		if has_lantern and outfit_info.has("offhandLantern"):
			var ol: Dictionary = outfit_info.offhandLantern
			var hook := _joint(offhand, Vector3(ol.pos[0], ol.pos[1], ol.pos[2]))
			lantern = _joint(hook, Vector3.ZERO)
			var lm := _part(parts, "OffhandLantern", lantern)
			_lantern_core = MeshInstance3D.new()
			_lantern_core.position = Vector3(ol.light[0], ol.light[1], ol.light[2])
			lantern.add_child(_lantern_core)
			lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lm.layers = LANTERN_LAYER
			_lantern_offset = Vector3(0.0, 0.1, 0.0)
			_light_kind = &"pole"
			_add_lantern_light()

	_trail = SwordTrail.new()
	add_child(_trail)
	if has_lantern and lantern == null:
		_build_lantern()
	if not willfault:
		_build_scabbard()
	# Grundzustand: alles in der Hand (Gegner); der Spieler steckt per set_equipment() weg
	if has_shield:
		off_item = &"shield"
		off_p = 2.0
	elif _light_kind == &"pole":
		off_item = &"light"
		off_p = 2.0
		want_off = &"light"
	else:
		want_off = &""
	if willfault:
		_build_shards()
		return
	cloth = FrayedCloth.new()
	cloth.legs = not ghost
	cloth.torn = ghost
	cloth.setup(self, outfit_info, parts, joints)


## Waffe tauschen (Spieler). null oder Kulturwaffe = Modell aus dem Outfit.
func set_weapon(w: WeaponDef) -> void:
	weapon_def = w
	if _custom_weapon:
		_custom_weapon.queue_free()
		_custom_weapon = null
	var culture := w == null or w.culture
	_culture_weapon.visible = culture
	weapon_length = _culture_len if culture else w.length
	if not culture:
		_custom_weapon = Node3D.new()
		_custom_weapon.name = "CustomWeapon"
		sword.add_child(_custom_weapon)
		WeaponDef.build_mesh(w.id, _custom_weapon)
	# Zweithand-Dolch gibt es für den Spieler immer (liegt hinten am Gürtel)
	if off_dagger == null and not willfault:
		off_dagger = _joint(chest, Vector3.ZERO)
		off_dagger.name = "OffDagger"
		WeaponDef.build_mesh(&"off_dagger", off_dagger)
		has_off_dagger = true
	var old := hips.get_node_or_null("Scabbard")
	if old:
		old.free()
	var old2 := hips.get_node_or_null("DaggerSheath")
	if old2:
		old2.free()
	if not willfault:
		_build_scabbard()


## Weltposition einer Hand (links/rechts) – z. B. Ursprung der Schattenranke.
func hand_position(left: bool) -> Vector3:
	var lo := arm_lo_l if left else arm_lo_r
	return lo.global_transform * Vector3(0, -LOWER_ARM, 0)


## Sofort umrüsten (ohne Animation): Waffe gezogen?, linke Hand: &"shield", &"light" oder &"".
func set_equipment(weapon: bool, off: StringName) -> void:
	want_weapon = weapon
	weapon_p = 2.0 if weapon else 0.0
	want_off = off
	if off == &"shield" and not has_shield:
		off = &""
	if off == &"light" and _light_kind == &"":
		off = &""
	if off == &"dagger" and not has_off_dagger:
		off = &""
	off_item = off
	off_p = 2.0 if off != &"" else 0.0


func has_light_item() -> bool:
	return _light_kind != &""


## Waffe vollständig in der Hand?
func weapon_ready() -> bool:
	return weapon_p >= 2.0


## Schild vollständig am Arm?
func shield_ready() -> bool:
	return off_item == &"shield" and off_p >= 2.0


## Licht vorgehalten (ganz oder auf dem Weg)?
func light_held() -> bool:
	return off_item == &"light" and off_p > 1.0


## Scheide an der linken Hüfte (Säbel und Klinge); die Axt hängt in einer Gürtelschlaufe.
func _build_scabbard() -> void:
	var leather := LowPoly.mat(Color(0.075, 0.055, 0.045))
	var fitting := LowPoly.mat(Color(0.32, 0.24, 0.12), 0.0, 0.5)
	if has_off_dagger:
		var ds := _joint(hips, Vector3.ZERO)
		ds.name = "DaggerSheath"
		ds.transform = _off_dagger_stow_xf()
		LowPoly.mesh_instance(LowPoly.box(Vector3(0.05, 0.026, 0.3)), leather, ds, Vector3(0, 0, -0.2))
	var holder := _joint(hips, Vector3.ZERO)
	holder.name = "Scabbard"
	if weapon_def and weapon_def.stow == &"back":
		# Stangenwaffe auf dem Rücken: nur ein Riemen quer über den Rumpf
		holder.transform = Transform3D.IDENTITY
		var strap := LowPoly.mesh_instance(LowPoly.box(Vector3(0.035, 0.62, 0.02)), leather, chest, Vector3(0.0, 0.2, 0.0))
		strap.name = "BackStrap"
		strap.rotation.z = -0.55 if weapon_def.id == &"spear" else 0.55
		strap.position.z = 0.23
		strap.reparent(holder)
		return
	holder.transform = _sword_stow_xf()
	if outfit == "rimefall" and (weapon_def == null or weapon_def.culture):
		LowPoly.mesh_instance(LowPoly.box(Vector3(0.07, 0.05, 0.05)), leather, holder, Vector3(0, 0, -0.1))
		return
	var length := weapon_length - 0.1
	var sc := LowPoly.mesh_instance(LowPoly.box(Vector3(0.075, 0.034, length)), leather, holder, Vector3(0, 0, -0.13 - length * 0.5))
	sc.name = "Sheath"
	LowPoly.mesh_instance(LowPoly.box(Vector3(0.085, 0.044, 0.05)), fitting, holder, Vector3(0, 0, -0.14))
	LowPoly.mesh_instance(LowPoly.box(Vector3(0.08, 0.04, 0.06)), fitting, holder, Vector3(0, 0, -0.1 - length))
	# Riemen zum Gürtel
	LowPoly.mesh_instance(LowPoly.box(Vector3(0.03, 0.09, 0.03)), leather, holder, Vector3(0.03, 0.05, -0.2))


## Lage der weggesteckten Waffe (Hüft-Koordinaten): Griff vorn an der linken Hüfte, Klinge nach hinten unten.
func _sword_stow_xf() -> Transform3D:
	var st: Dictionary = PoseLibrary.weapon(pose_id()).stow
	var xf := Transform3D(_basis_from(-(st.dir as Vector3), st.hint), st.pos)
	if st.get("space", "hips") == "chest":
		return chest.transform * xf
	return xf


## Haltungen dieser Figur in der PoseLibrary: Kulturwaffe = Kultur (kiln/rimefall/glowmire), sonst die Waffe.
func pose_id() -> String:
	if weapon_def and not weapon_def.culture:
		return String(weapon_def.id)
	return outfit if outfit != "" else "kiln"


## Wo die linke Hand beidhändig greift (m hinter der rechten Hand).
func two_hand_offset() -> float:
	return float(PoseLibrary.weapon(pose_id()).get("two_hand_offset", 0.0))


static func _blend_held(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	if k <= 0.0:
		return a
	var out := {}
	for key in a:
		out[key] = (a[key] as Vector3).lerp(b.get(key, a[key]), k)
	return out


## Zweithand-Dolch weggesteckt: quer hinten am Gürtel (Hüft-Koordinaten, aus PoseLibrary "gear").
func _off_dagger_stow_xf() -> Transform3D:
	var g: Dictionary = PoseLibrary.gear().dagger_stow
	return Transform3D(_basis_from(-(g.dir as Vector3), g.hint), g.pos)


## Geisterschleier: unsichtbarer Tiefen-Durchgang am Teil selbst, Farbe als Kind darüber
func _ghostify(mi: MeshInstance3D) -> void:
	mi.material_override = ghost_material(false, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var veil := MeshInstance3D.new()
	veil.name = "Veil"
	veil.mesh = mi.mesh
	veil.material_override = ghost_material(false, false)
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(veil)
	_meshes.append(veil)


static var _ghost_mats: Dictionary = {}


## Geistermaterial (geteilt): depth = Tiefen-Durchgang, tail = Schweif mit Schwingen
static func ghost_material(tail: bool, depth: bool) -> ShaderMaterial:
	var key := "%s_%s" % [tail, depth]
	if not _ghost_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = GHOST_DEPTH_SHADER if depth else GHOST_SHADER
		m.set_shader_parameter("tail", tail)
		m.render_priority = -1 if depth else 0
		_ghost_mats[key] = m
	return _ghost_mats[key]


## Ausrüstung verbraucht darstellen: jedes Material wird durch eine verblasste, verschmutzte Fassung ersetzt
static func wear(mi: MeshInstance3D, seed_value: float) -> void:
	var mesh := mi.mesh
	for i in mesh.get_surface_count():
		var src := mi.get_surface_override_material(i)
		if src == null:
			src = mesh.surface_get_material(i)
		if src is StandardMaterial3D:
			mi.set_surface_override_material(i, worn_material(src as StandardMaterial3D, seed_value))


static func worn_material(src: StandardMaterial3D, seed_value: float) -> Material:
	if src.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src
	var m := ShaderMaterial.new()
	m.shader = WORN_SHADER
	m.set_shader_parameter("albedo", src.albedo_color)
	m.set_shader_parameter("has_tex", src.albedo_texture != null)
	if src.albedo_texture:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("metallic", src.metallic)
	m.set_shader_parameter("seed", seed_value)
	return m


func _dim_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.0, 0.0, 0.01, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Schwebende Schattensplitter um Rumpf und Kopf, glimmen am Rand im Willfault-Violett.
func _build_shards() -> void:
	var black := skin_material()
	var edge := shard_mat if shard_mat else LowPoly.mat(eye_color, 2.0)
	for i in 7:
		var piv := _joint(chest if i < 5 else head, Vector3.ZERO)
		var sh := Node3D.new()
		piv.add_child(sh)
		var h := _rng.randf_range(0.07, 0.15)
		var m := LowPoly.mesh_instance(LowPoly.crystal(h, h * 0.28), black, sh)
		var tip := LowPoly.mesh_instance(LowPoly.crystal(h * 0.35, h * 0.1), edge, sh, Vector3(0, h * 0.75, 0))
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_meshes.append(m)
		sh.set_meta("r", _rng.randf_range(0.26, 0.36) if i < 5 else _rng.randf_range(0.2, 0.26))
		sh.set_meta("y", _rng.randf_range(0.15, 0.5) if i < 5 else _rng.randf_range(0.0, 0.18))
		sh.set_meta("a", _rng.randf() * TAU)
		sh.set_meta("w", _rng.randf_range(0.5, 1.2) * (1.0 if _rng.randf() < 0.5 else -1.0))
		sh.rotation = Vector3(_rng.randf_range(-1, 1), _rng.randf() * TAU, _rng.randf_range(-1, 1))
		_shards.append(sh)


func _update_willfault(delta: float) -> void:
	for sh in _shards:
		var a: float = sh.get_meta("a") + delta * float(sh.get_meta("w"))
		sh.set_meta("a", a)
		var r: float = sh.get_meta("r")
		sh.position = Vector3(cos(a) * r, float(sh.get_meta("y")) + sin(_time * 1.7 + a) * 0.03, sin(a) * r)
		sh.rotate_y(delta * 1.3)
	# Zucken: kurze, ruckartige Verdrehungen von Kopf und Rumpf
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		_twitch_t = _rng.randf_range(0.6, 2.2)
		_twitch = Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.3, 0.3))
	_twitch = _twitch.lerp(Vector3.ZERO, 1.0 - exp(-7.0 * delta))
	head.rotation += _twitch
	chest.rotation.z += _twitch.z * 0.3


## Kleine Käfiglaterne mit leuchtendem Kristallsplitter, an einem kurzen Riemen.
func _build_lantern() -> void:
	var metal := LowPoly.mat(Color(0.09, 0.08, 0.07), 0.0, 0.6)
	var strap := LowPoly.mat(Color(0.07, 0.07, 0.07))
	var hook := _joint(self, Vector3.ZERO)  # Lage setzt tick(): Gürtel rechts oder linke Hand
	_lantern_hook = hook
	_light_kind = &"belt"
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

	_add_lantern_light()


func _add_lantern_light() -> void:
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
	var out := global_basis * Vector3(_lantern_offset.x, 0.0, _lantern_offset.z) + Vector3.UP * _lantern_offset.y
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
	if _flash_t <= 0.0:
		_saved_overlays.clear()
		for m in _meshes:
			_saved_overlays.append(m.material_overlay)
			m.material_overlay = _flash_mat
	_flash_t = duration


func set_eye_intensity(v: float) -> void:
	eye_mat.emission_energy_multiplier = v


func sword_points() -> Array[Vector3]:
	var base := sword.global_transform * Vector3(0, 0, -maxf(0.12, weapon_length - 0.6))
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
	_sp_off = Spring.new(3.0, 0.8, 1.0, OFFHAND_HOLD)
	_sp_off_up = Spring.new(2.5, 0.6, 1.0, Vector3(0.0, 1.0, -0.08))
	_sp_hz = Spring.new(2.5, 0.9, 1.0, 0.0)
	_sp_rest_r = Spring.new(3.2, 0.8, 1.0, Vector3(0.25, -0.14, -0.03))
	_sp_rest_l = Spring.new(3.2, 0.8, 1.0, Vector3(-0.25, -0.14, -0.03))
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
			for i in _meshes.size():
				_meshes[i].material_overlay = _saved_overlays[i] if i < _saved_overlays.size() else null

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

	_update_draw(delta)
	var s := clampf(speed / run_speed_ref, 0.0, 1.6)
	# stufenloser Übergang Stand <-> Laufen <-> Luft
	var w_move: float = clampf(_u(_sp_moving, delta, 1.0 if (s > 0.04 and on_floor) else 0.0), 0.0, 1.2)
	var w_air: float = clampf(_u(_sp_air, delta, 0.0 if on_floor else 1.0), 0.0, 1.0)

	# --- Schrittzyklus: Schrittlänge wächst mit Tempo, Beinausschlag passt zur Schrittlänge (kein Gleiten) ---
	var backwards := local_move.y < -0.1
	var dir_sign := -1.0 if backwards else 1.0
	var stride := lerpf(1.25, 2.5, clampf(s, 0.0, 1.0)) + 1.0 * sprint  # Meter pro Doppelschritt: wenige, lange Schritte
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
	# Kampfhaltung nur mit gezogener Waffe (sonst hängen die Arme natürlich)
	var cw: float = clampf(_u(_sp_combat, delta, combat * clampf(weapon_p - 1.0, 0.0, 1.0) * (1.0 - sprint)), 0.0, 1.0)
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
	var lean := -0.06 - 0.1 * cw - 0.16 * minf(s, 1.0) * wm - 0.14 * sprint * wm - clampf(accel * 0.012, -0.25, 0.25) - 0.08 * w_air
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
	var roll_basis := Basis.IDENTITY
	var hips_z := 0.0
	# Handziele (Körper-Koordinaten) für Klettern/Hochziehen/Schwimmen; Gewicht 0 = normale Arme
	var hand_ovr := 0.0
	var hand_l_local := Vector3.ZERO
	var hand_r_local := Vector3.ZERO
	# Hände ohne Waffe während der Rolle (Brust-Koordinaten), sonst null
	var free_hands: Variant = null

	# --- Waffe / Schild Grundposen (aus PoseLibrary, bearbeitbar in der Animationswerkstatt) ---
	var pw := PoseLibrary.weapon(pose_id())
	var k2 := _two_w * _two_w * (3.0 - 2.0 * _two_w)
	var ip := _blend_held(pw.idle, pw.idle_2h, k2)
	var wpz := _blend_held(pw.walk, pw.idle_2h, k2)
	var gp := _blend_held(pw.guard, pw.guard_2h, k2)
	var mv := minf(s, 1.0) * wm
	# Waffe gezogen, ohne Kampfhaltung: Haltung im Stehen bzw. beim Gehen
	var grip := _unscale(ip.grip).lerp(_unscale(wpz.grip), mv)
	var sdir: Vector3 = (ip.dir as Vector3).lerp(wpz.dir, mv)
	var sflat: Vector3 = (ip.flat as Vector3).lerp(wpz.flat, mv)
	grip.z += sin(_phase) * 0.07 * mv
	grip.y += breathe * 0.006 * (1.0 - wm)
	var sh_pos := _unscale(ip.off).lerp(_unscale(wpz.off), mv)
	var sh_front: Vector3 = (ip.off_front as Vector3).lerp(wpz.off_front, mv)
	sh_pos.z += sin(_phase + PI) * 0.05 * mv
	# Kampfhaltung: Schild vor der Brust, Klinge schräg nach vorn oben gerichtet
	if cw > 0.0:
		var bob_g := Vector3(0, sin(_phase * 2.0) * 0.015 * wm + breathe * 0.008, 0)
		grip = grip.lerp(_unscale(gp.grip) + bob_g, cw)
		sdir = sdir.lerp(gp.dir, cw)
		sflat = sflat.lerp(gp.flat, cw)
		sh_pos = sh_pos.lerp(_unscale(gp.off) + bob_g, cw)
		sh_front = sh_front.lerp(gp.off_front, cw)
	var hand_f := 3.0  # Federfrequenz der Hände (niedrig = träge, schwer)

	match action:
		&"swing":
			if swing_serial != _serial_seen:
				_serial_seen = swing_serial
				var chained := _last_action == &"swing" and swing_sample.size() >= 10
				_swing_from = swing_sample.duplicate(true) if chained else []
				_swing_from_t = action_t if chained else 0.0
			var k := _swing_pose(swing_index, action_t, [grip, sdir, sflat, sh_pos, sh_front])
			_body_ofs = k[9]
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
			# Ablauf: Abtauchen (Gewicht in die Rollrichtung), enge Drehung über die Schulter,
			# Landen in der Hocke, Aufrichten mit Schwung. Vorwärts, rückwärts und seitlich sehen verschieden aus.
			var t := action_t
			var back := roll_kind == &"back"
			var side := -1.0 if roll_kind == &"left" else (1.0 if roll_kind == &"right" else 0.0)
			var dive := smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.08, 0.26, t))
			var u := clampf((t - 0.07) / (ROLL_SPIN - 0.07), 0.0, 1.0)
			var e := _ease_spin(u)
			var tuck := sin(u * PI)
			var kneel := smoothstep(ROLL_SPIN - 0.14, ROLL_SPIN, t) * (1.0 - smoothstep(ROLL_SPIN + 0.04, 1.0, t))
			rig_direct = true
			pivot = ROLL_PIVOT
			ground_glue = true  # Höhe ergibt sich aus Bodenkontakt (siehe unten)
			rig_scale = 1.0 - 0.18 * tuck  # zusammenrollen -> kein Eintauchen in den Boden
			var ang := TAU * e
			if back:
				# Rückwärtsrolle: erst nach hinten absetzen, dann über die linke Schulter
				roll_basis = Basis(Vector3(1.0, 0.0, -0.3).normalized(), ang)
				hips_drop = 0.22 * dive
				lean = lerpf(lean, 0.35, dive)
				kl = lerpf(kl, -1.7, dive)
				kr = lerpf(kr, -1.5, dive)
				hl.x = lerpf(hl.x, 0.9, dive)
				hr.x = lerpf(hr.x, 0.7, dive)
			elif side != 0.0:
				# Seitenrolle: in die Richtung eindrehen, über die äußere Schulter rollen, zurückdrehen
				var turn := sin(clampf(t / (ROLL_SPIN + 0.12), 0.0, 1.0) * PI)
				roll_basis = Basis(Vector3.UP, -side * 1.15 * turn) * Basis(Vector3(1.0, 0.0, 0.4 * side).normalized(), -ang)
				bank += side * 0.5 * dive
				hips_drop = 0.12 * dive
				kl = lerpf(kl, -1.0, dive)
				kr = lerpf(kr, -1.0, dive)
			else:
				# Vorwärtsrolle über die rechte Schulter, Kopf zur linken Seite weg
				roll_basis = Basis(Vector3(1.0, 0.0, 0.35).normalized(), -ang)
				lean = lerpf(lean, -0.75, dive)
				hips_drop = 0.14 * dive
				kl = lerpf(kl, -1.0, dive)
				kr = lerpf(kr, -0.7, dive)
				twist = 0.35 * tuck
			lean = lerpf(lean, -1.05, tuck)
			head_tuck = 0.55 * tuck
			hl.x = lerpf(hl.x, 1.5, tuck)
			hr.x = lerpf(hr.x, 1.3, tuck)
			kl = lerpf(kl, -2.3, tuck)
			kr = lerpf(kr, -2.2, tuck)
			if kneel > 0.0:
				# Hocke nach der Drehung: vorwärts ein Bein vor, rückwärts beide Knie tief, seitlich breit
				hips_drop = 0.09 * kneel
				lean = lerpf(lean, -0.45 if back else -0.32, kneel)
				if back:
					hl.x = lerpf(hl.x, 0.95, kneel)
					hr.x = lerpf(hr.x, 0.55, kneel)
					kl = lerpf(kl, -1.75, kneel)
					kr = lerpf(kr, -1.55, kneel)
				else:
					hl.x = lerpf(hl.x, 1.0, kneel)
					hr.x = lerpf(hr.x, -0.3, kneel)
					kl = lerpf(kl, -1.6, kneel)
					kr = lerpf(kr, -1.4, kneel)
				if side != 0.0:
					hl.z = lerpf(hl.z, -0.25, kneel)
					hr.z = lerpf(hr.z, 0.25, kneel)
					bank += -side * 0.18 * kneel
			# Freie Hände: beim Abtauchen zum Boden, in der Drehung an die Brust, in der Hocke zur Balance raus
			var fl := Vector3(-0.17, 0.08, -0.22)
			var fr := Vector3(0.17, 0.08, -0.22)
			var reach := Vector3(0.0, -0.32, -0.36) if not back else Vector3(0.0, -0.42, 0.12)
			fl = fl.lerp(Vector3(-0.2, 0.0, 0.0) + reach, dive)
			fr = fr.lerp(Vector3(0.2, 0.0, 0.0) + reach, dive)
			fl = fl.lerp(Vector3(-0.42, 0.02, -0.22), kneel)
			fr = fr.lerp(Vector3(0.36, -0.12, -0.3), kneel)
			free_hands = [fl, fr]
			# Klinge zeigt zur Seite (parallel zur Drehachse) -> sticht nie in den Boden
			var wb := clampf(t * 12.0, 0.0, 1.0) * (1.0 - smoothstep(0.82, 1.0, t))
			grip = grip.lerp(Vector3(0.3, 0.02, -0.08), wb)
			sdir = sdir.lerp(Vector3(1.0, -0.05, 0.12), wb)
			sflat = Vector3(0, 1, 0)
			sh_pos = sh_pos.lerp(Vector3(-0.3, 0.06, -0.04), wb)
			sh_front = sh_front.lerp(Vector3(-1.0, 0.0, -0.1), wb)
			hand_f = 7.0  # Waffe schnell anlegen, sonst sticht sie beim Abtauchen in den Boden
		&"climb":
			# An der Wand: Hände greifen abwechselnd nach oben, Füße steigen gegengleich
			var m := clampf(climb_move.length(), 0.0, 1.0)
			var la := sin(climb_phase) * m
			var lb := absf(cos(climb_phase)) * m
			hips_z = -0.1
			lean = -0.14
			bank = 0.0
			hips_drop = 0.04
			hl = Vector3(0.75 + 0.42 * la, 0.0, -0.14)
			hr = Vector3(0.75 - 0.42 * la, 0.0, 0.14)
			kl = -0.55 - 1.05 * hl.x
			kr = -0.55 - 1.05 * hr.x
			var sx := climb_move.x * 0.07
			hand_ovr = 1.0
			hand_l_local = Vector3(-0.24 + sx, 1.56 - 0.17 * la - 0.05 * lb, -0.37)
			hand_r_local = Vector3(0.24 + sx, 1.56 + 0.17 * la - 0.05 * lb, -0.37)
			head_tuck = -0.3
			hand_f = 6.0
		&"ledge_up":
			# Hochziehen an einer Kante: greifen, hochdrücken, Knie auf die Kante, aufstehen
			var t := action_t
			var lp: Vector3 = global_transform.affine_inverse() * ledge_world
			var release := smoothstep(0.55, 0.82, t)
			hand_ovr = 1.0 - release
			hand_l_local = lp + Vector3(-0.23, 0.03, -0.07)
			hand_r_local = lp + Vector3(0.23, 0.03, -0.07)
			var push := smoothstep(0.1, 0.45, t) * (1.0 - smoothstep(0.7, 1.0, t))
			var knee_up := smoothstep(0.35, 0.55, t) * (1.0 - smoothstep(0.72, 0.95, t))
			hips_z = -0.12 * (1.0 - release)
			lean = lerpf(lean, -0.55, push)
			hips_drop = 0.1 * knee_up
			hl.x = lerpf(lerpf(hl.x, 0.25, 1.0 - release), 0.5, knee_up)
			kl = lerpf(lerpf(kl, -0.35, 1.0 - release), -1.2, knee_up)
			hr.x = lerpf(lerpf(hr.x, 0.1, 1.0 - release), 1.55, knee_up)
			kr = lerpf(lerpf(kr, -0.25, 1.0 - release), -2.3, knee_up)
			head_tuck = -0.2 * (1.0 - push)
			hand_f = 6.0
		&"swim", &"water_enter":
			# Brustschwimmen; im Stand Wassertreten. Kein Tauchen: Kopf und Schultern bleiben über Wasser.
			var m := clampf(swim_amount, 0.0, 1.0)
			var u := fposmod(swim_phase / TAU, 1.0)
			rig_x = -0.8 * m - 0.1 * (1.0 - m)
			pivot = 1.0
			lean = -0.05
			bank = 0.0
			head_tuck = -0.95 * m - 0.1
			# Arme: Gleiten -> nach außen ziehen -> unter die Brust -> nach vorn strecken
			var stroke := _swim_arm(u)
			var tread := Vector3(0.34, 0.06 + 0.04 * sin(swim_phase), -0.22 + 0.1 * cos(swim_phase))
			var ar := tread.lerp(stroke, m)
			var al := Vector3(-ar.x, ar.y, ar.z)
			if m < 1.0:
				al = Vector3(-0.34, 0.06 + 0.04 * sin(swim_phase + PI), -0.22 + 0.1 * cos(swim_phase + PI)).lerp(al, m)
			# Beine: Froschbeinschlag beim Schwimmen, Radfahren beim Wassertreten
			var bend := smoothstep(0.35, 0.62, u) * (1.0 - smoothstep(0.72, 0.9, u))
			var fl_x := 0.1 + 0.75 * bend
			var fk := -0.15 - 1.75 * bend
			var spread := 0.08 + 0.3 * bend
			hl = Vector3(lerpf(0.45 + 0.35 * sin(swim_phase), fl_x, m), 0.0, lerpf(-0.06, -spread, m))
			hr = Vector3(lerpf(0.45 - 0.35 * sin(swim_phase), fl_x, m), 0.0, lerpf(0.06, spread, m))
			kl = lerpf(-0.9 - 0.45 * cos(swim_phase), fk, m)
			kr = lerpf(-0.9 + 0.45 * cos(swim_phase), fk, m)
			if action == &"water_enter":
				# Eintauchen: Arme hoch, Beine geschlossen, dann Arme zur Seite ausbreiten und auftreiben
				var t := action_t
				var up := 1.0 - smoothstep(0.25, 0.6, t)
				var out := smoothstep(0.25, 0.55, t) * (1.0 - smoothstep(0.7, 1.0, t))
				var fade := 1.0 - smoothstep(0.7, 1.0, t)
				ar = ar.lerp(Vector3(0.12, 0.95, -0.08), up).lerp(Vector3(0.55, 0.35, -0.12), out)
				al = al.lerp(Vector3(-0.12, 0.95, -0.08), up).lerp(Vector3(-0.55, 0.35, -0.12), out)
				hl = hl.lerp(Vector3(0.12, 0.0, -0.03), fade)
				hr = hr.lerp(Vector3(-0.05, 0.0, 0.03), fade)
				kl = lerpf(kl, -0.2, fade)
				kr = lerpf(kr, -0.25, fade)
				rig_x = lerpf(rig_x, 0.0, fade)
			free_hands = [al, ar]
			hand_f = 5.0
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
		&"knockdown":
			# nach hinten umgeworfen: fallen (schnell), liegen, über die Knie aufstehen
			var fall := clampf(action_t / 0.16, 0.0, 1.0)
			var up := clampf((action_t - knockdown_getup) / (1.0 - knockdown_getup), 0.0, 1.0)
			var w := (1.0 - pow(1.0 - fall, 3.0)) * (1.0 - smoothstep(0.0, 0.75, up))
			rig_x = 1.45 * w
			rig_direct = true
			rig_y = RIG_Y - 0.3 * w - 0.25 * sin(up * PI)
			var crouch := sin(clampf(up * 1.15, 0.0, 1.0) * PI)
			lean -= 0.5 * crouch
			hips_drop = 0.22 * crouch
			kl = -0.6 * w - 1.1 * crouch
			kr = -0.3 * w - 0.8 * crouch
			grip = Vector3(0.45, -0.3 + 0.2 * crouch, 0.1)
			sh_pos = Vector3(-0.4, -0.3 + 0.15 * crouch, 0.0)
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
		_body_ofs = []
	# Körper-Zusätze aus dem Clip (Werkstatt: Neigung, Hüfte, Kopf, Beine, Ellbogen)
	var bo: Array = _body_ofs
	if bo.size() == AnimLibrary.BODY_FIELDS.size():
		bank += bo[0]
		hips_z += bo[4]
		hl += Vector3(bo[5], 0.0, -bo[6])
		kl -= bo[7]
		hr += Vector3(bo[8], 0.0, bo[9])
		kr -= bo[10]
		# ganze Figur kippen/absenken (Tod u. ä.): direkt gesteuert, solange der Clip es verlangt
		if absf(bo[13]) > 0.0005 or absf(bo[14]) > 0.0005:
			rig_x = bo[13]
			rig_y = RIG_Y - bo[14]
			rig_direct = true

	if block_amount > 0.0 and has_shield and off_item == &"shield" and off_p >= 1.5:
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
	elif block_amount > 0.0 and action != &"swing" and weapon_p >= 1.5:
		# ohne Schild: Klinge quer vor den Körper, Laternenstab zurück
		var b := block_amount * block_amount * (3.0 - 2.0 * block_amount)
		grip = grip.lerp(Vector3(0.24, 0.12, -0.36), b)
		sdir = sdir.lerp(Vector3(-1.0, 0.3, -0.25), b)
		sflat = sflat.lerp(Vector3(0, 0.3, -1.0), b)
		sh_pos = sh_pos.lerp(Vector3(-0.32, -0.1, -0.08), b)
		lean -= 0.1 * b
		hips_drop += 0.06 * b
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
	var rb := (roll_basis * Basis.from_euler(Vector3(rx, 0.0, bk))).scaled(Vector3.ONE * rig_scale)
	rig.transform = Transform3D(rb, Vector3(0, ry - RIG_Y + pv, 0) + rb * Vector3(0, RIG_Y - pv, 0))
	hips.position.y = HIPS_Y + hips_y - dr
	hips.position.z = _u(_sp_hz, delta, hips_z)
	if bo.size() == AnimLibrary.BODY_FIELDS.size():
		lower_yaw += bo[1]
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
	if bo.size() == AnimLibrary.BODY_FIELDS.size():
		head.rotation += Vector3(bo[3], bo[2], 0.0)

	# Bodenkontakt: während der Rolle liegt der tiefste Körperpunkt genau auf dem Boden
	# (kein Eintauchen, kein Schweben). Danach klingt der Versatz weich aus.
	if ground_glue:
		_glue = -_lowest_body_point()
	else:
		_glue *= exp(-10.0 * delta)
	if absf(_glue) > 0.0005 or ground_glue:
		rig.position.y += _glue

	# --- Ausrüstung platzieren: in der Hand, auf dem Weg oder an Gürtel/Rücken ---
	var cb := chest.global_basis
	var chest_xf := chest.global_transform
	var to_chest := chest.transform.affine_inverse()  # Hüft- -> Brust-Koordinaten
	# natürliche Arme (Brust-Koordinaten): hängen locker, schwingen gegengleich zu den Beinen, beim Sprint angewinkelt
	var sw := sin(_phase) * (0.11 + 0.1 * sprint) * minf(s, 1.0) * wm
	var rest_r := Vector3(0.25 + 0.03 * sprint, -0.14 + 0.16 * sprint + absf(sw) * 0.35, -0.03 - sw - 0.08 * sprint)
	var rest_l := Vector3(-0.25 - 0.03 * sprint, -0.14 + 0.16 * sprint + absf(sw) * 0.35, -0.03 + sw - 0.08 * sprint)
	rest_r.y += breathe * 0.006 * (1.0 - wm)
	rest_l.y += breathe * 0.006 * (1.0 - wm)
	# in der Luft: Arme etwas raus zur Balance
	rest_r = rest_r.lerp(Vector3(0.37, 0.02, -0.08), w_air * 0.8)
	rest_l = rest_l.lerp(Vector3(-0.37, 0.02, -0.08), w_air * 0.8)
	if free_hands != null:
		rest_l = free_hands[0]
		rest_r = free_hands[1]
	var rest_r_w: Vector3 = chest_xf * (_u(_sp_rest_r, delta, rest_r) as Vector3)
	var rest_l_w: Vector3 = chest_xf * (_u(_sp_rest_l, delta, rest_l) as Vector3)

	# Waffe (rechte Hand)
	var drawn_sword := Transform3D(_basis_from(-d.normalized(), f.normalized()), g)
	var stow_hips := _sword_stow_xf()
	var stow_sword: Transform3D = to_chest * stow_hips
	# Scheide/Schlaufe folgt der (bearbeitbaren) Ablage
	var scab := hips.get_node_or_null("Scabbard") as Node3D
	if scab and not (weapon_def and weapon_def.stow == &"back"):
		scab.transform = stow_hips
	var dsh := hips.get_node_or_null("DaggerSheath") as Node3D
	if dsh:
		dsh.transform = _off_dagger_stow_xf()
	var draw_ctrl := stow_sword.origin + stow_sword.basis.z * weapon_length * 0.9
	if weapon_def and weapon_def.stow == &"back":
		draw_ctrl = Vector3(0.32, 0.72, 0.12)  # über die rechte Schulter nach vorn ziehen
	sword.transform = _carry(stow_sword, drawn_sword, _out(weapon_p), draw_ctrl)
	var hand_r: Vector3 = rest_r_w.lerp(sword.global_transform * Vector3(0, 0, 0.02), _reach(weapon_p))

	# Schild: am Arm oder auf dem Rücken
	var hand_l: Vector3 = rest_l_w
	if has_shield:
		var held_sh := Transform3D(_basis_from(-sf.normalized(), Vector3.UP, true), sp)
		var gsb: Dictionary = PoseLibrary.gear().shield_back
		var back_sh := Transform3D(_basis_from(-(gsb.front as Vector3).normalized(), Vector3.UP, true), gsb.pos)
		var sp_t := off_p if off_item == &"shield" else 0.0
		shield.transform = _carry(back_sh, held_sh, _out(sp_t), Vector3(-0.42, 0.5, 0.08))
		if off_item == &"shield":
			hand_l = rest_l_w.lerp(shield.global_transform * Vector3(0, 0, 0.07), _reach(sp_t))
	# Licht: Gürtellaterne (rechte Hüfte) oder Laternenstab (Rücken); vorgehalten in der linken Hand
	var lp_t := off_p if off_item == &"light" else 0.0
	_light_out = _out(lp_t)
	if _light_kind == &"belt":
		var to_body := global_transform.affine_inverse()
		var gr: Dictionary = PoseLibrary.gear()
		var belt: Transform3D = to_body * hips.global_transform * Transform3D(Basis(Vector3.UP, float(gr.lantern_belt.yaw)), gr.lantern_belt.pos)
		var held_l: Transform3D = to_body * chest_xf * Transform3D(Basis.IDENTITY, (gr.lantern_held.pos as Vector3) + Vector3(0, sin(_phase * 2.0) * 0.01 * wm, 0))
		var ctrl: Vector3 = (to_body * chest_xf) * Vector3(0.05, 0.05, -0.3)
		_lantern_hook.transform = _carry(belt, held_l, _light_out, ctrl)
		if off_item == &"light":
			hand_l = rest_l_w.lerp(_lantern_hook.global_position + _lantern_hook.global_basis.y * 0.03, _reach(lp_t))
		_lantern_offset = Vector3(0.3, 0.2, 0.0).lerp(Vector3(0.0, 0.05, -0.12), _light_out)
	elif offhand:
		# Laternenstab: vor dem Körper gehalten, Stab fast senkrecht; Rolle/Stoß/Block nutzen die Schild-Pose
		var hold_t := OFFHAND_HOLD + Vector3(0, sin(_phase * 2.0) * 0.012 * wm, sin(_phase + PI) * 0.04 * minf(s, 1.0) * wm)
		if action in [&"roll", &"bash", &"stagger", &"knockdown", &"dead"] or block_amount > 0.05:
			hold_t = sp
		var hold: Vector3 = _u(_sp_off, delta, hold_t)
		var up_t := Vector3(0.0, 1.0, -0.08) if action != &"roll" else Vector3(-0.7, 0.5, 0.1)
		var pole_up: Vector3 = _u(_sp_off_up, delta, up_t)
		pole_up = pole_up.normalized()
		var pz := (Vector3(0, 0, 1) - pole_up * pole_up.z).normalized()
		var held_p := Transform3D(_basis_from(pz, pole_up, true), hold)
		var bu := Vector3(-0.55, 0.82, 0.12).normalized()
		var back_p := Transform3D(_basis_from((Vector3(0, 0, 1) - bu * bu.z).normalized(), bu, true), POLE_BACK)
		offhand.transform = _carry(back_p, held_p, _light_out, Vector3(-0.42, 0.45, 0.05))
		if off_item == &"light":
			hand_l = rest_l_w.lerp(offhand.global_position, _reach(lp_t))

	# Zweithand-Dolch: in der linken Hand (folgt der Schild-Pose), sonst hinten am Gürtel
	if off_dagger:
		var dp_t := off_p if off_item == &"dagger" else 0.0
		off_jab = move_toward(off_jab, 0.0, delta * 5.0)
		var jab := sin(clampf(1.0 - off_jab, 0.0, 1.0) * PI) if off_jab > 0.0 else 0.0
		var dpos := sp + Vector3(0.06, 0.02, -0.06) + Vector3(0.1, 0.05, -0.3) * jab
		var ddir := (sf + Vector3(0.25, 0.9, 0.0)).normalized().lerp(Vector3(0.15, 0.1, -1.0).normalized(), jab).normalized()
		var held_d := Transform3D(_basis_from(-ddir, Vector3(1, 0, 0)), dpos)
		var stow_d: Transform3D = to_chest * _off_dagger_stow_xf()
		off_dagger.transform = _carry(stow_d, held_d, _out(dp_t), Vector3(-0.35, -0.05, 0.25))
		if off_item == &"dagger":
			hand_l = rest_l_w.lerp(off_dagger.global_transform * Vector3(0, 0, 0.03), _reach(dp_t))
	# Beidhändig: linke Hand greift den Schaft hinter der rechten
	var two_t := 1.0 if two_hand and off_item == &"" and action != &"roll" and weapon_p >= 1.6 and weapon_def != null else 0.0
	_two_w = move_toward(_two_w, two_t, delta * 4.0)
	if _two_w > 0.0:
		var shaft_pt: Vector3 = sword.global_transform * Vector3(0, 0, two_hand_offset())
		var k := _two_w * _two_w * (3.0 - 2.0 * _two_w)
		hand_l = hand_l.lerp(shaft_pt, k)

	# Klettern/Hochziehen: Hände an Wand bzw. Kante
	if hand_ovr > 0.0:
		hand_l = hand_l.lerp(global_transform * hand_l_local, hand_ovr)
		hand_r = hand_r.lerp(global_transform * hand_r_local, hand_ovr)

	# --- Arm-IK ---
	# Ellbogen zeigt nach außen-hinten; greift die Hand quer vor den Körper, wandert er nach vorn
	var cross := clampf((0.12 - g.x) / 0.3, 0.0, 1.0)
	var pole_r := Vector3(0.7, -1.0, 0.6).lerp(Vector3(0.35, -0.8, -0.9), cross)
	var pole_l := Vector3(-0.8, -1.0, 0.4)
	var free_r := 1.0 - _reach(weapon_p)
	pole_r = pole_r.lerp(Vector3(0.35, -0.4, 1.0), free_r)  # freier Arm: Ellbogen nach hinten
	if off_item == &"" and _two_w < 0.5:
		pole_l = Vector3(-0.35, -0.4, 1.0)
	if hand_ovr > 0.0:
		pole_r = pole_r.lerp(Vector3(0.9, -1.0, 0.2), hand_ovr)
		pole_l = pole_l.lerp(Vector3(-0.9, -1.0, 0.2), hand_ovr)
	var pole_rw: Vector3 = cb * pole_r
	var pole_lw: Vector3 = cb * pole_l
	if bo.size() == AnimLibrary.BODY_FIELDS.size():
		# Ellbogen um die Achse Schulter -> Hand drehen (+ = nach außen/oben)
		var ax_r: Vector3 = hand_r - chest_xf * SHOULDER_R
		var ax_l: Vector3 = hand_l - chest_xf * SHOULDER_L
		if ax_r.length() > 0.05 and absf(bo[11]) > 0.001:
			pole_rw = pole_rw.rotated(ax_r.normalized(), -bo[11])
		if ax_l.length() > 0.05 and absf(bo[12]) > 0.001:
			pole_lw = pole_lw.rotated(ax_l.normalized(), bo[12])
	_solve_arm(arm_up_r, arm_lo_r, chest_xf * SHOULDER_R, hand_r, pole_rw)
	_solve_arm(arm_up_l, arm_lo_l, chest_xf * SHOULDER_L, hand_l, pole_lw)
	_update_lantern(delta, s, accel, yaw_rate)

	if _trail.emitting or _trail.has_points():
		var pts := sword_points()
		_trail.push(pts[0], pts[1], delta)
	if cloth:
		cloth.update(delta)
	if willfault:
		_update_willfault(delta)
	if head_light:
		head_light.light_energy = 0.45 * (1.0 + 0.35 * sin(_time * 11.3) * sin(_time * 7.1 + 1.0))
	_last_action = action


func _process(_delta: float) -> void:
	if _hem_mats.is_empty():
		return
	# Flammenmuster bewegt sich mit der Figur (interpolierte Lage, sonst ruckelt es bei hoher Bildrate)
	var o := get_global_transform_interpolated().origin if is_inside_tree() else global_position
	for m in _hem_mats:
		m.set_shader_parameter("origin", o)


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
	# Hände/Unterarme (Handstütze beim Abtauchen) und die weggesteckte Waffe samt Scheide
	for al: Node3D in [arm_lo_l, arm_lo_r]:
		pts.append(al.global_transform * Vector3(0, -LOWER_ARM, 0))
		pts.append(al.global_position)
	if weapon_p < 1.0:
		var sx: Transform3D = hips.global_transform * _sword_stow_xf()
		pts.append(sx * Vector3(0, 0, -weapon_length))
		pts.append(sx * Vector3(0, 0, 0.12))
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


## Dreh-Verlauf der Rolle (u = 0..1 innerhalb der Drehung): kräftig rein, weich raus.
func _ease_spin(u: float) -> float:
	return lerpf(u * u * (3.0 - 2.0 * u), 1.0 - pow(1.0 - u, 2.0), 0.5)


## Hand (rechts, Brust-Koordinaten) im Brustschwimm-Zyklus u = 0..1.
func _swim_arm(u: float) -> Vector3:
	var keys: Array[Vector3] = [Vector3(0.1, 0.92, -0.2), Vector3(0.45, 0.72, -0.28), Vector3(0.33, 0.42, -0.38), Vector3(0.1, 0.55, -0.32)]
	var ts: Array[float] = [0.0, 0.3, 0.52, 0.72, 1.0]
	var i := 0
	while i < 3 and u > ts[i + 1]:
		i += 1
	var w := (u - ts[i]) / (ts[i + 1] - ts[i])
	return _cr(keys[(i + 3) % 4], keys[i], keys[(i + 1) % 4], keys[(i + 2) % 4], w)


## Ziehen/Wegstecken voranbringen. Die linke Hand steckt erst das alte Teil weg, bevor sie das neue greift.
func _update_draw(delta: float) -> void:
	weapon_p = move_toward(weapon_p, 2.0 if want_weapon else 0.0, delta * 2.0 / 0.55 * draw_speed)
	var tgt := want_off
	if tgt == &"shield" and not has_shield:
		tgt = &""
	if tgt == &"light" and _light_kind == &"":
		tgt = &""
	if tgt == &"dagger" and not has_off_dagger:
		tgt = &""
	var rate := delta * 2.0 / 0.6 * draw_speed
	if off_item != tgt:
		if off_item != &"" and off_p > 0.0:
			off_p = move_toward(off_p, 0.0, rate)
		else:
			off_item = tgt
			off_p = 0.0
	elif off_item != &"":
		off_p = move_toward(off_p, 2.0, rate)


## Hand -> Griff: 0..1 im ersten Abschnitt
func _reach(p: float) -> float:
	var x := clampf(p, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Teil -> Hand: 0..1 im zweiten Abschnitt
func _out(p: float) -> float:
	var x := clampf(p - 1.0, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Teil zwischen Ablage a und Hand b bewegen (Bogen über ctrl), Drehung folgt etwas verzögert.
func _carry(a: Transform3D, b: Transform3D, e: float, ctrl: Vector3) -> Transform3D:
	if e <= 0.0:
		return a
	if e >= 1.0:
		return b
	var p := a.origin.lerp(ctrl, e).lerp(ctrl.lerp(b.origin, e), e)
	var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), smoothstep(0.15, 1.0, e))
	return Transform3D(Basis(q), p)


func _ease_roll(t: float) -> float:
	# kräftiger Absprung, Drehung bis ROLL_SPIN, weich auslaufend
	var u := clampf(t / ROLL_SPIN, 0.0, 1.0)
	return lerpf(u * u * (3.0 - 2.0 * u), 1.0 - pow(1.0 - u, 2.0), 0.5)


## Keyframes eines Schwungs. Liefert [griff, klingenrichtung, flachseite, drehung, vorlage, absenken, trail_fenster]
func _swing_pose(index: int, t: float, base: Array) -> Array:
	# Keyframes kommen aus AnimLibrary (data/anims/*.json, bearbeitbar in der Animationswerkstatt).
	# Erster und letzter Key = aktuelle Grundhaltung -> nahtloser Übergang aus/zurück in die Kampfhaltung.
	var c: Dictionary = AnimLibrary.clip(swing_clip if swing_clip != "" else AnimLibrary.CLIPS[clampi(index, 0, AnimLibrary.CLIPS.size() - 1)])
	var trail_window: Vector2 = c.trail
	# Zeile: [t, Griff, Klingenrichtung, Flachseite, Drehung, Vorlage, Absenken, Schild, Schild-Front]
	# Angeschlossener Schlag: erster Key = Haltung am Ende des vorigen Schlags (dort, wo er eingestiegen ist)
	var t0 := 0.0
	var keys: Array
	if _swing_from.size() >= 10:
		var fr := _swing_from
		t0 = clampf(_swing_from_t, 0.0, 0.9)
		keys = [[t0, fr[0], fr[1], fr[2], fr[3], fr[4], fr[5], fr[7], fr[8], fr[9]]]
	else:
		keys = [[0.0, base[0], base[1], base[2], 0.0, 0.0, 0.0, base[3], base[4], AnimLibrary.zero_body()]]
	for k in c.keys:
		if k.t > t0 + 0.005:
			keys.append([k.t, _unscale(k.grip), k.dir, k.flat, k.twist, k.lean, k.drop, _unscale(k.shield), k.shield_front, k.get("body", AnimLibrary.zero_body())])
	if t0 > 0.0 or _swing_from.size() >= 10:
		if _via_serial != _serial_seen:
			_via_serial = _serial_seen
			_swing_via = _transition_via(keys, base) if keys.size() >= 2 else []
		if not _swing_via.is_empty():
			keys.insert(1, _swing_via)
	if c.get("hold_end", false) and keys.size() >= 2:
		# Haltung bleibt am Ende stehen (z. B. Tod), statt zur Grundhaltung zurückzukehren
		var end_key: Array = (keys[keys.size() - 1] as Array).duplicate()
		end_key[0] = 1.0
		keys.append(end_key)
	else:
		keys.append([1.0, base[0], base[1], base[2], 0.0, 0.0, 0.0, base[3], base[4], AnimLibrary.zero_body()])
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
	var bod: Array = []
	var b0: Array = k0[9]
	var b1: Array = k1[9]
	var b2: Array = k2[9]
	var b3: Array = k3[9]
	for j in b1.size():
		bod.append(_crf(b0[j], b1[j], b2[j], b3[j], u))
	return [g, d, f, sc.x, sc.y, sc.z, trail_window, shp, shf, bod]


## Übergang zwischen zwei Schlägen: Ginge die Klinge auf direktem Weg durch den eigenen Körper, führt ein
## Zwischen-Key sie nahe an der Grundhaltung vorbei (vor dem Körper, Spitze nach vorn oben).
func _transition_via(keys: Array, base: Array) -> Array:
	var a: Array = keys[0]
	var b: Array = keys[1]
	if _seg_depth(a, b) < 0.015:
		return []
	var tm: float = lerpf(a[0], b[0], 0.5)
	var d_mid: Vector3 = (a[2] as Vector3).normalized().lerp((b[2] as Vector3).normalized(), 0.5)
	var bod: Array = []
	for j in (a[9] as Array).size():
		bod.append(lerpf(a[9][j], b[9][j], 0.5))
	var best: Array = []
	var best_d := INF
	for w in [0.6, 0.8, 1.0]:
		var via: Array = [tm, (a[1] as Vector3).lerp(b[1], 0.5).lerp(base[0], w), d_mid.lerp(base[1], minf(w + 0.15, 1.0)).normalized(),
			(base[2] as Vector3), lerpf(a[4], b[4], 0.5), lerpf(a[5], b[5], 0.5), lerpf(a[6], b[6], 0.5),
			(a[7] as Vector3).lerp(b[7], 0.5).lerp(base[3], 0.5), base[4], bod]
		var dd := maxf(_seg_depth(a, via), _seg_depth(via, b))
		if dd < best_d:
			best_d = dd
			best = via
		if dd < 0.015:
			break
	return best


## Wie tief ginge die Klinge auf dem Weg von Key a nach Key b in den Körper (grobe Abschätzung, Meter)?
func _seg_depth(a: Array, b: Array) -> float:
	var worst := 0.0
	for i in range(1, 8):
		var u := i / 8.0
		var g: Vector3 = (a[1] as Vector3).lerp(b[1], u)
		var d: Vector3 = (a[2] as Vector3).normalized().lerp((b[2] as Vector3).normalized(), u)
		d = d.normalized() if d.length() > 0.05 else Vector3(0, 0.5, -1).normalized()
		var gs := _scale_pose(g)
		for s in [0.0, 0.25, 0.5, 0.75, 1.0]:
			worst = maxf(worst, clip_depth(gs + d * weapon_length * s))
		# Hand dicht an der Schulter: der Arm faltet sich, der Ellbogen kippt in den Körper
		var fold := (UPPER_ARM + LOWER_ARM) * 0.5 - gs.distance_to(SHOULDER_R)
		if fold > 0.0:
			worst = maxf(worst, 0.02 + fold)
	return worst


func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


func _crf(p0: float, p1: float, p2: float, p3: float, u: float) -> float:
	return _cr(Vector3(p0, 0, 0), Vector3(p1, 0, 0), Vector3(p2, 0, 0), Vector3(p3, 0, 0), u).x
