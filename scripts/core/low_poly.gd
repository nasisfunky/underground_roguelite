class_name LowPoly
extends RefCounted
## Hilfsfunktionen für den Flat-Shaded-Low-Poly-Look.
## Alle Meshes werden "flach" gemacht (jede Fläche eigene Normale -> harte Facetten).

static var _mat_cache: Dictionary = {}

# --- Palette (an einer Stelle, damit der Look leicht justierbar bleibt) ---
const STONE_DARK := Color(0.10, 0.16, 0.18)
const STONE := Color(0.17, 0.26, 0.28)
const STONE_LIGHT := Color(0.33, 0.47, 0.48)
const FLOOR := Color(0.36, 0.52, 0.52)
const SHADOW_SKIN := Color(0.035, 0.035, 0.05)
const CYAN := Color(0.35, 0.95, 1.0)
const OCHRE := Color(0.56, 0.30, 0.13)
const EYE_YELLOW := Color(1.0, 0.78, 0.18)
const EYE_ORANGE := Color(1.0, 0.45, 0.12)


static func mat(color: Color, emission: float = 0.0, roughness: float = 0.92) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(), emission, roughness]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	m.metallic_specular = 0.25
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mat_cache[key] = m
	return m


static func unshaded(color: Color) -> StandardMaterial3D:
	var key := "unshaded_%s" % color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m


## Macht aus einem beliebigen Mesh ein flach schattiertes ArrayMesh.
static func flatten(mesh: Mesh, jitter: float = 0.0, seed_value: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	var arrays := st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if jitter > 0.0:
		# Gleiche Positionen müssen gleich verschoben werden, sonst reißt das Mesh auf.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var offsets: Dictionary = {}
		for i in verts.size():
			var k := Vector3i((verts[i] * 1000.0).round())
			if not offsets.has(k):
				offsets[k] = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
			verts[i] += offsets[k]
	var out := SurfaceTool.new()
	out.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri_count := indices.size() / 3 if indices.size() > 0 else verts.size() / 3
	for t in tri_count:
		var a: Vector3
		var b: Vector3
		var c: Vector3
		if indices.size() > 0:
			a = verts[indices[t * 3]]
			b = verts[indices[t * 3 + 1]]
			c = verts[indices[t * 3 + 2]]
		else:
			a = verts[t * 3]
			b = verts[t * 3 + 1]
			c = verts[t * 3 + 2]
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		out.set_normal(n)
		out.add_vertex(a)
		out.set_normal(n)
		out.add_vertex(b)
		out.set_normal(n)
		out.add_vertex(c)
	return out.commit()


static func mesh_instance(mesh: Mesh, material: Material, parent: Node = null, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	if parent:
		parent.add_child(mi)
	return mi


# --- Grundformen ---

static func box(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Kegel-/Prismenstumpf mit wenigen Seiten. Spitze bei top_r = 0.
static func prism(bottom_r: float, top_r: float, height: float, sides: int = 5) -> ArrayMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom_r
	c.top_radius = top_r
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return flatten(c)


## Kantiger Felsbrocken (verzerrte Low-Poly-Kugel).
static func rock(radius: float, seed_value: int, sides: int = 6, rings: int = 4, jitter: float = 0.28) -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = sides
	s.rings = rings
	return flatten(s, radius * jitter, seed_value)


## Kristall: langgezogener, spitzer Prismenkörper.
static func crystal(height: float, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 5
	var base_y := 0.0
	var shoulder := height * 0.72
	var ring: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / sides
		ring.append(Vector3(cos(a) * radius, 0, sin(a) * radius))
	var tip := Vector3(0, height, 0)
	for i in sides:
		var p0 := ring[i]
		var p1 := ring[(i + 1) % sides]
		var b0 := p0 + Vector3(0, base_y, 0)
		var b1 := p1 + Vector3(0, base_y, 0)
		var s0 := p0 * 1.05 + Vector3(0, shoulder, 0)
		var s1 := p1 * 1.05 + Vector3(0, shoulder, 0)
		var center := Vector3(0, height * 0.4, 0)
		tri_out(st, b0, s0, s1, center)
		tri_out(st, b0, s1, b1, center)
		tri_out(st, s0, tip, s1, center)
	return st.commit()


## Fügt ein Dreieck hinzu, dessen Vorderseite von `center` weg zeigt (Godot: Vorderseite im Uhrzeigersinn).
static func tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = n.normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


## Schwertklinge mit Rautenquerschnitt. Griff am Ursprung, Klinge entlang -Z.
static func blade(length: float, width: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := -0.06
	var z1 := -length * 0.86
	var z2 := -length
	var hw := width * 0.5
	var ht := thickness * 0.5
	var sec := func(z: float, k: float) -> Array:
		return [Vector3(0, hw * k, z), Vector3(ht * k, 0, z), Vector3(0, -hw * k, z), Vector3(-ht * k, 0, z)]
	var s0: Array = sec.call(z0, 1.0)
	var s1: Array = sec.call(z1, 0.92)
	var tip := Vector3(0, 0, z2)
	for i in 4:
		var j := (i + 1) % 4
		var c := Vector3(0, 0, (z0 + z1) * 0.5)
		tri_out(st, s0[i], s1[i], s1[j], c)
		tri_out(st, s0[i], s1[j], s0[j], c)
		tri_out(st, s1[i], tip, s1[j], Vector3(0, 0, z1))
		tri_out(st, s0[i], s0[j], Vector3(0, 0, z0), Vector3(0, 0, z0 - 0.1))
	return st.commit()
