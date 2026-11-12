class_name PoseLibrary
extends RefCounted
## Waffenhaltungen und Ablagen als Daten (bearbeitbar in der Animationswerkstatt, Modus "Weapon poses"/"Stowed gear").
##
## data/poses/<waffe>.json  – je Waffe: Haltung im Stehen (idle), beim Gehen (walk), Kampfhaltung (guard),
##                            beidhändig (idle_2h, guard_2h), weggesteckt (stow) und Griffpunkt der linken Hand.
##                            Waffen-IDs: kiln / rimefall / glowmire (Kulturwaffe), spear, greataxe, dagger.
## data/poses/gear.json      – Schild auf dem Rücken, Zweithand-Dolch am Gürtel, Laterne am Gürtel / vorgehalten.
##
## Alle Positionen in Brust-Koordinaten der Figur (x rechts, y hoch, -z vorn), außer `stow` mit space = "hips".
## "dir" = Richtung der Klinge/Spitze, "flat" = Breitseite, "off"/"off_front" = linke Hand (Schild, Dolch) und ihre Ausrichtung.

const DIR := "res://data/poses/"
const WEAPONS := ["kiln", "rimefall", "glowmire", "spear", "greataxe", "dagger"]
const HELD_POSES := ["idle", "walk", "guard", "idle_2h", "guard_2h"]
const POSE_LABELS := {"idle": "Standing", "walk": "Walking", "guard": "Combat stance", "idle_2h": "Standing, two-handed",
	"guard_2h": "Combat stance, two-handed", "stow": "Stowed"}
const GEAR_ITEMS := ["shield_back", "dagger_stow", "lantern_belt", "lantern_held"]
const GEAR_LABELS := {"shield_back": "Shield on the back", "dagger_stow": "Off-hand dagger at the belt",
	"lantern_belt": "Lantern at the belt", "lantern_held": "Lantern held out"}

static var _cache := {}
static var version := 0  ## steigt bei jeder Änderung (Körper lesen dann neu)


