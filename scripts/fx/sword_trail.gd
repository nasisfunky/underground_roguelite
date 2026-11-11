class_name SwordTrail
extends MeshInstance3D
## Leuchtende Schwungspur aus den letzten Klingenpositionen (Weltkoordinaten).

const LIFETIME := 0.14

var emitting := false
var color := Color(0.55, 0.95, 1.0)
var _points: Array = []  # [base, tip, age]
var _im := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	material_override = m


func has_points() -> bool:
	return not _points.is_empty()


func push(base: Vector3, tip: Vector3, delta: float) -> void:
	for p in _points:
		p[2] += delta
	while not _points.is_empty() and _points[0][2] > LIFETIME:
		_points.pop_front()
	if emitting:
		_points.append([base, tip, 0.0])
	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	if _points.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _points:
		var a := 1.0 - clampf(p[2] / LIFETIME, 0.0, 1.0)
		_im.surface_set_color(Color(color, 0.0))
		_im.surface_add_vertex(p[0])
		_im.surface_set_color(Color(color, 0.85 * a * a))
		_im.surface_add_vertex(p[1])
	_im.surface_end()
