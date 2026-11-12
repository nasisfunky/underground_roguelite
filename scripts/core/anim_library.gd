class_name AnimLibrary
extends RefCounted
## Kampfanimationen als Daten. Jede Animation liegt als JSON in res://data/anims/<name>.json
## und wird in der Animationswerkstatt (tools/anim_workshop.tscn) bearbeitet.
##
## Format: {"name", "label", "duration" (s), "hit" (0..1, Trefferzeitpunkt), "trail" [von, bis],
##          "keys": [{"t", "grip" [x,y,z], "dir", "flat", "twist", "lean", "drop", "shield", "shield_front"}]}
## Alle Positionen/Richtungen in Brust-Koordinaten der Figur (x rechts, y hoch, -z vorn).
## Erster und letzter Key (t=0 und t=1) sind immer die aktuelle Grundhaltung und stehen nicht in der Datei.

const DIR := "res://data/anims/"
const CLIPS := ["swing_0", "swing_1", "heavy", "thrust", "shove", "sweep", "hook", "bind", "sever", "rake", "flurry"]
## Animationen der Gegner mit Shade-Körper. Angriffe: Ausholen bis trail.x, Schlag (Schaden) bis trail.y, dann Erholen;
## ohne eigene Datei eine Kopie der Heavy-Animation (so sahen sie vorher aus). Taumeln/Tod: eingebaute Startfassung
## (vorher fest im Code von ShadowBody). Der Tod hält seine letzte Haltung ("hold_end").
const ENEMY_CLIPS := ["hollowed_strike", "hollowed_stagger", "hollowed_death", "hollow_one_strike"]
const ENEMY_LABELS := {"hollowed_strike": "Enemy: Hollowed strike", "hollowed_stagger": "Enemy: Hollowed staggered",
	"hollowed_death": "Enemy: Hollowed death", "hollow_one_strike": "Enemy: Hollow One strike"}
## Welcher Gegner wie aussieht (Figur in der Werkstatt)
const ENEMY_LOOKS := {"hollowed_strike": "hollowed", "hollowed_stagger": "hollowed", "hollowed_death": "hollowed", "hollow_one_strike": "hollow_one"}
const ALL_CLIPS := CLIPS + ENEMY_CLIPS
## Zusätzliche Körpersteuerung je Keyframe (Werkstatt). Werte addieren sich zur prozeduralen Pose (0 = unverändert).
## Winkel in Radiant, step in Metern. In der Datei stehen nur Werte ungleich 0.
## fall/sink: ganze Figur nach vorn (+) / hinten kippen (rad) und absenken (m), z. B. beim Tod.
const BODY_FIELDS := ["bank", "hips_turn", "head_yaw", "head_pitch", "step",
	"leg_l_swing", "leg_l_spread", "leg_l_knee", "leg_r_swing", "leg_r_spread", "leg_r_knee", "elbow_r", "elbow_l", "fall", "sink"]
## Waffen, für die es eigene Versionen eines Clips geben kann (Datei <clip>@<waffe>.json)
const VARIANT_WEAPONS := ["sword", "spear", "greataxe", "dagger"]


static func zero_body() -> Array:
	var a: Array = []
	a.resize(BODY_FIELDS.size())
	a.fill(0.0)
	return a


## Name des Clips für eine Waffe: eigene Version "<clip>@<waffe>", falls vorhanden, sonst der allgemeine Clip.
static func resolve(clip_name: String, weapon_id: String) -> String:
	var v := clip_name + "@" + weapon_id
	if _cache.has(v) or FileAccess.file_exists(DIR + v + ".json"):
		return v
	return clip_name


static func has_variant(clip_name: String, weapon_id: String) -> bool:
	return resolve(clip_name, weapon_id) != clip_name


