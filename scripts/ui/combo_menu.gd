class_name ComboMenu
extends ColorRect
## Kombo-Baukasten (Taste C): Kette aus 5 Plätzen zusammenstellen, Waffe und Zweithand wählen.
## Bedienung: Baustein anklicken, dann einen Platz anklicken (oder umgekehrt). Rechtsklick auf einen Platz leert ihn.
## Im Testlevel überall erreichbar; später nur an Feuern/Rastplätzen.

signal closed

var player: Player
var _slot_btns: Array[Button] = []
var _pool_box: GridContainer
var _detail: RichTextLabel
var _weapon_box: HBoxContainer
var _off_box: HBoxContainer
var _picked: StringName = &""  ## ausgewählter Baustein
var _picked_slot := -1  ## ausgewählter Platz
var _hint: Label

const C_TITLE := Color(0.85, 0.97, 0.97)
const C_GOLD := Color(1.0, 0.82, 0.45)
const C_DIM := Color(0.55, 0.66, 0.68)


func setup(p: Player) -> void:
	player = p
	color = Color(0.02, 0.05, 0.06, 0.86)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := _label("Combo Chain", 30, C_TITLE)
	col.add_child(title)
	col.add_child(_label("Left click plays the chain from left to right. Every order works: each move reacts to what earlier moves left on the enemy.", 14, C_DIM))

	# Waffe + Zweithand
	var gear := HBoxContainer.new()
	gear.add_theme_constant_override("separation", 10)
	col.add_child(gear)
	gear.add_child(_label("Weapon", 16, C_GOLD))
	_weapon_box = HBoxContainer.new()
	gear.add_child(_weapon_box)
	for wid in WeaponDef.IDS:
		var b := Button.new()
		b.text = WeaponDef.make(wid).display_name
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(120, 34)
		b.pressed.connect(_on_weapon.bind(wid))
		b.set_meta("id", wid)
		_weapon_box.add_child(b)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(30, 0)
	gear.add_child(sp)
	gear.add_child(_label("Off-hand", 16, C_GOLD))
	_off_box = HBoxContainer.new()
	gear.add_child(_off_box)
	for o in [[&"shield", "Shield"], [&"dagger", "Dagger"], [&"", "Empty (two-handed)"]]:
		var b := Button.new()
		b.text = o[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 34)
		b.pressed.connect(_on_off.bind(o[0]))
		b.set_meta("id", o[0])
		_off_box.add_child(b)

	# Kette
	var chain := HBoxContainer.new()
	chain.add_theme_constant_override("separation", 8)
	col.add_child(chain)
	for i in Player.CHAIN_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 64)
		b.toggle_mode = true
		b.gui_input.connect(_on_slot_input.bind(i))
		b.pressed.connect(_on_slot.bind(i))
		b.mouse_entered.connect(func(): _show_detail(_slot_id(i)))
		chain.add_child(b)
		_slot_btns.append(b)
		if i < Player.CHAIN_SLOTS - 1:
			chain.add_child(_label(">", 22, C_DIM))

	_hint = _label("", 13, C_DIM)
	col.add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var pool_col := VBoxContainer.new()
	pool_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pool_col)
	pool_col.add_child(_label("Moves", 18, C_GOLD))
	_pool_box = GridContainer.new()
	_pool_box.columns = 4
	_pool_box.add_theme_constant_override("h_separation", 6)
	_pool_box.add_theme_constant_override("v_separation", 6)
	pool_col.add_child(_pool_box)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.custom_minimum_size = Vector2(380, 220)
	_detail.add_theme_font_size_override("normal_font_size", 15)
	_detail.add_theme_font_size_override("bold_font_size", 19)
	_detail.fit_content = true
	row.add_child(_detail)

	var close := Button.new()
	close.text = "Close (C / Esc)"
	close.custom_minimum_size = Vector2(200, 36)
	close.pressed.connect(close_menu)
	col.add_child(close)


