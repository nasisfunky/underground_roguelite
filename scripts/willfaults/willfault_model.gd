class_name WillfaultModel
extends RefCounted
## Lädt ein Willfault-Modell der Konzeptseite (tools/willfault_export) und setzt die Spielmaterialien ein:
## Schattenkörper, violetter Flammensaum, Kopfflamme, glühende Augen. Gelenke werden über ihre Namen gefunden.

const VIOLET_HEAT := "#1c0b3d"
const VIOLET_HOT := "#9f6bff"
const MURK_SHADER := preload("res://assets/shaders/willfault_murk.gdshader")


## Instanziert das Modell. Liefert {root, joints: {Name -> Node3D}, meshes, hem_mats}.
static func spawn(path: String, parent: Node3D, hem: Dictionary = {}) -> Dictionary:
	var scene: PackedScene = load(path)
	var top: Node3D = scene.instantiate()
	parent.add_child(top)
	var root: Node3D = top.get_child(0)
	var out := {"top": top, "root": root, "joints": {}, "meshes": [], "hem_mats": [], "mats": {}}
	var info := {"heat": VIOLET_HEAT, "hot": VIOLET_HOT, "hemH": hem.get("hair", 0.24)}
	var body_hem: Array = []
	var head_hem: Array = []
	if hem.get("layers", 0) > 0:
		body_hem = FrayedOutfit.hem_chain(info, hem.layers, false, hem.get("glow", 1.3), VIOLET_HEAT, VIOLET_HOT)
		head_hem = FrayedOutfit.hem_chain(info, 16, true, hem.get("glow", 1.3), VIOLET_HEAT, VIOLET_HOT)
		var sc: float = hem.get("scale", 1.0)  # Saum in Weltmaß (Shader arbeitet in Weltkoordinaten)
		for m: ShaderMaterial in body_hem[1]:
			m.set_shader_parameter("thick", hem.get("thick", 0.011) * sc)
			m.set_shader_parameter("rise", hem.get("rise", 0.03) * sc)
		for m: ShaderMaterial in head_hem[1]:
			m.set_shader_parameter("thick", hem.get("head_thick", 0.025) * sc)
			m.set_shader_parameter("rise", hem.get("head_rise", 0.05) * sc)
		out.hem_mats = body_hem[1] + head_hem[1]
	_walk(root, out, body_hem, head_hem)
	if hem.get("dark_gear", false):
		# Farben der Konzeptseite als sRGB lesen: Ausrüstung wirkt dunkler und schwerer
		for k in out.mats:
			var m = out.mats[k]
			if m is StandardMaterial3D and (m as StandardMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and not m.has_meta("dark"):
				m.set_meta("dark", true)  # Materialien teilen sich alle Instanzen: nur einmal umrechnen
				(m as StandardMaterial3D).albedo_color = (m as StandardMaterial3D).albedo_color.srgb_to_linear()
	return out


static func _walk(n: Node, out: Dictionary, body_hem: Array, head_hem: Array) -> void:
	for c in n.get_children():
		_walk(c, out, body_hem, head_hem)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		out.meshes.append(mi)
		var mesh := mi.mesh
		if n.name == &"HeadHem":
			if head_hem.is_empty():
				mi.visible = false
			else:
				mi.material_override = head_hem[0]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m == null:
				continue
			var mn := m.resource_name
			match mn:
				"Skin":
					mi.set_surface_override_material(i, ShadowBody.skin_material())
				"Sh":
					mi.set_surface_override_material(i, _shared(out, "Sh", func() -> Material:
						var sm := ShaderMaterial.new()
						sm.shader = MURK_SHADER
						return sm))
				_:
					if m is StandardMaterial3D:
						var sm3 := m as StandardMaterial3D
						if sm3.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and sm3.metallic < 0.05:
							sm3.metallic_specular = 0.0
							sm3.roughness = 1.0
					(out.mats as Dictionary)[mn] = m
		# Flammensaum über Körperteilen mit Saummaske
		if n.name.begins_with("Body") and not body_hem.is_empty() and _has_mask(mesh):
			var hm := MeshInstance3D.new()
			hm.name = "Hem"
			hm.mesh = mesh
			hm.material_override = body_hem[0]
			hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(hm)


static func _shared(out: Dictionary, key: String, make: Callable) -> Material:
	if not out.mats.has(key):
		out.mats[key] = make.call()
	return out.mats[key]


static func _has_mask(mesh: Mesh) -> bool:
	var arr := mesh.surface_get_arrays(0)
	var cols = arr[Mesh.ARRAY_COLOR]
	if cols == null:
		return false
	for c: Color in cols:
		if c.a > 0.5:
			return true
	return false


## Alle Knoten mit eigenem Namen (Gelenke), rekursiv
static func joints(root: Node) -> Dictionary:
	var d := {}
	_collect(root, d)
	return d


static func _collect(n: Node, d: Dictionary) -> void:
	if not String(n.name).begins_with("Node") and n is Node3D and not n is MeshInstance3D:
		d[String(n.name)] = n
	for c in n.get_children():
		_collect(c, d)


## Drehung wie auf der Konzeptseite (three.js, Reihenfolge XYZ), Skalierung bleibt erhalten.
static func rot(n: Node3D, x: float, y: float, z: float) -> void:
	n.quaternion = (Basis(Vector3.RIGHT, x) * Basis(Vector3.UP, y) * Basis(Vector3.BACK, z)).get_rotation_quaternion()


static func sm(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func ease_in(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x


static func ease_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	const C := 2.2
	return 1.0 + (C + 1.0) * pow(x - 1.0, 3.0) + C * pow(x - 1.0, 2.0)
