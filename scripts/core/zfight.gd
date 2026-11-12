class_name ZFight
extends RefCounted
## Z-Fighting finden und vermeiden (Arbeitsweise aus dem Shooter-Projekt übernommen).
##
## Zwei Flächen, die in (fast) einer Ebene liegen, in dieselbe Richtung schauen und sich
## überlappen, flackern durcheinander, sobald sich die Kamera bewegt: Der Tiefenpuffer kann
## nicht entscheiden, welche vorne ist. Typisch: zwei Wandblöcke, die sich an einer Ecke
## treffen und oben bündig abschließen; eine Platte, die exakt auf einer anderen liegt.
##
##  fix(root)   beim Levelaufbau: Kisten (BoxMesh), deren Flächen sich so treffen, werden um
##              ein paar Millimeter vergrößert, bis die Flächen auseinanderliegen
##              (jede Kiste höchstens MAX_BUMPS-mal, sonst wächst eine Platte zum Klotz).
##  scan(root)  im Test: alle sichtbaren Dreiecke, liefert die verbleibenden Paare mit Ort.
##
## Regeln beim Bauen (damit erst gar nichts flackert):
##  - Was auf einer Fläche liegt, steht mindestens 1 cm davon ab oder steckt sichtbar darin,
##    nie bündig. Abziehbilder (Brandflecken, Ringe) liegen 2-3 cm über dem Boden.
##  - Wandteile, die sich treffen, bekommen unterschiedliche Höhen/Tiefen oder überlappen
##    deutlich (> 2 cm), nie exakt dieselbe Außenfläche.
##  - Gleiche Farbe auf beiden Flächen flackert zwar auch, sieht aber gleich aus: zählt nicht.

const GAP := 0.02          # Flächen näher als das gelten als eine Ebene (m)
const MIN_AREA := 0.0004   # kleinere Überlappungen ignorieren (m²)
const PLANE_EPS := GAP     # fix(): dieselbe Schwelle wie der Scan (weit weg reichen Millimeter nicht)
const BUMP := 0.012        # fix(): Wachstum pro Durchgang und Seite
const MAX_BUMPS := 4


# ------------------------------------------------------------------
# fix(): Kisten auseinanderschieben
# ------------------------------------------------------------------

static func fix(root: Node, passes := 10) -> int:
	var boxes := _collect_boxes(root)
	var times := {}
	var total := 0
	for pass_i in passes:
		var pairs := _box_pairs(boxes)
		if pairs.is_empty():
			break
		var bumped := {}
		for p: Array in pairs:
			# je Durchgang nur eine Kiste eines Paares: wachsen beide gleich, bleiben sie bündig
			if bumped.has(p[0]) or bumped.has(p[1]):
				continue
			# die kräftigere Kiste wächst: ein paar Zentimeter fallen an einer Wand nicht auf,
			# an einem dünnen Beschlag schon
			var id: int = p[1] if _thickness(boxes[p[1]]) >= _thickness(boxes[p[0]]) else p[0]
			if int(times.get(id, 0)) >= MAX_BUMPS:
				id = p[0] if id == p[1] else p[1]
			if int(times.get(id, 0)) >= MAX_BUMPS:
				continue
			bumped[id] = true
			times[id] = int(times.get(id, 0)) + 1
			_grow(boxes[id], GAP + BUMP * (1 + (id + pass_i) % 2) + 0.003 * pass_i)
		total += bumped.size()
	var thin := 0
	for id in times:
		if _thickness(boxes[id]) < 0.4:
			thin += 1
	if thin > 0:
		print("[zfight] %d dünne Teile (< 40 cm) mussten wachsen: lieber beim Bauen absetzen" % thin)
	return total


static func _collect_boxes(root: Node) -> Array:
	var out := []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh is BoxMesh:
			out.append({"node": mi, "size": (mi.mesh as BoxMesh).size, "key": _key(mi)})
	return out


