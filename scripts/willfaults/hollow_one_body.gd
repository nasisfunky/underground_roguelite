class_name HollowOneBody
extends Node3D
## Hollow One: verblassender Wille in der alten Ausrüstung eines Shades (eine der drei Kulturen,
## verschmutzt, angerostet, Stoffe zerrissen). Der Körper ist ein heller, durchscheinender Schleier
## ohne Beine; statt der Beine ein Schweif. Schwebt in ruhigen Achten. Augen: leere schwarze Kreise
## mit weiß glimmendem Rand. Angriff: holt aus, gleitet mit dem Hieb nach vorn und wieder zurück.

const TAIL_RINGS := [[0.03, 0.1, 0.085], [-0.08, 0.108, 0.09], [-0.25, 0.092, 0.076], [-0.45, 0.066, 0.055],
	[-0.65, 0.04, 0.034], [-0.85, 0.016, 0.014], [-0.95, 0.0, 0.0]]
const ATTACK_CYCLE := 3.4

var outfit := ""  ## leer: zufällige Kultur
var attacking := false
var t := 0.0
var body: ShadowBody
var _t0 := 0.0
var _halos: Array[MeshInstance3D] = []
var _eye_light: OmniLight3D


func _ready() -> void:
	body = ShadowBody.new()
	body.outfit = outfit if outfit != "" else FrayedOutfit.CULTURES.pick_random()
	body.ghost = true
	body.has_shield = false
	body.has_lantern = false
	body.build()
	add_child(body)
	body.cloth.floor_from_body = false
	_build_tail()
	_build_eyes()
	_break_weapon()
	# Scheide und übrige Kleinteile am Gürtel ebenfalls verbraucht
	for n in ["Scabbard", "DaggerSheath"]:
		var holder := body.hips.get_node_or_null(n)
		if holder:
			for mi in holder.find_children("*", "MeshInstance3D", true, false):
				ShadowBody.wear(mi, 4.0)
	tick(0.0)


func set_attacking(on: bool) -> void:
	if on != attacking:
		attacking = on
		_t0 = t


func tick(delta: float) -> void:
	t += delta
	var ta := fmod(t - _t0, ATTACK_CYCLE) if attacking else -1.0
	# Schweben: weite, ruhige Acht; im Angriff Ausholen, Durchgleiten mit Hieb, Zurückgleiten
	var x := 0.42 * sin(t * 0.45)
	var z := 0.26 * sin(t * 0.9)
	var y := 0.34 + 0.06 * sin(t * 1.7)
	var bank := -0.35 * 0.42 * 0.45 * cos(t * 0.45) * 2.4
	var flare := 0.0
	body.action = &""
	if attacking:
		var k_w := WillfaultModel.sm(ta / 0.8)
		var k_d := WillfaultModel.sm((ta - 0.8) / 0.28)
		var k_b := WillfaultModel.sm((ta - 1.4) / 1.4)
		x = lerpf(x, 0.0, k_w)
		z = lerpf(lerpf(z, 0.35, k_w), -0.6, k_d) * (1.0 - k_b) + z * k_b
		y = 0.42 + 0.14 * k_w * (1.0 - k_d) - 0.1 * k_d * (1.0 - k_b)
		bank *= k_b
		flare = k_w * (1.0 - k_b)
		if ta < 0.8:
			body.action = &"swing"
			body.swing_index = 2
			body.action_t = 0.36 * ta / 0.8
		elif ta < 1.08:
			body.action = &"swing"
			body.swing_index = 2
			body.action_t = 0.36 + 0.26 * (ta - 0.8) / 0.28
		elif ta < 2.4:
			body.action = &"swing"
			body.swing_index = 2
			body.action_t = 0.62 + 0.38 * (ta - 1.08) / 1.32
	body.position = Vector3(x, y, z)
	body.rotation = Vector3(0, 0, bank)
	body.combat = 1.0 if attacking else 0.25
	body.speed = 0.0
	body.on_floor = true
	body.cloth.floor_y = global_position.y
	body.tick(delta)
	for h in _halos:
		h.scale = Vector3.ONE * (1.0 + 0.6 * flare + 0.08 * sin(t * 5.0))
	_eye_light.light_energy = 0.15 + 0.8 * flare


## Schweif aus Ringen (Hüftraum): Tiefen-Durchgang + Schleier, wie der Körper
func _build_tail() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 16
	var ring_pts: Array = []
	for r: Array in TAIL_RINGS:
		var pts: Array[Vector3] = []
		for k in sides:
			var a := TAU * k / sides
			pts.append(Vector3(sin(a) * r[1], r[0], -cos(a) * r[2]))
		ring_pts.append(pts)
	for i in ring_pts.size() - 1:
		var r0: Array = ring_pts[i]
		var r1: Array = ring_pts[i + 1]
		for k in sides:
			var k1 := (k + 1) % sides
			_tri(st, r0[k], r0[k1], r1[k])
			_tri(st, r0[k1], r1[k1], r1[k])
	# Deckel oben
	var top: Array = ring_pts[0]
	for k in sides:
		_tri(st, Vector3(0, TAIL_RINGS[0][0], 0), top[k], top[(k + 1) % sides], Vector3.UP)
	st.generate_normals()
	var mesh := st.commit()
	var depth := MeshInstance3D.new()
	depth.name = "Tail"
	depth.mesh = mesh
	depth.material_override = ShadowBody.ghost_material(true, true)
	depth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.hips.add_child(depth)
	var veil := MeshInstance3D.new()
	veil.mesh = mesh
	veil.material_override = ShadowBody.ghost_material(true, false)
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	depth.add_child(veil)


