class_name CreatureAnim
extends RefCounted
## Keyframe-Animationen der Gegner ohne Shade-Körper (Splinterkin, Grimhauler, Willamber) und das Schweben
## des Hollow One. Jede Aktion besteht vollständig aus Keys: je Key eine komplette Haltung (Drehung je Gelenk
## in Grad, Positionen in m). Dazwischen weich interpoliert (Catmull-Rom, Drehungen über Quaternionen).
## Automatisch bleiben nur Bein-IK (Füße sind Ziele), Schattenfäden, Effekte und die Blickrichtung.
##
## Startfassung: Ohne Datei wird die frühere, prozedurale Bewegung einmal abgetastet und auf wenige Keys
## verdichtet ("baken"); jeder Gegner meldet dafür beim Start einen Abtaster an (ensure()).
##
## data/enemy_anims/<gegner>.json:
##   {"version": 2, "actions": {"<aktion>": {"keys": [{"t": 0.25, "ch": {"chest": [x, y, z], ...}}, ...]}}}
## Drehungen: Euler-Winkel in Grad, Reihenfolge wie WillfaultModel.rot (X, dann Y, dann Z um die eigenen Achsen).
## Gespeichert werden nur Aktionen, die von der Startfassung abweichen.
## Hollowed (Shade-Körper): Angriff, Taumeln und Tod sind normale Clips (AnimLibrary.ENEMY_CLIPS).

const DIR := "res://data/enemy_anims/"
const VERSION := 2
const DEG := PI / 180.0
const MAX_KEYS := 28
const TOL_ROT := 1.5  ## Grad: so genau trifft die Startfassung die alte Bewegung
const TOL_POS := 0.006  ## m

## Aktion: [id, Anzeige, Schleife?, Dauer (s), Erklärung]. Kanal: [id, Anzeige, "rot"/"pos"].
const CREATURES := {
	"splinterkin": {
		"label": "Splinterkin",
		"actions": [
			["idle", "Standing (loop)", true, 2.732, "Standing still, breathing."],
			["move", "Scuttling (loop)", true, 0.3, "One step cycle at 3 m/s; plays faster or slower with its speed and turns with its walking direction."],
			["windup", "Crouch before the leap", false, 0.6, "Eyes flare up, it ducks (0.6 s)."],
			["leap", "Leap", false, 0.32, "The jump itself, deals damage (0.32 s)."],
			["recover", "Landing / recover", false, 0.85, "Defenceless after landing (0.85 s)."],
			["stagger", "Staggered", false, 0.6, "After a heavy hit or parry; stretched to the stagger length (0.55-1.4 s)."],
			["death", "Death", false, 1.0, "Collapses, then shrinks away."],
			["knockdown", "Knocked down", false, 1.6, "Thrown onto its back by a very heavy hit, then scrambles up."],
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
			["attack", "Overhead slam", false, 4.8, "Impact (sparks, shockwave) at 36 %."],
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
			["axe", "Axe (sits in the hand)", "rot"],
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
			["sink", "Sinking into the shadow", false, 0.4, "Slips back into the shadow (end pose = hidden)."],
		],
		"channels": [
			["rise_pos", "Whole body (down = in the shadow)", "pos"],
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
			["legR_ft", "Right foot", "rot"],
			["legL_th", "Left thigh", "rot"],
			["legL_sh", "Left shin", "rot"],
			["legL_ft", "Left foot", "rot"],
		],
	},
	"hollow_one": {
		"label": "Hollow One",
		"actions": [
			["hover", "Hovering (loop)", true, 13.963, "Wide, calm figure of eight."],
			["attack", "Strike glide", false, 3.4, "Glides forward with the strike and back. The arms are the clip \"Enemy: Hollow One strike\"."],
		],
		"channels": [
			["drift", "Hover position", "pos"],
			["tilt", "Body tilt", "rot"],
		],
	},
}

static var _cache := {}  ## gegner -> {aktion: {"keys": [{"t", "ch": {kanal: Vector3}}]}}  (Grad bzw. m)
static var _defaults := {}  ## gegner -> Startfassung (gleiche Form)
static var _prep := {}  ## "gegner/aktion" -> vorbereitete Keys (Quaternionen) fürs Abspielen


