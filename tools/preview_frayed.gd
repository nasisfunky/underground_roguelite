extends Node
## Entwickler-Werkzeug: rendert die Frayed-Shades aller Kulturen in einigen Posen als PNG.
## Aufruf: godot --path . tools/preview_frayed.tscn -- <out_dir> [hell|dunkel] [nohem] [flash] [motion] [lampe]

const POSES := [["idle", &"", 0.0, 0.0, 0.0, 0.0], ["run", &"", 0.0, 4.8, 0.0, 0.0], ["guard", &"", 0.0, 0.0, 0.0, 1.0],
	["swing", &"swing", 0.45, 0.0, 0.0, 1.0], ["block", &"", 0.0, 0.0, 1.0, 1.0], ["roll", &"roll", 0.3, 0.0, 0.0, 0.0]]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	var bright := args.size() < 2 or args[1] != "dunkel"
	await get_tree().process_frame
	var root3d := Node3D.new()
	get_tree().root.add_child(root3d)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.24, 0.25) if bright else Color(0.02, 0.035, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.7, 0.7)
	e.ambient_light_energy = 0.7 if bright else 0.08
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root3d.add_child(env)
	if bright:
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.8, 2.6, 0)
		sun.light_energy = 0.9
		root3d.add_child(sun)
	# "lampe": warmes Punktlicht nah an der Figur, wie die Laterne im Spiel (prüft Körper gegen Flammensaum)
	var lamp: OmniLight3D = null
	if "lampe" in args:
		lamp = OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.8, 0.52)
		lamp.light_energy = 2.5
		lamp.omni_range = 6.0
		root3d.add_child(lamp)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = LowPoly.mat(Color(0.12, 0.17, 0.18))
	root3d.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40
	root3d.add_child(cam)
	var bodies: Array[ShadowBody] = []
	var x := 0.0
	for c in FrayedOutfit.CULTURES:
		for pz in POSES:
			var b := ShadowBody.new()
			b.outfit = c
			b.has_lantern = true
			root3d.add_child(b)
			b.build()
			b.position = Vector3(x, 0, 0)
			x += 3.0
			b.action = pz[1]
			b.action_t = pz[2]
			b.speed = pz[3]
			b.local_move = Vector2(0, 1) if pz[3] > 0 else Vector2.ZERO
			b.block_amount = pz[4]
			b.combat = pz[5]
			bodies.append(b)
			if "flash" in args:
				b.flash(999.0)
			if "nohem" in args:
				for n in b.find_children("HeadHem", "", true, false):
					n.visible = false
	# "motion": Figuren drehen sich hin und her, damit der Stoff schwingt (Stoff-Prüfung)
	var motion := "motion" in args
	for i in 60:
		for b in bodies:
			if motion:
				b.rotation.y = sin(i * 0.12) * 1.3
			b.tick(1.0 / 60.0)
		await get_tree().physics_frame
	# reine Rechenzeit pro Figur und Tick (Animation + Stoff), ohne Rendern
	var t0 := Time.get_ticks_usec()
	for i in 30:
		for b in bodies:
			b.tick(1.0 / 60.0)
	print("Tick pro Figur: %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / (30.0 * bodies.size())))
	var views := [["front", Vector3(0.0, 1.15, -2.6)], ["side", Vector3(2.4, 1.1, -0.9)], ["back", Vector3(-0.6, 1.2, 2.5)], ["face", Vector3(0.15, 1.55, -0.95)]]
	for i in bodies.size():
		var b := bodies[i]
		for v in views:
			if POSES[i % POSES.size()][0] != "idle" and v[0] in ["back", "face"]:
				continue
			for o in bodies:
				o.visible = o == b
			cam.position = b.position + v[1]
			if lamp:
				lamp.position = b.position + Vector3(0.9, 1.6, -1.2)
			cam.look_at(b.position + Vector3(0, 1.48 if v[0] == "face" else 0.95, 0))
			for k in 3:
				b.tick(1.0 / 60.0)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(out_dir.path_join("%s_%s_%s.png" % [b.outfit, POSES[i % POSES.size()][0], v[0]]))
	get_tree().quit()
