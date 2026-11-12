extends Node3D
## Animation Workshop: Kampfanimationen (Keyframes) ansehen und bearbeiten.
## Starten: tools/anim_workshop.tscn öffnen und "Aktuelle Szene starten" (F6).
## Gespeichert wird nach res://data/anims/<clip>.json; das Spiel lädt diese Dateien direkt.
##
## Bedienung (steht auch im Fenster):
##   Gelbe Kugel = Schwertgriff, cyan = Klingenspitze, orange = Schild, kleine orange = Schild-Ausrichtung.
##   Kugel mit LMB ziehen -> setzt/ändert den Keyframe an der aktuellen Zeit (Auto-Key).
##   RMB ziehen = Kamera drehen, MMB ziehen = verschieben, Mausrad = Zoom.

const HANDLE_PICK_PX := 16.0
const KEY_SNAP := 0.004

var body: ShadowBody
var cam: Camera3D
var clip_name := "swing_0"
var clip: Dictionary
var t := 0.0
var playing := false
var speed := 1.0
var springs_in_play := true
var combat_stance := true
var sel_key := -1
var dirty := false

var _cam_yaw := 2.4
var _cam_pitch := -0.25
var _cam_dist := 3.2
var _cam_target := Vector3(0, 0.95, -0.25)
var _orbiting := false
var _panning := false

var _handles := {}  # name -> MeshInstance3D
var _drag_handle := ""
var _drag_plane: Plane
var _hover_handle := ""
var _undo: Array = []
var _last_undo_push := -10.0
var _pause_t := 0.0  # Wiedergabe: kurze Pause in der Grundhaltung zwischen Durchläufen
var _updating_ui := false

# UI
var _clip_select: OptionButton
var _key_list: ItemList
var _spins := {}
var _status: Label
var _clip_warn: Label
var _time_label: Label
var _play_btn: Button
var _timeline: Timeline
var _help: Label


func _ready() -> void:
	_build_world()
	_build_ui()
	_load_clip(clip_name)
	_update_camera()


# ==================================================================
# Welt
# ==================================================================

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.15, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.7, 0.72)
	e.ambient_light_energy = 0.8
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, -2.3, 0)
	fill.light_energy = 0.35
	add_child(fill)

	var floor_mi := LowPoly.mesh_instance(LowPoly.box(Vector3(8, 0.1, 8)), LowPoly.mat(LowPoly.FLOOR), self, Vector3(0, -0.05, 0))
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Gitter alle 0,5 m
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-6, 7):
		var f := i * 0.5
		grid.surface_add_vertex(Vector3(f, 0.002, -3))
		grid.surface_add_vertex(Vector3(f, 0.002, 3))
		grid.surface_add_vertex(Vector3(-3, 0.002, f))
		grid.surface_add_vertex(Vector3(3, 0.002, f))
	grid.surface_end()
	var gm := MeshInstance3D.new()
	gm.mesh = grid
	gm.material_override = LowPoly.unshaded(Color(0.3, 0.42, 0.42))
	add_child(gm)
	# Referenz-Ziel in typischer Schlagdistanz (1,6 m vor der Figur)
	var ghost := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.6
	ghost.mesh = cap
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(1.0, 0.5, 0.3, 0.18)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = gmat
	ghost.position = Vector3(0, 0.8, -1.6)
	add_child(ghost)

	body = ShadowBody.new()
	body.outfit = "kiln"  # gleiche Figur wie im Spiel (Frayed-Stil)
	add_child(body)
	body.build()
	body.on_floor = true

	cam = Camera3D.new()
	cam.fov = 50
	add_child(cam)

	for h in [["grip", Color(1.0, 0.85, 0.2), 0.045], ["tip", Color(0.3, 1.0, 1.0), 0.04],
			["shield", Color(1.0, 0.55, 0.2), 0.045], ["shield_front", Color(1.0, 0.7, 0.4), 0.03]]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = h[2]
		sm.height = h[2] * 2.0
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = 10
		m.albedo_color = h[1]
		mi.material_override = m
		mi.set_meta("color", h[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_handles[h[0]] = mi


# ==================================================================
# UI
# ==================================================================

func _panel(parent: Control) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.1, 0.92)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	return v


func _btn(parent: Control, text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _spin(parent: Control, key: String, label: String, lo: float, hi: float, step: float) -> SpinBox:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 92
	h.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.x = 150
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v): _on_spin(key, v))
	h.add_child(s)
	_spins[key] = s
	return s


