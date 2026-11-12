extends Node3D
## Animation Workshop: Kampfanimationen, Waffenhaltungen und verstaute Ausrüstung ansehen und bearbeiten.
## Starten: tools/anim_workshop.tscn öffnen und "Aktuelle Szene starten" (F6).
##
## Drei Modi (oben umschalten):
##   Animations     – Keyframes der Kampfanimationen (data/anims/<clip>.json, eigene Versionen je Waffe: <clip>@<waffe>.json).
##                    Pro Keyframe: Waffenhand, Zweithand, Rumpf, Kopf, Beine, Ellbogen.
##   Weapon poses   – Haltung je Waffe im Stehen, Gehen, in Kampfhaltung, beidhändig und weggesteckt (data/poses/<waffe>.json).
##   Stowed gear    – Schild auf dem Rücken, Zweithand-Dolch, Laterne am Gürtel / vorgehalten (data/poses/gear.json).
## Griffe (Kugeln) mit LMB ziehen; alle Werte gibt es auch als Regler rechts. Das Spiel lädt die Dateien direkt.

const HANDLE_PICK_PX := 16.0
const KEY_SNAP := 0.004
const DEG := PI / 180.0

enum Mode { CLIP, POSE, GEAR, ENEMY }

var body: ShadowBody
var cam: Camera3D
var mode := Mode.CLIP
var culture := "kiln"
var weapon_id := &"sword"
var offhand := &"shield"  ## &"shield", &"dagger", &"light", &""

# Animation
var base_clip := "swing_0"  ## allgemeiner Name
var clip_name := "swing_0"  ## bearbeiteter Clip (ggf. "<clip>@<waffe>")
var clip: Dictionary
var t := 0.0
var playing := false
var speed := 1.0
var springs_in_play := true
var combat_stance := true
var sel_key := -1
var _clipboard: Dictionary = {}

# Haltungen / Ausrüstung
var pose_name := "idle"
var gear_item := "shield_back"
# Gegner
var enemy_id := "splinterkin"
var enemy_action := "move"
var _enemy: Node3D
var _enemy_walk := 0.0
var _body_look := ""  ## "", "hollowed", "hollow_one": Figur im Animationsmodus sieht wie dieser Gegner aus
var _enemy_select: OptionButton
var _eaction_select: OptionButton
var _eaction_info: Label
var _enemy_redirect: Control
var _enemy_edit: Control
var _enemy_boxes := {}
var _figure_ctrls: Array = []
var _springs_cb: CheckBox  # Gegner -> Control mit seinen Gelenkreglern
const ENEMY_CHOICES := [["hollowed", "Hollowed"], ["hollow_one", "Hollow One"], ["splinterkin", "Splinterkin"],
	["grimhauler", "Grimhauler"], ["willamber", "Willamber"]]
const ENEMY_CAM := {"splinterkin": [Vector3(0, 0.35, -0.2), 2.4], "grimhauler": [Vector3(0, 1.45, -0.3), 6.8],
	"willamber": [Vector3(0, 0.55, -0.2), 2.8]}

var dirty := {}  ## Datei -> true (ungespeichert)
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
var _pause_t := 0.0
var _updating_ui := false
var _walk_t := 0.0

# UI
var _mode_btns: Array[Button] = []
var _clip_select: OptionButton
var _variant_cb: CheckBox
var _variant_info: Label
var _weapon_select: OptionButton
var _off_select: OptionButton
var _culture_select: OptionButton
var _ckey_list: ItemList
var _ekey_list: ItemList
## Key-Liste des aktuellen Modus (Animationen oder Gegner)
var _key_list: ItemList:
	get:
		return _ekey_list if mode == Mode.ENEMY else _ckey_list
var _params := {}  # key -> {"slider", "spin", "scale"}
var _status: Label
var _clip_warn: Label
var _time_label: Label
var _play_btn: Button
var _timeline: Timeline
var _help: Label
var _bottom: Control
var _panels := {}  # Mode -> Control
var _pose_select: OptionButton
var _pose_info: Label
var _gear_select: OptionButton
var _pose_held_box: Control
var _pose_stow_box: Control
var _two_hand_row: Control
var _pose_off_box: Control
var _copy_2h_btn: Button
var _gear_dir_box: Control
var _gear_front_box: Control
var _gear_yaw_row: Control

const WEAPON_CHOICES := [[&"sword", "Culture blade"], [&"spear", "Spear"], [&"greataxe", "Greataxe"], [&"dagger", "Dagger"]]
const OFF_CHOICES := [[&"shield", "Shield"], [&"dagger", "Off-hand dagger"], [&"light", "Light"], [&"", "Empty (two-handed)"]]


func _ready() -> void:
	_build_world()
	_build_ui()
	_load_clip(base_clip)
	_set_mode(Mode.CLIP)
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

	_rebuild_body()

	cam = Camera3D.new()
	cam.fov = 50
	add_child(cam)

	for h in [["grip", Color(1.0, 0.85, 0.2), 0.045], ["tip", Color(0.3, 1.0, 1.0), 0.04],
			["off", Color(1.0, 0.55, 0.2), 0.045], ["off_front", Color(1.0, 0.7, 0.4), 0.03]]:
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


func _rebuild_body() -> void:
	if body:
		body.free()
	body = ShadowBody.new()
	body.outfit = culture
	body.has_lantern = true
	match _body_look:
		"hollowed":  # wie Hollowed._ready
			body.willfault = true
			body.hem_layers = 4
			body.head_layers = 12
			body.hem_heat = Hollowed.HEM_HEAT
			body.hem_hot = Hollowed.HEM_HOT
			body.eye_color = Hollowed.VIOLET
			body.has_shield = false
		"hollow_one":
			body.ghost = true
			body.has_shield = false
			body.has_lantern = false
	add_child(body)
	body.build()
	body.on_floor = true
	_apply_weapon()


func _apply_weapon() -> void:
	body.set_weapon(WeaponDef.make(&"sword" if _body_look != "" else weapon_id))
	body.set_equipment(true, _effective_off())


## Zweithand, wie sie im Spiel wäre (Zweihandaxt: nur Licht oder leer).
func _effective_off() -> StringName:
	if _body_look != "":
		return &""
	var w := WeaponDef.make(weapon_id)
	if not w.allows_offhand() and offhand != &"light":
		return &""
	if offhand == &"shield" and not body.has_shield:
		return &""
	return offhand


# ==================================================================
# UI-Bausteine
# ==================================================================

func _panel(parent: Control) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.1, 0.93)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
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


func _heading(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
	parent.add_child(l)
	return l


func _note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.6, 0.72, 0.72))
	parent.add_child(l)
	return l


