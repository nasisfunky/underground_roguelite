extends Node3D
## Entwickler-Werkzeug: rendert Hollowed und Splinterkin aus mehreren Blickwinkeln als PNG.
## Aufruf: godot --path . tools/preview_willfaults.tscn -- <out_dir> [hell|dunkel]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	var bright := args.size() < 2 or args[1] != "dunkel"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.24, 0.25) if bright else Color(0.02, 0.035, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.7, 0.7)
	e.ambient_light_energy = 0.7 if bright else 0.08
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	if bright:
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.8, 2.6, 0)
		add_child(sun)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Game.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	cs.position.y = -0.5
	floor_body.add_child(cs)
	var ground := LowPoly.mesh_instance(LowPoly.box(Vector3(40, 0.02, 40)), LowPoly.mat(Color(0.12, 0.17, 0.18)), floor_body)
	ground.position.y = -0.01
	add_child(floor_body)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var h := Hollowed.new()
	h.position = Vector3(-1.2, 0.05, 0)
	add_child(h)
	var k := Splinterkin.new()
	k.position = Vector3(1.2, 0.05, 0)
	add_child(k)
	for i in 90:
		await get_tree().physics_frame
	var shots := [["hollowed_front", h, Vector3(0.0, 1.2, -2.8), 1.0], ["hollowed_side", h, Vector3(2.6, 1.2, -0.8), 1.0],
		["kin_front", k, Vector3(0.3, 0.8, -1.6), 0.35], ["kin_side", k, Vector3(1.7, 0.7, 0.2), 0.35], ["kin_top", k, Vector3(-0.8, 1.6, 1.0), 0.35]]
	for s in shots:
		var n: Node3D = s[1]
		h.visible = n == h
		k.visible = n == k
		cam.position = n.global_position + s[2]
		cam.look_at(n.global_position + Vector3(0, s[3], 0))
		for f in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(s[0] + ".png"))
	get_tree().quit()
