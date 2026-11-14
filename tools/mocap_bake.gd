extends SceneTree
## Entwickler-Werkzeug: rechnet Lauf-Clips der Quaternius Universal Animation Library (CC0) auf das
## Gelenk-Rig der Shades um und schreibt `data/locomotion.json`.
##
## Aufruf:
##   godot --headless --path . -s tools/mocap_bake.gd -- <ordner mit UAL1_Standard.glb und UAL1_Standard_RM.glb>
##
## Die Shade hat kein Skinning, sondern starre Teile an Gelenken (Hüfte, Brust, Kopf, Hüftgelenke, Knie;
## Arme per IK). Deshalb werden keine Knochenrotationen kopiert, sondern je Bild:
## - Hüfte: Versatz (Höhe, seitlich, vor/zurück) und Drehung gegenüber der Ruhehaltung
## - Brust (spine_03) relativ zur Hüfte, Kopf relativ zur Brust
## - Fußziele (Bodenkontaktpunkt) relativ zum Hüftgelenk im Hüftraum, skaliert auf die Shade-Beinlänge
## - Kniepol (Richtung, in die das Knie zeigt)
## - Handziele relativ zur Schulter im Brustraum, skaliert auf die Shade-Armlänge, und Ellbogenpol
## Alles im Shade-Koordinatensystem (Blick nach -Z, rechts = +X). Die UAL-Figur schaut nach +Z.
## Phase: Bild 0 = linker Fuß ganz vorn bei u = 0.25 (passt zu sin(_phase) des alten Zyklus).

const CLIPS := {
	"walk": "Walk_Loop",
	"jog": "Jog_Fwd_Loop",
	"sprint": "Sprint_Loop",
}
const FRAMES := 48  ## Bilder pro Zyklus

# Shade-Maße (siehe ShadowBody)
const SHADE_HIP_H := 0.81  ## Hüftgelenk über dem Boden (RIG_Y + HIPS_Y)
const SHADE_ARM := 0.62  ## UPPER_ARM + LOWER_ARM

var C := Basis(Vector3.UP, PI)  ## UAL (+Z vorn) -> Shade (-Z vorn)
var sk: Skeleton3D
var ap: AnimationPlayer
var bi := {}
var rest := {}  ## globale Ruhe-Transformationen (Modellraum)
var leg_scale := 1.0
var arm_scale := 1.0
var ankle_h := 0.1
var ball_h := 0.015


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "F:/Nasisfunky/ual-transfer/UAL1"
	var out_path: String = args[1] if args.size() > 1 else "res://data/locomotion.json"
	var speeds := _root_speeds(dir.path_join("UAL1_Standard_RM.glb"))
	var scene := _load(dir.path_join("UAL1_Standard.glb"))
	root.add_child(scene)
	sk = scene.find_children("*", "Skeleton3D", true, false)[0]
	ap = scene.find_children("*", "AnimationPlayer", true, false)[0]
	for i in sk.get_bone_count():
		bi[sk.get_bone_name(i)] = i
		rest[sk.get_bone_name(i)] = sk.get_bone_global_rest(i)
	var thigh_h: float = (_rp("thigh_l").y + _rp("thigh_r").y) * 0.5
	leg_scale = SHADE_HIP_H / thigh_h
	var ual_arm: float = _rp("upperarm_l").distance_to(_rp("lowerarm_l")) + _rp("lowerarm_l").distance_to(_rp("hand_l"))
	arm_scale = SHADE_ARM / ual_arm
	ankle_h = _rp("foot_l").y
	ball_h = _rp("ball_l").y
	print("Beinskalierung %.3f, Armskalierung %.3f" % [leg_scale, arm_scale])

	var out := {
		"source": "Quaternius Universal Animation Library (CC0), UAL1_Standard.glb",
		"fields": ["hips_pos", "hips_rot", "chest_rot", "head_rot", "foot_l", "foot_r", "knee_l", "knee_r",
			"hand_l", "hand_r", "elbow_l", "elbow_r"],
		"clips": {},
	}
	for key in CLIPS:
		var anim_name: String = CLIPS[key]
		var a := ap.get_animation(anim_name)
		var frames: Array = []
		for f in FRAMES:
			frames.append(_sample(anim_name, a.length * f / FRAMES))
		# Phase ausrichten: linker Fuß ganz vorn (kleinstes z) bei u = 0.25
		var best := 0
		for f in FRAMES:
			if frames[f][4][2] < frames[best][4][2]:
				best = f
		var shift := (best - FRAMES / 4 + FRAMES) % FRAMES
		var aligned: Array = []
		for f in FRAMES:
			aligned.append(frames[(f + shift) % FRAMES])
		var speed: float = speeds.get(anim_name, 0.0) * leg_scale
		var clip := {
			"anim": anim_name,
			"duration": a.length,
			"speed": snappedf(speed, 0.001),
			"stride": snappedf(speed * a.length, 0.001),  ## Meter pro Zyklus (Doppelschritt)
			"frames": aligned,
		}
		out.clips[key] = clip
		print("%s: %.3f s, %.2f m/s, Doppelschritt %.2f m (Shade-Maßstab)" % [key, a.length, speed, speed * a.length])
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	fa.store_string(_to_json(out))
	fa.close()
	print("geschrieben: ", out_path)
	quit()


