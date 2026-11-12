extends Node3D
## Bestiarium: die drei neuen Willfaults (Grimhauler, Hollow One, Willambers) zum Ansehen in einer
## dunklen Halle, mit ihren Animationen. Ersetzt keine Gegner im Spiel und hat noch keine Kampf-KI.
## Steuerung: Linke Maustaste ziehen = Kamera drehen, Mausrad = Zoom, 1/2/3 = Willfault wählen,
## Leertaste = Unterwegs/Angriff, L = Licht, C = Kultur des Hollow One, Esc = Beenden.
## Für Bilder: godot --path . res://scenes/bestiary.tscn -- shots <out_dir>

const STATIONS := [
	["Grimhauler", Vector3(-7.0, 0, 0), 8.5, 1.5],
	["Hollow One", Vector3(0, 0, 0), 3.8, 1.15],
	["Willambers", Vector3(7.0, 0, 0), 4.6, 0.6],
]

var grim: GrimhaulerBody
var hollow: HollowOneBody
var swarm: WillamberSwarm
var hero: ShadowBody
var attacking := false
var bright := true
var focus := 0
var _cam: Camera3D
var _yaw := 0.6
var _pitch := 0.22
var _dist := 8.5
var _env: Environment
var _sun: DirectionalLight3D
var _label: Label
var _hollow_culture := 0
var _grim_angle := 0.0
var _dragging := false


func _ready() -> void:
	_build_world()
	grim = GrimhaulerBody.new()
	add_child(grim)
	_spawn_hollow()
	hero = ShadowBody.new()
	hero.outfit = "kiln"
	hero.has_lantern = true
	hero.build()
	add_child(hero)
	hero.position = STATIONS[2][1]
	hero.rotation.y = PI * 0.15
	swarm = WillamberSwarm.new()
	add_child(swarm)
	swarm.position = STATIONS[2][1]
	_cam = Camera3D.new()
	_cam.fov = 45
	add_child(_cam)
	_build_ui()
	_set_focus(0)
	_apply_light()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "shots":
		_shots(args[1])


func _spawn_hollow() -> void:
	if hollow:
		hollow.queue_free()
	hollow = HollowOneBody.new()
	hollow.outfit = FrayedOutfit.CULTURES[_hollow_culture]
	hollow.position = STATIONS[1][1]
	add_child(hollow)
	hollow.set_attacking(attacking)


func _build_world() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.22, 0.36, 0.38)
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.15
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.012, 0.022, 0.026)
	_env.fog_density = 0.035
	_env.glow_enabled = true
	_env.glow_bloom = 0.02
	_env.glow_hdr_threshold = 1.1
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(-0.9, 2.5, 0)
	_sun.light_energy = 0.8
	_sun.shadow_enabled = true
	add_child(_sun)
	# Boden aus alten Steinplatten
	var stone := LowPoly.mat(Color(0.13, 0.17, 0.17))
	var stone2 := LowPoly.mat(Color(0.11, 0.14, 0.145))
	for x in range(-12, 13, 2):
		for z in range(-10, 11, 2):
			var tile := LowPoly.mesh_instance(LowPoly.box(Vector3(1.94, 0.2, 1.94)), stone if (x + z) % 4 == 0 else stone2, self, Vector3(x, -0.1 - randf() * 0.015, z))
			tile.rotation.y = randf_range(-0.01, 0.01)
	# Säulen der alten Halle
	for x in [-10.5, -3.5, 3.5, 10.5]:
		for z in [-8.0, 8.0]:
			LowPoly.mesh_instance(LowPoly.prism(0.75, 0.65, 9.0, 6), LowPoly.mat(Color(0.12, 0.15, 0.15)), self, Vector3(x, 4.5, z))
	# Lichter: warme Laterne je Station, kalter Kristall dahinter (the Bright)
	for s in STATIONS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.52)
		l.light_energy = 1.6
		l.omni_range = 7.0
		l.omni_attenuation = 1.4
		l.shadow_enabled = true
		l.position = (s[1] as Vector3) + Vector3(1.6, 1.6, -2.0)
		add_child(l)
		var c := OmniLight3D.new()
		c.light_color = LowPoly.CYAN
		c.light_energy = 1.2
		c.omni_range = 6.0
		c.position = (s[1] as Vector3) + Vector3(-2.0, 1.4, 2.4)
		add_child(c)
		LowPoly.mesh_instance(LowPoly.crystal(0.7, 0.18), LowPoly.mat(LowPoly.CYAN, 3.0), self, (s[1] as Vector3) + Vector3(-2.0, 0.0, 2.4))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_label)


