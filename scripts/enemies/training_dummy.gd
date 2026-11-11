class_name TrainingDummy
extends Enemy
## Trainingspuppe: unendlich Leben, wackelt bei Treffern, zeigt Schaden an.

var _visual: Node3D
var _wobble := Vector2.ZERO  # x = Neigung vor/zurück, y = seitlich
var _wobble_vel := Vector2.ZERO
var _flash_t := 0.0
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D


func _ready() -> void:
	display_name = "Training Dummy"
	max_health = 500.0
	target_height = 2.2
	radius = 0.4
	super._ready()
	_build()


func _build() -> void:
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 1, 1, 0.7)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var parts := ModelParts.load_parts("res://assets/models/dummy_parts.glb")
	# Sockel bleibt fest, der Rest wackelt
	var base := MeshInstance3D.new()
	base.mesh = parts.get("DummyBase")
	add_child(base)
	_meshes.append(base)
	_visual = Node3D.new()
	_visual.position.y = 0.25
	add_child(_visual)
	var body := MeshInstance3D.new()
	body.mesh = parts.get("DummyBody")
	_visual.add_child(body)
	_meshes.append(body)


func _m(mesh: Mesh, material: Material, parent: Node, pos: Vector3) -> MeshInstance3D:
	var mi := LowPoly.mesh_instance(mesh, material, parent, pos)
	_meshes.append(mi)
	return mi


func _on_hit(info: DamageInfo, dir: Vector3) -> void:
	_knock = Vector3.ZERO  # Puppe bewegt sich nicht
	var local := global_transform.basis.inverse() * dir
	_wobble_vel += Vector2(-local.z, local.x) * (3.0 + info.knockback * 1.2)
	_flash_t = 0.08
	for m in _meshes:
		m.material_overlay = _flash_mat
	# Puppe "stirbt" nie
	if health < max_health * 0.2:
		health = max_health


func _physics_process(delta: float) -> void:
	if hitstop > 0.0:
		hitstop -= delta
		return
	# Feder-Dämpfer fürs Wackeln
	_wobble_vel += (-_wobble * 90.0 - _wobble_vel * 7.0) * delta
	_wobble += _wobble_vel * delta
	_visual.rotation = Vector3(_wobble.x * -0.35, 0.0, _wobble.y * -0.35)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for m in _meshes:
				m.material_overlay = null
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity = Vector3.ZERO
	move_and_slide()
