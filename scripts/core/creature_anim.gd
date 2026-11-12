class_name CreatureAnim
extends RefCounted
## Bearbeitbare Animationen der Gegner ohne Shade-Körper (Splinterkin, Grimhauler, Willamber).
##
## Diese Gegner bewegen sich prozedural (Beine suchen den Boden, Axt folgt der Hand ...). Die Werkstatt legt
## Keyframes als ZUSÄTZE darauf: je Aktion (z. B. "attack") und Zeitpunkt eine Drehung je Gelenk (Grad, um die
## eigenen Achsen des Gelenks) bzw. eine Verschiebung (m). Ohne Keys = unverändert. Nicht schleifende Aktionen
## beginnen und enden bei 0, damit die Übergänge weich bleiben; Schleifen (Gehen) laufen rund.
##
## data/enemy_anims/<gegner>.json: {"<aktion>": {"keys": [{"t": 0.4, "ch": {"chest": [x, y, z], ...}}, ...]}}
## Hollowed und Hollow One haben Shade-Körper; ihre Angriffe sind normale Clips (AnimLibrary.ENEMY_CLIPS).

const DIR := "res://data/enemy_anims/"

## Aktion: [id, Anzeige, Schleife?, Vorschau-Dauer (s), Erklärung]. Kanal: [id, Anzeige, "rot"/"pos"].
const CREATURES := {
	"splinterkin": {
		"label": "Splinterkin",
		"actions": [
			["move", "Scuttling (loop)", true, 0.8, "Played while it moves; legs keep finding the ground by themselves."],
			["windup", "Crouch before the leap", false, 0.6, "Eyes flare up, it ducks (0.6 s)."],
			["leap", "Leap", false, 0.32, "The jump itself, deals damage (0.32 s)."],
			["recover", "Landing / recover", false, 0.85, "Defenceless after landing (0.85 s)."],
			["stagger", "Staggered", false, 0.5, "After a heavy hit."],
		],
		"channels": [
			["torso", "Body (core + crown)", "rot"],
			["torso_pos", "Body position", "pos"],
			["foot_fl", "Front left foot", "pos"],
			["foot_fr", "Front right foot", "pos"],
			["foot_bl", "Back left foot", "pos"],
			["foot_br", "Back right foot", "pos"],
		],
	},
	"grimhauler": {
		"label": "Grimhauler",
		"actions": [
			["walk", "Stomping walk (loop)", true, 2.1, "One full step cycle, the axe drags behind."],
			["attack", "Overhead slam", false, 4.8, "Wind up 0-31 %, slam 31-36 %, impact at 36 %, pull back from 57 %."],
		],
		"channels": [
			["hips_pos", "Hips position", "pos"],
			["hips", "Hips", "rot"],
			["chest", "Chest", "rot"],
			["neck", "Neck", "rot"],
			["head", "Head", "rot"],
			["upR", "Axe arm (upper)", "rot"],
			["foreR", "Axe arm (forearm)", "rot"],
			["upL", "Other arm (upper)", "rot"],
			["foreL", "Other arm (forearm)", "rot"],
			["axe", "Axe tilt in the hand", "rot"],
			["foot_L", "Left foot", "pos"],
			["foot_R", "Right foot", "pos"],
		],
	},
	"willamber": {
		"label": "Willamber",
		"actions": [
			["lurk", "Lurking (loop)", true, 1.2, "Crouched and twitching between the jumps."],
			["dash", "Darting", false, 0.14, "The fast jerky jump from spot to spot."],
			["strike", "Strike", false, 0.45, "Long arms slash at the target."],
			["rise", "Rising from the shadow", false, 0.45, "Climbs out of its shadow pool."],
			["sink", "Sinking into the shadow", false, 0.4, "Slips back into the shadow."],
		],
		"channels": [
			["hips_pos", "Hips position", "pos"],
			["spine", "Spine", "rot"],
			["neck", "Neck", "rot"],
			["head", "Head", "rot"],
			["armR_up", "Right arm (upper)", "rot"],
			["armR_lo", "Right arm (lower)", "rot"],
			["armL_up", "Left arm (upper)", "rot"],
			["armL_lo", "Left arm (lower)", "rot"],
			["legR_th", "Right thigh", "rot"],
			["legR_sh", "Right shin", "rot"],
			["legL_th", "Left thigh", "rot"],
			["legL_sh", "Left shin", "rot"],
		],
	},
}