func _label(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func open_menu() -> void:
	visible = true
	_picked = &""
	_picked_slot = -1
	refresh()
	_show_detail(&"")


func close_menu() -> void:
	visible = false
	closed.emit()


func _slot_id(i: int) -> StringName:
	return player.combo_chain[i] if i < player.combo_chain.size() else &""


func refresh() -> void:
	for b: Button in _weapon_box.get_children():
		b.button_pressed = b.get_meta("id") == player.weapon.id
	for b: Button in _off_box.get_children():
		b.button_pressed = b.get_meta("id") == player.offhand_choice
		b.disabled = not player.weapon.allows_offhand() and b.get_meta("id") != &""
	for i in _slot_btns.size():
		var id := _slot_id(i)
		var b := _slot_btns[i]
		b.button_pressed = i == _picked_slot
		if id == &"":
			b.text = "%d\n(empty)" % (i + 1)
			b.modulate = Color(0.7, 0.75, 0.75)
		else:
			var m := ComboModules.make(id)
			var ok := ComboModules.usable(id, player.weapon)
			b.text = "%d\n%s%s" % [i + 1, m.display_name, "" if ok else "  (skipped)"]
			b.modulate = Color(1, 0.9, 0.7) if m.finisher else Color(1, 1, 1)
			if not ok:
				b.modulate = Color(0.6, 0.5, 0.5)
	# Der gedrückte Knopf sendet gerade noch sein Signal: erst aus dem Baum nehmen, später löschen
	# (sofortiges free() lässt Godot im Editor an dieser Stelle anhalten)
	for c in _pool_box.get_children():
		_pool_box.remove_child(c)
		c.queue_free()
	for id in player.combo_pool:
		var m := ComboModules.make(id)
		var b := Button.new()
		b.text = m.display_name + ("  *" if m.finisher else "")
		b.custom_minimum_size = Vector2(150, 40)
		b.toggle_mode = true
		b.button_pressed = id == _picked
		var ok := ComboModules.usable(id, player.weapon)
		b.disabled = not ok
		if m.weapon != &"":
			b.tooltip_text = WeaponDef.make(m.weapon).display_name + " only"
		b.pressed.connect(_on_pool.bind(id))
		b.mouse_entered.connect(_show_detail.bind(id))
		_pool_box.add_child(b)
	if _picked != &"":
		_hint.text = "Now click a slot to place " + ComboModules.make(_picked).display_name + "."
	elif _picked_slot >= 0:
		_hint.text = "Now click a move for slot %d.  Right click a slot to clear it." % (_picked_slot + 1)
	else:
		_hint.text = "Pick a move, then a slot.  Right click a slot to clear it.  * = finisher (heavy, long recovery)."


func _show_detail(id: StringName) -> void:
	if id == &"":
		var w := player.weapon
		var two := w.two_handed(player.offhand_choice if not player.light_out else &"light")
		_detail.text = "[b]%s[/b]\n%s\nReach %+.1f m   Damage x%.2f   Speed x%.2f\n\n[color=#9ab]Own moves: %s[/color]" % [
			w.display_name, "two-handed" if two else "one-handed",
			w.eff_reach(&"" if two else &"shield"), w.eff_damage(&"" if two else &"shield"), 1.0 / w.eff_speed(&"" if two else &"shield"),
			", ".join(w.own_modules.map(func(x): return ComboModules.make(x).display_name))]
		return
	var m := ComboModules.make(id)
	var t := "[b]%s[/b]%s\n%s\n" % [m.display_name, "  (finisher)" if m.finisher else "", m.desc]
	if m.creates != "":
		t += "\n[color=#ffd27a]Creates:[/color] " + m.creates
	if m.reacts != "":
		t += "\n[color=#8fe8ff]Reacts to:[/color] " + m.reacts
	t += "\n\n[color=#9ab]Stamina %d[/color]" % roundi(m.cost * player.weapon.cost)
	_detail.text = t


func _on_pool(id: StringName) -> void:
	if _picked_slot >= 0:
		player.set_chain_slot(_picked_slot, id)
		_picked_slot = -1
		_picked = &""
	else:
		_picked = &"" if _picked == id else id
	refresh()
	_show_detail(id)


func _on_slot(i: int) -> void:
	if _picked != &"":
		player.set_chain_slot(i, _picked)
		_picked = &""
		_picked_slot = -1
	else:
		_picked_slot = -1 if _picked_slot == i else i
	refresh()


func _on_slot_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		player.set_chain_slot(i, &"")
		refresh()


func _on_weapon(wid: StringName) -> void:
	player.set_weapon(wid)
	refresh()
	_show_detail(&"")


func _on_off(item: StringName) -> void:
	player.set_offhand(item)
	refresh()
	_show_detail(&"")
