class_name FX
extends RefCounted
## Kleine, selbstaufräumende Effekte: Funken, Zahlen, Staub, Ringe.


static func _spawn_root(at: Vector3, tree_node: Node) -> Node3D:
	var n := Node3D.new()
	n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	tree_node.get_tree().current_scene.add_child(n)
	n.global_position = at
	return n


## Kantige Funkensplitter, die aus dem Trefferpunkt fliegen.
static func sparks(tree_node: Node, at: Vector3, color: Color, count := 8, power := 1.0) -> void:
	var root := _spawn_root(at, tree_node)
	var mat := LowPoly.mat(color, 4.0)
	var shard := LowPoly.prism(0.035 * power, 0.0, 0.22 * power, 3)
	for i in count:
		var mi := LowPoly.mesh_instance(shard, mat, root)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.3, 1.0), randf_range(-1, 1)).normalized()
		mi.basis = Basis(Quaternion(Vector3.UP, dir))
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "position", dir * randf_range(0.5, 1.1) * power, 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# kurzer Lichtblitz
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.5 * power
	l.omni_range = 3.0
	root.add_child(l)
	var tl := l.create_tween()
	tl.tween_property(l, "light_energy", 0.0, 0.15)
	root.get_tree().create_timer(0.35).timeout.connect(root.queue_free)


## Schadenszahl wie in WoW: springt hoch und verblasst.
static func number(tree_node: Node, at: Vector3, text: String, color: Color, big := false) -> void:
	var root := _spawn_root(at + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), tree_node)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0011 if big else 0.0008
	lbl.font_size = 48
	lbl.outline_size = 12
	lbl.modulate = color
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	root.add_child(lbl)
	lbl.scale = Vector3.ONE * 1.6
	var tw := lbl.create_tween().set_parallel()
	tw.tween_property(lbl, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "position:y", 1.1, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.tween_property(lbl, "outline_modulate:a", 0.0, 0.35).set_delay(0.55)
	root.get_tree().create_timer(1.0).timeout.connect(root.queue_free)


## Staubwolke beim Landen / Rollen.
static func dust(tree_node: Node, at: Vector3, amount := 6, size := 1.0) -> void:
	var root := _spawn_root(at + Vector3.UP * 0.05, tree_node)
	var mat := LowPoly.unshaded(Color(0.55, 0.68, 0.68, 0.45))
	var m := LowPoly.rock(0.12 * size, randi(), 5, 3)
	for i in amount:
		var mi := LowPoly.mesh_instance(m, mat, root)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * float(i) / amount + randf() * 0.5
		var d := Vector3(cos(a), 0.0, sin(a))
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "position", d * randf_range(0.4, 0.8) * size + Vector3.UP * randf_range(0.05, 0.25), 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ZERO, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	root.get_tree().create_timer(0.5).timeout.connect(root.queue_free)


## Flacher, sich ausbreitender Ring (z.B. Parade, schwerer Hieb).
static func ring(tree_node: Node, at: Vector3, color: Color, radius := 2.0, duration := 0.3) -> void:
	var root := _spawn_root(at + Vector3.UP * 0.06, tree_node)
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 16
	t.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var mi := LowPoly.mesh_instance(t, mat, root)
	mi.scale = Vector3(0.2, 0.05, 0.2)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, 0.05, radius), duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	root.get_tree().create_timer(duration + 0.05).timeout.connect(root.queue_free)
