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
@export var body_height := 1.8  ## Höhe der Kollisionskapsel

var health := 60.0
var poise := 20.0
var hitstop := 0.0
var spawn_transform: Transform3D
var _knock := Vector3.ZERO
## Zustände aus dem Kombo-System: &"reeling" (taumelt), &"bound" (Klinge gebunden), &"marked" (Lichtmal, stapelt bis 3)
## name -> {"t": Restzeit, "n": Stapel}
var status := {}
var _force_vel := Vector3.ZERO  ## erzwungene Bewegung (Heranziehen/Wegstoßen)
var _force_t := 0.0
var _force_len := 0.0
var _status_vis: Node3D
var _status_label: Label3D
var _bound_ring: MeshInstance3D
var _marks: Array[MeshInstance3D] = []
var _status_time := 0.0
const MAX_MARKS := 3


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
	cap.height = body_height
	col.shape = cap
	col.position.y = body_height * 0.5
	add_child(col)
	var hb := Hurtbox.new(self, Game.LAYER_ENEMY_HURTBOX, cap, Vector3(0, body_height * 0.5, 0))
	add_child(hb)
	_build_status_vis()


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


# ------------------------------------------------------------------
# Zustände (Kombo-System) und erzwungene Bewegung
# ------------------------------------------------------------------

func has_status(s: StringName) -> bool:
	return status.has(s)


func status_stacks(s: StringName) -> int:
	return int(status[s].n) if status.has(s) else 0


## Zustand setzen/auffrischen. Taumeln und Binden halten den Gegner fest (er kann nicht angreifen).
func add_status(s: StringName, duration: float, stacks := 1) -> void:
	if is_dead():
		return
	if status.has(s):
		status[s].t = maxf(status[s].t, duration)
		status[s].n = mini(int(status[s].n) + stacks, MAX_MARKS if s == &"marked" else 1)
	else:
		status[s] = {"t": duration, "n": mini(stacks, MAX_MARKS if s == &"marked" else 1)}
	if s == &"reeling" or s == &"bound":
		hold(duration)
	_refresh_status_vis()


## Zustand entfernen. Rückgabe: wie viele Stapel es waren.
func clear_status(s: StringName) -> int:
	var n := status_stacks(s)
	status.erase(s)
	_refresh_status_vis()
	return n


## Gegner kann für `duration` Sekunden nichts tun (Unterklassen: Taumeln/Stagger).
func hold(_duration: float) -> void:
	pass


## Erzwungene Bewegung über `time` Sekunden (bremst zum Ende hin ab). Überschreibt Rückstoß.
func force_move(offset: Vector3, time: float) -> void:
	offset.y = 0.0
	_force_len = maxf(time, 0.05)
	_force_t = _force_len
	_force_vel = offset / _force_len * 2.0  # linear abbremsend -> Durchschnitt = offset / time
	_knock = Vector3.ZERO


func is_forced() -> bool:
	return _force_t > 0.0


## Von Unterklassen in ihrer Bewegung aufzurufen: ersetzt die horizontale Geschwindigkeit, solange erzwungen.
func _forced_velocity(hv: Vector3, delta: float) -> Vector3:
	if _force_t <= 0.0:
		return hv
	var k := _force_t / _force_len
	_force_t -= delta
	return _force_vel * k


func _process(delta: float) -> void:
	if status.is_empty():
		if _status_vis and _status_vis.visible:
			_status_vis.visible = false
		return
	_status_time += delta
	var changed := false
	for s in status.keys():
		status[s].t -= delta
		if status[s].t <= 0.0:
			status.erase(s)
			changed = true
	if changed:
		_refresh_status_vis()
	_animate_status_vis()


func _build_status_vis() -> void:
	_status_vis = Node3D.new()
	_status_vis.name = "StatusVis"
	_status_vis.visible = false
	add_child(_status_vis)
	_status_label = Label3D.new()
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = true
	_status_label.fixed_size = true
	_status_label.pixel_size = 0.0011
	_status_label.font_size = 26
	_status_label.outline_size = 8
	_status_label.position = Vector3(0, target_height + 0.42, 0)
	_status_vis.add_child(_status_label)
	var tor := TorusMesh.new()
	tor.inner_radius = radius + 0.16
	tor.outer_radius = radius + 0.22
	tor.rings = 16
	tor.ring_segments = 4
	_bound_ring = MeshInstance3D.new()
	_bound_ring.mesh = tor
	_bound_ring.material_override = LowPoly.unshaded(Color(0.45, 0.95, 1.0))
	_bound_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bound_ring.position.y = body_height * 0.55
	_status_vis.add_child(_bound_ring)
	var mark_mat := LowPoly.mat(Color(1.0, 0.82, 0.4), 4.0)
	for i in MAX_MARKS:
		var m := MeshInstance3D.new()
		m.mesh = LowPoly.crystal(0.14, 0.05)
		m.material_override = mark_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_status_vis.add_child(m)
		_marks.append(m)


func _refresh_status_vis() -> void:
	if _status_vis == null:
		return
	_status_vis.visible = not status.is_empty()
	var words: Array[String] = []
	if status.has(&"bound"):
		words.append("BOUND")
	if status.has(&"reeling"):
		words.append("REELING")
	var n := status_stacks(&"marked")
	if n > 0:
		words.append("MARK x%d" % n)
	_status_label.text = "  ".join(words)
	_status_label.modulate = Color(0.55, 0.95, 1.0) if status.has(&"bound") else (Color(1.0, 0.62, 0.3) if status.has(&"reeling") else Color(1.0, 0.85, 0.45))
	_bound_ring.visible = status.has(&"bound")
	for i in _marks.size():
		_marks[i].visible = i < n


func _animate_status_vis() -> void:
	var n := status_stacks(&"marked")
	for i in n:
		var a := _status_time * 2.2 + TAU * i / float(maxi(n, 1))
		_marks[i].position = Vector3(cos(a) * (radius + 0.25), body_height * 0.7 + sin(_status_time * 3.0 + i) * 0.06, sin(a) * (radius + 0.25))
		_marks[i].rotation = Vector3(0.3, -a, 0.0)
	if _bound_ring.visible:
		_bound_ring.rotation.y = _status_time * 1.5
		var sc := 1.0 + 0.04 * sin(_status_time * 9.0)
		_bound_ring.scale = Vector3(sc, 1.0, sc)
