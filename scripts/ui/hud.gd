class_name HUD
extends CanvasLayer
## Spieler-HUD: Leben/Ausdauer, Aktionsleiste 1-9, Zielrahmen, Hilfe, Pause.

var player: Player
var _hp: UIBar
var _st: UIBar
var _slots: Array[AbilitySlot] = []
var _target_box: Control
var _target_name: Label
var _target_bar: UIBar
var _target_enemy: Enemy
var _help: Label
var _mode: Label
var _room: Label
var _debug: Label
var _pause: Control
var _marker: TargetMarker


func setup(p: Player) -> void:
	player = p
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Aktionsleiste + Balken unten mittig ---
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -18
	bottom.add_theme_constant_override("separation", 5)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_hp = _bar(Color(0.78, 0.26, 0.18), Vector2(560, 16))
	_st = _bar(Color(0.30, 0.85, 0.88), Vector2(560, 9))
	bottom.add_child(_hp)
	bottom.add_child(_st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(row)
	for i in 9:
		var s := AbilitySlot.new()
		s.custom_minimum_size = Vector2(56, 56)
		s.key_text = str(i + 1)
		row.add_child(s)
		_slots.append(s)

	# --- Zielrahmen oben mittig ---
	_target_box = VBoxContainer.new()
	_target_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_target_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_target_box.offset_top = 22
	_target_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_target_box)
	_target_name = Label.new()
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name.add_theme_font_size_override("font_size", 18)
	_target_name.add_theme_color_override("font_color", Color(1.0, 0.78, 0.45))
	_target_name.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_target_name.add_theme_constant_override("outline_size", 6)
	_target_box.add_child(_target_name)
	_target_bar = _bar(Color(0.78, 0.26, 0.18), Vector2(320, 14))
	_target_box.add_child(_target_bar)
	_target_box.visible = false

	# --- Hilfe oben links ---
	_help = _label(13, Color(0.8, 0.92, 0.92, 0.9))
	_help.position = Vector2(18, 16)
	_help.text = """WASD  move        Space  jump (hold = higher)
Shift  roll (in move direction)        Hold right mouse / Q  block (early = parry)
Mouse  camera        Mouse wheel  zoom        Hold Alt  free cursor
Left click  attack (click again in rhythm = combo)
Middle mouse  thrust (sword alt attack, more reach)
1  Heavy Strike        2  Shield Bash
F1 Help   F2 Change culture   F3 Debug   Esc Pause"""
	root.add_child(_help)
	_mode = _label(13, Color(1.0, 0.85, 0.5, 0.9))
	_mode.position = Vector2(18, 192)
	root.add_child(_mode)

	# --- Raumtitel ---
	_room = _label(30, Color(0.85, 0.97, 0.97))
	_room.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_room.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_room.offset_top = 120
	_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room.modulate.a = 0.0
	root.add_child(_room)

	_debug = _label(13, Color(0.7, 1.0, 0.7))
	_debug.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_debug.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_debug.offset_right = -18
	_debug.offset_top = 16
	_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug.visible = false
	root.add_child(_debug)

	_build_pause(root)

	_marker = TargetMarker.new()
	add_child(_marker)

	p.health_changed.connect(_on_health)
	p.stamina_changed.connect(func(c, m): _st.set_value(c / m))
	p.ability_used.connect(func(i): _slots[i].flash = 1.0)
	Game.room_entered.connect(show_room)
	_hp.text = "%d / %d" % [p.health, p.max_health]


func _on_health(c: float, m: float) -> void:
	_hp.set_value(c / m)
	_hp.text = "%d / %d" % [c, m]


func _bar(c: Color, s: Vector2) -> UIBar:
	var b := UIBar.new()
	b.fill_color = c
	b.custom_minimum_size = s
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _label(fs: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_pause(root: Control) -> void:
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0.02, 0.05, 0.06, 0.7)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	root.add_child(_pause)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	_pause.add_child(box)
	var title := _label(36, Color(0.85, 0.97, 0.97))
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(220, 40)
	resume.pressed.connect(_toggle_pause)
	box.add_child(resume)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)


func show_room(room_name: String) -> void:
	_room.text = room_name
	var tw := create_tween()
	tw.tween_property(_room, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.6)
	tw.tween_property(_room, "modulate:a", 0.0, 0.8)


func _on_target_changed(t: Node3D) -> void:
	if _target_enemy and is_instance_valid(_target_enemy) and _target_enemy.health_changed.is_connected(_on_target_health):
		_target_enemy.health_changed.disconnect(_on_target_health)
	_target_enemy = t as Enemy
	_marker.target = t
	_target_box.visible = t != null
	if _target_enemy:
		_target_name.text = _target_enemy.display_name
		_target_enemy.health_changed.connect(_on_target_health)
		_on_target_health(_target_enemy.health, _target_enemy.max_health)


func _on_target_health(c: float, m: float) -> void:
	_target_bar.set_value(c / m)
	_target_bar.text = "%d / %d" % [c, m]


func _toggle_pause() -> void:
	Game.paused = not Game.paused
	get_tree().paused = Game.paused
	_pause.visible = Game.paused
	if player.input:
		if Game.paused:
			player.input.release_mouse()
		else:
			player.input.capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible
	elif event.is_action_pressed("toggle_debug"):
		_debug.visible = not _debug.visible


func _process(_delta: float) -> void:
	if not player:
		return
	_mode.text = ""
	for i in 9:
		var a: Ability = player.abilities[i]
		var s := _slots[i]
		s.empty = a == null
		if a:
			s.label_text = a.short_name
			s.cooldown_left = a.cooldown_left
			s.cooldown_frac = a.cooldown_left / a.cooldown if a.cooldown > 0.0 else 0.0
	if _debug.visible:
		_debug.text = "FPS %d\nState %s\nLight %.2f\nSpeed %.1f m/s" % [Engine.get_frames_per_second(), Player.State.keys()[player.state], Game.light_level_at(player.global_position + Vector3.UP), player.get_horizontal_speed()]
