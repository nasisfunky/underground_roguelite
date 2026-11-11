extends Node
## Entwickler-Werkzeug: spielt eine feste Abfolge (Stand, Anlaufen, Stoppen, Schwünge, Rolle, Block)
## mit einer Figur ab und speichert jedes n-te Bild. Aufruf: godot --path . tools/anim_sheet.tscn -- <out_dir>

const FPS := 60.0
const EVERY := 3


func _ready() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	await get_tree().process_frame
	var root := Node3D.new()
	add_child(root)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.32, 0.33)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.7, 0.7)
	e.ambient_light_energy = 0.9
	we.environment = e
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root.add_child(sun)
	var floor_mi := LowPoly.mesh_instance(LowPoly.box(Vector3(20, 0.1, 20)), LowPoly.mat(LowPoly.FLOOR), root, Vector3(0, -0.05, 0))
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b := ShadowBody.new()
	root.add_child(b)
	b.build()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(1.3, 1.3, -2.1)
	cam.look_at(Vector3(0, 0.95, -0.2))
	var frame := 0
	var t := 0.0
	var spd := 0.0
	while t < 6.6:
		var target_spd := 0.0
		b.action = &""
		b.block_amount = 0.0
		b.combat = 1.0 if t > 2.0 and t < 4.35 else 0.0
		if t > 0.5 and t < 2.0:
			target_spd = 4.8
		spd = move_toward(spd, target_spd, 20.0 / FPS)
		b.speed = spd
		b.local_move = Vector2(0, 1) if spd > 0.1 else Vector2.ZERO
		b.on_floor = true
		if t >= 2.4 and t < 3.35:
			b.action = &"swing"; b.swing_index = 0; b.action_t = (t - 2.4) / 0.95
		elif t >= 3.35 and t < 4.3:
			b.action = &"swing"; b.swing_index = 1; b.action_t = (t - 3.35) / 0.95
		elif t >= 4.4 and t < 5.25:
			b.action = &"roll"; b.action_t = (t - 4.4) / 0.85
		elif t >= 5.6 and t < 6.3:
			b.block_amount = clampf((t - 5.6) * 9.0, 0.0, 1.0)
		b.tick(1.0 / FPS)
		t += 1.0 / FPS
		if frame % EVERY == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("f_%03d.png" % (frame / EVERY)))
		else:
			await get_tree().process_frame
		frame += 1
	get_tree().quit()