static func _box_pairs(boxes: Array) -> Array:
	var faces := []
	for id in boxes.size():
		var t: Transform3D = (boxes[id].node as Node3D).global_transform
		var size: Vector3 = boxes[id].size
		var ax := [t.basis.x * size.x * 0.5, t.basis.y * size.y * 0.5, t.basis.z * size.z * 0.5]
		for i in 3:
			for sgn in [1.0, -1.0]:
				var nrm: Vector3 = (ax[i] as Vector3).normalized() * sgn
				faces.append([t.origin + ax[i] * sgn, nrm, ax[(i + 1) % 3], ax[(i + 2) % 3], id])
	var buckets := {}
	for fi in faces.size():
		var f: Array = faces[fi]
		var nrm: Vector3 = f[1]
		var k := Vector4i(roundi(nrm.x * 40), roundi(nrm.y * 40), roundi(nrm.z * 40), floori(nrm.dot(f[0]) / PLANE_EPS))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(fi)
	var out := []
	for k: Vector4i in buckets:
		var list: Array = buckets[k]
		var nxt: Array = buckets.get(Vector4i(k.x, k.y, k.z, k.w + 1), [])
		for i in list.size():
			var a: Array = faces[list[i]]
			for j in range(i + 1, list.size() + nxt.size()):
				var b: Array = faces[list[j]] if j < list.size() else faces[nxt[j - list.size()]]
				if a[4] == b[4] or (a[1] as Vector3).dot(b[1]) < 0.9995:
					continue
				if absf((a[1] as Vector3).dot(b[0] - a[0])) > PLANE_EPS:
					continue
				if boxes[a[4]].key == boxes[b[4]].key:
					continue  # gleiche Farbe: flackert unsichtbar
				if _rect_overlap(a, b):
					out.append([mini(a[4], b[4]), maxi(a[4], b[4])])
	return out


static func _rect_overlap(a: Array, b: Array) -> bool:
	var d: Vector3 = b[0] - a[0]
	for axis: Vector3 in [a[2], a[3], b[2], b[3]]:
		if axis.length() < 0.0001:
			continue
		var n := axis.normalized()
		var ra := absf((a[2] as Vector3).dot(n)) + absf((a[3] as Vector3).dot(n))
		var rb := absf((b[2] as Vector3).dot(n)) + absf((b[3] as Vector3).dot(n))
		if absf(d.dot(n)) >= ra + rb - 0.01:
			return false
	return true


static func _thickness(b: Dictionary) -> float:
	var size: Vector3 = b.size
	var w := (b.node as Node3D).global_basis
	return minf(size.x * w.x.length(), minf(size.y * w.y.length(), size.z * w.z.length()))


## Kiste auf allen Seiten um `by` (Welt-Meter) wachsen lassen.
static func _grow(b: Dictionary, by: float) -> void:
	var mi: MeshInstance3D = b.node
	var size: Vector3 = b.size
	var world := mi.global_basis
	var lb := mi.basis
	for ax in 3:
		var len: float = size[ax] * world[ax].length()
		if len > 0.0001:
			lb[ax] = lb[ax] * ((len + by * 2.0) / len)
	mi.basis = lb


# ------------------------------------------------------------------
# scan(): alle Dreiecke prüfen
# ------------------------------------------------------------------