## Regler-Zeile: Name, Schieberegler, Zahlenfeld, Zurücksetzen. `scale` rechnet Anzeige -> gespeicherter Wert
## (z. B. Grad -> Radiant).
func _param(parent: Control, key: String, label: String, lo: float, hi: float, step: float, scale := 1.0, tip := "", reset_to := 0.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	parent.add_child(h)
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.custom_minimum_size.x = 128
	l.clip_text = true
	h.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.custom_minimum_size.x = 110
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.tooltip_text = tip
	h.add_child(sl)
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.allow_greater = true
	sp.allow_lesser = true
	sp.custom_minimum_size.x = 82
	sp.select_all_on_focus = true
	h.add_child(sp)
	var rb := Button.new()
	rb.text = "0" if reset_to == 0.0 else "R"
	rb.tooltip_text = "Set to %s" % str(snappedf(reset_to, 0.01))
	rb.focus_mode = Control.FOCUS_NONE
	rb.custom_minimum_size.x = 26
	h.add_child(rb)
	sl.value_changed.connect(func(v): _param_changed(key, v))
	sp.value_changed.connect(func(v): _param_changed(key, v))
	rb.pressed.connect(func(): _param_changed(key, reset_to))
	_params[key] = {"slider": sl, "spin": sp, "scale": scale, "row": h}
	return h


func _vec(parent: Control, key: String, label: String, lo: float, hi: float, tip := "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color(0.75, 0.88, 0.88))
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(l)
	for axis in ["x", "y", "z"]:
		var names := {"x": "   x (right)", "y": "   y (up)", "z": "   z (back)"}
		var row := _param(box, key + "." + axis, names[axis], lo, hi, 0.005, 1.0, tip)
		var rb: Button = row.get_child(row.get_child_count() - 1)
		rb.modulate.a = 0.0  # Koordinate auf 0 setzen ist hier sinnlos (Platz bleibt für saubere Spalten)
		rb.disabled = true
		rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _set_param_ui(key: String, value: float) -> void:
	if not _params.has(key):
		return
	var p: Dictionary = _params[key]
	var shown: float = value / p.scale
	_updating_ui = true
	(p.slider as HSlider).set_value_no_signal(shown)
	(p.spin as SpinBox).set_value_no_signal(shown)
	_updating_ui = false


func _enable_params(prefix: String, on: bool) -> void:
	for k in _params:
		if (k as String).begins_with(prefix):
			(_params[k].slider as HSlider).editable = on
			(_params[k].spin as SpinBox).editable = on


func _scroll(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	return v


# ==================================================================
# UI-Aufbau
# ==================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# --- obere Leiste: Modus, Figur, Datei ---
	var topv := VBoxContainer.new()
	topv.position = Vector2(10, 8)
	topv.add_theme_constant_override("separation", 4)
	root.add_child(topv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	topv.add_child(top)
	var title := Label.new()
	title.text = "Animation Workshop  "
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 1.0))
	top.add_child(title)
	for m in [[Mode.CLIP, "Animations"], [Mode.POSE, "Weapon poses"], [Mode.GEAR, "Stowed gear"], [Mode.ENEMY, "Enemies"]]:
		var b := _btn(top, m[1], _set_mode.bind(m[0]))
		b.toggle_mode = true
		_mode_btns.append(b)
	var sep := VSeparator.new()
	top.add_child(sep)
	_btn(top, "Save", _save, "Save what you are editing (Ctrl+S)")
	_btn(top, "Revert", _revert, "Reload from file, discarding unsaved changes")
	_btn(top, "Undo", _do_undo, "Ctrl+Z")

	var top2 := HBoxContainer.new()
	top2.add_theme_constant_override("separation", 6)
	topv.add_child(top2)
	var wl := Label.new()
	wl.text = "Weapon"
	top2.add_child(wl)
	_weapon_select = OptionButton.new()
	_weapon_select.focus_mode = Control.FOCUS_NONE
	for w in WEAPON_CHOICES:
		_weapon_select.add_item(w[1])
	_weapon_select.item_selected.connect(func(i): _set_weapon(WEAPON_CHOICES[i][0]))
	top2.add_child(_weapon_select)
	var ol := Label.new()
	ol.text = "  Off-hand"
	top2.add_child(ol)
	_off_select = OptionButton.new()
	_off_select.focus_mode = Control.FOCUS_NONE
	for o in OFF_CHOICES:
		_off_select.add_item(o[1])
	_off_select.item_selected.connect(func(i): _set_offhand(OFF_CHOICES[i][0]))
	top2.add_child(_off_select)
	var cl := Label.new()
	cl.text = "  Culture"
	top2.add_child(cl)
	_culture_select = OptionButton.new()
	_culture_select.focus_mode = Control.FOCUS_NONE
	for c in FrayedOutfit.CULTURES:
		_culture_select.add_item(c.capitalize())
	_culture_select.item_selected.connect(func(i): _set_culture(FrayedOutfit.CULTURES[i]))
	top2.add_child(_culture_select)
	_figure_ctrls = [wl, _weapon_select, ol, _off_select, cl, _culture_select]
	top2.add_child(VSeparator.new())
	for v in [["Front", 0.0, -0.1], ["Side", PI * 0.5, -0.1], ["3/4", 2.4, -0.25], ["Back", PI, -0.2], ["Top", 0.0001, -1.45]]:
		_btn(top2, v[0], _view.bind(v[1], v[2]))

	_build_clip_panel(root)
	_build_pose_panel(root)
	_build_gear_panel(root)
	_build_enemy_panel(root)

	# --- untere Leiste: Zeitleiste + Transport (nur Animationen) ---
	var bottom := _panel(root)
	_bottom = bottom.get_parent()
	_bottom.anchor_left = 0.0
	_bottom.anchor_right = 1.0
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.offset_left = 10
	_bottom.offset_right = -420
	_bottom.offset_top = -112
	_bottom.offset_bottom = -10
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
	_springs_cb = spr
	_time_label = Label.new()
	tr.add_child(_time_label)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_status.add_theme_font_size_override("font_size", 15)
	_status.position = Vector2(12, 74)
	root.add_child(_status)

	_help = Label.new()
	_help.position = Vector2(12, 98)
	_help.add_theme_color_override("font_color", Color(0.75, 0.85, 0.85))
	_help.add_theme_font_size_override("font_size", 13)
	root.add_child(_help)


func _right_panel(root: Control) -> VBoxContainer:
	var v := _panel(root)
	var pc: Control = v.get_parent()
	pc.anchor_left = 1.0
	pc.anchor_right = 1.0
	pc.anchor_top = 0.0
	pc.anchor_bottom = 1.0
	pc.offset_left = -410
	pc.offset_right = -10
	pc.offset_top = 76
	pc.offset_bottom = -10
	return v


func _build_clip_panel(root: Control) -> void:
	var right := _right_panel(root)
	_panels[Mode.CLIP] = right.get_parent()
	var row := HBoxContainer.new()
	right.add_child(row)
	var l := Label.new()
	l.text = "Animation"
	row.add_child(l)
	_clip_select = OptionButton.new()
	_clip_select.focus_mode = Control.FOCUS_NONE
	_clip_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in AnimLibrary.ALL_CLIPS:
		_clip_select.add_item(AnimLibrary.clip(n).label)
	_clip_select.item_selected.connect(func(i): _switch_clip(AnimLibrary.ALL_CLIPS[i]))
	row.add_child(_clip_select)
	_variant_cb = CheckBox.new()
	_variant_cb.text = "Own version for this weapon"
	_variant_cb.focus_mode = Control.FOCUS_NONE
	_variant_cb.tooltip_text = "On: this weapon gets its own copy of the animation (saved as <clip>@<weapon>.json).\nOff: the weapon uses the general animation (its own copy is deleted)."
	_variant_cb.toggled.connect(_on_variant_toggled)
	right.add_child(_variant_cb)
	_variant_info = _note(right, "")

	_heading(right, "Keyframes")
	_ckey_list = ItemList.new()
	_ckey_list.custom_minimum_size = Vector2(0, 92)
	_ckey_list.focus_mode = Control.FOCUS_NONE
	_ckey_list.item_selected.connect(func(i): _select_key(i, true))
	right.add_child(_ckey_list)
	var kb := HBoxContainer.new()
	right.add_child(kb)
	_btn(kb, "Add", _add_key_here, "Add a keyframe at the playhead (K)")
	_btn(kb, "Delete", _delete_key, "Delete selected keyframe (Del)")
	_btn(kb, "Copy", _copy_key, "Copy the pose of the selected keyframe (Ctrl+C)")
	_btn(kb, "Paste", _paste_key, "Paste the copied pose at the playhead (Ctrl+V); creates a key if needed")
	_btn(kb, "Clean", _clean_body, "Set all body extras of this key back to 0")

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	right.add_child(tabs)

	var hands := _scroll(tabs)
	hands.get_parent().name = "Hands"
	_param(hands, "k.t", "Time (0-1)", 0.01, 0.99, 0.005, 1.0, "Where in the animation this key sits")
	_vec(hands, "k.grip", "Weapon hand (grip)", -1.0, 1.2, "Grip position, chest space")
	_vec(hands, "k.dir", "Blade / tip direction", -1.0, 1.0)
	var rr := HBoxContainer.new()
	hands.add_child(rr)
	_btn(rr, "Roll blade -15°", func(): _roll_blade(-0.26), "Rotate the edge around the blade")
	_btn(rr, "Roll +15°", func(): _roll_blade(0.26))
	_vec(hands, "k.shield", "Off hand (shield / dagger)", -1.0, 1.2)
	_vec(hands, "k.shield_front", "Off hand facing", -1.0, 1.0)

	var bod := _scroll(tabs)
	bod.get_parent().name = "Body"
	_note(bod, "Body values are added on top of the automatic pose (0 = unchanged). Angles in degrees.")
	_heading(bod, "Torso")
	_param(bod, "k.twist", "Twist", -86, 86, 0.5, DEG, "+ = right shoulder forward")
	_param(bod, "k.lean", "Lean", -70, 60, 0.5, DEG, "- = forward")
	_param(bod, "b.bank", "Side lean", -40, 40, 0.5, DEG, "Tilt the whole body sideways")
	_param(bod, "k.drop", "Hips down (m)", -0.1, 0.4, 0.005, 1.0, "Lower the hips (bend the knees)")
	_param(bod, "b.hips_turn", "Hips turn", -60, 60, 0.5, DEG, "Turn the lower body (legs) left/right")
	_param(bod, "b.step", "Hips fwd/back (m)", -0.3, 0.3, 0.005, 1.0, "Shift the hips forward (+) or back")
	_heading(bod, "Head")
	_param(bod, "b.head_yaw", "Look left/right", -60, 60, 0.5, DEG)
	_param(bod, "b.head_pitch", "Look up/down", -45, 45, 0.5, DEG, "+ = up")
	_heading(bod, "Arms")
	_param(bod, "b.elbow_r", "Right elbow", -90, 90, 0.5, DEG, "Swing the right elbow around the arm (+ = out/up)")
	_param(bod, "b.elbow_l", "Left elbow", -90, 90, 0.5, DEG, "Swing the left elbow around the arm (+ = out/up)")

	var legs := _scroll(tabs)
	legs.get_parent().name = "Legs"
	_note(legs, "Added on top of the automatic stance (0 = unchanged). Angles in degrees.")
	_heading(legs, "Left leg")
	_param(legs, "b.leg_l_swing", "Forward/back", -60, 60, 0.5, DEG, "+ = leg forward")
	_param(legs, "b.leg_l_spread", "Out/in", -30, 40, 0.5, DEG, "+ = leg out to the side")
	_param(legs, "b.leg_l_knee", "Knee bend", -30, 90, 0.5, DEG, "+ = bend more")
	_heading(legs, "Right leg")
	_param(legs, "b.leg_r_swing", "Forward/back", -60, 60, 0.5, DEG, "+ = leg forward")
	_param(legs, "b.leg_r_spread", "Out/in", -30, 40, 0.5, DEG, "+ = leg out to the side")
	_param(legs, "b.leg_r_knee", "Knee bend", -30, 90, 0.5, DEG, "+ = bend more")

	var cl := _scroll(tabs)
	cl.get_parent().name = "Timing"
	_param(cl, "c.duration", "Duration (s)", 0.3, 3.0, 0.01, 1.0, "", 0.95)
	_param(cl, "c.hit", "Hit at (0-1)", 0.05, 0.95, 0.005, 1.0, "When the hit lands", 0.44)
	_param(cl, "c.trail_a", "Trail from", 0.0, 1.0, 0.005, 1.0, "", 0.32)
	_param(cl, "c.trail_b", "Trail to", 0.0, 1.0, 0.005, 1.0, "", 0.62)
	var cb := CheckBox.new()
	cb.text = "Start/end in combat stance"
	cb.button_pressed = combat_stance
	cb.focus_mode = Control.FOCUS_NONE
	cb.tooltip_text = "Start/end pose: combat stance (enemy near) or relaxed"
	cb.toggled.connect(func(on): combat_stance = on)
	cl.add_child(cb)
	_btn(cl, "Check whole clip", _check_whole_clip, "Scan the animation for blade/arm passing through the body")

	_clip_warn = Label.new()
	_clip_warn.autowrap_mode = TextServer.AUTOWRAP_WORD
	_clip_warn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	right.add_child(_clip_warn)


func _build_pose_panel(root: Control) -> void:
	var right := _right_panel(root)
	_panels[Mode.POSE] = right.get_parent()
	_heading(right, "Weapon pose")
	_pose_select = OptionButton.new()
	_pose_select.focus_mode = Control.FOCUS_NONE
	for n in PoseLibrary.HELD_POSES + ["stow"]:
		_pose_select.add_item(PoseLibrary.POSE_LABELS[n])
	_pose_select.item_selected.connect(func(i): _set_pose((PoseLibrary.HELD_POSES + ["stow"])[i]))
	right.add_child(_pose_select)
	_pose_info = _note(right, "")
	var rb := HBoxContainer.new()
	right.add_child(rb)
	_btn(rb, "Reset this pose", _reset_pose, "Back to the built-in default (until you save)")
	_copy_2h_btn = _btn(rb, "Copy to two-handed", _copy_pose_2h, "Use this pose as starting point for the two-handed version")
	var sc := _scroll(right)
	_pose_held_box = VBoxContainer.new()
	sc.add_child(_pose_held_box)
	_vec(_pose_held_box, "p.grip", "Weapon hand (grip)", -1.0, 1.2, "Chest space")
	_vec(_pose_held_box, "p.dir", "Blade / tip direction", -1.0, 1.0)
	var r1 := HBoxContainer.new()
	_pose_held_box.add_child(r1)
	_btn(r1, "Roll blade -15°", func(): _roll_pose(-0.26))
	_btn(r1, "Roll +15°", func(): _roll_pose(0.26))
	_pose_off_box = VBoxContainer.new()
	_pose_held_box.add_child(_pose_off_box)
	_vec(_pose_off_box, "p.off", "Off hand (shield / dagger / light)", -1.0, 1.2)
	_vec(_pose_off_box, "p.off_front", "Off hand facing", -1.0, 1.0)
	_pose_stow_box = VBoxContainer.new()
	sc.add_child(_pose_stow_box)
	_note(_pose_stow_box, "Where the weapon hangs when stowed (belt weapons: hip space, back weapons: chest space).")
	_vec(_pose_stow_box, "s.pos", "Grip position", -1.0, 1.0)
	_vec(_pose_stow_box, "s.dir", "Blade / tip direction", -1.0, 1.0)
	var r2 := HBoxContainer.new()
	_pose_stow_box.add_child(r2)
	_btn(r2, "Roll -15°", func(): _roll_stow(-0.26))
	_btn(r2, "Roll +15°", func(): _roll_stow(0.26))
	_two_hand_row = _param(sc, "w.two_hand_offset", "Left hand gap (m)", 0.0, 0.8, 0.005, 1.0, "How far behind the right hand the left hand grips (two-handed)", 0.3)


func _build_gear_panel(root: Control) -> void:
	var right := _right_panel(root)
	_panels[Mode.GEAR] = right.get_parent()
	_heading(right, "Stowed gear")
	_gear_select = OptionButton.new()
	_gear_select.focus_mode = Control.FOCUS_NONE
	for n in PoseLibrary.GEAR_ITEMS:
		_gear_select.add_item(PoseLibrary.GEAR_LABELS[n])
	_gear_select.item_selected.connect(func(i): _set_gear(PoseLibrary.GEAR_ITEMS[i]))
	right.add_child(_gear_select)
	_note(right, "Same for every weapon. Shield and lantern: chest/hip space as in the game.")
	_btn(right, "Reset this item", _reset_gear)
	var sc := _scroll(right)
	_vec(sc, "g.pos", "Position", -1.0, 1.0)
	_gear_front_box = _vec(sc, "g.front", "Facing (front side)", -1.0, 1.0)
	_gear_dir_box = _vec(sc, "g.dir", "Blade direction", -1.0, 1.0)
	_gear_yaw_row = _param(sc, "g.yaw", "Turn", -180, 180, 1.0, DEG, "Turn the lantern around its hook", -20.0)


# ==================================================================
# Modus, Figur, Waffe
# ==================================================================

var _prev_mode := Mode.CLIP


func mode_was_enemy() -> bool:
	return _prev_mode == Mode.ENEMY


func _set_mode(m: Mode) -> void:
	_prev_mode = mode
	mode = m
	for i in _mode_btns.size():
		_mode_btns[i].set_pressed_no_signal(i == int(m))
	for k in _panels:
		(_panels[k] as Control).visible = k == m
	_bottom.visible = m == Mode.CLIP or (m == Mode.ENEMY and not enemy_id in ["hollowed", "hollow_one"])
	if playing:
		_toggle_play()
	body.visible = m != Mode.ENEMY
	for c in _figure_ctrls:
		(c as Control).visible = m != Mode.ENEMY
	_springs_cb.visible = m == Mode.CLIP
	if _enemy and is_instance_valid(_enemy):
		_enemy.visible = m == Mode.ENEMY
	if m != Mode.ENEMY and _body_look == "" and mode_was_enemy():
		_cam_target = Vector3(0, 0.95, -0.25)
		_cam_dist = 3.2
		_cam_yaw = 2.4
		_cam_pitch = -0.25
		_update_camera()
	_undo.clear()
	match m:
		Mode.CLIP:
			_help.text = ("Drag handles with LMB:  yellow = weapon grip,  cyan = blade tip,  orange = off hand,  small orange = off-hand facing\n"
				+ "Dragging at a time without a key creates one.  Red grip = arm can't reach.  Body, legs, head: tabs on the right.\n"
				+ "RMB drag = orbit   MMB drag = pan   Wheel = zoom   Space = play   K = add key   Del = delete key\n"
				+ "Left/Right = step (Shift = bigger)   Up/Down = previous/next key   Ctrl+C / Ctrl+V = copy/paste pose   Ctrl+S = save   Ctrl+Z = undo")
			if _prev_mode == Mode.ENEMY:
				_load_clip(base_clip)
			else:
				_refresh_clip_ui()
		Mode.POSE:
			_help.text = ("Weapon poses: how each weapon is held standing, walking, in combat stance, two-handed, and where it hangs when stowed.\n"
				+ "Pick weapon and off-hand at the top, the pose on the right. Drag the handles or use the sliders.  Ctrl+S saves data/poses/<weapon>.json\n"
				+ "RMB drag = orbit   MMB drag = pan   Wheel = zoom   Ctrl+Z = undo")
			_set_pose(pose_name)
		Mode.GEAR:
			_help.text = ("Stowed gear: shield on the back, off-hand dagger at the belt, lantern at the belt and held out.\n"
				+ "Drag the orange handle (position) and the small one (facing / blade).  Ctrl+S saves data/poses/gear.json\n"
				+ "RMB drag = orbit   MMB drag = pan   Wheel = zoom   Ctrl+Z = undo")
			_set_gear(gear_item)
		Mode.ENEMY:
			_help.text = ("Enemies: pick the enemy and one of its actions on the right. Their motion stays procedural (feet find the ground, the axe follows the hand);
"
				+ "your keys turn joints and shift feet/body on top of it.  Hollowed and Hollow One: their strike is a normal animation (button on the right).
"
				+ "RMB drag = orbit   MMB drag = pan   Wheel = zoom   Space = play   K = add key   Del = delete key   Ctrl+C / Ctrl+V = copy/paste   Ctrl+S = save data/enemy_anims/<enemy>.json")
			_set_enemy(enemy_id)


func _set_weapon(w: StringName) -> void:
	weapon_id = w
	_apply_weapon()
	if mode == Mode.CLIP:
		_load_clip(base_clip)
	elif mode == Mode.POSE:
		_set_pose(pose_name)


func _set_offhand(o: StringName) -> void:
	offhand = o
	_apply_weapon()
	_refresh_pose_ui()


func _set_culture(c: String) -> void:
	culture = c
	_rebuild_body()
	if mode == Mode.POSE:
		_set_pose(pose_name)


## Datei-ID der Haltungen für die aktuelle Waffe/Kultur.
func _pose_id() -> String:
	return body.pose_id()


# ==================================================================
# Animationen
# ==================================================================

func _load_clip(n: String) -> void:
	base_clip = n
	var look := ""
	if n in AnimLibrary.ENEMY_CLIPS:
		look = "hollowed" if n == "hollowed_strike" else "hollow_one"
	if look != _body_look:
		_body_look = look
		_rebuild_body()
	clip_name = n if look != "" else AnimLibrary.resolve(n, String(weapon_id))
	clip = AnimLibrary.clip(clip_name)
	_undo.clear()
	sel_key = -1
	_clip_select.select(AnimLibrary.ALL_CLIPS.find(n))
	_refresh_clip_ui()


func _refresh_clip_ui() -> void:
	_variant_cb.visible = _body_look == ""
	_variant_cb.set_pressed_no_signal(clip_name != base_clip)
	var wname: String = WEAPON_CHOICES[_weapon_index()][1]
	_variant_info.text = ("Editing the %s version (only used with this weapon)." % wname) if clip_name != base_clip else ("Editing the general version (used by all weapons without their own).")
	if _body_look != "":
		_variant_info.text = "Enemy attack. Timing tab: trail window = strike phase (deals damage); before = wind-up, after = recovery."
	_refresh_keys()
	_refresh_fields()


func _weapon_index() -> int:
	for i in WEAPON_CHOICES.size():
		if WEAPON_CHOICES[i][0] == weapon_id:
			return i
	return 0


func _switch_clip(n: String) -> void:
	if dirty.get("anim:" + clip_name, false):
		_flash("Unsaved changes in %s are kept until you close the workshop." % clip_name)
	_load_clip(n)


func _on_variant_toggled(on: bool) -> void:
	if on:
		clip_name = AnimLibrary.make_variant(base_clip, String(weapon_id))
		clip = AnimLibrary.clip(clip_name)
		dirty["anim:" + clip_name] = true
		_flash("Own version for this weapon created. Save to keep it.")
	else:
		AnimLibrary.delete_variant(base_clip, String(weapon_id))
		dirty.erase("anim:" + clip_name)
		clip_name = base_clip
		clip = AnimLibrary.clip(clip_name)
		_flash("Own version deleted, the weapon uses the general animation again.")
	_undo.clear()
	sel_key = -1
	_refresh_clip_ui()


func _key_at(time: float) -> int:
	for i in clip.keys.size():
		if absf(clip.keys[i].t - time) < KEY_SNAP:
			return i
	return -1


## Neuer Key an der Abspielposition mit der aktuell sichtbaren (exakten) Pose.
func _add_key_here() -> int:
	if mode == Mode.ENEMY:
		return _add_enemy_key()
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
		"body": (s[9] as Array).duplicate() if s.size() > 9 else AnimLibrary.zero_body(),
	}
	clip.keys.append(k)
	clip.keys.sort_custom(func(a, b): return a.t < b.t)
	sel_key = clip.keys.find(k)
	_set_t(k.t)
	_changed()
	return sel_key


func _add_enemy_key() -> int:
	if clip.is_empty():
		return -1
	if not clip.loop and (t <= 0.01 or t >= 0.99):
		_flash("Start and end are the enemy's own motion. Move the playhead inside the action.")
		return -1
	var existing := _key_at(t)
	if existing >= 0:
		_select_key(existing)
		return existing
	_push_undo()
	var k := {"t": snappedf(minf(t, 0.995), 0.005), "ch": _enemy_values_here()}
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


func _copy_key() -> void:
	if mode == Mode.ENEMY:
		var ek := _key_at(t)
		_clipboard = {"ch": (clip.keys[ek].ch as Dictionary).duplicate() if ek >= 0 else _enemy_values_here(), "enemy": enemy_id}
		_flash("Pose copied")
		return
	var k := _key_at(t)
	if k < 0:
		_pose_now(0.0, true)
		var s: Array = body.swing_sample
		_clipboard = {"grip": body._scale_pose(s[0]), "dir": s[1], "flat": s[2], "twist": s[3], "lean": s[4], "drop": s[5],
			"shield": body._scale_pose(s[7]), "shield_front": s[8], "body": (s[9] as Array).duplicate()}
	else:
		_clipboard = clip.keys[k].duplicate(true)
	_flash("Pose copied")


func _paste_key() -> void:
	if _clipboard.is_empty():
		_flash("Nothing copied yet")
		return
	if mode == Mode.ENEMY:
		if _clipboard.get("enemy", "") != enemy_id:
			_flash("Copy a pose of this enemy first")
			return
		var ek := _key_at(t)
		if ek < 0:
			ek = _add_enemy_key()
			if ek < 0:
				return
		else:
			_push_undo()
		clip.keys[ek].ch = (_clipboard.ch as Dictionary).duplicate()
		_changed()
		_flash("Pose pasted at t = %.3f" % clip.keys[ek].t)
		return
	if _clipboard.has("enemy"):
		_flash("That pose belongs to an enemy")
		return
	var k := _key_at(t)
	if k < 0:
		k = _add_key_here()
		if k < 0:
			return
	else:
		_push_undo()
	var key: Dictionary = clip.keys[k]
	for f in _clipboard:
		if f != "t":
			key[f] = _clipboard[f].duplicate() if _clipboard[f] is Array else _clipboard[f]
	_changed()
	_flash("Pose pasted at t = %.3f" % key.t)


func _clean_body() -> void:
	if sel_key < 0:
		return
	_push_undo()
	if mode == Mode.ENEMY:
		clip.keys[sel_key].ch = {}
		_changed()
		return
	clip.keys[sel_key].body = AnimLibrary.zero_body()
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
	if mode == Mode.ENEMY:
		sel_key = _key_at(t)
		if sel_key >= 0 and _key_list.item_count > sel_key:
			_key_list.select(sel_key)
		elif _key_list:
			_key_list.deselect_all()
		_refresh_enemy_fields()
		return
	var k := _key_at(t)
	if k >= 0 and k != sel_key:
		sel_key = k
		_refresh_fields()
		if _key_list.item_count > k:
			_key_list.select(k)


func _changed() -> void:
	_mark_dirty()
	_refresh_keys()
	_refresh_fields()


func _refresh_keys() -> void:
	_key_list.clear()
	if mode == Mode.ENEMY:
		for k in clip.get("keys", []):
			var names: Array[String] = []
			for c in k.ch:
				if (k.ch[c] as Vector3).length() > 0.0005:
					names.append(str(c))
			_key_list.add_item("t = %.3f   %s" % [k.t, ", ".join(names) if not names.is_empty() else "(nothing changed)"])
		if sel_key >= 0 and sel_key < _key_list.item_count:
			_key_list.select(sel_key)
		if _timeline:
			_timeline.queue_redraw()
		return
	for k in clip.keys:
		var extras := 0
		for v in k.get("body", []):
			if absf(v) > 0.0005:
				extras += 1
		_key_list.add_item("t = %.3f   twist %+.0f°  lean %+.0f°%s" % [k.t, rad_to_deg(k.twist), rad_to_deg(k.lean), ("   +%d body" % extras) if extras > 0 else ""])
	if sel_key >= 0 and sel_key < clip.keys.size():
		_key_list.select(sel_key)
	if _timeline:
		_timeline.queue_redraw()


func _refresh_fields() -> void:
	if clip.is_empty():
		return
	if mode == Mode.ENEMY:
		_refresh_enemy_fields()
		return
	_set_param_ui("c.duration", clip.duration)
	_set_param_ui("c.hit", clip.hit)
	_set_param_ui("c.trail_a", clip.trail.x)
	_set_param_ui("c.trail_b", clip.trail.y)
	var has: bool = sel_key >= 0 and sel_key < clip.keys.size()
	_enable_params("k.", has)
	_enable_params("b.", has)
	if not has:
		return
	var k: Dictionary = clip.keys[sel_key]
	for f in ["t", "twist", "lean", "drop"]:
		_set_param_ui("k." + f, k[f])
	for f in ["grip", "dir", "shield", "shield_front"]:
		var v: Vector3 = k[f]
		_set_param_ui("k.%s.x" % f, v.x)
		_set_param_ui("k.%s.y" % f, v.y)
		_set_param_ui("k.%s.z" % f, v.z)
	var b: Array = k.get("body", AnimLibrary.zero_body())
	for i in AnimLibrary.BODY_FIELDS.size():
		_set_param_ui("b." + AnimLibrary.BODY_FIELDS[i], b[i])


## Ein Regler wurde bewegt (Anzeigewert v).
func _param_changed(key: String, v: float) -> void:
	if _updating_ui or not _params.has(key):
		return
	var value: float = v * _params[key].scale
	_set_param_ui(key, value)
	var parts := key.split(".")
	match parts[0]:
		"c":
			_push_undo(true)
			match parts[1]:
				"duration": clip.duration = value
				"hit": clip.hit = value
				"trail_a": clip.trail = Vector2(value, clip.trail.y)
				"trail_b": clip.trail = Vector2(clip.trail.x, value)
			_mark_dirty()
		"k", "b":
			if sel_key < 0 or sel_key >= clip.keys.size():
				return
			_push_undo(true)
			var k: Dictionary = clip.keys[sel_key]
			if parts[0] == "b":
				if not k.has("body"):
					k.body = AnimLibrary.zero_body()
				k.body[AnimLibrary.BODY_FIELDS.find(parts[1])] = value
			elif parts.size() == 2:
				k[parts[1]] = value
				if parts[1] == "t":
					clip.keys.sort_custom(func(a, b): return a.t < b.t)
					sel_key = clip.keys.find(k)
					t = value
			else:
				k[parts[1]] = _set_axis(k[parts[1]], parts[2], value, parts[1] in ["dir", "shield_front"])
			_mark_dirty()
			_refresh_keys()
		"p":
			_push_undo(true)
			var pz: Dictionary = PoseLibrary.weapon(_pose_id())[pose_name]
			pz[parts[1]] = _set_axis(pz[parts[1]], parts[2], value, parts[1] in ["dir", "off_front"])
			_pose_changed()
		"s":
			_push_undo(true)
			var st: Dictionary = PoseLibrary.weapon(_pose_id()).stow
			st[parts[1]] = _set_axis(st[parts[1]], parts[2], value, parts[1] == "dir")
			_pose_changed()
		"w":
			_push_undo(true)
			PoseLibrary.weapon(_pose_id()).two_hand_offset = value
			_pose_changed()
		"e":
			if clip.is_empty() or parts[1] != enemy_id:
				return
			var ek := _key_at(t)
			if ek < 0:
				ek = _add_enemy_key()
				if ek < 0:
					_refresh_enemy_fields()
					return
			else:
				_push_undo(true)
			var ch: Dictionary = clip.keys[ek].ch
			ch[parts[2]] = _set_axis(ch.get(parts[2], Vector3.ZERO), parts[3], value, false)
			_mark_dirty()
			_refresh_keys()
		"g":
			_push_undo(true)
			var g: Dictionary = PoseLibrary.gear()[gear_item]
			if parts[1] == "yaw":
				g.yaw = value
			elif g.has(parts[1]):
				g[parts[1]] = _set_axis(g[parts[1]], parts[2], value, parts[1] != "pos")
			_gear_changed()
	if _timeline:
		_timeline.queue_redraw()


## Regler zeigen den Key an der Abspielposition, sonst die dort gerade wirkenden Werte.
func _refresh_enemy_fields() -> void:
	var k := _key_at(t)
	var vals: Dictionary = clip.keys[k].ch if k >= 0 else _enemy_values_here()
	for c in CreatureAnim.CREATURES[enemy_id].channels:
		var v: Vector3 = vals.get(c[0], Vector3.ZERO)
		for ai in 3:
			_set_param_ui("e.%s.%s.%s" % [enemy_id, c[0], ["x", "y", "z"][ai]], v[ai])


func _set_axis(v: Vector3, axis: String, value: float, normalize: bool) -> Vector3:
	v[["x", "y", "z"].find(axis)] = value
	if normalize:
		v = v.normalized() if v.length() > 0.01 else Vector3(0, 0, -1)
	return v


# ==================================================================
# Haltungen (Weapon poses) und Ausrüstung (Stowed gear)
# ==================================================================

func _set_pose(n: String) -> void:
	pose_name = n
	_pose_select.select((PoseLibrary.HELD_POSES + ["stow"]).find(n))
	_undo.clear()
	_refresh_pose_ui()


func _refresh_pose_ui() -> void:
	if mode != Mode.POSE:
		return
	var stow := pose_name == "stow"
	_pose_held_box.visible = not stow
	_pose_stow_box.visible = stow
	var w := WeaponDef.make(weapon_id)
	var pid := _pose_id()
	var two := pose_name.ends_with("_2h")
	_two_hand_row.visible = two and w.grip != &"1h"
	_pose_off_box.visible = not two
	_copy_2h_btn.visible = pose_name in ["idle", "walk", "guard"]
	var info := "File: data/poses/%s.json" % pid
	if pose_name.ends_with("_2h"):
		info += "\nShown with an empty off hand. The left hand grips the shaft by itself; set the gap below." + ("" if w.grip != &"1h" else "  (This weapon is never two-handed.)")
	elif not stow and w.grip == &"2h":
		info += "\nThe greataxe is only one-handed while you hold the light (shown with the light)."
	elif not stow and w.grip != &"1h" and _effective_off() == &"":
		info += "\nShown with the light, otherwise this pose would be two-handed."
	if pose_name == "walk":
		info += "\nThe walk cycle adds a little sway on top."
	_pose_info.text = info
	var pw := PoseLibrary.weapon(pid)
	if stow:
		var st: Dictionary = pw.stow
		for f in ["pos", "dir"]:
			var v: Vector3 = st[f]
			for a in ["x", "y", "z"]:
				_set_param_ui("s.%s.%s" % [f, a], v[["x", "y", "z"].find(a)])
	else:
		var pz: Dictionary = pw[pose_name]
		for f in ["grip", "dir", "off", "off_front"]:
			var v: Vector3 = pz[f]
			for a in ["x", "y", "z"]:
				_set_param_ui("p.%s.%s" % [f, a], v[["x", "y", "z"].find(a)])
	_set_param_ui("w.two_hand_offset", float(pw.get("two_hand_offset", 0.0)))


func _pose_changed() -> void:
	PoseLibrary.mark_changed()
	_mark_dirty()
	_refresh_pose_ui()


func _reset_pose() -> void:
	_push_undo()
	PoseLibrary.reset_entry(_pose_id(), pose_name)
	_pose_changed()
	_flash("Pose reset to default (save to keep)")


func _copy_pose_2h() -> void:
	if pose_name == "stow":
		return
	_push_undo()
	var pw := PoseLibrary.weapon(_pose_id())
	var target := "idle_2h" if pose_name in ["idle", "walk"] else ("guard_2h" if pose_name == "guard" else pose_name)
	pw[target] = (pw[pose_name] as Dictionary).duplicate()
	_pose_changed()
	_flash("Copied to %s" % PoseLibrary.POSE_LABELS[target])


func _roll_pose(angle: float) -> void:
	if pose_name == "stow":
		return
	_push_undo(true)
	var pz: Dictionary = PoseLibrary.weapon(_pose_id())[pose_name]
	pz.flat = (pz.flat as Vector3).rotated((pz.dir as Vector3).normalized(), angle)
	_pose_changed()


func _roll_stow(angle: float) -> void:
	_push_undo(true)
	var st: Dictionary = PoseLibrary.weapon(_pose_id()).stow
	st.hint = (st.hint as Vector3).rotated((st.dir as Vector3).normalized(), angle)
	_pose_changed()


func _set_gear(n: String) -> void:
	gear_item = n
	_gear_select.select(PoseLibrary.GEAR_ITEMS.find(n))
	_undo.clear()
	_refresh_gear_ui()


func _refresh_gear_ui() -> void:
	var g: Dictionary = PoseLibrary.gear()[gear_item]
	_gear_front_box.visible = g.has("front")
	_gear_dir_box.visible = g.has("dir")
	_gear_yaw_row.visible = g.has("yaw")
	for f in ["pos", "front", "dir"]:
		if g.has(f):
			var v: Vector3 = g[f]
			for a in ["x", "y", "z"]:
				_set_param_ui("g.%s.%s" % [f, a], v[["x", "y", "z"].find(a)])
	if g.has("yaw"):
		_set_param_ui("g.yaw", g.yaw)


func _gear_changed() -> void:
	PoseLibrary.mark_changed()
	_mark_dirty()
	_refresh_gear_ui()


func _reset_gear() -> void:
	_push_undo()
	PoseLibrary.reset_entry("gear", gear_item)
	_gear_changed()
	_flash("Reset to default (save to keep)")


# ==================================================================
# Gegner
# ==================================================================

func _build_enemy_panel(root: Control) -> void:
	var right := _right_panel(root)
	_panels[Mode.ENEMY] = right.get_parent()
	_heading(right, "Enemy")
	_enemy_select = OptionButton.new()
	_enemy_select.focus_mode = Control.FOCUS_NONE
	for e in ENEMY_CHOICES:
		_enemy_select.add_item(e[1])
	_enemy_select.item_selected.connect(func(i): _set_enemy(ENEMY_CHOICES[i][0]))
	right.add_child(_enemy_select)
	# Hollowed / Hollow One: Shade-Körper, ihr Angriff ist ein normaler Clip
	_enemy_redirect = VBoxContainer.new()
	right.add_child(_enemy_redirect)
	_note(_enemy_redirect, "This enemy has a Shade body, so its attack is a normal animation with all hand, body and leg controls. "
		+ "It is edited in the Animations mode (the figure there then looks like this enemy).\n\n"
		+ "Timing tab: the trail window is the enemy's strike phase. Before it = wind-up, after it = recovery.")
	_btn(_enemy_redirect, "Edit its strike in Animations", _open_enemy_clip)
	# übrige Gegner: Aktion, Keys, Gelenke
	_enemy_edit = VBoxContainer.new()
	_enemy_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_enemy_edit)
	var row := HBoxContainer.new()
	_enemy_edit.add_child(row)
	var l := Label.new()
	l.text = "Action"
	row.add_child(l)
	_eaction_select = OptionButton.new()
	_eaction_select.focus_mode = Control.FOCUS_NONE
	_eaction_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eaction_select.item_selected.connect(func(i): _set_enemy_action(CreatureAnim.CREATURES[enemy_id].actions[i][0]))
	row.add_child(_eaction_select)
	_eaction_info = _note(_enemy_edit, "")
	_heading(_enemy_edit, "Keyframes")
	_ekey_list = ItemList.new()
	_ekey_list.custom_minimum_size = Vector2(0, 80)
	_ekey_list.focus_mode = Control.FOCUS_NONE
	_ekey_list.item_selected.connect(func(i): _select_key(i, true))
	_enemy_edit.add_child(_ekey_list)
	var kb := HBoxContainer.new()
	_enemy_edit.add_child(kb)
	_btn(kb, "Add", _add_key_here, "Add a keyframe at the playhead (K)")
	_btn(kb, "Delete", _delete_key, "Delete the selected keyframe (Del)")
	_btn(kb, "Copy", _copy_key, "Copy the pose at the playhead (Ctrl+C)")
	_btn(kb, "Paste", _paste_key, "Paste the copied pose at the playhead (Ctrl+V)")
	_btn(kb, "Clean", _clean_body, "Set every joint of this key back to 0")
	var sc := _scroll(_enemy_edit)
	_note(sc, "Values are added on top of the enemy's own motion (0 = unchanged). Turns in degrees around the joint's own axes. Moving a slider where no key is creates one.")
	for cid in CreatureAnim.CREATURES:
		var box := VBoxContainer.new()
		sc.add_child(box)
		_enemy_boxes[cid] = box
		for c in CreatureAnim.CREATURES[cid].channels:
			var head := Label.new()
			head.text = c[1] + ("   (m)" if c[2] == "pos" else "")
			head.add_theme_color_override("font_color", Color(0.75, 0.88, 0.88))
			box.add_child(head)
			var names: Array = ["   x (right)", "   y (up)", "   z (back)"] if c[2] == "pos" else ["   Pitch (x)", "   Turn (y)", "   Roll (z)"]
			for ai in 3:
				var key := "e.%s.%s.%s" % [cid, c[0], ["x", "y", "z"][ai]]
				if c[2] == "pos":
					_param(box, key, names[ai], -0.6, 0.6, 0.005, 1.0)
				else:
					_param(box, key, names[ai], -180.0, 180.0, 0.5, 1.0)


