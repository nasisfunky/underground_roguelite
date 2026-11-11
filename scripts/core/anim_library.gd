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
const CLIPS := ["swing_0", "swing_1", "heavy", "thrust"]

static var _cache := {}


static func clip(clip_name: String) -> Dictionary:
	if _cache.has(clip_name):
		return _cache[clip_name]
	var c := _load_file(clip_name)
	if c.is_empty():
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
		})
	keys.sort_custom(func(a, b): return a.t < b.t)
	var tr: Array = d.get("trail", [0.32, 0.62])
	return {
		"name": str(d.get("name", "")),
		"label": str(d.get("label", d.get("name", ""))),
		"duration": float(d.get("duration", 0.95)),
		"hit": float(d.get("hit", 0.44)),
		"trail": Vector2(float(tr[0]), float(tr[1])),
		"keys": keys,
	}


static func _r(x: float) -> float:
	return snappedf(x, 0.001)


static func _a(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


static func _to_json(c: Dictionary) -> Dictionary:
	var keys: Array = []
	for k in c.keys:
		keys.append({"t": _r(k.t), "grip": _a(k.grip), "dir": _a(k.dir), "flat": _a(k.flat),
			"twist": _r(k.twist), "lean": _r(k.lean), "drop": _r(k.drop),
			"shield": _a(k.shield), "shield_front": _a(k.shield_front)})
	return {"name": c.name, "label": c.label, "duration": _r(c.duration), "hit": _r(c.hit),
		"trail": [_r(c.trail.x), _r(c.trail.y)], "keys": keys}


## Lesbares JSON: Kopfdaten oben, ein Keyframe pro Zeile.
static func _to_text(c: Dictionary) -> String:
	var j := _to_json(c)
	var lines: Array[String] = []
	for k in j.keys:
		lines.append("\t\t" + JSON.stringify(k, "", false))
	return "{\n\t\"name\": %s,\n\t\"label\": %s,\n\t\"duration\": %s,\n\t\"hit\": %s,\n\t\"trail\": %s,\n\t\"keys\": [\n%s\n\t]\n}\n" % [
		JSON.stringify(j.name), JSON.stringify(j.label), JSON.stringify(j.duration), JSON.stringify(j.hit),
		JSON.stringify(j.trail), ",\n".join(lines)]


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
		keys.append({"t": r[0], "grip": r[1], "dir": r[2], "flat": r[3], "twist": r[4], "lean": r[5], "drop": r[6],
			"shield": [sh.x, sh.y, sh.z], "shield_front": [shf.x, shf.y, shf.z]})
	d.keys = keys
	return _from_json(d)