# ------------------------------------------------------------------
# Daten
# ------------------------------------------------------------------

## Startfassung erzeugen, falls noch nicht geschehen. sampler(aktion, k) -> {kanal: Quaternion | Vector3}
static func ensure(creature: String, sampler: Callable) -> void:
	if _defaults.has(creature):
		return
	var d := {}
	for a in CREATURES[creature].actions:
		var act: String = a[0]
		d[act] = {"keys": bake(creature, act, func(kk: float) -> Dictionary: return sampler.call(act, kk))}
	_defaults[creature] = d
	_cache.erase(creature)
	invalidate(creature)


static func has_defaults(creature: String) -> bool:
	return _defaults.has(creature)


## Startfassung einer Aktion (Kopie).
static func default_keys(creature: String, action: String) -> Array:
	if not _defaults.has(creature) or not _defaults[creature].has(action):
		return []
	return _copy_keys(_defaults[creature][action].keys)


## Alle Aktionen eines Gegners (live bearbeitet von der Werkstatt). Datei vor Startfassung.
static func data(creature: String) -> Dictionary:
	if _cache.has(creature):
		return _cache[creature]
	var d := {}
	for a in CREATURES[creature].actions:
		d[a[0]] = {"keys": default_keys(creature, a[0])}
	var path := DIR + creature + ".json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and int(parsed.get("version", 1)) >= VERSION and parsed.get("actions") is Dictionary:
			var acts: Dictionary = parsed.actions
			for act in acts:
				if not d.has(act) or not (acts[act] is Dictionary):
					continue
				var keys: Array = []
				for k in acts[act].get("keys", []):
					var ch := {}
					var src: Dictionary = k.get("ch", {})
					for c in src:
						var v: Array = src[c]
						if v.size() == 3:
							ch[c] = Vector3(float(v[0]), float(v[1]), float(v[2]))
					keys.append({"t": clampf(float(k.get("t", 0.5)), 0.0, 1.0), "ch": ch})
				if keys.is_empty():
					continue
				keys.sort_custom(func(a, b): return a.t < b.t)
				_fill_missing(creature, act, keys)
				d[act].keys = keys
		elif parsed is Dictionary:
			push_warning("CreatureAnim: %s hat das alte Zusatz-Format und wird ignoriert (beim Speichern als .legacy.json gesichert)" % path)
		else:
			push_warning("CreatureAnim: %s ist kein gültiges JSON" % path)
	if _defaults.has(creature):
		_cache[creature] = d
	return d


## Kanäle, die in einem Key fehlen, aus der Startfassung an dieser Stelle ergänzen.
static func _fill_missing(creature: String, action: String, keys: Array) -> void:
	for k in keys:
		for c in CREATURES[creature].channels:
			if not k.ch.has(c[0]):
				var v: Variant = sample_default(creature, action, k.t).get(c[0])
				if v is Quaternion:
					k.ch[c[0]] = to_euler_deg(v)
				elif v is Vector3:
					k.ch[c[0]] = v
				else:
					k.ch[c[0]] = Vector3.ZERO


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
	invalidate(creature)


static func set_data(creature: String, d: Dictionary) -> void:
	_cache[creature] = d
	invalidate(creature)


## Nach jeder Änderung an den Keys aufrufen (Werkstatt), damit das Abspielen die neuen Werte nimmt.
static func invalidate(creature := "") -> void:
	if creature == "":
		_prep.clear()
		return
	for a in CREATURES[creature].actions:
		_prep.erase(creature + "/" + a[0])


static func copy(creature: String) -> Dictionary:
	return data(creature).duplicate(true)


static func is_modified(creature: String, action: String) -> bool:
	return not _same_keys(data(creature)[action].keys, default_keys(creature, action))


