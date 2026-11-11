class_name PlayerInput
extends Node
## Sammelt die Eingaben EINES lokalen Spielers.
## Der Spieler-Controller liest nur diesen Zustand und kennt keine Geräte.
## Für Koop kann später ein NetworkInput mit derselben Schnittstelle eingesetzt werden.
##
## Action-Steuerung:
##   Maus bewegen     -> Kamera dreht frei um den Charakter (Cursor im Spiel versteckt)
##   Linksklick       -> normaler Angriff (Kombo)
##   Rechtsklick      -> blocken (halten; früh = Parade)
##   Mittlere Taste   -> Alternativangriff der Waffe (Schwert: Stich)
##   Alt halten       -> Cursor kurz freigeben
## Fähigkeiten liegen auf 1-9.

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
var look_delta := Vector2.ZERO  # wird von der Kamera verbraucht
var zoom_delta := 0.0

# Einmal-Ereignisse; werden vom Controller abgeholt (consume_*)
var _jump_pressed := false
var _roll_pressed := false
var _target_next := false
var _attack: int = 0  # 1 = normal (LMB), 2 = alternativ (MMB)
var _ability: int = 0  # 1..9, 0 = keine
var _alt_free := false


func _ready() -> void:
	capture_mouse()


func _process(_delta: float) -> void:
	# Alt halten gibt den Cursor frei (später für Inventar/Menüs)
	var alt := Input.is_key_pressed(KEY_ALT)
	if alt != _alt_free:
		_alt_free = alt
		if alt:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			capture_mouse()


func capture_mouse() -> void:
	if not Game.paused and not _alt_free:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if Game.paused:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					if captured:
						if mb.button_index != MOUSE_BUTTON_RIGHT:  # rechts = blocken (über die Aktion "block")
							_attack = 1 if mb.button_index == MOUSE_BUTTON_LEFT else 2
					elif not _alt_free:
						capture_mouse()  # erster Klick nach Fokusverlust holt nur die Maus zurück
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_delta -= 1.0
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_delta += 1.0
	elif event is InputEventMouseMotion:
		if captured:
			look_delta += (event as InputEventMouseMotion).screen_relative
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


func consume_attack() -> int:
	var v := _attack
	_attack = 0
	return v


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