static var _cache := {}


## Alle Aktionen eines Gegners: {aktion: {"keys": [...]}} (Werte in Grad bzw. m). Wird live bearbeitet.
static func data(creature: String) -> Dictionary:
	if _cache.has(creature):
		return _cache[creature]
	var d := {}
	for a in CREATURES[creature].actions:
		d[a[0]] = {"keys": []}
	var path := DIR + creature + ".json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			for act in parsed:
				if not d.has(act) or not (parsed[act] is Dictionary):
					continue
				for k in parsed[act].get("keys", []):
					var ch := {}
					var src: Dictionary = k.get("ch", {})
					for c in src:
						var v: Array = src[c]
						if v.size() == 3:
							ch[c] = Vector3(float(v[0]), float(v[1]), float(v[2]))
					d[act].keys.append({"t": float(k.get("t", 0.5)), "ch": ch})
				d[act].keys.sort_custom(func(a, b): return a.t < b.t)
		else:
			push_warning("CreatureAnim: %s ist kein gültiges JSON" % path)
	_cache[creature] = d
	return d


static func action_info(creature: String, action: String) -> Array:
	for a in CREATURES[creature].actions:
		if a[0] == action:
			return a
	return []


static func channel_kind(creature: String, channel: String) -> String:
	for c in CREATURES[creature].channels:
		if c[0] == channel:
			return c[2]
	return "rot"


static func reload(creature := "") -> void:
	if creature == "":
		_cache.clear()
	else:
		_cache.erase(creature)


static func set_data(creature: String, d: Dictionary) -> void:
	_cache[creature] = d


static func save(creature: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(DIR + creature + ".json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var d := data(creature)
	var lines: Array[String] = []
	for act in d:
		var keys: Array[String] = []
		for k in d[act].keys:
			var ch := {}
			for c in k.ch:
				var v: Vector3 = k.ch[c]
				if v.length() > 0.0001:
					ch[c] = [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
			keys.append("\t\t" + JSON.stringify({"t": snappedf(k.t, 0.001), "ch": ch}, "", false))
		lines.append("\t%s: {\"keys\": [%s]}" % [JSON.stringify(act), ("\n" + ",\n".join(keys) + "\n\t") if not keys.is_empty() else ""])
	f.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	f.close()
	return OK


static func copy(creature: String) -> Dictionary:
	return data(creature).duplicate(true)


## Zusätze zur normierten Zeit k (0..1): {kanal: Vector3}; Drehungen in Radiant, Verschiebungen in m.
static func sample(creature: String, action: String, k: float) -> Dictionary:
	var d := data(creature)
	if not d.has(action):
		return {}
	var keys: Array = d[action].keys
	if keys.is_empty():
		return {}
	var loop: bool = action_info(creature, action)[2]
	var pts: Array = []
	if loop:
		var last: Dictionary = keys[keys.size() - 1]
		var first: Dictionary = keys[0]
		pts.append({"t": last.t - 1.0, "ch": last.ch})
		pts.append_array(keys)
		pts.append({"t": first.t + 1.0, "ch": first.ch})
		k = fposmod(k, 1.0)
	else:
		pts.append({"t": 0.0, "ch": {}})
		pts.append_array(keys)
		pts.append({"t": 1.0, "ch": {}})
		k = clampf(k, 0.0, 1.0)
	var i := 0
	while i < pts.size() - 2 and k > pts[i + 1].t:
		i += 1
	var a: Dictionary = pts[i]
	var b: Dictionary = pts[i + 1]
	var u := clampf((k - a.t) / maxf(b.t - a.t, 0.0001), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var out := {}
	for c in CREATURES[creature].channels:
		var id: String = c[0]
		var va: Vector3 = a.ch.get(id, Vector3.ZERO)
		var vb: Vector3 = b.ch.get(id, Vector3.ZERO)
		if va == Vector3.ZERO and vb == Vector3.ZERO:
			continue
		var v := va.lerp(vb, u)
		out[id] = v * (PI / 180.0) if c[2] == "rot" else v
	return out


## Gelenk zusätzlich um seine eigenen Achsen drehen (Radiant, Reihenfolge XYZ).
static func turn(n: Node3D, r: Variant) -> void:
	if n and r is Vector3 and r != Vector3.ZERO:
		n.quaternion = n.quaternion * Quaternion.from_euler(r)