static func save(creature: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := DIR + creature + ".json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and int(parsed.get("version", 1)) < VERSION:
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(DIR + creature + ".legacy.json"))
	var d := data(creature)
	var lines: Array[String] = []
	for a in CREATURES[creature].actions:
		var act: String = a[0]
		if not is_modified(creature, act):
			continue
		var keys: Array[String] = []
		for k in d[act].keys:
			var ch := {}
			for c in CREATURES[creature].channels:
				var v: Vector3 = k.ch.get(c[0], Vector3.ZERO)
				ch[c[0]] = [snappedf(v.x, 0.01 if c[2] == "rot" else 0.0001), snappedf(v.y, 0.01 if c[2] == "rot" else 0.0001), snappedf(v.z, 0.01 if c[2] == "rot" else 0.0001)]
			keys.append("\t\t\t" + JSON.stringify({"t": snappedf(k.t, 0.001), "ch": ch}, "", false))
		lines.append("\t\t%s: {\"keys\": [\n%s\n\t\t]}" % [JSON.stringify(act), ",\n".join(keys)])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string("{\n\t\"version\": %d,\n\t\"actions\": {\n%s\n\t}\n}\n" % [VERSION, ",\n".join(lines)])
	f.close()
	return OK


static func _copy_keys(keys: Array) -> Array:
	var out: Array = []
	for k in keys:
		out.append({"t": k.t, "ch": (k.ch as Dictionary).duplicate()})
	return out


static func _same_keys(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i].t - b[i].t) > 0.0005:
			return false
		for c in a[i].ch:
			if not b[i].ch.has(c) or (a[i].ch[c] as Vector3).distance_to(b[i].ch[c]) > 0.002:
				return false
	return true


# ------------------------------------------------------------------
# Umrechnung
# ------------------------------------------------------------------

## Euler (Grad, X dann Y dann Z wie WillfaultModel.rot) -> Quaternion
static func from_euler_deg(v: Vector3) -> Quaternion:
	return Basis.from_euler(v * DEG, EULER_ORDER_XYZ).get_rotation_quaternion()


static func to_euler_deg(q: Quaternion) -> Vector3:
	return Basis(q.normalized()).get_euler(EULER_ORDER_XYZ) / DEG


# ------------------------------------------------------------------
# Abspielen
# ------------------------------------------------------------------

## Komplette Haltung zur normierten Zeit k (0..1): {kanal: Quaternion (rot) | Vector3 (pos)}.
static func sample(creature: String, action: String, k: float) -> Dictionary:
	var id := creature + "/" + action
	if not _prep.has(id):
		var d := data(creature)
		if not d.has(action):
			return {}
		_prep[id] = _prepare(creature, d[action].keys)
	var info := action_info(creature, action)
	return _eval(_prep[id], info[2] if not info.is_empty() else false, k)


## Startfassung abspielen (ohne Bearbeitungen), z. B. zum Ergänzen fehlender Kanäle.
static func sample_default(creature: String, action: String, k: float) -> Dictionary:
	if not _defaults.has(creature) or not _defaults[creature].has(action):
		return {}
	var info := action_info(creature, action)
	return _eval(_prepare(creature, _defaults[creature][action].keys), info[2], k)


static func _prepare(creature: String, keys: Array) -> Array:
	var out: Array = []
	for k in keys:
		var ch := {}
		for c in CREATURES[creature].channels:
			var v: Vector3 = k.ch.get(c[0], Vector3.ZERO)
			ch[c[0]] = from_euler_deg(v) if c[2] == "rot" else v
		out.append({"t": k.t, "ch": ch})
	out.sort_custom(func(a, b): return a.t < b.t)
	return out


