class_name TargetMarker
extends Node3D
## Markierung des aktuellen Ziels: drehender Bodenring + schwebender Pfeil über dem Kopf.

var target: Node3D:
	set(v):
		target = v
		visible = v != null
		if v:
			_pop = 1.0

var _ring: MeshInstance3D
var _arrow: MeshInstance3D
var _t := 0.0
var _pop := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.2, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = false
	var t := TorusMesh.new()
	t.inner_radius = 0.82
	t.outer_radius = 0.9
	t.rings = 6
	t.ring_segments = 3
	_ring = LowPoly.mesh_instance(t, mat, self)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var amat := mat.duplicate()
	amat.no_depth_test = true
	amat.render_priority = 10
	_arrow = LowPoly.mesh_instance(LowPoly.prism(0.13, 0.0, 0.26, 3), amat, self)
	_arrow.rotation.x = PI
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		visible = false
		return
	_t += delta
	_pop = maxf(_pop - delta * 5.0, 0.0)
	var r: float = (target.radius if "radius" in target else 0.45) * 1.6
	var base := target.get_global_transform_interpolated().origin
	_ring.global_position = base + Vector3.UP * 0.05
	_ring.rotation.y = _t * 1.2
	_ring.scale = Vector3(r, 0.04, r) * (1.0 + _pop * 0.6)
	var h: float = target.target_height if "target_height" in target else 2.2
	_arrow.global_position = base + Vector3.UP * (h + 0.35 + sin(_t * 4.0) * 0.08)
	_arrow.scale = Vector3.ONE * (1.0 + _pop)
