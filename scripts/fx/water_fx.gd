class_name WaterFX
extends RefCounted
## Wasser-Effekte im Cel-Look: weiße Ringwellen auf der Oberfläche und Spritzer beim Eintauchen.

static var _ring_mat: StandardMaterial3D
static var _drop_mat: StandardMaterial3D


static func _ring() -> StandardMaterial3D:
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.albedo_texture = _crisp_ring()
		_ring_mat.albedo_color = Color(0.85, 0.97, 1.0, 0.8)
		_ring_mat.vertex_color_use_as_albedo = false
		_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _ring_mat


## Harter, dünner weißer Ring (Cel-Look) statt weichem Rauchring.
static func _crisp_ring() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var wob := sin(atan2(y - n * 0.5, x - n * 0.5) * 7.0) * 0.015
			var a := 1.0 if absf(d - 0.88 - wob) < 0.05 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _drop() -> StandardMaterial3D:
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_drop_mat.albedo_color = Color(0.86, 0.97, 1.0)
		_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_drop_mat.billboard_keep_scale = true
	return _drop_mat


static func _root(tree_node: Node, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	tree_node.get_tree().current_scene.add_child(n)
	n.global_position = at
	return n


## Flache Ringwelle auf der Oberfläche (at = Punkt auf der Wasserlinie).
static func ripple(tree_node: Node, at: Vector3, radius := 0.9, duration := 0.9) -> void:
	var root := _root(tree_node, at + Vector3.UP * 0.03)
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _ring().duplicate()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * radius * 0.25
	root.add_child(mi)
	var tw := root.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(root.queue_free)


## Spritzer: Ringe, Tropfen, die hochfliegen und zurückfallen, eine kurze weiße Krone.
static func splash(tree_node: Node, at: Vector3, power := 1.0) -> void:
	ripple(tree_node, at, 1.2 * power + 0.4, 0.8)
	ripple(tree_node, at, 2.2 * power + 0.6, 1.4)
	var root := _root(tree_node, at)
	var count := int(10 + 14 * power)
	for i in count:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.035, 0.07) * (0.8 + 0.4 * power)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		mi.mesh = sm
		mi.material_override = _drop()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var a := randf() * TAU
		var r := randf_range(0.15, 0.45)
		var start := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var vel := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.8, 2.0) * power + Vector3.UP * randf_range(2.0, 4.2) * (0.6 + 0.4 * power)
		var life := vel.y / 9.8 * 2.0
		mi.position = start
		var tw := mi.create_tween()
		tw.tween_method(func(t: float):
			mi.position = start + vel * t + Vector3.DOWN * 4.9 * t * t
			mi.scale = Vector3.ONE * (1.0 - 0.6 * t / life), 0.0, life, life)
		tw.tween_callback(mi.queue_free)
	# Krone: kurzer weißer Kegel, der aufgeht und zusammenfällt
	var crown := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.2
	cm.height = 0.5
	cm.radial_segments = 10
	cm.cap_top = false
	cm.cap_bottom = false
	crown.mesh = cm
	var cmat: StandardMaterial3D = _drop().duplicate()
	cmat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown.material_override = cmat
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown.position.y = 0.2
	var pw := minf(power, 1.1)
	crown.scale = Vector3(0.6, 0.2, 0.6) * pw
	root.add_child(crown)
	var tc := root.create_tween().set_parallel()
	tc.tween_property(crown, "scale", Vector3(1.3, 1.2, 1.3) * pw, 0.18).set_ease(Tween.EASE_OUT)
	tc.tween_property(cmat, "albedo_color:a", 0.0, 0.3).set_delay(0.08)
	tc.chain().tween_interval(1.2)
	tc.chain().tween_callback(root.queue_free)