## Eigene Version für eine Waffe anlegen (Kopie des allgemeinen Clips, nur im Speicher bis gespeichert).
static func make_variant(clip_name: String, weapon_id: String) -> String:
	var v := clip_name + "@" + weapon_id
	if not _cache.has(v):
		var c := duplicate_clip(clip(clip_name))
		c.name = v
		c.label = c.label + " [" + weapon_id + "]"
		_cache[v] = c
	return v


## Eigene Version löschen (Datei entfernen); danach gilt wieder der allgemeine Clip.
static func delete_variant(clip_name: String, weapon_id: String) -> void:
	var v := clip_name + "@" + weapon_id
	_cache.erase(v)
	var path := ProjectSettings.globalize_path(DIR + v + ".json")
	if FileAccess.file_exists(DIR + v + ".json"):
		DirAccess.remove_absolute(path)

static var _cache := {}


static func clip(clip_name: String) -> Dictionary:
	if _cache.has(clip_name):
		return _cache[clip_name]
	var c := _load_file(clip_name)
	if c.is_empty():
		if "@" in clip_name:
			return clip(clip_name.get_slice("@", 0))  # keine eigene Version: allgemeiner Clip
		if clip_name in ["hollowed_strike", "hollow_one_strike"]:
			c = duplicate_clip(clip("heavy"))
			c.name = clip_name
			c.label = ENEMY_LABELS[clip_name]
			c.trail = Vector2(0.36, 0.62)
		else:
			c = builtin(clip_name)
	_cache[clip_name] = c
	return c


static func set_clip(clip_name: String, data: Dictionary) -> void:
	_cache[clip_name] = data


static func reload() -> void:
	_cache.clear()


