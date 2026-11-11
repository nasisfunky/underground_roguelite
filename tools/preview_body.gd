extends Node
## Entwickler-Werkzeug: rendert die Spielfigur in einigen Posen als PNG.
## Aufruf: godot --path . tools/preview_body.tscn -- <out_dir>

func _ready() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	await get_tree().process_frame
	var root3d := Node3D.new()
	get_tree().root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.3, 0.32)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.7, 0.7)
	e.ambient_light_energy = 0.8
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root3d.add_child(sun)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	var poses := [["idle", &"", 0.0, 0.0, 0.0], ["run", &"", 0.0, 6.5, 0.0], ["swing0", &"swing", 0.42, 0.0, 0.0], ["swing1", &"swing", 0.30, 0.0, 0.0], ["heavy", &"swing", 0.36, 0.0, 0.0], ["block", &"", 0.0, 0.0, 1.0], ["roll", &"roll", 0.35, 0.0, 0.0]]
	var bodies := []
	var x := 0.0
	for p in poses:
		var b := ShadowBody.new()
		root3d.add_child(b)
		b.build()
		b.position.x = x
		x += 1.4
		b.action = p[1]
		b.action_t = p[2]
		b.speed = p[3]
		b.local_move = Vector2(0, 1) if p[3] > 0 else Vector2.ZERO
		b.block_amount = p[4]
		b.swing_index = 2 if p[0] == "heavy" else (1 if p[0] == "swing1" else 0)
		bodies.append(b)
	for i in 60:
		for b in bodies:
			b.tick(1.0 / 60.0) if b.action != &"swing" else b.tick(1.0 / 60.0)
		await get_tree().process_frame
	# Jede Pose einzeln aus zwei Blickwinkeln
	for i in bodies.size():
		var b: Node3D = bodies[i]
		for v in [["a", Vector3(-0.8, 1.1, -1.5)], ["b", Vector3(1.7, 0.95, 0.2)]]:
			for o in bodies:
				o.visible = o == b
			cam.position = b.position + v[1]
			cam.look_at(b.position + Vector3(0, 1.0, 0))
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(out_dir.path_join("pose_%d_%s.png" % [i, v[0]]))
	get_tree().quit()
