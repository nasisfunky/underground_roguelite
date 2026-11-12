extends Node
## Entwickler-Werkzeug: spielt Bewegungsabläufe mit dem echten Spieler im Testlevel ab
## (Rollen, Ziehen/Wegstecken, Licht, Sprint, Klettern, Hochziehen, Schwimmen, Reinspringen, Abrollen)
## und speichert je Ablauf einen Filmstreifen. Aufruf: godot --path . tools/move_strips.tscn -- <out_dir> [name...]

const W := 300
const H := 260
const COLS := 10

var out_dir := ""
var p: Player
var level: Node
var cam: Camera3D
var cam_off := Vector3(3.0, 1.0, 0.0)  ## relativ zum Spieler (Welt), Blick auf Brusthöhe
var cam_look_h := 0.9
const C := Vector3(35, 0, -34)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0]
	var only := args.slice(1)
	await get_tree().process_frame
	level = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	# zum Begutachten heller ausleuchten
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.7, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	level.add_child(sun)
	var we: WorldEnvironment = level.find_children("*", "WorldEnvironment", true, false)[0]
	we.environment.ambient_light_energy = 0.9
	we.environment.fog_density = 0.004
	we.environment.volumetric_fog_enabled = false
	await _frames(10)
	p = level.player
	p.get_node("HUD") if p.has_node("HUD") else null
	for n in level.get_children():
		if n is CanvasLayer:
			n.visible = false
	cam = Camera3D.new()
	cam.fov = 40.0
	level.add_child(cam)
	cam.make_current()
	var all := ["roll_fwd", "roll_dirs", "draw_light", "walk_sprint", "climb", "swim", "jump_in", "fall_rolls"]
	for n in all:
		if only.is_empty() or n in only:
			await call("_s_" + n)
	get_tree().quit()


# --- Abläufe ---

func _s_roll_fwd() -> void:
	_tp(C + Vector3(-4, 0.1, 8), PI * 0.5)
	cam_off = Vector3(0, 1.0, 4.0)
	await _frames(20)
	p.input._roll_pressed = true
	await _record("roll_fwd", 3, 30)


func _s_roll_dirs() -> void:
	_tp(C + Vector3(-4, 0.1, 8), 0.0)
	p.input._draw = true
	await _frames(50)
	var imgs: Array[Image] = []
	for a in ["move_back", "move_left", "move_right"]:
		_tp(C + Vector3(-4, 0.1, 8), 0.0)
		cam_off = Vector3(3.6, 1.0, 0.6) if a == "move_back" else Vector3(0.5, 1.0, 4.0)
		await _frames(25)
		Input.action_press(a)
		await _frames(2)
		p.input._roll_pressed = true
		await _frames(2)
		Input.action_release(a)
		imgs.append_array(await _grab(3, 20))
	_save("roll_dirs", imgs, 20)
	p.input._draw = true
	await _frames(50)


func _s_draw_light() -> void:
	_tp(C + Vector3(-4, 0.1, 8), 0.0)
	cam_off = Vector3(1.6, 0.9, -2.4)
	await _frames(20)
	var imgs: Array[Image] = []
	p.input._draw = true
	imgs.append_array(await _grab(4, 10))  # Ziehen
	p.input._light = true
	imgs.append_array(await _grab(8, 10))  # Schild weg, Licht vor
	p.input._light = true
	imgs.append_array(await _grab(8, 10))  # Licht weg, Schild her
	p.input._draw = true
	imgs.append_array(await _grab(4, 10))  # alles weg
	_save("draw_light", imgs, 10)


func _s_walk_sprint() -> void:
	_tp(C + Vector3(-12, 0.1, 6), -PI * 0.5)
	cam_off = Vector3(0, 1.0, 3.6)
	await _frames(10)
	Input.action_press("move_forward")
	await _frames(40)
	var imgs: Array[Image] = await _grab(3, 10)
	Input.action_press("sprint")
	await _frames(40)
	imgs.append_array(await _grab(3, 10))
	Input.action_release("sprint")
	Input.action_release("move_forward")
	_save("walk_sprint", imgs, 10)
	await _frames(40)


