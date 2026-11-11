class_name PlayerCamera
extends Node3D
## WoW-artige Orbit-Kamera mit Kollision, Zoom, weichem Nachführen und Screenshake.
## Läuft in _process (Bildrate) und folgt der interpolierten Spielerposition,
## damit sie auch bei 144 Hz butterweich bleibt.

@export var sensitivity := 0.0032  # Radiant pro Pixel
@export var min_pitch := deg_to_rad(-72.0)
@export var max_pitch := deg_to_rad(38.0)
@export var min_zoom := 2.2
@export var max_zoom := 13.0
@export var zoom_step := 1.1
@export var pivot_height := 1.55
@export var follow_sharpness_xz := 22.0
@export var follow_sharpness_y := 9.0
## Nur im klassischen Modus: Kamera schwenkt beim Laufen langsam hinter den Charakter.
@export var auto_follow_speed := 2.2

var yaw := 0.0
var pitch := deg_to_rad(-18.0)
var target_distance := 6.5
var distance := 6.5
var trauma := 0.0  # 0..1, Screenshake

var target: Node3D
var input: PlayerInput
var camera: Camera3D
var _arm: SpringArm3D
var _shake_node: Node3D
var _pivot_pos := Vector3.ZERO
var _noise := FastNoiseLite.new()
var _noise_t := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arm = SpringArm3D.new()
	_arm.collision_mask = Game.LAYER_WORLD
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	_arm.shape = sphere
	_arm.margin = 0.1
	add_child(_arm)
	# Der SpringArm setzt die Position seines direkten Kindes -> Shake auf einem Zwischenknoten
	_shake_node = Node3D.new()
	_arm.add_child(_shake_node)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.08
	camera.far = 400.0
	_shake_node.add_child(camera)
	camera.make_current()
	_noise.frequency = 2.0
	if target:
		snap_to_target()


func snap_to_target() -> void:
	_pivot_pos = target.global_position + Vector3.UP * pivot_height
	global_position = _pivot_pos


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Richtung, in die die Kamera schaut (nur horizontal) – Basis für kamera-relatives Laufen.
func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func _process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		return
	if input:
		var look := input.consume_look()
		yaw -= look.x * sensitivity
		pitch = clampf(pitch - look.y * sensitivity, min_pitch, max_pitch)
		var z := input.consume_zoom()
		if z != 0.0:
			target_distance = clampf(target_distance * pow(zoom_step, z), min_zoom, max_zoom)

	# Klassischer WoW-Modus: Kamera rutscht beim Laufen hinter den Charakter.
	if Game.classic_turning and input and not (input.lmb_held or input.rmb_held):
		if target.has_method("get_horizontal_speed") and target.get_horizontal_speed() > 0.5:
			var behind: float = target.get_facing_yaw()
			yaw = lerp_angle(yaw, behind, 1.0 - exp(-auto_follow_speed * delta))

	# Weiches Folgen. Y langsamer, damit Sprünge die Kamera nicht zappeln lassen.
	var tpos: Vector3 = target.get_global_transform_interpolated().origin + Vector3.UP * pivot_height
	var kxz := 1.0 - exp(-follow_sharpness_xz * delta)
	var ky := 1.0 - exp(-follow_sharpness_y * delta)
	_pivot_pos.x = lerpf(_pivot_pos.x, tpos.x, kxz)
	_pivot_pos.z = lerpf(_pivot_pos.z, tpos.z, kxz)
	_pivot_pos.y = lerpf(_pivot_pos.y, tpos.y, ky)
	# Nie zu weit hinterherhängen (z.B. bei Rolle/Teleport)
	if _pivot_pos.distance_to(tpos) > 3.0:
		_pivot_pos = tpos + (_pivot_pos - tpos).limit_length(3.0)

	distance = lerpf(distance, target_distance, 1.0 - exp(-10.0 * delta))
	global_position = _pivot_pos
	rotation = Vector3(pitch, yaw, 0.0)
	_arm.spring_length = distance

	# Screenshake (Trauma²-Verfahren, klingt schnell ab)
	_noise_t += delta * 30.0
	var shake := trauma * trauma
	camera.position = Vector3(_noise.get_noise_2d(_noise_t, 0.0), _noise.get_noise_2d(0.0, _noise_t), 0.0) * 0.28 * shake
	camera.rotation.z = _noise.get_noise_2d(_noise_t, 50.0) * deg_to_rad(2.5) * shake
	trauma = maxf(trauma - delta * 1.8, 0.0)