func _vec_spins(parent: Control, key: String, label: String, lo: float, hi: float) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color(0.7, 0.85, 0.85))
	parent.add_child(l)
	var h := HBoxContainer.new()
	parent.add_child(h)
	for axis in ["x", "y", "z"]:
		var s := SpinBox.new()
		s.min_value = lo
		s.max_value = hi
		s.step = 0.01
		s.prefix = axis
		s.custom_minimum_size.x = 92
		s.value_changed.connect(func(v): _on_spin(key + "." + axis, v))
		h.add_child(s)
		_spins[key + "." + axis] = s


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# --- obere Leiste ---
	var top := HBoxContainer.new()
	top.position = Vector2(10, 10)
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	var title := Label.new()
	title.text = "Animation Workshop  "
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 1.0))
	top.add_child(title)
	_clip_select = OptionButton.new()
	_clip_select.focus_mode = Control.FOCUS_NONE
	for n in AnimLibrary.CLIPS:
		_clip_select.add_item(AnimLibrary.clip(n).label)
	_clip_select.item_selected.connect(func(i): _switch_clip(AnimLibrary.CLIPS[i]))
	top.add_child(_clip_select)
	_btn(top, "Save", _save, "Save this animation to data/anims (Ctrl+S)")
	_btn(top, "Revert", _revert, "Reload from file, discarding unsaved changes")
	_btn(top, "Undo", _do_undo, "Ctrl+Z")
	_btn(top, "Check clip", _check_whole_clip, "Scan the whole animation for blade/arm passing through the body")
	var cb := CheckBox.new()
	cb.text = "Combat stance"
	cb.button_pressed = combat_stance
	cb.focus_mode = Control.FOCUS_NONE
	cb.tooltip_text = "Start/end pose: combat stance (target in reach) or relaxed"
	cb.toggled.connect(func(on): combat_stance = on)
	top.add_child(cb)
	for v in [["Front", 0.0, -0.1], ["Side", PI * 0.5, -0.1], ["3/4", 2.4, -0.25], ["Back", PI, -0.2], ["Top", 0.0001, -1.45]]:
		_btn(top, v[0], _view.bind(v[1], v[2]))

	# --- rechte Spalte: Keyframe-Werte ---
	var right := _panel(root)
	var right_pc: Control = right.get_parent()
	right_pc.anchor_left = 1.0
	right_pc.anchor_right = 1.0
	right_pc.anchor_top = 0.0
	right_pc.anchor_bottom = 1.0
	right_pc.offset_left = -340
	right_pc.offset_right = -10
	right_pc.offset_top = 52
	right_pc.offset_bottom = -10
	var kh := Label.new()
	kh.text = "Keyframes"
	kh.add_theme_font_size_override("font_size", 17)
	right.add_child(kh)
	_key_list = ItemList.new()
	_key_list.custom_minimum_size = Vector2(0, 110)
	_key_list.focus_mode = Control.FOCUS_NONE
	_key_list.item_selected.connect(func(i): _select_key(i, true))
	right.add_child(_key_list)
	var kb := HBoxContainer.new()
	right.add_child(kb)
	_btn(kb, "Add key", _add_key_here, "Add a keyframe at the playhead (K)")
	_btn(kb, "Delete", _delete_key, "Delete selected keyframe (Del)")
	_btn(kb, "Blade roll -", func(): _roll_blade(-0.26), "Rotate blade edge around its length")
	_btn(kb, "+", func(): _roll_blade(0.26))
	_spin(right, "t", "Time", 0.01, 0.99, 0.005)
	_spin(right, "twist", "Body twist", -1.5, 1.5, 0.01)
	_spin(right, "lean", "Lean (-fwd)", -1.2, 1.0, 0.01)
	_spin(right, "drop", "Hips down", -0.1, 0.35, 0.005)
	_vec_spins(right, "grip", "Sword grip (chest space)", -1.0, 1.2)
	_vec_spins(right, "dir", "Blade direction", -1.0, 1.0)
	_vec_spins(right, "shield", "Shield position", -1.0, 1.2)
	var ch := Label.new()
	ch.text = "Animation"
	ch.add_theme_font_size_override("font_size", 17)
	right.add_child(ch)
	_spin(right, "duration", "Duration (s)", 0.3, 3.0, 0.01)
	_spin(right, "hit", "Hit at", 0.05, 0.95, 0.005)
	_spin(right, "trail_a", "Trail from", 0.0, 1.0, 0.005)
	_spin(right, "trail_b", "Trail to", 0.0, 1.0, 0.005)
	_clip_warn = Label.new()
	_clip_warn.autowrap_mode = TextServer.AUTOWRAP_WORD
	_clip_warn.custom_minimum_size.x = 300
	right.add_child(_clip_warn)

	# --- untere Leiste: Zeitleiste + Transport ---
	var bottom := _panel(root)
	var bottom_pc: Control = bottom.get_parent()
	bottom_pc.anchor_left = 0.0
	bottom_pc.anchor_right = 1.0
	bottom_pc.anchor_top = 1.0
	bottom_pc.anchor_bottom = 1.0
	bottom_pc.offset_left = 10
	bottom_pc.offset_right = -350
	bottom_pc.offset_top = -112
	bottom_pc.offset_bottom = -10
	_timeline = Timeline.new()
	_timeline.ws = self
	_timeline.custom_minimum_size = Vector2(0, 54)
	bottom.add_child(_timeline)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	bottom.add_child(tr)
	_play_btn = _btn(tr, "Play", _toggle_play, "Space")
	_btn(tr, "|<", func(): _set_t(0.0))
	_btn(tr, "< key", func(): _jump_key(-1), "Up")
	_btn(tr, "key >", func(): _jump_key(1), "Down")
	var sp := OptionButton.new()
	sp.focus_mode = Control.FOCUS_NONE
	for s in ["Speed 1x", "0.5x", "0.25x", "0.1x"]:
		sp.add_item(s)
	sp.item_selected.connect(func(i): speed = [1.0, 0.5, 0.25, 0.1][i])
	tr.add_child(sp)
	var spr := CheckBox.new()
	spr.text = "Springs (as in game)"
	spr.button_pressed = springs_in_play
	spr.focus_mode = Control.FOCUS_NONE
	spr.tooltip_text = "On: playback with the game's spring smoothing. Paused/scrubbing always shows the exact keyframe pose."
	spr.toggled.connect(func(on): springs_in_play = on)
	tr.add_child(spr)
	_time_label = Label.new()
	tr.add_child(_time_label)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	tr.add_child(_status)

	_help = Label.new()
	_help.position = Vector2(12, 52)
	_help.add_theme_color_override("font_color", Color(0.75, 0.85, 0.85))
	_help.add_theme_font_size_override("font_size", 13)
	_help.text = ("Drag handles with LMB:  yellow = sword grip,  cyan = blade tip,  orange = shield,  small orange = shield facing\n"
		+ "Dragging at a time without a key creates one (auto-key).  Red handle = arm can't reach.\n"
		+ "RMB drag = orbit   MMB drag = pan   Wheel = zoom   Space = play   K = add key   Del = delete key\n"
		+ "Left/Right = step (Shift = bigger)   Up/Down = previous/next key   Ctrl+S = save   Ctrl+Z = undo")
	root.add_child(_help)