func _set_enemy(id: String) -> void:
	enemy_id = id
	for i in ENEMY_CHOICES.size():
		if ENEMY_CHOICES[i][0] == id:
			_enemy_select.select(i)
	var shade := id in ["hollowed", "hollow_one"]
	_enemy_redirect.visible = shade
	_enemy_edit.visible = not shade
	if _enemy:
		_enemy.queue_free()
		_enemy = null
	if mode == Mode.ENEMY:
		_bottom.visible = not shade
	if shade:
		clip = {}
		_cam_target = Vector3(0, 0.95, -0.25)
		_cam_dist = 3.2
		_update_camera()
		return
	for cid in _enemy_boxes:
		(_enemy_boxes[cid] as Control).visible = cid == id
	match id:
		"splinterkin":
			var sk := Splinterkin.new()
			sk.puppet = true
			_enemy = sk
		"grimhauler":
			_enemy = GrimhaulerBody.new()
		"willamber":
			_enemy = WillamberBody.new()
	add_child(_enemy)
	_enemy.visible = mode == Mode.ENEMY
	_eaction_select.clear()
	for a in CreatureAnim.CREATURES[id].actions:
		_eaction_select.add_item(a[1])
	var cam_set: Array = ENEMY_CAM[id]
	_cam_target = cam_set[0]
	_cam_dist = cam_set[1]
	_cam_yaw = 0.75  # schräg von vorn: Gesicht und Arme sichtbar
	_cam_pitch = -0.2
	_update_camera()
	_set_enemy_action(CreatureAnim.CREATURES[id].actions[0][0])


