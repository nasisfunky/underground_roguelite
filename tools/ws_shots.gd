extends Node
## Bildkontrolle der Animationswerkstatt (nur Entwicklung): Screenshots je Modus.
## Aufruf: godot --path . tools/ws_shots.tscn -- <ausgabeordner>

var out := "user://"
var ws: Node


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	ws = load("res://tools/anim_workshop.tscn").instantiate()
	add_child(ws)
	await _wait(20)
	await _shot("clip")
	# Ketten-Vorschau: Vorhand -> Rückhand, Bilder rund um den Übergang
	for tc in ws.find_children("*", "TabContainer", true, false):
		if tc.get_tab_count() >= 4:
			tc.current_tab = 3  # Timing (Kombo-Anschluss)
	ws.chain_next = "swing_1"
	ws._chain_select.select(2)
	ws._toggle_play()
	var shots := 0
	var was := 0
	for i in 400:
		await _wait(1)
		if ws._chain_phase == 1 and was == 0:
			await _shot("chain_0")
			shots = 1
		elif shots > 0 and shots < 4 and i % 6 == 0:
			await _shot("chain_%d" % shots)
			shots += 1
		was = ws._chain_phase
		if shots >= 4:
			break
	ws._toggle_play()
	ws.chain_next = ""
	ws._set_mode(ws.Mode.POSE)
	await _wait(10)
	await _shot("pose_idle")
	ws._set_weapon(&"spear")
	ws._set_offhand(&"")
	ws._set_pose("idle_2h")
	await _wait(10)
	await _shot("pose_spear2h")
	ws._set_mode(ws.Mode.GEAR)
	ws._set_gear("dagger_stow")
	await _wait(10)
	await _shot("gear_dagger")
	# Gegner
	ws._set_mode(ws.Mode.ENEMY)
	ws._set_enemy("hollowed")
	await _wait(5)
	await _shot("enemy_hollowed")
	ws._open_enemy_clip()
	ws._set_t(0.5)
	await _wait(10)
	await _shot("clip_hollowed")
	ws._set_mode(ws.Mode.ENEMY)
	for e in ["splinterkin", "grimhauler", "willamber"]:
		ws._set_enemy(e)
		var acts: Array = CreatureAnim.CREATURES[e].actions
		ws._set_enemy_action(acts[acts.size() - 1][0] if e != "willamber" else "strike")
		ws._set_t(0.5)
		await _wait(20)
		await _shot("enemy_" + e)
		ws._set_enemy_action(acts[0][0])
		ws._toggle_play()
		await _wait(40)
		await _shot("enemy_%s_loop" % e)
		ws._toggle_play()
	# Zusatz wirkt: Grimhauler-Kopf drehen
	ws._set_enemy("grimhauler")
	ws._set_enemy_action("attack")
	ws._set_t(0.3)
	await _wait(5)
	await _shot("grim_before")
	ws._param_changed("e.grimhauler.chest.y", 60.0)
	ws._param_changed("e.grimhauler.upL.x", -90.0)
	await _wait(5)
	await _shot("grim_after")
	print("keys: ", ws.clip.keys.size(), " sample: ", CreatureAnim.sample("grimhauler", "attack", 0.3))
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