# ==================================================================
# Clip-Verwaltung
# ==================================================================

func _load_clip(n: String) -> void:
	clip_name = n
	clip = AnimLibrary.clip(n)
	_undo.clear()
	dirty = false
	sel_key = -1
	_refresh_keys()
	_refresh_fields()


func _switch_clip(n: String) -> void:
	if dirty:
		_flash("Unsaved changes in %s are kept until you close the workshop." % clip_name)
	_load_clip(n)


func _save() -> void:
	var err := AnimLibrary.save(clip_name, clip)
	if err == OK:
		dirty = false
		_flash("Saved data/anims/%s.json" % clip_name)
	else:
		_flash("Save failed (%s)" % error_string(err))


func _revert() -> void:
	AnimLibrary.reload()
	_load_clip(clip_name)
	_flash("Reverted to saved file")


func _push_undo(coalesce := false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if coalesce and now - _last_undo_push < 0.6:
		return
	_last_undo_push = now
	_undo.append(AnimLibrary.duplicate_clip(clip))
	if _undo.size() > 60:
		_undo.pop_front()


func _do_undo() -> void:
	if _undo.is_empty():
		_flash("Nothing to undo")
		return
	clip = _undo.pop_back()
	AnimLibrary.set_clip(clip_name, clip)
	sel_key = mini(sel_key, clip.keys.size() - 1)
	dirty = true
	_refresh_keys()
	_refresh_fields()


func _changed() -> void:
	dirty = true
	_refresh_keys()
	_refresh_fields()


# ==================================================================
# Keyframes
# ==================================================================

func _key_at(time: float) -> int:
	for i in clip.keys.size():
		if absf(clip.keys[i].t - time) < KEY_SNAP:
			return i
	return -1


## Neuer Key an der Abspielposition mit der aktuell sichtbaren (exakten) Pose.
func _add_key_here() -> int:
	if t <= 0.01 or t >= 0.99:
		_flash("Start and end are the stance pose. Move the playhead inside the animation.")
		return -1
	var existing := _key_at(t)
	if existing >= 0:
		_select_key(existing)
		return existing
	_push_undo()
	_pose_now(0.0, true)
	var s: Array = body.swing_sample
	var k := {
		"t": snappedf(t, 0.005),
		"grip": body._scale_pose(s[0]),
		"dir": (s[1] as Vector3).normalized(),
		"flat": (s[2] as Vector3).normalized(),
		"twist": s[3], "lean": s[4], "drop": s[5],
		"shield": body._scale_pose(s[7]),
		"shield_front": (s[8] as Vector3).normalized(),
	}
	clip.keys.append(k)
	clip.keys.sort_custom(func(a, b): return a.t < b.t)
	sel_key = clip.keys.find(k)
	_set_t(k.t)
	_changed()
	return sel_key


func _delete_key() -> void:
	if sel_key < 0 or sel_key >= clip.keys.size():
		return
	_push_undo()
	clip.keys.remove_at(sel_key)
	sel_key = mini(sel_key, clip.keys.size() - 1)
	_changed()


func _select_key(i: int, jump := false) -> void:
	sel_key = i
	if jump and i >= 0 and i < clip.keys.size():
		_set_t(clip.keys[i].t)
	_refresh_fields()
	if _key_list.item_count > i and i >= 0:
		_key_list.select(i)


func _jump_key(dir: int) -> void:
	var times: Array = [0.0]
	for k in clip.keys:
		times.append(k.t)
	times.append(1.0)
	var target := t
	if dir > 0:
		for x in times:
			if x > t + 0.001:
				target = x
				break
	else:
		for i in range(times.size() - 1, -1, -1):
			if times[i] < t - 0.001:
				target = times[i]
				break
	_set_t(target)
	var k := _key_at(target)
	if k >= 0:
		_select_key(k)


func _roll_blade(angle: float) -> void:
	var k := _key_at(t)
	if k < 0:
		k = _add_key_here()
	if k < 0:
		return
	_push_undo(true)
	var key: Dictionary = clip.keys[k]
	key.flat = (key.flat as Vector3).rotated((key.dir as Vector3).normalized(), angle)
	_changed()


func _set_t(v: float) -> void:
	t = clampf(v, 0.0, 1.0)
	var k := _key_at(t)
	if k >= 0 and k != sel_key:
		sel_key = k
		_refresh_fields()
		if _key_list.item_count > k:
			_key_list.select(k)


func _refresh_keys() -> void:
	_key_list.clear()
	for k in clip.keys:
		_key_list.add_item("t = %.3f    twist %+.2f   lean %+.2f" % [k.t, k.twist, k.lean])
	if sel_key >= 0 and sel_key < clip.keys.size():
		_key_list.select(sel_key)
	if _timeline:
		_timeline.queue_redraw()


func _refresh_fields() -> void:
	_updating_ui = true
	_spins.duration.value = clip.duration
	_spins.hit.value = clip.hit
	_spins.trail_a.value = clip.trail.x
	_spins.trail_b.value = clip.trail.y
	var has: bool = sel_key >= 0 and sel_key < clip.keys.size()
	for key in ["t", "twist", "lean", "drop", "grip.x", "grip.y", "grip.z", "dir.x", "dir.y", "dir.z", "shield.x", "shield.y", "shield.z"]:
		var s: SpinBox = _spins[key]
		s.editable = has
		if not has:
			continue
		var k: Dictionary = clip.keys[sel_key]
		var parts: PackedStringArray = key.split(".")
		if parts.size() == 1:
			s.value = k[parts[0]]
		else:
			var v: Vector3 = k[parts[0]]
			s.value = v[["x", "y", "z"].find(parts[1])]
	_updating_ui = false


func _on_spin(key: String, v: float) -> void:
	if _updating_ui:
		return
	_push_undo(true)
	match key:
		"duration":
			clip.duration = v
		"hit":
			clip.hit = v
		"trail_a":
			clip.trail = Vector2(v, clip.trail.y)
		"trail_b":
			clip.trail = Vector2(clip.trail.x, v)
		_:
			if sel_key < 0 or sel_key >= clip.keys.size():
				return
			var k: Dictionary = clip.keys[sel_key]
			var parts: PackedStringArray = key.split(".")
			if parts.size() == 1:
				k[parts[0]] = v
				if parts[0] == "t":
					clip.keys.sort_custom(func(a, b): return a.t < b.t)
					sel_key = clip.keys.find(k)
					t = v
			else:
				var vec: Vector3 = k[parts[0]]
				vec[["x", "y", "z"].find(parts[1])] = v
				if parts[0] == "dir":
					vec = vec.normalized() if vec.length() > 0.01 else Vector3(0, 0, -1)
				k[parts[0]] = vec
	dirty = true
	_refresh_keys()
	if _timeline:
		_timeline.queue_redraw()


# ==================================================================
# Wiedergabe / Pose
# ==================================================================

func _toggle_play() -> void:
	playing = not playing
	_pause_t = 0.0
	_play_btn.text = "Pause" if playing else "Play"


func _pose_now(delta: float, exact: bool) -> void:
	body.snap = exact
	body.combat = 1.0 if combat_stance else 0.0
	body.speed = 0.0
	body.local_move = Vector2.ZERO
	if playing and _pause_t > 0.0:
		body.action = &""
	else:
		body.action = &"swing"
		body.swing_index = AnimLibrary.CLIPS.find(clip_name)
		body.action_t = t
	body.tick(maxf(delta, 1.0 / 120.0))


func _process(delta: float) -> void:
	if playing:
		if _pause_t > 0.0:
			_pause_t -= delta
		else:
			t += delta * speed / maxf(clip.duration, 0.05)
			if t >= 1.0:
				t = 0.0
				_pause_t = 0.45 / speed
	_pose_now(delta, not (playing and springs_in_play))
	_update_handles()
	var d := body.blade_clip_depth()
	_clip_warn.text = "" if d < 0.02 else "Warning: blade/arm %d cm inside the body here" % roundi(d * 100.0)
	_clip_warn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_time_label.text = "t = %.3f   (%.2f s of %.2f s)%s" % [t, t * clip.duration, clip.duration, "   *unsaved*" if dirty else ""]
	_timeline.queue_redraw()


func _update_handles() -> void:
	var pts := body.sword_points()
	_handles.grip.global_position = body.sword.global_position
	_handles.tip.global_position = pts[1]
	_handles.shield.global_position = body.shield.global_position
	_handles.shield_front.global_position = body.shield.global_transform * Vector3(0, 0, -0.3)
	# Griff außer Reichweite -> rot
	var inv := body.chest.global_transform.affine_inverse()
	var reach := (inv * body.sword.global_position).distance_to(ShadowBody.SHOULDER_R)
	for n in _handles:
		var mi: MeshInstance3D = _handles[n]
		var c: Color = mi.get_meta("color")
		if n == "grip" and reach > ShadowBody.UPPER_ARM + ShadowBody.LOWER_ARM + 0.02:
			c = Color(1.0, 0.2, 0.2)
		if n == _hover_handle or n == _drag_handle:
			c = c.lightened(0.5)
		(mi.material_override as StandardMaterial3D).albedo_color = c
		mi.scale = Vector3.ONE * (1.35 if n == _drag_handle else 1.0)


func _check_whole_clip() -> void:
	var was_playing := playing
	playing = false
	var keep_t := t
	var worst := 0.0
	var worst_t := 0.0
	for i in 101:
		t = i / 100.0
		_pose_now(0.0, true)
		var d := body.blade_clip_depth()
		if d > worst:
			worst = d
			worst_t = t
	t = keep_t
	playing = was_playing
	if worst < 0.02:
		_flash("Clip OK: blade and arm stay outside the body")
	else:
		_flash("Blade/arm %d cm inside the body at t = %.2f" % [roundi(worst * 100.0), worst_t])
		_set_t(worst_t)


func _flash(msg: String) -> void:
	_status.text = msg
	var tw := create_tween()
	_status.modulate.a = 1.0
	tw.tween_interval(3.0)
	tw.tween_property(_status, "modulate:a", 0.0, 1.0)


# ==================================================================
# Eingabe: Kamera und Griffe
# ==================================================================

func _view(yaw: float, pitch: float) -> void:
	_cam_yaw = yaw
	_cam_pitch = pitch
	_update_camera()


func _update_camera() -> void:
	var off := Vector3(sin(_cam_yaw) * cos(_cam_pitch), -sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch)) * _cam_dist
	# yaw 0 = Kamera vor der Figur (Figur schaut nach -Z)
	off = Vector3(off.x, off.y, -off.z)
	cam.position = _cam_target + off
	cam.look_at(_cam_target, Vector3.UP if absf(_cam_pitch) < 1.4 else Vector3(0, 0, -1))