func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	assert(err == OK, "konnte %s nicht laden" % path)
	return doc.generate_scene(st)


## Geschwindigkeit je Clip aus der Root-Motion-Fassung (Weg des root-Knochens über die Clip-Länge).
func _root_speeds(path: String) -> Dictionary:
	var scene := _load(path)
	root.add_child(scene)
	var s := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var p := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var ri := s.find_bone("root")
	var res := {}
	for key in CLIPS:
		var n: String = CLIPS[key]
		var a := p.get_animation(n)
		p.play(n)
		p.seek(0.0, true)
		var p0 := s.get_bone_pose_position(ri)
		p.seek(a.length - 0.0001, true)
		var p1 := s.get_bone_pose_position(ri)
		var d := Vector2(p1.x - p0.x, p1.z - p0.z).length()
		res[n] = d / a.length
		print("Root-Motion %s: %.3f m in %.3f s" % [n, d, a.length])
	p.stop()
	scene.queue_free()
	return res


func _rp(b: String) -> Vector3:
	return (rest[b] as Transform3D).origin


func _sample(anim_name: String, t: float) -> Array:
	ap.play(anim_name)
	ap.seek(t, true)
	# globale Posen selbst aus den lokalen zusammensetzen (der Cache des Skeletts ist hier noch nicht aktualisiert;
	# Eltern stehen in der UAL-Knochenliste immer vor ihren Kindern)
	var glob: Array[Transform3D] = []
	glob.resize(sk.get_bone_count())
	for i in sk.get_bone_count():
		var par := sk.get_bone_parent(i)
		var local := sk.get_bone_pose(i)
		glob[i] = local if par < 0 else glob[par] * local
	var g := {}
	for b in bi:
		g[b] = glob[bi[b]]
	# Drehungen gegenüber der Ruhehaltung (Modellraum)
	var r_p := _rel(g, "pelvis")
	# Rumpf der Shade ist ein starres Teil: Ausrichtung aus der Linie Lende -> Hals und der Schulterlinie
	# (die UAL-Wirbelsäule biegt sich stark im oberen Brustbereich, das würde den ganzen Rumpf zu weit kippen)
	var r_c := _torso(g) * _torso(rest).inverse()
	var r_h := _rel(g, "Head")
	var hip_mid: Vector3 = ((g.thigh_l as Transform3D).origin + (g.thigh_r as Transform3D).origin) * 0.5
	var hip_rest := (_rp("thigh_l") + _rp("thigh_r")) * 0.5
	var hips_pos := C * (hip_mid - hip_rest) * leg_scale
	var hips_rot := _conv(r_p)
	var chest_rot := _conv(r_p.inverse() * r_c)
	var head_rot := _conv(r_c.inverse() * r_h)
	var res: Array = [_v(hips_pos), _v(hips_rot.get_euler()), _v(chest_rot.get_euler()), _v(head_rot.get_euler())]
	var feet: Array = []
	var knees: Array = []
	for side in ["l", "r"]:
		var hip: Vector3 = (g["thigh_" + side] as Transform3D).origin
		var ankle: Vector3 = (g["foot_" + side] as Transform3D).origin
		var ball: Vector3 = (g["ball_" + side] as Transform3D).origin
		var knee: Vector3 = (g["calf_" + side] as Transform3D).origin
		# Bodenkontaktpunkt unter dem Knöchel: Ferse oder Ballen, je nachdem was tiefer ist
		var contact := Vector3(ankle.x, minf(ankle.y - ankle_h, ball.y - ball_h), ankle.z)
		var rel := C * (r_p.inverse() * (contact - hip)) * leg_scale
		feet.append(_v(rel))
		knees.append(_v(_pole(C * (r_p.inverse() * (hip)), C * (r_p.inverse() * knee), C * (r_p.inverse() * contact))))
	var hands: Array = []
	var elbows: Array = []
	for side in ["l", "r"]:
		var sh: Vector3 = (g["upperarm_" + side] as Transform3D).origin
		var el: Vector3 = (g["lowerarm_" + side] as Transform3D).origin
		var hd: Vector3 = (g["hand_" + side] as Transform3D).origin
		var to_c := (r_c).inverse()
		hands.append(_v(C * (to_c * (hd - sh)) * arm_scale))
		elbows.append(_v(_pole(C * (to_c * sh), C * (to_c * el), C * (to_c * hd))))
	res.append_array([feet[0], feet[1], knees[0], knees[1], hands[0], hands[1], elbows[0], elbows[1]])
	return res