func _update_label() -> void:
	_label.text = "Willfault Bestiary — %s\n1 / 2 / 3: Grimhauler / Hollow One / Willambers\nSpace: %s   L: %s light   C: Hollow One culture (%s)\nLeft drag: orbit   Wheel: zoom   Esc: quit" % [
		STATIONS[focus][0], "Attacking" if attacking else "Roaming", "Bright" if bright else "Dark", FrayedOutfit.CULTURES[_hollow_culture]]


func _set_focus(i: int) -> void:
	focus = i
	_dist = STATIONS[i][2]
	_update_label()


func _apply_light() -> void:
	_env.background_color = Color(0.11, 0.16, 0.17) if bright else Color(0.004, 0.007, 0.009)
	_env.ambient_light_energy = 0.55 if bright else 0.075
	_sun.visible = bright
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(1.5, _dist * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(20.0, _dist * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.006
		_pitch = clampf(_pitch + mm.relative.y * 0.004, -0.2, 1.3)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_set_focus(0)
			KEY_2:
				_set_focus(1)
			KEY_3:
				_set_focus(2)
			KEY_SPACE:
				_set_attacking(not attacking)
			KEY_L:
				bright = not bright
				_apply_light()
			KEY_C:
				_hollow_culture = (_hollow_culture + 1) % FrayedOutfit.CULTURES.size()
				_spawn_hollow()
				_update_label()
			KEY_ESCAPE:
				get_tree().quit()


func _set_attacking(on: bool) -> void:
	attacking = on
	grim.set_attacking(on)
	hollow.set_attacking(on)
	swarm.set_attacking(on)
	_update_label()


func _process(delta: float) -> void:
	_step(delta)
	var c: Vector3 = STATIONS[focus][1] + Vector3(0, STATIONS[focus][3], 0)
	if focus == 0:
		c = grim.position + Vector3(0, STATIONS[0][3], 0)
	_cam.position = c + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.look_at(c)


func _step(delta: float) -> void:
	# Grimhauler stampft im Kreis durch die Halle; im Angriff bleibt er stehen
	if not attacking:
		var r := 2.6
		_grim_angle += GrimhaulerBody.GROUND_SPEED / r * delta
	var center: Vector3 = STATIONS[0][1]
	grim.position = center + Vector3(cos(_grim_angle), 0, sin(_grim_angle)) * 2.6
	grim.rotation.y = PI - _grim_angle  # Blick entlang der Kreisbahn (gegen den Uhrzeigersinn)
	grim.tick(delta)
	hollow.tick(delta)
	hero.tick(delta)
	swarm.tick(delta)


## Bilder für die Prüfung: jede Station unterwegs und im Angriff
func _shots(dir: String) -> void:
	set_process(false)
	for mode in [false, true]:
		_set_attacking(mode)
		for i in 3:
			_set_focus(i)
			for k in 150:
				_step(1.0 / 60.0)
			for v in [[0.6, 0.22], [2.2, 0.35]]:
				_yaw = v[0]
				_pitch = v[1]
				_process_cam_only()
				await get_tree().process_frame
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(dir.path_join("%d_%s_%s.png" % [i, "atk" if mode else "walk", str(v[0])]))
	bright = false
	_apply_light()
	for i in 3:
		_set_focus(i)
		_process_cam_only()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("%d_dark.png" % i))
	get_tree().quit()


func _process_cam_only() -> void:
	var c: Vector3 = STATIONS[focus][1] + Vector3(0, STATIONS[focus][3], 0)
	if focus == 0:
		c = grim.position + Vector3(0, STATIONS[0][3], 0)
	_cam.position = c + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.look_at(c)
