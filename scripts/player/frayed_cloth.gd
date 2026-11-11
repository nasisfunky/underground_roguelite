class_name FrayedCloth
extends RefCounted
## Stoffsimulation der Frayed-Shades (Port der Konzeptseite): Verlet-Partikel in Weltkoordinaten,
## Abstands-, Scher- und Biegebedingungen, Kollision mit dem Körper (Rumpf und Becken als
## Ellipsen-Querschnitte inkl. Rüstungspolster, Glieder als Kapseln, Kopf als Kugel).
## Alle Stoffe einer Figur laufen in einem Löser: Stoffbahnen, Bänder, Schalenden und Perlenschnüre.
## Zeile 0 jedes Stoffs ist am Gelenk angeheftet.

const ITERATIONS := 4
const SUBSTEPS := 1
const LUT_N := 64  ## Stützstellen der Querschnitt-Tabellen
const GRAVITY := 9.8
const HEAD_R := 0.16

var body: ShadowBody
var st: Array = []  ## Rumpf-Querschnitte [y, rx, rz, ox, oz]
var seat: Array = []  ## Hosensitz/Becken-Querschnitte
var pad := 0.04
var hip_pad := 0.03
var leg_pad := 0.02

# Partikel
var p := PackedVector3Array()
var q := PackedVector3Array()
var pinned := PackedByteArray()
var pin_loc := PackedVector3Array()
var pin_joint := PackedInt32Array()  ## Index in _joints
var _joints: Array[Node3D] = []
var _jxf: Array[Transform3D] = []
var damp := PackedFloat32Array()
var root_of := PackedInt32Array()  ## Anheftpunkt derselben Spalte (gegen Überdehnung)
var max_d := PackedFloat32Array()
# Bedingungen
var ca := PackedInt32Array()
var cb := PackedInt32Array()
var cr := PackedFloat32Array()
var ck := PackedFloat32Array()
var quads := PackedInt32Array()  ## je 4 Indizes: Flächenmitten prüfen
# Darstellung
var cloths: Array[Dictionary] = []
var _ready := false
# Körperformen dieses Schritts
var _chest_inv: Transform3D
var _chest: Transform3D
var _hips_inv: Transform3D
var _hips: Transform3D
var _cap_a := PackedVector3Array()
var _cap_b := PackedVector3Array()
var _cap_r := PackedFloat32Array()  ## je 2: r0, r1
var _st_lut := PackedFloat32Array()
var _seat_lut := PackedFloat32Array()
var _head := Vector3.ZERO
var _floor := -INF  ## Bodenhöhe unter der Figur (Stoff liegt auf statt einzutauchen)


func setup(b: ShadowBody, info: Dictionary, parts: Dictionary, joints: Dictionary) -> void:
	body = b
	st = info.ST
	seat = info.SEAT
	var bo: Dictionary = info.get("body", {})
	pad = bo.get("pad", 0.04)
	hip_pad = bo.get("hipPad", 0.03)
	leg_pad = bo.get("legPad", 0.02)
	for c in info.cloths:
		_add_cloth(c, parts, joints)
	_st_lut = _make_lut(st, -0.02, 0.5)
	_seat_lut = _make_lut(seat, -0.11, 0.11)