## Dreieck nach außen gewickelt (Godot: Vorderseite im Uhrzeigersinn)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out := Vector3.INF) -> void:
	var o := out if out != Vector3.INF else Vector3((a + b + c).x, 0, (a + b + c).z)
	if (b - a).cross(c - a).dot(o) > 0.0:
		var tmp := b
		b = c
		c = tmp
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Augen: leere schwarze Scheiben mit weiß glimmendem Ring und Lichthof, dort wo die Shade-Augen sitzen
func _build_eyes() -> void:
	var centers: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var size := 0.03
	var holder: MeshInstance3D = null
	for c in body.head.get_children():
		if c is MeshInstance3D and String(c.name) == "G_head":
			holder = c
	if holder:
		var mesh := holder.mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m == null or m.resource_name != "Eye":
				continue
			var arr := mesh.surface_get_arrays(i)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for side in [-1.0, 1.0]:
				var acc := Vector3.ZERO
				var nacc := Vector3.ZERO
				var n := 0
				var lo := Vector3.INF
				var hi := -Vector3.INF
				for k in vs.size():
					if signf(vs[k].x) == side:
						acc += vs[k]
						nacc += ns[k]
						lo = lo.min(vs[k])
						hi = hi.max(vs[k])
						n += 1
				if n > 0:
					centers.append(holder.transform * (acc / n))
					var nn := nacc.normalized()
					if nn.z > 0.0:
						nn = -nn
					normals.append(nn)
					size = maxf((hi - lo).x, (hi - lo).y) * 0.5
	if centers.is_empty():
		centers = [Vector3(-0.05, 0.02, -0.12), Vector3(0.05, 0.02, -0.12)]
		normals = [Vector3(-0.3, 0, -1).normalized(), Vector3(0.3, 0, -1).normalized()]
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.96, 0.94, 1.0)
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.albedo_texture = _halo_tex()
	var r := clampf(size, 0.02, 0.035)
	for i in centers.size():
		var piv := Node3D.new()
		body.head.add_child(piv)
		piv.position = centers[i] + normals[i] * 0.004
		piv.basis = Basis(Quaternion(Vector3.FORWARD, normals[i]))
		var disc := MeshInstance3D.new()
		disc.mesh = _disc(r, 28)
		disc.material_override = black
		piv.add_child(disc)
		var ring := MeshInstance3D.new()
		ring.mesh = _ring(r, r * 1.32, 32)
		ring.material_override = white
		ring.position.z = -0.001
		piv.add_child(ring)
		var halo := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(r * 5.5, r * 5.5)
		halo.mesh = q
		halo.material_override = halo_mat
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.position.z = -0.006
		piv.add_child(halo)
		_halos.append(halo)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(0.91, 0.89, 1.0)
	_eye_light.omni_range = 1.2
	_eye_light.position = Vector3(0, 0.05, -0.18)
	body.head.add_child(_eye_light)


## Flache Scheibe in der XY-Ebene, Vorderseite Richtung -Z
static func _disc(r: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.FORWARD)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_tri(st, Vector3.ZERO, Vector3(cos(a0) * r, sin(a0) * r, 0), Vector3(cos(a1) * r, sin(a1) * r, 0), Vector3.FORWARD)
	return st.commit()


static func _ring(r0: float, r1: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.FORWARD)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p := [Vector3(cos(a0) * r0, sin(a0) * r0, 0), Vector3(cos(a0) * r1, sin(a0) * r1, 0), Vector3(cos(a1) * r1, sin(a1) * r1, 0), Vector3(cos(a1) * r0, sin(a1) * r0, 0)]
		_tri(st, p[0], p[1], p[2], Vector3.FORWARD)
		_tri(st, p[0], p[2], p[3], Vector3.FORWARD)
	return st.commit()


static var _halo_texture: GradientTexture2D


static func _halo_tex() -> GradientTexture2D:
	if _halo_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(0.78, 0.75, 1.0, 0.0))
		g.add_point(0.35, Color(0.88, 0.84, 1.0, 0.35))
		_halo_texture = GradientTexture2D.new()
		_halo_texture.gradient = g
		_halo_texture.fill = GradientTexture2D.FILL_RADIAL
		_halo_texture.fill_from = Vector2(0.5, 0.5)
		_halo_texture.fill_to = Vector2(0.5, 0.0)
		_halo_texture.width = 64
		_halo_texture.height = 64
	return _halo_texture


## Abgebrochene Klinge: alles jenseits der Bruchkante wird auf eine gezackte Kante gestaucht
func _break_weapon() -> void:
	var wm: MeshInstance3D = null
	for c in body.sword.get_children():
		if c is MeshInstance3D:
			wm = c
	if wm == null or wm.mesh == null:
		return
	var src := wm.mesh
	var cut := body.weapon_length * 0.52
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in vs.size():
			var v := vs[k]
			if v.z < -cut:
				var jag := fmod(absf(sin(v.x * 91.0 + v.y * 37.0) * 43758.5), 1.0)
				v.z = -cut - 0.045 * jag
				vs[k] = v
		arr[Mesh.ARRAY_VERTEX] = vs
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(i, src.surface_get_material(i))
	wm.mesh = out
	ShadowBody.wear(wm, 3.0)
	body.weapon_length = cut
