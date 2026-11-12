class_name Tendril
extends Node3D
## Schattenranke (Shadow Hook): ein Strang aus schwarzer Flamme mit violett-blau glimmender Spitze.
## Schießt von der linken Hand zum Ziel und zieht sich mit ihm zurück.

const SHOOT := 0.1
const HOLD := 0.06
const BACK := 0.3

var _player: Player
var _to := Vector3.ZERO
var _hit := false
var _t := 0.0
var _segs: Array[MeshInstance3D] = []
var _tip: MeshInstance3D


func setup(from: Vector3, to: Vector3, hit: bool, p: Player) -> void:
	_player = p
	_to = to
	_hit = hit
	var core := ShadowBody.skin_material()
	var glow := LowPoly.mat(Color(0.55, 0.42, 1.0), 3.0)
	for i in 10:
		var m := MeshInstance3D.new()
		m.mesh = LowPoly.prism(0.05, 0.02, 1.0, 4)
		m.material_override = core if i % 3 != 2 else glow
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_segs.append(m)
	_tip = MeshInstance3D.new()
	_tip.mesh = LowPoly.crystal(0.22, 0.07)
	_tip.material_override = glow
	_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tip)
	global_position = from
	_update(from)


func _process(delta: float) -> void:
	_t += delta
	if _t > SHOOT + HOLD + BACK or not is_instance_valid(_player):
		queue_free()
		return
	_update(_player.body.hand_position(true))


func _update(from: Vector3) -> void:
	var reach: float
	if _t < SHOOT:
		reach = _t / SHOOT
	elif _t < SHOOT + HOLD:
		reach = 1.0
	else:
		reach = 1.0 - (_t - SHOOT - HOLD) / BACK
	reach = clampf(reach, 0.0, 1.0)
	# beim Zurückziehen folgt die Spitze dem gezogenen Gegner (oder schnellt leer zurück)
	var end := from.lerp(_to, reach)
	if _hit and _t >= SHOOT + HOLD:
		var k := (_t - SHOOT - HOLD) / BACK
		end = from.lerp(_to, 1.0 - k * k)
	var n := _segs.size()
	var dir := end - from
	var length := dir.length()
	if length < 0.02:
		visible = false
		return
	visible = true
	var side := dir.normalized().cross(Vector3.UP).normalized()
	for i in n:
		var a := float(i) / n
		var b := float(i + 1) / n
		# leichte Wellenform: lebendige Flamme statt starrer Stange
		var wa := sin(a * PI) * sin(_t * 40.0 + a * 9.0) * 0.08 * length * 0.15
		var wb := sin(b * PI) * sin(_t * 40.0 + b * 9.0) * 0.08 * length * 0.15
		var pa := from + dir * a + side * wa + Vector3.UP * sin(a * PI) * 0.12
		var pb := from + dir * b + side * wb + Vector3.UP * sin(b * PI) * 0.12
		var seg := pb - pa
		var m := _segs[i]
		m.global_transform = Transform3D(_basis_y(seg.normalized()) * Basis.from_scale(Vector3(1.0 - a * 0.4, seg.length(), 1.0 - a * 0.4)), (pa + pb) * 0.5)
	_tip.global_transform = Transform3D(_basis_y(dir.normalized()), end)


static func _basis_y(y: Vector3) -> Basis:
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-5:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
