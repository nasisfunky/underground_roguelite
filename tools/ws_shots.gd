extends Node
## Bildkontrolle der Animationswerkstatt (nur Entwicklung): Screenshots je Modus.

var out := "user://"

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	var ws: Node = load("res://tools/anim_workshop.tscn").instantiate()
	add_child(ws)
	await _wait(20)
	await _shot("clip")
	ws._select_key(1, true)
	ws.playing = false
	ws._view(0.0, -0.1)
	await _wait(5)
	await _shot("body_before")
	var tabs: TabContainer = ws.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	ws._param_changed("b.leg_l_spread", 30.0)
	ws._param_changed("b.leg_r_swing", 40.0)
	ws._param_changed("b.leg_r_knee", 60.0)
	ws._param_changed("b.elbow_r", 70.0)
	ws._param_changed("b.head_pitch", 30.0)
	ws._param_changed("b.bank", 15.0)
	await _wait(5)
	await _shot("body_after")
	tabs.current_tab = 1
	await _wait(3)
	await _shot("body_tab")
	ws._view(PI * 0.5, -0.1)
	await _wait(3)
	await _shot("body_side")
	ws._view(2.4, -0.25)
	ws._set_mode(ws.Mode.POSE)
	await _wait(10)
	await _shot("pose_idle")
	ws._set_weapon(&"spear")
	ws._set_offhand(&"")
	ws._set_pose("idle_2h")
	await _wait(10)
	await _shot("pose_spear2h")
	ws._set_pose("stow")
	await _wait(10)
	await _shot("pose_stow")
	ws._set_weapon(&"greataxe")
	ws._set_pose("walk")
	await _wait(30)
	await _shot("pose_axe_walk")
	ws._set_mode(ws.Mode.GEAR)
	ws._set_gear("dagger_stow")
	await _wait(10)
	await _shot("gear_dagger")
	ws._set_gear("lantern_held")
	await _wait(10)
	await _shot("gear_lantern")
	get_tree().quit()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
