class_name ModelParts
extends RefCounted
## Lädt die in Blender gebauten Teile (tools/blender/build_dummy.py) aus einer .glb
## und liefert sie als Name -> Mesh. Wird pro Datei nur einmal geladen.

static var _cache: Dictionary = {}


static func load_parts(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var parts: Dictionary = {}
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("Modell nicht gefunden: " + path)
		return parts
	var root := scene.instantiate()
	_collect(root, parts)
	root.free()
	_cache[path] = parts
	return parts


static func _collect(n: Node, parts: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		parts[String(n.name)] = (n as MeshInstance3D).mesh
	for c in n.get_children():
		_collect(c, parts)


## Setzt pro Fläche ein Ersatzmaterial, wenn der Materialname in `overrides` vorkommt.
static func apply_overrides(mi: MeshInstance3D, overrides: Dictionary) -> void:
	var mesh := mi.mesh
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m and overrides.has(m.resource_name):
			mi.set_surface_override_material(i, overrides[m.resource_name])
