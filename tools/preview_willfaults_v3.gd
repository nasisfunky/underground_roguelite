extends Node
## Entwickler-Werkzeug: rendert Grimhauler, Hollow One und Willambers zu festen Zeitpunkten als PNG.
## Aufruf: godot --path . tools/preview_willfaults_v3.tscn -- <out_dir> <grimhauler|hollow|willamber> [hell|dunkel] [angriff] [clip] [kiln|rimefall|glowmire]

const VIEWS := [["front", 0.0], ["side", 1.35], ["back", 3.0], ["three", 0.7]]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	var who: String = args[1] if args.size() > 1 else "grimhauler"
	var bright := not "dunkel" in args
	var attack := "angriff" in args
	await get_tree().process_frame
	var w := Node3D.new()
	get_tree().root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.24, 0.25) if bright else Color(0.02, 0.035, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.7, 0.7)
	e.ambient_light_energy = 0.7 if bright else 0.08
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	w.add_child(env)
	if bright:
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.8, 2.6, 0)
		sun.light_energy = 0.9
		sun.shadow_enabled = true
		w.add_child(sun)
	else:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.8, 0.52)
		lamp.light_energy = 2.0
		lamp.omni_range = 7.0
		lamp.position = Vector3(1.2, 1.2, -1.6)
		w.add_child(lamp)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = LowPoly.mat(Color(0.12, 0.17, 0.18))
	w.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40
	w.add_child(cam)
	var subj: Node3D
	var dist := 4.0
	var look_y := 1.0
	match who:
		"grimhauler":
			var g := GrimhaulerBody.new()
			w.add_child(g)
			g.set_attacking(attack)
			subj = g
			dist = 8.5
			look_y = 1.4
		"willamber":
			var hero := ShadowBody.new()
			hero.outfit = "kiln"
			hero.has_lantern = true
			hero.build()
			w.add_child(hero)
			hero.rotation.y = PI * 0.15
			var sw := WillamberSwarm.new()
			w.add_child(sw)
			sw.set_attacking(attack)
			subj = sw
			dist = 4.6
			look_y = 0.5
		"hollow":
			var h := HollowOneBody.new()
			h.outfit = args[args.size() - 1] if args[args.size() - 1] in FrayedOutfit.CULTURES else ""
			w.add_child(h)
			h.set_attacking(attack)
			subj = h
			dist = 3.6
			look_y = 1.15
	# "clip": durchgehende Bildfolge mit 30 fps und langsam kreisender Kamera (für Videos)
	if "clip" in args:
		var dur := {"grimhauler": 4.8 if attack else 4.2, "hollow": 6.8 if attack else 5.0, "willamber": 8.0}[who] as float
		for f in int(dur * 30.0):
			for k in 2:
				subj.call("tick", 1.0 / 60.0)
			var a := 0.6 + 0.5 * sin(f / (dur * 30.0) * TAU)
			cam.position = Vector3(sin(a) * -dist, look_y + dist * 0.18, -cos(a) * dist)
			cam.look_at(Vector3(0, look_y, 0))
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(out_dir.path_join("f%04d.png" % f))
		get_tree().quit()
		return
	var times: Array = [0.4, 1.2, 1.8, 2.2, 3.4] if attack else [0.5, 1.4]
	if who == "willamber":
		times = [1.0, 2.5, 3.3, 4.1, 5.0]
	var t := 0.0
	for target_t in times:
		while t < target_t:
			subj.call("tick", 1.0 / 60.0)
			t += 1.0 / 60.0
			await get_tree().process_frame
		for v in VIEWS:
			if attack and v[0] != "three" and v[0] != "side":
				continue
			var a: float = v[1]
			cam.position = Vector3(sin(a) * -dist, look_y + dist * 0.18, -cos(a) * dist)
			cam.look_at(Vector3(0, look_y, 0))
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(out_dir.path_join("%s_%s_%.1f_%s.png" % [who, "atk" if attack else "walk", target_t, v[0]]))
	get_tree().quit()