func _set_enemy_action(a: String) -> void:
	enemy_action = a
	var info := CreatureAnim.action_info(enemy_id, a)
	_eaction_select.select(CreatureAnim.CREATURES[enemy_id].actions.find(info))
	_eaction_info.text = info[4] + ("  Loops: start and end flow into each other." if info[2] else "  Starts and ends with the enemy's own motion.")
	clip = {"keys": CreatureAnim.data(enemy_id)[a].keys, "duration": info[3], "hit": -1.0, "trail": Vector2(-1, -1), "loop": info[2]}
	if enemy_id == "splinterkin":
		_cam_target = ENEMY_CAM.splinterkin[0]
		_update_camera()
	sel_key = -1
	t = 0.0
	_undo.clear()
	_refresh_keys()
	_refresh_fields()


func _open_enemy_clip() -> void:
	var c := "hollowed_strike" if enemy_id == "hollowed" else "hollow_one_strike"
	_set_mode(Mode.CLIP)
	_switch_clip(c)


## Aktuelle Zusätze an der Abspielposition (Grad bzw. m), für neue Keys / Kopieren.
func _enemy_values_here() -> Dictionary:
	var out := {}
	var smp := CreatureAnim.sample(enemy_id, enemy_action, t)
	for c in smp:
		out[c] = (smp[c] as Vector3) * (180.0 / PI) if CreatureAnim.channel_kind(enemy_id, c) == "rot" else smp[c]
	return out