## Liefert [{a, b, area, at}] für jedes Mesh-Paar, das noch flackert (zusammengefasst).
static func scan(root: Node) -> Array:
	var tris: Array[PackedVector3Array] = []
	var owner: PackedInt32Array = []
	var names: Array[String] = []
	var keys: Array[String] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var mat := mi.material_override
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue  # Durchsichtiges (Glas, Effekte) schreibt keine Tiefe
		var id := names.size()
		names.append("%s/%s" % [mi.get_parent().name, mi.name])
		keys.append(_key(mi))
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := idx.size() if idx.size() > 0 else v.size()
			for t in range(0, count - 2, 3):
				var p := PackedVector3Array()
				if idx.size() > 0:
					p.append_array([v[idx[t]], v[idx[t + 1]], v[idx[t + 2]]])
				else:
					p.append_array([v[t], v[t + 1], v[t + 2]])
				tris.append(p)
				owner.append(id)

	# Ebene je Dreieck: Normale (eine Richtung je Ebene), Abstand, Blickrichtung
	var nrm: Array[Vector3] = []
	var dist: PackedFloat32Array = []
	var face: PackedInt32Array = []
	var keep: Array[bool] = []
	for t in tris:
		var c := (t[1] - t[0]).cross(t[2] - t[0])
		if c.length() < 2e-6:
			nrm.append(Vector3.ZERO)
			dist.append(0.0)
			face.append(0)
			keep.append(false)
			continue
		var nn := c.normalized()
		var f := 1
		if nn.x < -1e-6 or (absf(nn.x) <= 1e-6 and nn.y < -1e-6) or (absf(nn.x) <= 1e-6 and absf(nn.y) <= 1e-6 and nn.z < 0.0):
			nn = -nn
			f = -1
		nrm.append(nn)
		dist.append(nn.dot(t[0]))
		face.append(f)
		# Flächen, die nach unten schauen (Fuß einer Wand, Unterseite einer Kiste), sieht nie
		# jemand: Die Kamera kommt nicht unter den Boden. (Godots Vorderseiten laufen im
		# Uhrzeigersinn, das Kreuzprodukt zeigt also ins Innere: +y roh = Fläche nach unten.)
		keep.append(not (nn.y > 0.95 and f == 1))

	var buckets := {}
	for i in tris.size():
		if not keep[i]:
			continue
		var n: Vector3 = nrm[i]
		var k := Vector4i(roundi(n.x * 100), roundi(n.y * 100), roundi(n.z * 100), floori(dist[i] / GAP))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(i)

	var hits := {}
	var seen := {}
	for k: Vector4i in buckets:
		var cand: Array = (buckets[k] as Array).duplicate()
		cand.append_array(buckets.get(Vector4i(k.x, k.y, k.z, k.w + 1), []))
		if cand.size() < 2:
			continue
		var n0: Vector3 = nrm[cand[0]]
		var u := n0.cross(Vector3.FORWARD if absf(n0.z) < 0.9 else Vector3.RIGHT).normalized()
		var w := n0.cross(u)
		var flat := {}
		for i: int in cand:
			var t: PackedVector3Array = tris[i]
			flat[i] = [Vector2(t[0].dot(u), t[0].dot(w)), Vector2(t[1].dot(u), t[1].dot(w)), Vector2(t[2].dot(u), t[2].dot(w))]
		for ai in cand.size():
			var a: int = cand[ai]
			for bi in range(ai + 1, cand.size()):
				var b: int = cand[bi]
				if owner[a] == owner[b] or face[a] != face[b]:
					continue
				if (nrm[a] as Vector3).dot(nrm[b]) < 0.9995 or absf(dist[a] - dist[b]) >= GAP:
					continue
				if keys[owner[a]] == keys[owner[b]]:
					continue
				var pk := Vector2i(mini(a, b), maxi(a, b))
				if seen.has(pk):
					continue
				seen[pk] = true
				var poly := _clip(flat[a], flat[b])
				var area := _area(poly)
				if area < MIN_AREA:
					continue
				var cen := Vector2.ZERO
				for q: Vector2 in poly:
					cen += q
				cen /= poly.size()
				# eine Fläche, die genau dort in die andere Richtung schaut (etwas steht
				# dagegen), verdeckt die Stelle: kein sichtbares Flackern
				var sealed := false
				for oi: int in cand:
					if face[oi] != face[a] and absf(dist[oi] - dist[a]) < GAP and _in_tri(cen, flat[oi]):
						sealed = true
						break
				if sealed:
					continue
				var oa := mini(owner[a], owner[b])
				var ob := maxi(owner[a], owner[b])
				var hk := Vector2i(oa, ob)
				if not hits.has(hk):
					hits[hk] = {"a": names[oa], "b": names[ob], "area": 0.0, "at": n0 * dist[a] + u * cen.x + w * cen.y}
				hits[hk].area += area
	return hits.values()


static func _key(mi: MeshInstance3D) -> String:
	var m := mi.material_override
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		if bm.vertex_color_use_as_albedo:
			return "vc%d" % mi.get_instance_id()  # Vertexfarben: jede Fläche anders
		return "%s|%s|%.2f" % [bm.albedo_color.to_html(false), bm.emission.to_html(false) if bm.emission_enabled else "-", bm.emission_energy_multiplier if bm.emission_enabled else 0.0]
	return "mat%d" % (m.get_instance_id() if m else 0)


static func _area(poly: Array) -> float:
	if poly.size() < 3:
		return 0.0
	var s := 0.0
	for i in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return absf(s) * 0.5


static func _ccw(t: Array) -> Array:
	var a: Vector2 = t[0]
	var b: Vector2 = t[1]
	var c: Vector2 = t[2]
	if (b - a).cross(c - a) < 0.0:
		return [a, c, b]
	return [a, b, c]


## Überlappung zweier Dreiecke in der Ebene (Sutherland-Hodgman).
static func _clip(ta: Array, tb: Array) -> Array:
	var a := _ccw(ta)
	var poly := _ccw(tb)
	for k in 3:
		if poly.is_empty():
			return []
		var c: Vector2 = a[k]
		var e: Vector2 = (a[(k + 1) % 3] as Vector2) - c
		var out := []
		for i in poly.size():
			var p: Vector2 = poly[i]
			var q: Vector2 = poly[(i + 1) % poly.size()]
			var sp := e.cross(p - c)
			var sq := e.cross(q - c)
			if sp >= 0.0:
				out.append(p)
			if (sp >= 0.0) != (sq >= 0.0):
				out.append(p + (q - p) * (sp / (sp - sq)))
		poly = out
	return poly if poly.size() >= 3 else []


static func _in_tri(p: Vector2, t: Array) -> bool:
	var a: Vector2 = t[0]
	var b: Vector2 = t[1]
	var c: Vector2 = t[2]
	var d1: float = (b - a).cross(p - a)
	var d2: float = (c - b).cross(p - b)
	var d3: float = (a - c).cross(p - c)
	var neg: bool = d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9
	var pos: bool = d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9
	return not (neg and pos)
