extends Node
## Globaler Spielzustand: Eingabebelegung, Spielerliste, Licht-Abfrage.
## Bewusst klein gehalten – alles, was später übers Netzwerk laufen muss,
## lebt in den Entities selbst, nicht hier.

signal player_registered(player: Node)
signal room_entered(room_name: String)

const LAYER_WORLD := 1
const LAYER_PLAYERS := 2
const LAYER_ENEMIES := 4
const LAYER_PLAYER_HURTBOX := 8
const LAYER_ENEMY_HURTBOX := 16
const LAYER_TRIGGERS := 32

var players: Array[Node] = []
## Steuerungsmodus: false = Hybrid (WASD kamera-relativ), true = klassisch WoW (A/D drehen).
var classic_turning := false
var paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()


func register_player(p: Node) -> void:
	if p not in players:
		players.append(p)
		player_registered.emit(p)


func unregister_player(p: Node) -> void:
	players.erase(p)


## Nächster lebender Spieler – Gegner nutzen das, damit Koop später ohne Umbau funktioniert.
func nearest_player(from: Vector3, max_dist: float = INF) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for p in players:
		if not is_instance_valid(p) or p.is_dead():
			continue
		var d: float = (p as Node3D).global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = p
	return best


## Grobe Helligkeit an einer Position (0 = Schatten, 1+ = hell).
## Grundlage für spätere Mechaniken wie "durch Schatten gleiten" / "zu Licht teleportieren".
func light_level_at(pos: Vector3) -> float:
	var total := 0.0
	for l in get_tree().get_nodes_in_group("light_sources"):
		if l is OmniLight3D and l.visible:
			var d: float = l.global_position.distance_to(pos)
			var r: float = l.omni_range
			if d < r:
				total += l.light_energy * pow(1.0 - d / r, 2.0)
	return total


# --- Eingabebelegung ---
# Per Code, damit sie versioniert und leicht änderbar ist. Physische Tasten,
# damit WASD auch auf QWERTZ/AZERTY an der gleichen Stelle liegt.

func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("sprint", [KEY_SHIFT])
	_key_loc("roll", KEY_ALT, KEY_LOCATION_LEFT)
	_key("block", [KEY_Q])
	# Y/X nach Beschriftung (QWERTZ: Y liegt dort, wo auf US-Tastaturen Z ist)
	_key_label("draw_weapon", KEY_Y)
	_key_label("toggle_light", KEY_X)
	for i in range(1, 10):
		_key("ability_%d" % i, [KEY_0 + i])
	_key("toggle_help", [KEY_F1])
	_key("cycle_culture", [KEY_F2])
	_key("toggle_debug", [KEY_F3])
	_key("pause", [KEY_ESCAPE])
	_mouse("block", MOUSE_BUTTON_RIGHT)
	_mouse("block", MOUSE_BUTTON_XBUTTON1)
	_mouse("roll", MOUSE_BUTTON_XBUTTON2)


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _key_loc(action: String, key: Key, loc: KeyLocation) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.location = loc
	InputMap.action_add_event(action, ev)


func _key_label(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var ev := InputEventKey.new()
	ev.keycode = key
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
