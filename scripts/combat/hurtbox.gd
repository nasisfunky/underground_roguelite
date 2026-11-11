class_name Hurtbox
extends Area3D
## Trefferzone eines Wesens. Leitet Treffer an `entity.receive_hit(info)` weiter.

var entity: Node


func _init(owner_entity: Node = null, layer: int = 0, shape: Shape3D = null, offset := Vector3.ZERO) -> void:
	entity = owner_entity
	collision_layer = layer
	collision_mask = 0
	monitoring = false
	monitorable = true
	if shape:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = offset
		add_child(cs)


func take_hit(info: DamageInfo) -> int:
	if entity and entity.has_method("receive_hit"):
		return entity.receive_hit(info)
	return DamageInfo.Result.IGNORED
