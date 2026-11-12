extends Node
## Entwickler-Werkzeug: Standbilder von Feuerschale und Explosion. Aufruf (Forward+):
## godot --path . --rendering-driver vulkan tools/fx_shots.tscn -- <out_dir>
func _ready() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	await get_tree().process_frame
	var level: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	for i in 30: await get_tree().process_frame
	var p: Player = level.player
	# Feuerschale nah
	p.global_position = Vector3(1.6, 0.1, 8.6)
	p.facing_yaw = 2.6
	p.reset_physics_interpolation()
	p.cam.yaw = 2.2; p.cam.pitch = -0.12; p.cam.target_distance = 3.2; p.cam.distance = 3.2
	p.cam.snap_to_target()
	for i in 40: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(out_dir.path_join("fire_a.png"))
	for i in 7: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(out_dir.path_join("fire_b.png"))
	# Explosion im Übungsring
	p.global_position = Vector3(0, 0.1, -26.0)
	p.facing_yaw = 0.0
	p.reset_physics_interpolation()
	p.cam.yaw = 0.0; p.cam.pitch = -0.15; p.cam.target_distance = 4.2; p.cam.distance = 4.2
	p.cam.snap_to_target()
	for i in 20: await get_tree().process_frame
	Explosion.spawn(level, Vector3(3.2, 0.0, -31.5), 1.0)
	var t0 := Time.get_ticks_msec()
	for when in [0.03, 0.1, 0.25, 0.6, 1.4, 3.0]:
		while (Time.get_ticks_msec() - t0) / 1000.0 < when:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(out_dir.path_join("exp_%.2f.png" % when))
	get_tree().quit()
