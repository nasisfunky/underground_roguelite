class_name LocomotionLibrary
extends RefCounted
## Lauf-Zyklen aus Motion Capture (Quaternius Universal Animation Library, CC0), umgerechnet auf das
## Gelenk-Rig der Shades durch `tools/mocap_bake.gd` -> `data/locomotion.json`.
##
## Jeder Clip ist ein Doppelschritt mit FRAMES Bildern, Phase u = 0..1 (linker Fuß ganz vorn bei u = 0.25).
## Felder je Bild (Shade-Koordinaten, x rechts, y hoch, -z vorn):
##   hips_pos   Versatz der Hüfte gegenüber dem Stand (m)
##   hips_rot   Drehung der Hüfte (Euler YXZ, rad)
##   chest_rot  Rumpf relativ zur Hüfte, head_rot Kopf relativ zum Rumpf
##   foot_l/_r  Bodenkontaktpunkt relativ zum Hüftgelenk, im Hüftraum (m)
##   knee_l/_r  Richtung, in die das Knie zeigt (Hüftraum)
##   hand_l/_r  Hand relativ zur Schulter, im Rumpfraum (m)
##   elbow_l/_r Richtung, in die der Ellbogen zeigt (Rumpfraum)
## sample() mischt die Clips nach Tempo und passt die Schrittlänge an, damit die Füße nicht gleiten.

const PATH := "res://data/locomotion.json"
const FIELDS := ["hips_pos", "hips_rot", "chest_rot", "head_rot", "foot_l", "foot_r", "knee_l", "knee_r",
	"hand_l", "hand_r", "elbow_l", "elbow_r"]

## Überblendung Gehen -> Joggen -> Sprinten (m/s). Gehen (Strg, 2 m/s) ist reines Gehen,
## Laufen (4,8 m/s) reines Joggen, Sprint (7 m/s) reiner Sprint.
const WALK_TO_JOG := Vector2(2.4, 3.8)
const JOG_TO_SPRINT := Vector2(4.9, 6.8)
## Schrittlänge folgt dem Tempo nur gedämpft (sqrt): schneller = längere UND schnellere Schritte
const STRIDE_FIT := Vector2(0.6, 1.45)

static var _data: Dictionary = {}
static var _loaded := false


static func available() -> bool:
	_load()
	return not _data.is_empty()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_warning("LocomotionLibrary: %s fehlt, prozeduraler Laufzyklus bleibt aktiv" % PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_warning("LocomotionLibrary: %s ist kein gültiges JSON" % PATH)
		return
	for key in (parsed as Dictionary).clips:
		var c: Dictionary = parsed.clips[key]
		var frames: Array = []
		for fr in c.frames:
			var vs: Array[Vector3] = []
			for v in fr:
				vs.append(Vector3(v[0], v[1], v[2]))
			frames.append(vs)
		# mittlere Handposition vor/zurück: um diese Mitte wird der Armschwung mit der Schrittlänge gestreckt
		var mid := Vector2.ZERO
		for fr in frames:
			mid += Vector2(fr[8].z, fr[9].z) / frames.size()
		_data[key] = {"speed": float(c.speed), "stride": float(c.stride), "frames": frames, "hand_mid": mid}


## Gewichte der Clips bei Tempo v (m/s).
static func weights(v: float) -> Dictionary:
	var jog := smoothstep(WALK_TO_JOG.x, WALK_TO_JOG.y, v)
	var spr := smoothstep(JOG_TO_SPRINT.x, JOG_TO_SPRINT.y, v)
	return {"walk": 1.0 - jog, "jog": jog * (1.0 - spr), "sprint": jog * spr}


## Faktor, um den ein Clip bei Tempo v seine Schritte verlängert (bzw. verkürzt).
static func stride_scale(clip: String, v: float) -> float:
	var nat: float = _data[clip].speed
	return clampf(sqrt(maxf(v, 0.01) / nat), STRIDE_FIT.x, STRIDE_FIT.y)


## Meter pro Doppelschritt bei Tempo v (gemischt über die Clips).
static func stride(v: float) -> float:
	_load()
	var w := weights(v)
	var s := 0.0
	for k in w:
		if w[k] > 0.0:
			s += w[k] * _data[k].stride * stride_scale(k, v)
	return maxf(s, 0.2)


## Gemischte Pose bei Tempo v und Phase u (0..1). Liefert ein Array[Vector3] in der Reihenfolge FIELDS.
static func sample(v: float, u: float) -> Array[Vector3]:
	_load()
	var out: Array[Vector3] = []
	out.resize(FIELDS.size())
	out.fill(Vector3.ZERO)
	var w := weights(v)
	for k in w:
		var wk: float = w[k]
		if wk <= 0.0001:
			continue
		var frames: Array = _data[k].frames
		var n := frames.size()
		var x := fposmod(u, 1.0) * n
		var i0 := int(x) % n
		var i1 := (i0 + 1) % n
		var f := x - floorf(x)
		var a: Array = frames[i0]
		var b: Array = frames[i1]
		var ss := stride_scale(k, v)
		for fi in FIELDS.size():
			var val: Vector3 = (a[fi] as Vector3).lerp(b[fi], f)
			if fi == 4 or fi == 5:
				val.z *= ss  # Fuß vor/zurück: Schrittlänge ans Tempo anpassen
			elif fi == 8 or fi == 9:
				# Armschwung wächst mit der Schrittlänge
				var m: float = _data[k].hand_mid[fi - 8]
				val.z = m + (val.z - m) * ss
			out[fi] += val * wk
	return out