## Rumpf-Ausrichtung im Modellraum: y = Lende -> Hals, x = linke -> rechte Schulter (UAL: rechts = -X).
func _torso(g: Dictionary) -> Basis:
	var y: Vector3 = ((g.neck_01 as Transform3D).origin - (g.spine_01 as Transform3D).origin).normalized()
	var x: Vector3 = (g.upperarm_r as Transform3D).origin - (g.upperarm_l as Transform3D).origin
	x = (x - y * x.dot(y)).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


## Drehung des Knochens gegenüber seiner Ruhehaltung, im Modellraum.
func _rel(g: Dictionary, b: String) -> Basis:
	return ((g[b] as Transform3D).basis * (rest[b] as Transform3D).basis.inverse()).orthonormalized()


func _conv(b: Basis) -> Basis:
	return (C * b * C.inverse()).orthonormalized()


## Richtung, in die das Mittelgelenk (Knie/Ellbogen) von der Linie Anfang -> Ende absteht.
func _pole(a: Vector3, mid: Vector3, e: Vector3) -> Vector3:
	var d := (e - a).normalized()
	var m := mid - a
	var perp := m - d * m.dot(d)
	if perp.length_squared() < 1e-8:
		return Vector3.ZERO
	return perp.normalized()


func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


## kompaktes JSON: ein Bild pro Zeile
func _to_json(out: Dictionary) -> String:
	var s := "{\n"
	s += "\t\"source\": %s,\n" % JSON.stringify(out.source)
	s += "\t\"fields\": %s,\n" % JSON.stringify(out.fields)
	s += "\t\"clips\": {\n"
	var keys: Array = out.clips.keys()
	for ki in keys.size():
		var c: Dictionary = out.clips[keys[ki]]
		s += "\t\t\"%s\": {\n" % keys[ki]
		s += "\t\t\t\"anim\": \"%s\", \"duration\": %s, \"speed\": %s, \"stride\": %s,\n" % [c.anim, snappedf(c.duration, 0.0001), c.speed, c.stride]
		s += "\t\t\t\"frames\": [\n"
		for fi in c.frames.size():
			s += "\t\t\t\t" + JSON.stringify(c.frames[fi]) + ("," if fi < c.frames.size() - 1 else "") + "\n"
		s += "\t\t\t]\n\t\t}" + ("," if ki < keys.size() - 1 else "") + "\n"
	s += "\t}\n}\n"
	return s
