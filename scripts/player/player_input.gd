class_name PlayerInput
extends Node
## Sammelt die Eingaben EINES lokalen Spielers.
## Der Spieler-Controller liest nur diesen Zustand und kennt keine Geräte.
## Für Koop kann später ein NetworkInput mit derselben Schnittstelle eingesetzt werden.
##
## WoW-Maussteuerung:
##   Linke Maustaste halten  -> Kamera dreht frei um den Charakter
##   Rechte Maustaste halten -> Kamera dreht, Charakter schaut mit (Mouselook)
##   Beide halten            -> zusätzlich vorwärts laufen
##   Kurzer Linksklick       -> Gegner unter dem Mauszeiger anvisieren
## Normale Angriffe laufen automatisch (Auto-Angriff), Fähigkeiten liegen auf 1-9.

const TAP_MAX_TIME := 0.22
const TAP_MAX_MOVE := 10.0  # Pixel

# Zustand, den der Controller pro Physik-Tick liest
# (live abgefragt, damit der erste Physik-Tick nach dem Tastendruck schon stimmt)
var move: Vector2:
	get:
		if Game.paused:
			return Vector2.ZERO
		return Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
var jump_held: bool:
	get:
		return not Game.paused and Input.is_action_pressed("jump")
var block_held: bool:
	get:
		return not Game.paused and Input.is_action_pressed("block")
var lmb_held := false
var rmb_held := false
var look_delta := Vector2.ZERO  # wird von der Kamera verbraucht
var zoom_delta := 0.0

# Einmal-Ereignisse; werden vom Controller abgeholt (consume_*)
var _jump_pressed := false
var _roll_pressed := false
var _target_next := false
var _click_pos: Variant = null  # Bildschirmposition eines kurzen Linksklicks
var _ability: int = 0  # 1..9, 0 = keine

var _lmb_down_time := 0.0
var _lmb_motion := 0.0
var _restore_cursor := Vector2.ZERO


func _input(event: InputEvent) -> void:
	if Game.paused:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_lmb_down_time = Time.get_ticks_msec() / 1000.0
					_lmb_motion = 0.0
					_set_button(true, rmb_held)
				else:
					var held := Time.get_ticks_msec() / 1000.0 - _lmb_down_time
					if lmb_held and held <= TAP_MAX_TIME and _lmb_motion <= TAP_MAX_MOVE:
						_click_pos = _restore_cursor if not rmb_held else null
					_set_button(false, rmb_held)
			MOUSE_BUTTON_RIGHT:
				_set_button(lmb_held, mb.pressed)
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_delta -= 1.0
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_delta += 1.0
	elif event is InputEventMouseMotion:
		if lmb_held or rmb_held:
			var rel: Vector2 = (event as InputEventMouseMotion).screen_relative
			look_delta += rel
			if lmb_held:
				_lmb_motion += rel.length()
	if event.is_echo():
		return
	if event.is_action_pressed("jump"):
		_jump_pressed = true
	if event.is_action_pressed("target_next"):
		_target_next = true
	for i in range(1, 10):
		if event.is_action_pressed("ability_%d" % i):
			_ability = i
	if event.is_action_pressed("roll"):
		_roll_pressed = true


func _set_button(lmb: bool, rmb: bool) -> void:
	var was_any := lmb_held or rmb_held
	lmb_held = lmb
	rmb_held = rmb
	var is_any := lmb_held or rmb_held
	if is_any and not was_any:
		# Wie in WoW: Cursor verschwindet und taucht beim Loslassen an derselben Stelle wieder auf.
		_restore_cursor = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif was_any and not is_any:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.warp_mouse(_restore_cursor)


func release_mouse() -> void:
	_set_button(false, false)


func consume_jump() -> bool:
	var v := _jump_pressed
	_jump_pressed = false
	return v


func consume_ability() -> int:
	var v := _ability
	_ability = 0
	return v


func consume_target_next() -> bool:
	var v := _target_next
	_target_next = false
	return v


func consume_click() -> Variant:
	var v: Variant = _click_pos
	_click_pos = null
	return v


func consume_roll() -> bool:
	var v := _roll_pressed
	_roll_pressed = false
	return v


func consume_look() -> Vector2:
	var v := look_delta
	look_delta = Vector2.ZERO
	return v


func consume_zoom() -> float:
	var v := zoom_delta
	zoom_delta = 0.0
	return v