func _s_climb() -> void:
	var tw := C + Vector3(5, 0, -9)
	_tp(tw + Vector3(0, 0.1, 3.8), 0.0)
	p._set_stamina(100)
	cam_off = Vector3(3.2, 1.2, 2.4)
	await _frames(10)
	Input.action_press("move_forward")
	var imgs: Array[Image] = await _grab(10, 20)
	Input.action_release("move_forward")
	_save("climb", imgs, 10)
	# Hochziehen oben
	_tp(tw + Vector3(0, 2.3, 3.45), 0.0)
	p._climb_n = Vector3(0, 0, 1)
	p._set_state(Player.State.CLIMB)
	p._stow_all_now()
	cam_off = Vector3(3.0, 1.0, 1.6)
	Input.action_press("move_forward")
	imgs = await _grab(4, 20)
	Input.action_release("move_forward")
	_save("mantle", imgs, 10)


func _s_swim() -> void:
	_tp(C + Vector3(-4, -1.58, -6), 0.0)
	p._enter_swim()
	cam_off = Vector3(3.2, 1.6, 0.0)
	cam_look_h = 1.0
	await _frames(30)
	var imgs: Array[Image] = await _grab(6, 10)  # Wassertreten
	Input.action_press("move_forward")
	await _frames(40)
	imgs.append_array(await _grab(4, 20))  # Brustschwimmen
	_save("swim", imgs, 10)
	# bis zur Nordkante und raus
	cam_off = Vector3(3.2, 1.3, 0.8)
	var fr := 0
	while p.state == Player.State.SWIM and fr < 400:
		await get_tree().physics_frame
		fr += 1
	imgs = await _grab(4, 20)
	Input.action_release("move_forward")
	_save("climb_out", imgs, 10)
	cam_look_h = 0.9


func _s_jump_in() -> void:
	var tw := C + Vector3(5, 0, -9)
	_tp(tw + Vector3(-1.2, 4.3, 0), PI * 0.5)
	cam_off = Vector3(0.0, 0.8, 5.0)
	await _frames(15)
	Input.action_press("move_forward")
	p.input._jump_pressed = true
	var imgs: Array[Image] = await _grab(4, 30)
	Input.action_release("move_forward")
	_save("jump_in", imgs, 10)


func _s_fall_rolls() -> void:
	var tw := C + Vector3(5, 0, -9)
	_tp(tw + Vector3(1.0, 4.3, 0), -PI * 0.5)
	cam_off = Vector3(0.0, 1.2, 5.5)
	await _frames(15)
	Input.action_press("move_forward")
	var imgs: Array[Image] = await _grab(3, 30)
	Input.action_release("move_forward")
	_tp(tw + Vector3(0, 4.3, -2.0), 0.0)
	cam_off = Vector3(4.5, 1.2, 0.0)
	await _frames(15)
	Input.action_press("move_forward")
	imgs.append_array(await _grab(3, 30))
	Input.action_release("move_forward")
	_save("fall_rolls", imgs, 10)


# --- Hilfen ---

func _tp(pos: Vector3, yaw: float) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.facing_yaw = yaw
	p.cam.yaw = yaw
	p._set_state(Player.State.MOVE)
	p.collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMIES
	p.reset_physics_interpolation()


func _place_cam() -> void:
	var at := p.global_position + Vector3.UP * cam_look_h
	cam.global_position = at + cam_off
	cam.look_at(at)


func _grab(every: int, count: int) -> Array[Image]:
	var out: Array[Image] = []
	for i in count:
		for k in every:
			await get_tree().physics_frame
		_place_cam()
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		out.append(img)
	return out


func _record(name: String, every: int, count: int) -> void:
	_save(name, await _grab(every, count), COLS)


func _save(name: String, imgs: Array[Image], cols: int) -> void:
	if imgs.is_empty():
		return
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var rows := int(ceil(float(imgs.size()) / cols))
	var sheet := Image.create(w * cols, h * rows, false, imgs[0].get_format())
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(out_dir.path_join(name + ".png"))
	print("strip ", name, " ", imgs.size())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
