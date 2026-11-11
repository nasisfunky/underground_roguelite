extends Node
## Entwickler-Werkzeug: startet das Level, stellt den Spieler an einige Orte und speichert Screenshots.
## Aufruf: godot --path . tools/screenshots.tscn -- <out_dir>

func _ready() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	await get_tree().process_frame
	var level: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await _frames(30)
	var p: Player = level.player
	var shots := [
		["01_hall", Vector3(0, 0.1, 9), 0.0, -0.25, 7.0],
		["02_hall_parcours", Vector3(3, 0.1, 4), -1.0, -0.3, 7.5],
		["03_training", Vector3(0, 0.1, -26), 0.0, -0.3, 7.0],
		["04_ramp", Vector3(0, 0.1, -44), 0.0, -0.2, 6.0],
		["05_sealed_hall", Vector3(0, -2.9, -62), 0.0, -0.12, 7.0],
		["06_closeup", Vector3(0, 0.1, -30), 2.6, -0.15, 3.2],
		["07_husk_close", Vector3(-3, -2.9, -69), 0.0, -0.1, 3.5],
	]
	for s in shots:
		p.global_position = s[1]
		p.velocity = Vector3.ZERO
		p.facing_yaw = s[2]
		p.reset_physics_interpolation()
		p.cam.yaw = s[2] if s[0] != "06_closeup" else s[2] + PI
		p.cam.pitch = s[3]
		p.cam.target_distance = s[4]
		p.cam.distance = s[4]
		p.cam.snap_to_target()
		await _frames(25)
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