func _add_cloth(c: Dictionary, parts: Dictionary, joints: Dictionary) -> void:
	var joint: Node3D = joints[c.joint]
	var cols: int = c.cols
	var rows: int = c.rows
	var base := p.size()
	var locs: Array = c.loc
	for k in locs.size():
		var l := Vector3(locs[k][0], locs[k][1], locs[k][2])
		p.append(l)
		q.append(l)
		pin_loc.append(l)
		pin_joint.append(_joint_index(joint))
		pinned.append(1 if k < cols else 0)
		damp.append(c.get("damp", 0.985))
		root_of.append(base + k % cols)
		max_d.append(0.0)
	var id := func(r: int, i: int) -> int: return base + r * cols + i
	var bend: float = c.get("bend", 0.25)
	for r in rows:
		for i in cols:
			if i + 1 < cols:
				_con(id.call(r, i), id.call(r, i + 1), 1.0)
			if r + 1 < rows:
				_con(id.call(r, i), id.call(r + 1, i), 1.0)
			if r + 1 < rows and i + 1 < cols:
				_con(id.call(r, i), id.call(r + 1, i + 1), 0.6)
				_con(id.call(r, i + 1), id.call(r + 1, i), 0.6)
				quads.append_array([id.call(r, i), id.call(r, i + 1), id.call(r + 1, i), id.call(r + 1, i + 1)])
			if r + 2 < rows:
				_con(id.call(r, i), id.call(r + 2, i), bend)
			if i + 2 < cols:
				_con(id.call(r, i), id.call(r, i + 2), 0.5)
	# größter erlaubter Abstand zum Anheftpunkt: Länge der Spalte in Ruhelage + 12 %
	for i in cols:
		var acc := 0.0
		for r in range(1, rows):
			acc += p[id.call(r, i)].distance_to(p[id.call(r - 1, i)])
			max_d[id.call(r, i)] = acc * 1.12
	var d := {"base": base, "cols": cols, "rows": rows}
	if c.has("mat"):
		var mi := MeshInstance3D.new()
		mi.name = "Cloth"
		mi.mesh = ArrayMesh.new()
		var src: Mesh = parts.get(c.mat)
		if src:
			mi.material_override = src.surface_get_material(0)
		mi.extra_cull_margin = 1.0
		body.add_child(mi)
		body._meshes.append(mi)
		d.mesh = mi
		var uv := PackedVector2Array()
		var idx := PackedInt32Array()
		var us: float = c.get("us", 1.0)
		var vs: float = c.get("vs", 1.0)
		var v0: float = c.get("v0", 0.0)
		for r in rows:
			for i in cols:
				uv.append(Vector2(float(i) / (cols - 1) * us, v0 + float(r) / (rows - 1) * vs))
		for r in rows - 1:
			for i in cols - 1:
				var a := r * cols + i
				var cc := a + cols
				# Godot: Vorderseite im Uhrzeigersinn
				idx.append_array([a, a + 1, cc, a + 1, cc + 1, cc])
		d.uv = uv
		d.idx = idx
	if c.has("segs"):
		var segs: Array[MeshInstance3D] = []
		for sn in c.segs:
			var smi := MeshInstance3D.new()
			smi.mesh = parts.get(sn)
			body.add_child(smi)
			body._meshes.append(smi)
			segs.append(smi)
		d.segs = segs
		d.segL = c.get("segL", 0.05)
	if c.has("end"):
		var emi := MeshInstance3D.new()
		emi.mesh = parts.get(c.end)
		body.add_child(emi)
		body._meshes.append(emi)
		d.end = emi
	cloths.append(d)


func _joint_index(j: Node3D) -> int:
	var i := _joints.find(j)
	if i < 0:
		_joints.append(j)
		_jxf.append(Transform3D.IDENTITY)
		i = _joints.size() - 1
	return i


