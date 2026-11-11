class_name Enemy
extends CharacterBody3D
## Basis für alles, was man anvisieren und schlagen kann (Gegner, Trainingspuppen).

signal died(enemy: Enemy)
signal health_changed(current: float, maximum: float)

@export var display_name := "Enemy"
@export var max_health := 60.0
@export var max_poise := 20.0
@export var target_height := 2.1  ## Höhe für Zielmarker
@export var radius := 0.45

var health := 60.0
var poise := 20.0
var hitstop := 0.0
var spawn_transform: Transform3D
var _knock := Vector3.ZERO


func _ready() -> void:
	add_to_group("targetable")
	add_to_group("enemies")
	collision_layer = Game.LAYER_ENEMIES
	collision_mask = Game.LAYER_WORLD | Game.LAYER_PLAYERS | Game.LAYER_ENEMIES
	health = max_health
	poise = max_poise
	spawn_transform = global_transform
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	var hb := Hurtbox.new(self, Game.LAYER_ENEMY_HURTBOX, cap, Vector3(0, 0.9, 0))
	add_child(hb)


func is_dead() -> bool:
	return health <= 0.0


func target_point() -> Vector3:
	return global_position + Vector3.UP * target_height


## Wird vom Angreifer aufgerufen. Rückgabe: DamageInfo.Result
func receive_hit(info: DamageInfo) -> int:
	if is_dead():
		return DamageInfo.Result.IGNORED
	health = maxf(health - info.amount, 0.0)
	health_changed.emit(health, max_health)
	hitstop = info.hitstop
	var dir := Vector3.FORWARD
	if info.source:
		dir = (global_position - info.source.global_position)
		dir.y = 0
		dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
	_knock = dir * info.knockback
	poise -= info.poise_damage
	FX.number(self, target_point(), str(roundi(info.amount)), Color(1.0, 0.92, 0.55) if not info.heavy else Color(1.0, 0.6, 0.2), info.heavy)
	FX.sparks(self, global_position + Vector3.UP * 1.2 - dir * 0.3, LowPoly.CYAN if not info.heavy else Color(1.0, 0.75, 0.4), 7 if not info.heavy else 12, 1.0 if not info.heavy else 1.4)
	_on_hit(info, dir)
	if health <= 0.0:
		_on_death()
		died.emit(self)
	return DamageInfo.Result.HIT


## Wird aufgerufen, wenn ein Spieler unseren Angriff pariert.
func on_parried(_by: Node3D) -> void:
	pass


func _on_hit(_info: DamageInfo, _dir: Vector3) -> void:
	pass


func _on_death() -> void:
	pass