## Haltungen einer Waffe (vollständig, fehlende Werte aus den Vorgaben).
static func weapon(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var d := defaults(id)
	var f := _load(id)
	for k in f:
		if d.has(k) and d[k] is Dictionary and f[k] is Dictionary:
			for kk in f[k]:
				d[k][kk] = f[k][kk]
		else:
			d[k] = f[k]
	_cache[id] = d
	return d


static func gear() -> Dictionary:
	return weapon("gear")


static func mark_changed() -> void:
	version += 1


static func reload() -> void:
	_cache.clear()
	version += 1


static func save(id: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(DIR + id + ".json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(_to_text(weapon(id)))
	f.close()
	return OK


## Werte zurück auf die eingebauten Vorgaben (nur im Speicher, bis gespeichert wird).
static func reset_entry(id: String, entry: String) -> void:
	var d := weapon(id)
	d[entry] = defaults(id)[entry]
	version += 1


# ------------------------------------------------------------------

static func _pose(v: Vector3) -> Vector3:
	# alte Posen-Koordinaten -> Brust-Koordinaten (wie ShadowBody._scale_pose)
	return Vector3(v.x * 0.95, 0.43 + (v.y - 0.47) * 0.92, v.z * 0.92)


static func _held(grip: Vector3, dir: Vector3, flat: Vector3, off: Vector3, off_front: Vector3) -> Dictionary:
	return {"grip": grip, "dir": dir.normalized(), "flat": flat.normalized(), "off": off, "off_front": off_front.normalized()}


## Eingebaute Vorgaben (entsprechen den bisherigen festen Werten im Code).
static func defaults(id: String) -> Dictionary:
	if id == "gear":
		return {
			"shield_back": {"pos": Vector3(0.02, 0.2, 0.27), "front": Vector3(0.0, 0.12, 1.0).normalized()},
			"dagger_stow": {"pos": Vector3(-0.14, 0.02, 0.17), "dir": Vector3(-1.0, -0.25, -0.1).normalized(), "hint": Vector3(0, 0, 1)},
			"lantern_belt": {"pos": Vector3(0.21, 0.04, 0.0), "yaw": -0.35},
			"lantern_held": {"pos": Vector3(-0.12, 0.32, -0.5)},
		}
	var off_idle := _pose(Vector3(-0.28, -0.18, -0.12))
	var d := {
		"idle": _held(_pose(Vector3(0.27, -0.15, -0.16)), Vector3(0.12, -0.32, -1.0), Vector3(1, 0, 0), off_idle, Vector3(-0.5, 0.0, -0.85)),
		"walk": _held(_pose(Vector3(0.30, -0.16, 0.0)), Vector3(0.25, -0.75, 0.55), Vector3(1, 0, 0), off_idle, Vector3(-0.5, 0.0, -0.85)),
		"guard": _held(Vector3(0.30, 0.12, -0.32), Vector3(-0.12, 0.55, -0.85), Vector3(1, 0, 0.3), Vector3(-0.2, 0.2, -0.4), Vector3(0.18, 0.05, -1.0)),
		"idle_2h": {}, "guard_2h": {},
		"stow": {"space": "hips", "pos": Vector3(-0.21, 0.1, -0.12), "dir": Vector3(-0.14, -0.6, 0.79).normalized(), "hint": Vector3(1, 0, 0)},
		"two_hand_offset": 0.0,
	}
	d.idle_2h = d.idle.duplicate()
	d.guard_2h = d.guard.duplicate()
	match id:
		"rimefall":
			d.stow.dir = Vector3(-0.12, -0.9, 0.42).normalized()
		"spear":
			d.two_hand_offset = 0.42
			d.idle_2h = _held(_pose(Vector3(0.24, -0.08, -0.12)), Vector3(-0.05, -0.25, -1.0), Vector3(1, 0, 0), off_idle, Vector3(-0.5, 0, -0.85))
			d.guard_2h = _held(_pose(Vector3(0.22, 0.0, -0.2)), Vector3(-0.08, 0.12, -1.0), Vector3(1, 0, 0.3), Vector3(-0.2, 0.2, -0.4), Vector3(0.18, 0.05, -1.0))
			d.stow = {"space": "chest", "pos": Vector3(0.12, -0.04, 0.35), "dir": Vector3(-0.5, 0.85, 0.06).normalized(), "hint": Vector3(0, 0, 1)}
		"greataxe":
			d.two_hand_offset = 0.3
			d.idle_2h = _held(_pose(Vector3(0.12, 0.1, -0.28)), Vector3(0.45, 0.7, -0.45), Vector3(1, 0, 0), off_idle, Vector3(-0.5, 0, -0.85))
			d.guard_2h = _held(_pose(Vector3(0.12, 0.14, -0.3)), Vector3(0.35, 0.8, -0.45), Vector3(1, 0, 0.3), Vector3(-0.2, 0.2, -0.4), Vector3(0.18, 0.05, -1.0))
			d.stow = {"space": "chest", "pos": Vector3(-0.12, -0.12, 0.34), "dir": Vector3(0.36, 0.92, 0.06).normalized(), "hint": Vector3(0, 0, 1)}
	return d


static func _load(id: String) -> Dictionary:
	var path := DIR + id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PoseLibrary: %s ist kein gültiges JSON" % path)
		return {}
	return _from_json(parsed)


static func _from_json(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _from_json(v[k])
		return out
	if v is Array and v.size() == 3 and (v[0] is float or v[0] is int):
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return v


static func _to_json(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _to_json(v[k])
		return out
	if v is Vector3:
		return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
	if v is float:
		return snappedf(v, 0.001)
	return v


## Lesbar: ein Eintrag pro Zeile.
static func _to_text(d: Dictionary) -> String:
	var j: Dictionary = _to_json(d)
	var lines: Array[String] = []
	for k in j:
		lines.append("\t%s: %s" % [JSON.stringify(k), JSON.stringify(j[k], "", false)])
	return "{\n" + ",\n".join(lines) + "\n}\n"