func _enemy_pose(delta: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	var dt := maxf(delta, 1.0 / 120.0)
	if _enemy is Splinterkin:
		var sk := _enemy as Splinterkin
		if enemy_action == "move":
			# im Kreis laufen, damit die Beine wirklich Schritte setzen
			_enemy_walk += dt * 2.2 / 1.1
			var p := Vector3(cos(_enemy_walk), 0, sin(_enemy_walk)) * 1.1
			var v := Vector3(-sin(_enemy_walk), 0, cos(_enemy_walk)) * 2.2
			sk.global_position = p
			sk.velocity = v
			sk.facing_yaw = atan2(-v.x, -v.z)
			_cam_target = Vector3(p.x, _cam_target.y, p.z)  # Kamera läuft mit
			_update_camera()
		else:
			sk.global_position = Vector3.ZERO
			sk.velocity = Vector3.ZERO
			sk.facing_yaw = 0.0
		sk.preview(enemy_action, t, dt)
	else:
		_enemy.call("preview", enemy_action, t, dt)


# ==================================================================
# Speichern, Rückgängig
# ==================================================================

func _file_key() -> String:
	match mode:
		Mode.POSE:
			return "pose:" + _pose_id()
		Mode.GEAR:
			return "pose:gear"
		Mode.ENEMY:
			return "enemy:" + enemy_id
	return "anim:" + clip_name


func _mark_dirty() -> void:
	dirty[_file_key()] = true


func _save() -> void:
	var err: Error
	var what: String
	match mode:
		Mode.CLIP:
			err = AnimLibrary.save(clip_name, clip)
			what = "data/anims/%s.json" % clip_name
		Mode.POSE:
			err = PoseLibrary.save(_pose_id())
			what = "data/poses/%s.json" % _pose_id()
		Mode.GEAR:
			err = PoseLibrary.save("gear")
			what = "data/poses/gear.json"
		Mode.ENEMY:
			if clip.is_empty():
				_flash("Hollowed and Hollow One are saved in the Animations mode")
				return
			err = CreatureAnim.save(enemy_id)
			what = "data/enemy_anims/%s.json" % enemy_id
	if err == OK:
		dirty.erase(_file_key())
		_flash("Saved " + what)
	else:
		_flash("Save failed (%s)" % error_string(err))


func _revert() -> void:
	match mode:
		Mode.CLIP:
			AnimLibrary.reload()
			_load_clip(base_clip)
		Mode.ENEMY:
			CreatureAnim.reload(enemy_id)
			if not clip.is_empty():
				_set_enemy_action(enemy_action)
		Mode.POSE, Mode.GEAR:
			PoseLibrary.reload()
			_refresh_pose_ui()
			if mode == Mode.GEAR:
				_refresh_gear_ui()
	dirty.erase(_file_key())
	_flash("Reverted to saved file")


func _snapshot() -> Variant:
	match mode:
		Mode.POSE:
			return PoseLibrary.weapon(_pose_id()).duplicate(true)
		Mode.GEAR:
			return PoseLibrary.gear().duplicate(true)
		Mode.ENEMY:
			return CreatureAnim.copy(enemy_id)
	return AnimLibrary.duplicate_clip(clip)


func _push_undo(coalesce := false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if coalesce and now - _last_undo_push < 0.6:
		return
	_last_undo_push = now
	_undo.append(_snapshot())
	if _undo.size() > 80:
		_undo.pop_front()


func _do_undo() -> void:
	if _undo.is_empty():
		_flash("Nothing to undo")
		return
	var snap: Variant = _undo.pop_back()
	match mode:
		Mode.CLIP:
			clip = snap
			AnimLibrary.set_clip(clip_name, clip)
			sel_key = mini(sel_key, clip.keys.size() - 1)
			_refresh_keys()
			_refresh_fields()
		Mode.POSE:
			PoseLibrary._cache[_pose_id()] = snap
			PoseLibrary.mark_changed()
			_refresh_pose_ui()
		Mode.GEAR:
			PoseLibrary._cache["gear"] = snap
			PoseLibrary.mark_changed()
			_refresh_gear_ui()
		Mode.ENEMY:
			CreatureAnim.set_data(enemy_id, snap)
			clip.keys = (snap as Dictionary)[enemy_action].keys
			sel_key = mini(sel_key, clip.keys.size() - 1)
			_refresh_keys()
			_refresh_fields()
	_mark_dirty()


# ==================================================================
# Wiedergabe / Vorschau
# ==================================================================

func _toggle_play() -> void:
	playing = not playing
	_pause_t = 0.0
	_play_btn.text = "Pause" if playing else "Play"


func _pose_now(delta: float, exact: bool) -> void:
	var w := WeaponDef.make(weapon_id)
	body.snap = exact
	body.speed = 0.0
	body.local_move = Vector2.ZERO
	body.action = &""
	body.combat = 0.0
	var off := _effective_off()
	match mode:
		Mode.CLIP:
			body.combat = 1.0 if combat_stance else 0.0
			_hold(true, off)
			if not (playing and _pause_t > 0.0):
				body.action = &"swing"
				body.swing_clip = clip_name
				body.swing_index = AnimLibrary.CLIPS.find(base_clip)
				body.action_t = t
		Mode.POSE:
			if pose_name.ends_with("_2h"):
				off = &""
			elif off == &"" and WeaponDef.make(weapon_id).grip != &"1h":
				off = &"light"  # sonst würde die Figur beidhändig greifen und die einhändige Haltung wäre nicht zu sehen
			if pose_name in ["guard", "guard_2h"]:
				body.combat = 1.0
			if pose_name == "walk":
				body.speed = 2.6
				body.local_move = Vector2(0, 0.55)
			_hold(pose_name != "stow", off if pose_name != "stow" else &"")
		Mode.GEAR:
			var gear_off := &""
			match gear_item:
				"lantern_held":
					gear_off = &"light"
			_hold(false, gear_off)
	body.two_hand = w.two_handed(body.off_item) and body.want_weapon
	body.tick(maxf(delta, 1.0 / 120.0))


## Waffe gezogen/weggesteckt und Zweithand sofort setzen (ohne Zieh-Animation).
func _hold(weapon_drawn: bool, off: StringName) -> void:
	if body.want_weapon != weapon_drawn or body.want_off != off or body.off_item != off:
		body.set_equipment(weapon_drawn, off)


func _process(delta: float) -> void:
	if mode == Mode.ENEMY:
		if playing and not clip.is_empty():
			t += delta * speed / maxf(clip.duration, 0.05)
			if t >= 1.0:
				t = fposmod(t, 1.0) if clip.loop else 0.0
			_refresh_enemy_fields()
		_enemy_pose(delta * speed)
		_update_handles()
		if not clip.is_empty():
			_time_label.text = "t = %.3f   (%.2f s of %.2f s)%s" % [t, t * clip.duration, clip.duration, "   *unsaved*" if dirty.get(_file_key(), false) else ""]
			_timeline.queue_redraw()
		return
	if mode == Mode.CLIP and playing:
		if _pause_t > 0.0:
			_pause_t -= delta
		else:
			t += delta * speed / maxf(clip.duration, 0.05)
			if t >= 1.0:
				t = 0.0
				_pause_t = 0.45 / speed
	var exact := mode != Mode.CLIP or not (playing and springs_in_play)
	if mode == Mode.POSE and pose_name == "walk":
		exact = false
	_pose_now(delta, exact)
	_update_handles()
	if mode == Mode.CLIP:
		var d := body.blade_clip_depth()
		_clip_warn.text = "" if d < 0.02 else "Warning: blade/arm %d cm inside the body here" % roundi(d * 100.0)
		_time_label.text = "t = %.3f   (%.2f s of %.2f s)%s" % [t, t * clip.duration, clip.duration, "   *unsaved*" if dirty.get(_file_key(), false) else ""]
		_timeline.queue_redraw()
	elif dirty.get(_file_key(), false):
		_status.text = "*unsaved changes*  (Ctrl+S)"
		_status.modulate.a = 1.0


## Welche Griffe gibt es gerade, und wo liegen sie?
func _handle_positions() -> Dictionary:
	var out := {}
	if mode == Mode.ENEMY:
		return out
	var pts := body.sword_points()
	var off_node: Node3D = null
	if body.off_item == &"shield" and body.shield:
		off_node = body.shield
	elif body.off_item == &"dagger" and body.off_dagger:
		off_node = body.off_dagger
	match mode:
		Mode.CLIP:
			out.grip = body.sword.global_position
			out.tip = pts[1]
			if off_node:
				out.off = off_node.global_position
				out.off_front = off_node.global_transform * Vector3(0, 0, -0.3)
		Mode.POSE:
			out.grip = body.sword.global_position
			out.tip = body.sword.global_transform * Vector3(0, 0, -body.weapon_length)
			if pose_name != "stow" and off_node:
				out.off = off_node.global_position
				out.off_front = off_node.global_transform * Vector3(0, 0, -0.3)
		Mode.GEAR:
			match gear_item:
				"shield_back":
					if body.shield:
						out.off = body.shield.global_position
						out.off_front = body.shield.global_transform * Vector3(0, 0, -0.3)
				"dagger_stow":
					if body.off_dagger:
						out.off = body.off_dagger.global_position
						out.off_front = body.off_dagger.global_transform * Vector3(0, 0, -0.35)
				_:
					if body._lantern_hook:
						out.off = body._lantern_hook.global_position
	return out


func _update_handles() -> void:
	var pos := _handle_positions()
	var reach := 0.0
	if pos.has("grip"):
		var inv := body.chest.global_transform.affine_inverse()
		reach = (inv * (pos.grip as Vector3)).distance_to(ShadowBody.SHOULDER_R)
	for n in _handles:
		var mi: MeshInstance3D = _handles[n]
		mi.visible = pos.has(n)
		if not mi.visible:
			continue
		mi.global_position = pos[n]
		var c: Color = mi.get_meta("color")
		if n == "grip" and mode != Mode.GEAR and not (mode == Mode.POSE and pose_name == "stow") and reach > ShadowBody.UPPER_ARM + ShadowBody.LOWER_ARM + 0.02:
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
	off = Vector3(off.x, off.y, -off.z)  # yaw 0 = Kamera vor der Figur (Figur schaut nach -Z)
	cam.position = _cam_target + off
	cam.look_at(_cam_target, Vector3.UP if absf(_cam_pitch) < 1.4 else Vector3(0, 0, -1))


func _pick_handle(mp: Vector2) -> String:
	var best := ""
	var best_d := HANDLE_PICK_PX
	for n in _handles:
		var mi: MeshInstance3D = _handles[n]
		if not mi.visible:
			continue
		var p: Vector3 = mi.global_position
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
			_cam_target += (-cam.global_basis.x * mm.relative.x + cam.global_basis.y * mm.relative.y) * 0.0015 * _cam_dist
			_update_camera()
		elif _drag_handle != "":
			_drag_to(mm.position)
		else:
			_hover_handle = _pick_handle(mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		var big := 0.05 if k.shift_pressed else 0.01
		if k.ctrl_pressed:
			match k.keycode:
				KEY_S: _save()
				KEY_Z: _do_undo()
				KEY_C:
					if _keyed_mode():
						_copy_key()
				KEY_V:
					if _keyed_mode():
						_paste_key()
			return
		if not _keyed_mode():
			return
		match k.keycode:
			KEY_SPACE: _toggle_play()
			KEY_K: _add_key_here()
			KEY_DELETE, KEY_BACKSPACE: _delete_key()
			KEY_LEFT: _set_t(t - big)
			KEY_RIGHT: _set_t(t + big)
			KEY_UP: _jump_key(-1)
			KEY_DOWN: _jump_key(1)


## Modus mit Zeitleiste und Keys (Animationen, Gegner mit eigenen Aktionen).
func _keyed_mode() -> bool:
	return mode == Mode.CLIP or (mode == Mode.ENEMY and not clip.is_empty())


func _begin_drag(h: String) -> void:
	if mode == Mode.CLIP:
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
	else:
		_push_undo()
	_drag_handle = h
	_drag_plane = Plane(-cam.global_basis.z, _handles[h].global_position)


func _drag_to(mp: Vector2) -> void:
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var hit: Variant = _drag_plane.intersects_ray(from, dir)
	if hit == null:
		return
	var chest_local: Vector3 = body.chest.global_transform.affine_inverse() * (hit as Vector3)
	var hips_local: Vector3 = body.hips.global_transform.affine_inverse() * (hit as Vector3)
	match mode:
		Mode.CLIP:
			if sel_key < 0:
				return
			var key: Dictionary = clip.keys[sel_key]
			match _drag_handle:
				"grip":
					key.grip = chest_local
				"tip":
					var d: Vector3 = chest_local - (key.grip as Vector3)
					if d.length() > 0.05:
						key.dir = d.normalized()
				"off":
					key.shield = chest_local
				"off_front":
					var d: Vector3 = chest_local - (key.shield as Vector3)
					if d.length() > 0.03:
						key.shield_front = d.normalized()
			_mark_dirty()
			_refresh_fields()
		Mode.POSE:
			var pw := PoseLibrary.weapon(_pose_id())
			if pose_name == "stow":
				var st: Dictionary = pw.stow
				var local := chest_local if st.get("space", "hips") == "chest" else hips_local
				if _drag_handle == "grip":
					st.pos = local
				elif _drag_handle == "tip":
					var d: Vector3 = local - (st.pos as Vector3)
					if d.length() > 0.05:
						st.dir = d.normalized()
			else:
				var pz: Dictionary = pw[pose_name]
				match _drag_handle:
					"grip":
						pz.grip = chest_local
					"tip":
						var d: Vector3 = chest_local - (pz.grip as Vector3)
						if d.length() > 0.05:
							pz.dir = d.normalized()
					"off":
						pz.off = chest_local
					"off_front":
						var d: Vector3 = chest_local - (pz.off as Vector3)
						if d.length() > 0.03:
							pz.off_front = d.normalized()
			_pose_changed()
		Mode.GEAR:
			var g: Dictionary = PoseLibrary.gear()[gear_item]
			var hips_space := gear_item in ["dagger_stow", "lantern_belt"]
			var local := hips_local if hips_space else chest_local
			if _drag_handle == "off":
				g.pos = local
			elif _drag_handle == "off_front":
				var d: Vector3 = local - (g.pos as Vector3)
				if d.length() > 0.03:
					if g.has("front"):
						g.front = d.normalized()
					elif g.has("dir"):
						g.dir = d.normalized()
			_gear_changed()


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
		if c.is_empty():
			return
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.06))
		if c.trail.x >= 0.0:
			draw_rect(Rect2(_x(c.trail.x), 4, _x(c.trail.y) - _x(c.trail.x), h - 8), Color(0.3, 0.9, 1.0, 0.12))
		if c.hit >= 0.0:
			draw_line(Vector2(_x(c.hit), 2), Vector2(_x(c.hit), h - 2), Color(1.0, 0.3, 0.25), 2.0)
			draw_string(get_theme_default_font(), Vector2(_x(c.hit) + 4, 14), "hit", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.45, 0.4))
		for i in 11:
			var x := _x(i / 10.0)
			draw_line(Vector2(x, h - 10), Vector2(x, h - 2), Color(0.4, 0.5, 0.5), 1.0)
		if not c.get("loop", false):
			for tt in [0.0, 1.0]:
				_diamond(Vector2(_x(tt), h * 0.5), 6.0, Color(0.45, 0.5, 0.5))
		for i in c.keys.size():
			var col := Color(1.0, 0.85, 0.2) if i == ws.sel_key else Color(0.85, 0.9, 0.9)
			_diamond(Vector2(_x(c.keys[i].t), h * 0.5), 8.0, col)
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
				var nt := clampf(snappedf(_time(event.position.x), 0.005), 0.02, 0.98)
				ws.clip.keys[_drag_key].t = nt
				ws.t = nt
				ws._mark_dirty()
				ws._refresh_fields()
			elif _scrubbing:
				ws._set_t(_time(event.position.x))
			queue_redraw()