static func save(clip_name: String, data: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(DIR + clip_name + ".json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(_to_text(data))
	f.close()
	_cache[clip_name] = data
	return OK


static func _load_file(clip_name: String) -> Dictionary:
	var path := DIR + clip_name + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("AnimLibrary: %s ist kein gültiges JSON" % path)
		return {}
	return _from_json(parsed)


static func _v(a: Variant, fallback: Vector3) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func _from_json(d: Dictionary) -> Dictionary:
	var keys: Array = []
	for k in d.get("keys", []):
		keys.append({
			"t": float(k.get("t", 0.5)),
			"grip": _v(k.get("grip"), Vector3(0.3, 0.1, -0.4)),
			"dir": _v(k.get("dir"), Vector3(0, 0.5, -1)).normalized(),
			"flat": _v(k.get("flat"), Vector3(0, 1, 0)).normalized(),
			"twist": float(k.get("twist", 0.0)),
			"lean": float(k.get("lean", 0.0)),
			"drop": float(k.get("drop", 0.0)),
			"shield": _v(k.get("shield"), Vector3(-0.3, 0.1, -0.3)),
			"shield_front": _v(k.get("shield_front"), Vector3(-0.35, 0, -1)).normalized(),
			"body": _body_from(k),
		})
	keys.sort_custom(func(a, b): return a.t < b.t)
	var tr: Array = d.get("trail", [0.32, 0.62])
	return {
		"name": str(d.get("name", "")),
		"label": str(d.get("label", d.get("name", ""))),
		"duration": float(d.get("duration", 0.95)),
		"hit": float(d.get("hit", 0.44)),
		"trail": Vector2(float(tr[0]), float(tr[1])),
		"hold_end": bool(d.get("hold_end", false)),
		"keys": keys,
	}


static func _body_from(k: Dictionary) -> Array:
	var b := zero_body()
	for i in BODY_FIELDS.size():
		b[i] = float(k.get(BODY_FIELDS[i], 0.0))
	return b


static func _r(x: float) -> float:
	return snappedf(x, 0.001)


static func _a(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


static func _to_json(c: Dictionary) -> Dictionary:
	var keys: Array = []
	for k in c.keys:
		var kd := {"t": _r(k.t), "grip": _a(k.grip), "dir": _a(k.dir), "flat": _a(k.flat),
			"twist": _r(k.twist), "lean": _r(k.lean), "drop": _r(k.drop),
			"shield": _a(k.shield), "shield_front": _a(k.shield_front)}
		var b: Array = k.get("body", [])
		for i in mini(b.size(), BODY_FIELDS.size()):
			if absf(b[i]) > 0.0005:
				kd[BODY_FIELDS[i]] = _r(b[i])
		keys.append(kd)
	var out := {"name": c.name, "label": c.label, "duration": _r(c.duration), "hit": _r(c.hit),
		"trail": [_r(c.trail.x), _r(c.trail.y)], "keys": keys}
	if c.get("hold_end", false):
		out.hold_end = true
	return out


## Lesbares JSON: Kopfdaten oben, ein Keyframe pro Zeile.
static func _to_text(c: Dictionary) -> String:
	var j := _to_json(c)
	var lines: Array[String] = []
	for k in j.keys:
		lines.append("\t\t" + JSON.stringify(k, "", false))
	return "{\n\t\"name\": %s,\n\t\"label\": %s,\n\t\"duration\": %s,\n\t\"hit\": %s,\n\t\"trail\": %s,%s\n\t\"keys\": [\n%s\n\t]\n}\n" % [
		JSON.stringify(j.name), JSON.stringify(j.label), JSON.stringify(j.duration), JSON.stringify(j.hit),
		JSON.stringify(j.trail), "\n\t\"hold_end\": true," if j.get("hold_end", false) else "", ",\n".join(lines)]


static func duplicate_clip(c: Dictionary) -> Dictionary:
	return _from_json(_to_json(c))


## Eingebaute Standard-Animationen (falls keine Datei existiert).
static func builtin(clip_name: String) -> Dictionary:
	var sh := Vector3(-0.3, 0.1, -0.3)
	var shf := Vector3(-0.35, 0.0, -1.0)
	var rows: Array
	var d := {"name": clip_name, "label": clip_name, "duration": 0.95, "hit": 0.44, "trail": [0.32, 0.62]}
	match clip_name:
		"swing_0":
			d.label = "Forehand (auto attack)"
			rows = [
				[0.30, [0.40, 0.30, 0.08], [0.55, 0.5, 0.67], [0, 1, 0], -0.6, 0.08, 0.0],
				[0.44, [0.12, 0.18, -0.50], [-0.05, 0.05, -1], [0, 1, 0], -0.05, -0.18, 0.07],
				[0.56, [-0.15, 0.12, -0.34], [-1, -0.1, -0.4], [0, 1, 0], 0.55, -0.22, 0.08],
				[0.74, [-0.02, 0.14, -0.45], [-0.6, 0.2, -0.75], [0, 1, 0], 0.3, -0.1, 0.04],
			]
		"swing_1":
			d.label = "Backhand (auto attack)"
			rows = [
				[0.30, [-0.08, 0.08, -0.35], [-0.75, -0.45, -0.2], [0, 1, 0.3], 0.5, -0.05, 0.03],
				[0.44, [0.10, 0.16, -0.50], [0.1, 0.2, -1], [0, 1, 0.2], 0.0, -0.18, 0.07],
				[0.58, [0.42, 0.34, -0.25], [0.75, 0.6, 0.0], [-0.3, 1, 0], -0.5, -0.1, 0.04],
				[0.76, [0.34, 0.20, -0.35], [0.2, 0.7, -0.6], [0, 1, 0], -0.2, -0.05, 0.02],
			]
		"thrust":
			# Stich: Klinge zurückziehen, gerade nach vorn stoßen, Schild bleibt vorn
			d.label = "Thrust (middle mouse)"
			d.duration = 1.05
			d.hit = 0.46
			d.trail = [0.38, 0.52]
			rows = [
				[0.22, [0.30, 0.10, 0.05], [0.05, 0.12, -1], [0, 1, 0], -0.45, 0.05, 0.02],
				[0.36, [0.30, 0.12, 0.08], [0.02, 0.1, -1], [0, 1, 0], -0.55, 0.1, 0.04],
				[0.46, [0.12, 0.16, -0.54], [-0.04, 0.02, -1], [0, 1, 0], 0.15, -0.3, 0.12],
				[0.62, [0.14, 0.15, -0.52], [-0.04, 0.03, -1], [0, 1, 0], 0.12, -0.26, 0.1],
				[0.82, [0.26, 0.12, -0.36], [-0.12, 0.4, -0.9], [0, 1, 0], 0.0, -0.08, 0.03],
			]
		"shove":
			# Stoßen: Schild/Schulter kräftig nach vorn rammen (vorher prozedural als "bash")
			d.label = "Shove (combo)"
			d.duration = 0.82
			d.hit = 0.27
			d.trail = [1.1, 1.2]
			rows = [
				[0.1, [0.34, -0.14, 0.11], [0.3, 0.4, 0.6], [0, 1, 0], 0.22, -0.19, 0.05, [-0.04, 0.03, -0.5], [0.1, 0.1, -1]],
				[0.24, [0.34, -0.14, 0.11], [0.3, 0.4, 0.6], [0, 1, 0], 0.35, -0.3, 0.08, [-0.04, 0.03, -0.57], [0.1, 0.1, -1]],
				[0.38, [0.34, -0.12, 0.08], [0.3, 0.45, 0.55], [0, 1, 0], 0.2, -0.17, 0.05, [-0.04, 0.04, -0.49], [0.1, 0.1, -1]],
				[0.62, [0.3, 0.0, -0.12], [0.0, 0.5, -0.85], [0, 1, 0], 0.05, -0.05, 0.01, [-0.15, 0.15, -0.38]],
			]
		"sweep":
			# Fegen: tief rechts ausholen, flach und weit nach links durchziehen, in die Knie
			d.label = "Low Sweep (combo)"
			d.duration = 1.0
			d.hit = 0.46
			d.trail = [0.36, 0.62]
			rows = [
				[0.30, [0.46, -0.06, 0.14], [0.8, -0.25, 0.55], [0, 1, 0], -0.75, 0.12, 0.12],
				[0.46, [0.12, -0.18, -0.56], [0.05, -0.4, -1], [0, 1, 0], 0.0, -0.3, 0.24],
				[0.60, [-0.42, -0.12, -0.22], [-1, -0.32, 0.15], [0, 1, 0], 0.75, -0.28, 0.22],
				[0.80, [-0.08, 0.04, -0.4], [-0.6, 0.2, -0.75], [0, 1, 0], 0.35, -0.1, 0.06],
			]
		"hook":
			# Schattenranke: linke Hand schnellt vor (rechte Schulter zurück), dann kräftiges Zurückreißen
			d.label = "Shadow Hook (combo)"
			d.duration = 1.0
			d.hit = 0.4
			d.trail = [1.1, 1.2]
			rows = [
				[0.24, [0.36, -0.02, 0.1], [0.3, 0.55, 0.6], [0, 1, 0], -0.5, -0.05, 0.02, [-0.08, 0.26, -0.6]],
				[0.40, [0.38, -0.02, 0.12], [0.3, 0.55, 0.6], [0, 1, 0], -0.55, -0.14, 0.06, [-0.1, 0.24, -0.66]],
				[0.58, [0.34, 0.04, -0.02], [0.2, 0.6, 0.35], [0, 1, 0], 0.4, 0.14, 0.08, [-0.4, 0.06, 0.06]],
				[0.80, [0.3, 0.1, -0.2], [0, 0.6, -0.7], [0, 1, 0], 0.1, 0.04, 0.03, [-0.3, 0.1, -0.24]],
			]
		"bind":
			# Binden: Klinge hoch an die gegnerische drücken und dort halten
			d.label = "Bind (combo)"
			d.duration = 0.9
			d.hit = 0.42
			d.trail = [0.34, 0.46]
			rows = [
				[0.26, [0.3, 0.3, -0.08], [0.2, 0.85, -0.45], [1, 0, 0], -0.3, 0.05, 0.0],
				[0.42, [0.04, 0.28, -0.55], [-0.12, 0.45, -1], [1, 0, 0], 0.12, -0.2, 0.08],
				[0.64, [0.0, 0.25, -0.52], [-0.18, 0.38, -1], [1, 0, 0], 0.16, -0.22, 0.1],
				[0.84, [0.2, 0.15, -0.4], [0, 0.5, -0.8], [0, 1, 0], 0.05, -0.08, 0.03],
			]
		"sever":
			# Durchtrennen: hoch über der linken Schulter ausholen, schwer diagonal nach rechts unten
			d.label = "Sever (combo finisher)"
			d.duration = 1.25
			d.hit = 0.48
			d.trail = [0.38, 0.64]
			rows = [
				[0.34, [-0.18, 0.52, 0.04], [-0.5, 0.65, 0.55], [0, 1, 0.3], 0.62, 0.12, 0.0],
				[0.48, [0.06, 0.26, -0.58], [0.25, 0.2, -1], [0, 1, 0.2], 0.0, -0.3, 0.12],
				[0.62, [0.42, -0.06, -0.24], [0.8, -0.5, -0.3], [0, 1, 0], -0.55, -0.35, 0.2],
				[0.82, [0.32, 0.1, -0.35], [0.2, 0.5, -0.7], [0, 1, 0], -0.2, -0.1, 0.06],
			]
		"rake":
			# Reißen (Axtbart): weit vorn einhaken, dann ruckartig zurück zur Hüfte ziehen
			d.label = "Beard Hook (greataxe)"
			d.duration = 1.05
			d.hit = 0.44
			d.trail = [0.3, 0.46]
			rows = [
				[0.28, [0.22, 0.42, -0.2], [0.05, 0.8, -0.6], [1, 0, 0], -0.2, 0.05, 0.0],
				[0.44, [0.1, 0.2, -0.6], [0.0, -0.1, -1], [1, 0, 0], 0.1, -0.28, 0.1],
				[0.6, [0.3, 0.02, 0.0], [0.15, -0.3, -1], [1, 0, 0], -0.35, 0.15, 0.06],
				[0.82, [0.28, 0.1, -0.22], [0.05, 0.5, -0.85], [0, 1, 0], -0.1, 0.0, 0.02],
			]
		"flurry":
			# Stichfolge: drei kurze Stiche, dazwischen kaum zurückziehen
			d.label = "Flurry (dagger)"
			d.duration = 1.0
			d.hit = 0.3
			d.trail = [0.24, 0.66]
			rows = [
				[0.2, [0.28, 0.1, 0.0], [0.05, 0.1, -1], [0, 1, 0], -0.35, 0.0, 0.02],
				[0.3, [0.12, 0.15, -0.52], [-0.05, 0.05, -1], [0, 1, 0], 0.1, -0.22, 0.08],
				[0.38, [0.26, 0.08, -0.12], [0.05, 0.1, -1], [0, 1, 0], -0.25, -0.1, 0.06],
				[0.46, [0.08, 0.04, -0.54], [-0.1, -0.05, -1], [0, 1, 0], 0.15, -0.26, 0.1],
				[0.54, [0.26, 0.16, -0.12], [0.05, 0.12, -1], [0, 1, 0], -0.25, -0.12, 0.06],
				[0.62, [0.14, 0.22, -0.55], [-0.02, 0.12, -1], [0, 1, 0], 0.12, -0.26, 0.1],
				[0.82, [0.26, 0.12, -0.36], [-0.12, 0.4, -0.9], [0, 1, 0], 0.0, -0.08, 0.03],
			]
		"hollowed_stagger":
			# Taumeln: nach hinten geworfen, Waffe und freie Hand weichen zur Seite (vorher fest im Code)
			d.label = ENEMY_LABELS[clip_name]
			d.duration = 0.55
			d.hit = 0.385
			d.trail = [1.1, 1.2]
			rows = []
			for tt in [0.12, 0.25, 0.385, 0.55, 0.72]:
				var w := sin(minf(tt * 1.3, 1.0) * PI)
				rows.append([tt, _scaled(Vector3(0.42, -0.1, 0.12)), [0.3, 0.4, 0.6], [0, 1, 0], 0.25 * w, 0.45 * w, 0.0,
					_scaled(Vector3(-0.42, -0.05, 0.05)), [-0.35, 0.0, -1.0], {"leg_l_knee": 0.2 * w, "leg_r_knee": 0.15 * w}])
		"hollowed_death":
			# Tod: knickt ein und fällt nach vorn, bleibt liegen (hold_end); danach versinkt er (Code)
			d.label = ENEMY_LABELS[clip_name]
			d.duration = 1.2
			d.hit = 0.375
			d.trail = [1.1, 1.2]
			d.hold_end = true
			rows = []
			for tt in [0.1, 0.2, 0.3, 0.375, 0.6]:
				var w := clampf(tt * 1.2 * 2.2, 0.0, 1.0)
				var f := 1.0 - pow(1.0 - w, 3.0)
				rows.append([tt, _scaled(Vector3(0.45, -0.3, 0.1)), [0.2, -0.6, -0.75], [0, 1, 0], 0.0, 0.0, 0.0,
					_scaled(Vector3(-0.4, -0.3, 0.0)), [-0.35, -0.3, -1.0], {"leg_l_knee": 0.3 * w, "leg_r_knee": 0.1 * w, "fall": 1.45 * f, "sink": 0.3 * w}])
		_:
			d.label = "Heavy Strike"
			d.duration = 1.2
			d.hit = 0.42
			d.trail = [0.36, 0.62]
			rows = [
				[0.34, [0.30, 0.62, 0.02], [0.15, 0.55, 0.82], [1, 0, 0], -0.2, 0.15, 0.0],
				[0.42, [0.10, 0.30, -0.56], [0, 0.35, -1], [1, 0, 0], 0.0, -0.25, 0.1],
				[0.56, [0.08, -0.02, -0.36], [0, -0.65, -0.75], [1, 0, 0], 0.05, -0.4, 0.18],
				[0.78, [0.22, 0.05, -0.42], [0.0, 0.2, -1], [1, 0, 0], 0.0, -0.2, 0.08],
			]
	var keys: Array = []
	for r in rows:
		var shp: Array = r[7] if r.size() > 7 else [sh.x, sh.y, sh.z]
		var shfr: Array = r[8] if r.size() > 8 else [shf.x, shf.y, shf.z]
		var key := {"t": r[0], "grip": r[1], "dir": r[2], "flat": r[3], "twist": r[4], "lean": r[5], "drop": r[6],
			"shield": shp, "shield_front": shfr}
		if r.size() > 9:
			key.merge(r[9])
		keys.append(key)
	d.keys = keys
	var c := _from_json(d)
	# Sicherheit: Griff und Schildhand bleiben in Armreichweite (sonst reißt die Hand von der Waffe ab)
	for k in c.keys:
		k.grip = _in_reach(k.grip, ShadowBody.SHOULDER_R)
		k.shield = _in_reach(k.shield, ShadowBody.SHOULDER_L)
	return c


## Pose-Koordinaten wie ShadowBody._scale_pose (feste Werte aus dem alten Code -> Clip-Koordinaten)
static func _scaled(v: Vector3) -> Array:
	return [v.x * 0.95, 0.43 + (v.y - 0.47) * ShadowBody.POSE_SCALE, v.z * ShadowBody.POSE_SCALE]


static func _in_reach(p: Vector3, shoulder: Vector3) -> Vector3:
	var max_r := ShadowBody.UPPER_ARM + ShadowBody.LOWER_ARM - 0.01
	var v := p - shoulder
	return shoulder + v.limit_length(max_r)