## Auswerten vorbereiteter Keys ({"t", "ch": {kanal: Quaternion|Vector3}}).
static func _eval(keys: Array, loop: bool, k: float) -> Dictionary:
	var n := keys.size()
	if n == 0:
		return {}
	if n == 1:
		return (keys[0].ch as Dictionary).duplicate()
	var i1: int
	var t1: float
	var t2: float
	var t0: float
	var t3: float
	var p0: Dictionary
	var p1: Dictionary
	var p2: Dictionary
	var p3: Dictionary
	if loop:
		k = fposmod(k, 1.0)
		var first: float = keys[0].t
		var last: float = keys[n - 1].t
		if k < first:
			k += 1.0
		# Segment i1 -> i1+1 (mit Umlauf); Zeiten auf eine durchgehende Achse gelegt
		i1 = n - 1
		for i in n - 1:
			if k >= keys[i].t and k < keys[i + 1].t:
				i1 = i
				break
		t1 = _lt(keys, i1)
		t2 = _lt(keys, i1 + 1)
		t0 = _lt(keys, i1 - 1)
		t3 = _lt(keys, i1 + 2)
		p0 = keys[posmod(i1 - 1, n)].ch
		p1 = keys[i1].ch
		p2 = keys[posmod(i1 + 1, n)].ch
		p3 = keys[posmod(i1 + 2, n)].ch
		if last - first <= 0.0:
			return (keys[0].ch as Dictionary).duplicate()
	else:
		k = clampf(k, 0.0, 1.0)
		if k <= keys[0].t:
			return (keys[0].ch as Dictionary).duplicate()
		if k >= keys[n - 1].t:
			return (keys[n - 1].ch as Dictionary).duplicate()
		i1 = 0
		while i1 < n - 2 and k >= keys[i1 + 1].t:
			i1 += 1
		t1 = keys[i1].t
		t2 = keys[i1 + 1].t
		p1 = keys[i1].ch
		p2 = keys[i1 + 1].ch
		if i1 > 0:
			t0 = keys[i1 - 1].t
			p0 = keys[i1 - 1].ch
		else:
			t0 = t1 - (t2 - t1)
			p0 = p1
		if i1 + 2 < n:
			t3 = keys[i1 + 2].t
			p3 = keys[i1 + 2].ch
		else:
			t3 = t2 + (t2 - t1)
			p3 = p2
	var span := maxf(t2 - t1, 1e-5)
	var w := clampf((k - t1) / span, 0.0, 1.0)
	var out := {}
	for c in p1:
		var a: Variant = p1[c]
		var b: Variant = p2.get(c, a)
		var pre: Variant = p0.get(c, a)
		var post: Variant = p3.get(c, b)
		if a is Quaternion:
			var qa: Quaternion = a
			var qb: Quaternion = b
			var qp: Quaternion = pre
			var qn: Quaternion = post
			if qb.dot(qa) < 0.0:
				qb = -qb
			if qp.dot(qa) < 0.0:
				qp = -qp
			if qn.dot(qb) < 0.0:
				qn = -qn
			out[c] = qa.spherical_cubic_interpolate_in_time(qb, qp, qn, w, span, t0 - t1, t3 - t1).normalized()
		else:
			out[c] = (a as Vector3).cubic_interpolate_in_time(b, pre, post, w, span, t0 - t1, t3 - t1)
	return out


## Zeit eines Keys auf der durchgehenden Achse einer Schleife (Index darf über das Ende hinaus laufen).
static func _lt(keys: Array, j: int) -> float:
	var n := keys.size()
	return keys[posmod(j, n)].t + floorf(float(j) / n)