## Querschnitt-Tabelle [y, rx, rz, ox, oz] als gleichmäßig abgetastete Liste (schneller als Suchen)
func _make_lut(tab: Array, y0: float, y1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in LUT_N:
		var r := _ring(tab, lerpf(y0, y1, float(i) / (LUT_N - 1)))
		out.append_array([r[0], r[1], r[2], r[3]])
	return out


func _con(a: int, b: int, k: float) -> void:
	ca.append(a)
	cb.append(b)
	cr.append(p[a].distance_to(p[b]))
	ck.append(k)


## Alles auf die Ruhelage der aktuellen Gelenke setzen (Start, Teleport, Respawn).
func reset() -> void:
	for k in p.size():
		var w: Vector3 = _joints[pin_joint[k]].global_transform * pin_loc[k]
		p[k] = w
		q[k] = w
	_ready = true


func update(dt: float) -> void:
	if dt <= 0.0 or p.is_empty():
		return
	if not _ready:
		reset()
	# große Sprünge (Teleport, Respawn) nicht simulieren
	if (_joints[pin_joint[0]].global_transform * pin_loc[0]).distance_squared_to(p[0]) > 1.0:
		reset()
	_prep()
	var h := minf(dt, 1.0 / 30.0) / SUBSTEPS
	for s in SUBSTEPS:
		_step(h, float(s + 1) / SUBSTEPS)
	_render()


func _prep() -> void:
	_chest = body.chest.global_transform
	_chest_inv = _chest.affine_inverse()
	_hips = body.hips.global_transform
	_hips_inv = _hips.affine_inverse()
	_head = body.head.global_position
	_floor = body.global_position.y + 0.015 if body.on_floor else -INF
	_cap_a.clear()
	_cap_b.clear()
	_cap_r.clear()
	var lp := leg_pad
	for side in [[body.hip_l, body.knee_l], [body.hip_r, body.knee_r]]:
		var hip: Node3D = side[0]
		var knee: Node3D = side[1]
		_cap(hip.global_position, knee.global_position, 0.085 + lp, 0.05 + lp)
		_cap(knee.global_position, knee.global_transform * Vector3(0, -ShadowBody.SHIN, 0), 0.045 + lp, 0.012 + lp)
	for arm in [[body.arm_up_l, body.arm_lo_l], [body.arm_up_r, body.arm_lo_r]]:
		var up: Node3D = arm[0]
		var lo: Node3D = arm[1]
		_cap(up.global_position, lo.global_position, 0.066, 0.053)
		_cap(lo.global_position, lo.global_transform * Vector3(0, -0.3, 0), 0.053, 0.028)
	for i in _joints.size():
		_jxf[i] = _joints[i].global_transform


func _cap(a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	_cap_a.append(a)
	_cap_b.append(b - a)
	_cap_r.append(r0)
	_cap_r.append(r1)


func _step(h: float, frac: float) -> void:
	var g := -GRAVITY * h * h
	var n := p.size()
	for k in n:
		if pinned[k]:
			q[k] = p[k]
			p[k] = _jxf[pin_joint[k]] * pin_loc[k]
			continue
		var pk := p[k]
		var v := (pk - q[k]) * damp[k]
		q[k] = pk
		p[k] = pk + v + Vector3(0, g, 0)
	var nc := ca.size()
	for it in ITERATIONS:
		for c in nc:
			var a := ca[c]
			var b := cb[c]
			var pa := p[a]
			var d := p[b] - pa
			var len := d.length()
			if len < 1e-7:
				continue
			var fa := pinned[a] == 1
			var fb := pinned[b] == 1
			if fa and fb:
				continue
			var f := (len - cr[c]) / len * ck[c]
			if fa:
				p[b] -= d * f
			elif fb:
				p[a] = pa + d * f
			else:
				p[a] = pa + d * (f * 0.5)
				p[b] -= d * (f * 0.5)
		if it % 3 == 2:
			for k in n:
				if not pinned[k]:
					p[k] = _collide(p[k])
	for k in n:
		if pinned[k]:
			continue
		# nie weiter als die Spaltenlänge vom Anheftpunkt (sonst reißt der Stoff bei der Rolle aus)
		var r := root_of[k]
		var dv := p[k] - p[r]
		var dl := dv.length()
		if dl > max_d[k] and dl > 1e-6:
			p[k] = p[r] + dv * (max_d[k] / dl)
		p[k] = _collide(p[k])
		if p[k].y < _floor:
			p[k].y = _floor
	# Flächenmitten prüfen, damit Stoff nicht zwischen zwei Partikeln durch ein Bein schneidet
	var i := 0
	while i < quads.size():
		var k0 := quads[i]
		var k1 := quads[i + 1]
		var k2 := quads[i + 2]
		var k3 := quads[i + 3]
		var c := (p[k0] + p[k1] + p[k2] + p[k3]) * 0.25
		var cc := _collide(c)
		var push := cc - c
		if push.length_squared() > 1e-10:
			if not pinned[k0]: p[k0] += push
			if not pinned[k1]: p[k1] += push
			if not pinned[k2]: p[k2] += push
			if not pinned[k3]: p[k3] += push
		i += 4


func _ring(tab: Array, y: float) -> Array:
	var asc: bool = tab[0][0] < tab[tab.size() - 1][0]
	for i in tab.size() - 1:
		var a: Array = tab[i]
		var b: Array = tab[i + 1]
		var lo := minf(a[0], b[0])
		var hi := maxf(a[0], b[0])
		if y >= lo and y <= hi:
			var den: float = b[0] - a[0]
			var t: float = (y - a[0]) / (den if absf(den) > 1e-9 else 1.0)
			return [lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(_e(a, 3), _e(b, 3), t), lerpf(_e(a, 4), _e(b, 4), t)]
	var l: Array = tab[tab.size() - 1] if asc else tab[0]
	return [l[1], l[2], _e(l, 3), _e(l, 4)]


func _e(a: Array, i: int) -> float:
	return a[i] if a.size() > i else 0.0


func _ell(w: Vector3, inv: Transform3D, xf: Transform3D, lut: PackedFloat32Array, y0: float, y1: float, ylo: float, yc: float, pd: float) -> Vector3:
	var v := inv * w
	if v.y < y0 or v.y > y1:
		return w
	var i := clampi(int(roundf((clampf(v.y, ylo, yc) - ylo) / (yc - ylo) * (LUT_N - 1))), 0, LUT_N - 1) * 4
	var a := lut[i] + pd
	var b := lut[i + 1] + pd
	var ox := lut[i + 2]
	var oz := lut[i + 3]
	var dx := v.x - ox
	var dz := v.z - oz
	var e := (dx / a) * (dx / a) + (dz / b) * (dz / b)
	if e >= 1.0:
		return w
	if e < 1e-6:
		v.z = oz - b
	else:
		var s := 1.0 / sqrt(e)
		v.x = ox + dx * s
		v.z = oz + dz * s
	return xf * v


func _collide(w: Vector3) -> Vector3:
	w = _ell(w, _chest_inv, _chest, _st_lut, -0.06, 0.6, -0.02, 0.5, pad)
	w = _ell(w, _hips_inv, _hips, _seat_lut, -0.22, 0.14, -0.11, 0.11, hip_pad)
	for ci in _cap_a.size():
		var a := _cap_a[ci]
		var ab := _cap_b[ci]
		var aw := w - a
		var t := clampf(aw.dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := aw - ab * t
		var rad := lerpf(_cap_r[ci * 2], _cap_r[ci * 2 + 1], t)
		var dl2 := d.length_squared()
		if dl2 < rad * rad and dl2 > 1e-12:
			w = a + ab * t + d * (rad / sqrt(dl2))
	var dh := w - _head
	var dh2 := dh.length_squared()
	if dh2 < HEAD_R * HEAD_R and dh2 > 1e-12:
		w = _head + dh * (HEAD_R / sqrt(dh2))
	return w


func _render() -> void:
	var inv := body.global_transform.affine_inverse()
	for d in cloths:
		var base: int = d.base
		var cols: int = d.cols
		var rows: int = d.rows
		if d.has("mesh"):
			var verts := PackedVector3Array()
			verts.resize(cols * rows)
			for k in cols * rows:
				verts[k] = inv * p[base + k]
			var normals := PackedVector3Array()
			normals.resize(cols * rows)
			for r in rows:
				for i in cols:
					var du := verts[r * cols + mini(i + 1, cols - 1)] - verts[r * cols + maxi(i - 1, 0)]
					var dv := verts[mini(r + 1, rows - 1) * cols + i] - verts[maxi(r - 1, 0) * cols + i]
					var nn := dv.cross(du)
					normals[r * cols + i] = nn.normalized() if nn.length_squared() > 1e-12 else Vector3.FORWARD
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = normals
			arr[Mesh.ARRAY_TEX_UV] = d.uv
			arr[Mesh.ARRAY_INDEX] = d.idx
			var am: ArrayMesh = (d.mesh as MeshInstance3D).mesh
			am.clear_surfaces()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if d.has("segs"):
			var segs: Array[MeshInstance3D] = d.segs
			for k in segs.size():
				var a := inv * p[base + k]
				var b := inv * p[base + k + 1]
				var dir := b - a
				var l := dir.length()
				var bs := Basis.IDENTITY
				if l > 1e-6:
					bs = Basis(Quaternion(Vector3.DOWN, dir / l))
				segs[k].transform = Transform3D(bs * Basis.from_scale(Vector3(1, maxf(l, 1e-3) / d.segL, 1)), a)
		if d.has("end"):
			var last := base + (rows - 1) * cols
			var mid := (p[last] + p[last + cols - 1]) * 0.5
			(d.end as MeshInstance3D).position = inv * mid