func _pick_handle(mp: Vector2) -> String:
	var best := ""
	var best_d := HANDLE_PICK_PX
	for n in _handles:
		var p: Vector3 = _handles[n].global_position
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(mp)
		if d < best_d:
			best_d = d
			best = n
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist = maxf(0.8, _cam_dist * 0.9)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist = minf(10.0, _cam_dist * 1.1)
				_update_camera()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var h := _pick_handle(mb.position)
					if h != "":
						_begin_drag(h)
				else:
					_drag_handle = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_cam_yaw -= mm.relative.x * 0.008
			_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.006, -1.45, 0.6)
			_update_camera()
		elif _panning:
			var right := cam.global_basis.x
			var up := cam.global_basis.y
			_cam_target += (-right * mm.relative.x + up * mm.relative.y) * 0.0015 * _cam_dist
			_update_camera()
		elif _drag_handle != "":
			_drag_to(mm.position)
		else:
			_hover_handle = _pick_handle(mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		var big := 0.05 if k.shift_pressed else 0.01
		match k.keycode:
			KEY_SPACE:
				_toggle_play()
			KEY_K:
				_add_key_here()
			KEY_DELETE, KEY_BACKSPACE:
				_delete_key()
			KEY_LEFT:
				_set_t(t - big)
			KEY_RIGHT:
				_set_t(t + big)
			KEY_UP:
				_jump_key(-1)
			KEY_DOWN:
				_jump_key(1)
			KEY_S:
				if k.ctrl_pressed:
					_save()
			KEY_Z:
				if k.ctrl_pressed:
					_do_undo()


func _begin_drag(h: String) -> void:
	if playing:
		_toggle_play()
	var k := _key_at(t)
	if k < 0:
		k = _add_key_here()
		if k < 0:
			return
	else:
		_push_undo()
	_select_key(k)
	_drag_handle = h
	_drag_plane = Plane(-cam.global_basis.z, _handles[h].global_position)


func _drag_to(mp: Vector2) -> void:
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var hit: Variant = _drag_plane.intersects_ray(from, dir)
	if hit == null or sel_key < 0:
		return
	var key: Dictionary = clip.keys[sel_key]
	var local: Vector3 = body.chest.global_transform.affine_inverse() * (hit as Vector3)
	match _drag_handle:
		"grip":
			key.grip = local
		"tip":
			var d: Vector3 = local - (key.grip as Vector3)
			if d.length() > 0.05:
				key.dir = d.normalized()
		"shield":
			key.shield = local
		"shield_front":
			var d: Vector3 = local - (key.shield as Vector3)
			if d.length() > 0.03:
				key.shield_front = d.normalized()
	dirty = true
	_refresh_fields()


# ==================================================================
# Zeitleiste
# ==================================================================

class Timeline extends Control:
	var ws: Node
	var _drag_key := -1
	var _scrubbing := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _x(time: float) -> float:
		return 8.0 + time * (size.x - 16.0)

	func _time(x: float) -> float:
		return clampf((x - 8.0) / (size.x - 16.0), 0.0, 1.0)

	func _draw() -> void:
		var c: Dictionary = ws.clip
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.06))
		# Trail-Fenster und Trefferzeitpunkt
		draw_rect(Rect2(_x(c.trail.x), 4, _x(c.trail.y) - _x(c.trail.x), h - 8), Color(0.3, 0.9, 1.0, 0.12))
		draw_line(Vector2(_x(c.hit), 2), Vector2(_x(c.hit), h - 2), Color(1.0, 0.3, 0.25), 2.0)
		draw_string(get_theme_default_font(), Vector2(_x(c.hit) + 4, 14), "hit", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.45, 0.4))
		# Skala
		for i in 11:
			var x := _x(i / 10.0)
			draw_line(Vector2(x, h - 10), Vector2(x, h - 2), Color(0.4, 0.5, 0.5), 1.0)
		# Keys (Start/Ende = Grundhaltung, grau)
		for tt in [0.0, 1.0]:
			_diamond(Vector2(_x(tt), h * 0.5), 6.0, Color(0.45, 0.5, 0.5))
		for i in c.keys.size():
			var col := Color(1.0, 0.85, 0.2) if i == ws.sel_key else Color(0.85, 0.9, 0.9)
			_diamond(Vector2(_x(c.keys[i].t), h * 0.5), 8.0, col)
		# Abspielposition
		var px := _x(ws.t)
		draw_line(Vector2(px, 0), Vector2(px, h), Color(0.4, 1.0, 1.0), 2.0)

	func _diamond(p: Vector2, r: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_key = -1
				for i in ws.clip.keys.size():
					if absf(_x(ws.clip.keys[i].t) - event.position.x) < 8.0:
						_drag_key = i
						ws._push_undo()
						ws._select_key(i, true)
						break
				_scrubbing = _drag_key < 0
				if _scrubbing:
					ws._set_t(_time(event.position.x))
			else:
				if _drag_key >= 0:
					ws.clip.keys.sort_custom(func(a, b): return a.t < b.t)
					ws._refresh_keys()
				_drag_key = -1
				_scrubbing = false
			accept_event()
		elif event is InputEventMouseMotion:
			if _drag_key >= 0:
				# Key zeitlich verschieben (Timing ändern)
				var nt := clampf(snappedf(_time(event.position.x), 0.005), 0.02, 0.98)
				ws.clip.keys[_drag_key].t = nt
				ws.t = nt
				ws.dirty = true
				ws._refresh_fields()
			elif _scrubbing:
				ws._set_t(_time(event.position.x))
			queue_redraw()