## Zwei Haltungen mischen (w = 0: a, 1: b).
static func blend(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	if w >= 1.0 or a.is_empty():
		return b
	if w <= 0.0:
		return a
	var out := b.duplicate()
	for c in b:
		if not a.has(c):
			continue
		if b[c] is Quaternion:
			var qa: Quaternion = a[c]
			out[c] = qa.slerp(b[c], w)
		else:
			out[c] = (a[c] as Vector3).lerp(b[c], w)
	return out


## Haltung auf Gelenke anwenden: nodes = {kanal: Node3D}; Drehungen absolut, Positionen absolut.
static func apply(p: Dictionary, nodes: Dictionary) -> void:
	for c in nodes:
		if not p.has(c):
			continue
		var n: Node3D = nodes[c]
		if p[c] is Quaternion:
			n.quaternion = p[c]
		else:
			n.position = p[c]


# ------------------------------------------------------------------
# Startfassung verdichten
# ------------------------------------------------------------------

## Abtasten und auf möglichst wenige Keys verdichten, die die Bewegung auf TOL_ROT/TOL_POS genau treffen.
## sampler(k) -> {kanal: Quaternion | Vector3}. Ergebnis im Datei-Format (Grad bzw. m).
static func bake(creature: String, action: String, sampler: Callable) -> Array:
	var info := action_info(creature, action)
	var loop: bool = info[2]
	var dur: float = info[3]
	var n := clampi(roundi(dur * 40.0), 40, 160)
	var dense: Array = []  # vorbereitete Form
	var count := n if loop else n + 1
	for i in count:
		var kk := float(i) / n
		var p: Dictionary = sampler.call(kk)
		var ch := {}
		for c in CREATURES[creature].channels:
			var v: Variant = p.get(c[0])
			if v == null:
				v = Quaternion.IDENTITY if c[2] == "rot" else Vector3.ZERO
			ch[c[0]] = v
		dense.append({"t": kk, "ch": ch})
	# Hemisphären der Quaternionen durchgehend halten
	for i in range(1, dense.size()):
		for c in dense[i].ch:
			var v: Variant = dense[i].ch[c]
			if v is Quaternion and (v as Quaternion).dot(dense[i - 1].ch[c]) < 0.0:
				dense[i].ch[c] = -(v as Quaternion)
	var sel: Array[int] = []
	sel.append(0)
	sel.append(int(n / 2.0) if loop else n)
	var errs: Array[float] = []
	errs.resize(dense.size())
	var dirty_from := 0
	var dirty_to := dense.size() - 1
	while true:
		var keys: Array = []
		for s in sel:
			keys.append(dense[s])
		for i in range(dirty_from, dirty_to + 1):
			errs[i] = _err(_eval(keys, loop, dense[i].t), dense[i].ch)
		var worst := -1
		var worst_e := 1.0
		for i in errs.size():
			if errs[i] > worst_e and not sel.has(i):
				worst_e = errs[i]
				worst = i
		if worst < 0 or sel.size() >= MAX_KEYS:
			break
		sel.append(worst)
		sel.sort()
		# Einfluss eines Keys: zwei Nachbarn je Seite (kubisch)
		var at := sel.find(worst)
		if loop:
			dirty_from = 0
			dirty_to = dense.size() - 1
		else:
			dirty_from = sel[maxi(at - 2, 0)]
			dirty_to = sel[mini(at + 2, sel.size() - 1)]
	var out: Array = []
	for s in sel:
		var ch := {}
		for c in CREATURES[creature].channels:
			var v: Variant = dense[s].ch[c[0]]
			ch[c[0]] = to_euler_deg(v) if v is Quaternion else v
		out.append({"t": snappedf(dense[s].t, 0.0005), "ch": ch})
	return out


static func _err(a: Dictionary, b: Dictionary) -> float:
	var e := 0.0
	for c in b:
		if not a.has(c):
			continue
		if b[c] is Quaternion:
			e = maxf(e, rad_to_deg((a[c] as Quaternion).angle_to(b[c])) / TOL_ROT)
		else:
			e = maxf(e, (a[c] as Vector3).distance_to(b[c]) / TOL_POS)
	return e


# ------------------------------------------------------------------
# Überblenden zwischen Aktionen
# ------------------------------------------------------------------

## Spielt Aktionen eines Gegners und blendet beim Wechsel kurz über (fade_len s; 0 = hart, Werkstatt).
class Track:
	var creature := ""
	var action := ""
	var fade_len := 0.15
	var last := {}
	var _from := {}
	var _fade := 0.0

	func _init(c: String, fade := 0.15) -> void:
		creature = c
		fade_len = fade

	func pose(act: String, k: float, delta: float) -> Dictionary:
		return push(act, CreatureAnim.sample(creature, act, k), delta)

	## Fertige Haltung unter einem Namen weitergeben (z. B. Mischung aus Stehen und Laufen).
	func push(label: String, p: Dictionary, delta: float) -> Dictionary:
		if label != action:
			if action != "" and fade_len > 0.0 and not last.is_empty():
				_from = last
				_fade = fade_len
			action = label
		if _fade > 0.0 and fade_len > 0.0:
			_fade = maxf(_fade - delta, 0.0)
			var w := 1.0 - _fade / fade_len
			p = CreatureAnim.blend(_from, p, w * w * (3.0 - 2.0 * w))
		last = p
		return p
