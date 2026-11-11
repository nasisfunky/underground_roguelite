class_name Hitbox
extends Area3D
## Angriffszone. Ist nur während der aktiven Frames eines Angriffs scharf
## und trifft jedes Ziel pro Schwung höchstens einmal.

signal hit_landed(target: Node, result: int, info: DamageInfo)

var info: DamageInfo
var active := false
var _already_hit: Array[Node] = []


func _init(mask: int = 0, shape: Shape3D = null, offset := Vector3.ZERO) -> void:
	collision_layer = 0
	collision_mask = mask
	monitoring = true
	monitorable = false
	if shape:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = offset
		add_child(cs)


func activate(damage: DamageInfo) -> void:
	info = damage
	active = true
	_already_hit.clear()


func deactivate() -> void:
	active = false


func _physics_process(_delta: float) -> void:
	if not active:
		return
	for area in get_overlapping_areas():
		if area is Hurtbox:
			var target: Node = area.entity
			if target == null or target in _already_hit or target == info.source:
				continue
			_already_hit.append(target)
			var result: int = area.take_hit(info.duplicate_info())
			hit_landed.emit(target, result, info)
