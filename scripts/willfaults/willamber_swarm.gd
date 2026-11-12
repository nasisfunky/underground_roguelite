class_name WillamberSwarm
extends Node3D
## Schwarm aus Willambers um einen Punkt (target, lokal). Unterwegs: tauchen auf, lauern, springen
## sprunghaft umher und tauchen wieder ab. Angriff: kreisen den Punkt ein, einer nach dem anderen
## stößt vor und schlägt zu, danach schnell zurück; manche tauchen zur Verteidigung ab.

@export var count := 5
var attacking := false
var target := Vector3.ZERO
var t := 0.0
var _t0 := 0.0
var crew: Array[WillamberBody] = []
var _from: Array[Vector3] = []
var _to: Array[Vector3] = []
var _strike_next: Array[bool] = []
var _moves: Array[int] = []


func _ready() -> void:
	for i in count:
		var c := WillamberBody.new()
		c.index = i
		c.rng.seed = 23 + i * 29
		add_child(c)
		var a := float(i) / count * TAU + 0.4
		c.position = target + Vector3(cos(a), 0, sin(a)) * 1.1
		c.state_t = 0.2 + (i % 7) * 0.25
		crew.append(c)
		_from.append(c.position)
		_to.append(c.position)
		_strike_next.append(false)
		_moves.append(0)


func set_attacking(on: bool) -> void:
	if on == attacking:
		return
	attacking = on
	_t0 = t
	for c in crew:
		if c.state == WillamberBody.S.HIDDEN:
			c.state_t = minf(c.state_t, 0.3)


func _pick_spot(i: int) -> void:
	var c := crew[i]
	var rel := c.position - target
	if attacking:
		var a := atan2(rel.z, rel.x) + (c.rng.randf() - 0.5) * 1.4
		var r := 1.0 + c.rng.randf() * 0.3
		_to[i] = target + Vector3(cos(a) * r, 0, sin(a) * r)
	else:
		var a := c.rng.randf() * TAU
		var r := 0.8 + c.rng.randf() * 0.8
		_to[i] = target + Vector3(cos(a) * r, 0, sin(a) * r)


func tick(delta: float) -> void:
	t += delta
	for i in crew.size():
		var c := crew[i]
		c.state_t -= delta
		c.state_k += delta
		match c.state:
			WillamberBody.S.HIDDEN:
				c.position = c.position.lerp(_to[i], minf(1.0, delta * 1.3))
				if c.state_t <= 0.0:
					c.set_state(WillamberBody.S.RISE, 0.45)
			WillamberBody.S.RISE:
				if c.state_t <= 0.0:
					c.set_state(WillamberBody.S.LURK, 0.3 + c.rng.randf() * 0.7)
			WillamberBody.S.SINK:
				if c.state_t <= 0.0:
					c.set_state(WillamberBody.S.HIDDEN, (0.7 + c.rng.randf() * 0.6) if attacking else (1.2 + c.rng.randf() * 1.5))
					_pick_spot(i)
					_moves[i] = 0
			WillamberBody.S.LURK:
				if c.state_t <= 0.0:
					_moves[i] += 1
					var my_turn := attacking and int(floorf((t - _t0) / 1.1)) % crew.size() == i
					var rel := c.position - target
					if my_turn and rel.length() > 0.7:
						_from[i] = c.position
						var a := atan2(rel.z, rel.x)
						_to[i] = target + Vector3(cos(a), 0, sin(a)) * 0.42
						c.set_state(WillamberBody.S.DASH, 0.13)
						_strike_next[i] = true
					elif (not attacking and _moves[i] > 4 + (i % 3)) or (attacking and c.rng.randf() < 0.12):
						c.set_state(WillamberBody.S.SINK, 0.4)
					else:
						_from[i] = c.position
						_pick_spot(i)
						c.set_state(WillamberBody.S.DASH, 0.1 + c.rng.randf() * 0.08)
					c._puff.restart()
			WillamberBody.S.DASH:
				var total := maxf(c.state_t + c.state_k, 0.01)
				var k := minf(1.0, c.state_k / total)
				c.position = _from[i].lerp(_to[i], 1.0 - pow(1.0 - k, 3.0))
				if c.state_t <= 0.0:
					c.position = _to[i]
					if _strike_next[i]:
						_strike_next[i] = false
						c.set_state(WillamberBody.S.STRIKE, 0.45)
					else:
						c.set_state(WillamberBody.S.LURK, (0.2 + c.rng.randf() * 0.5) if attacking else (0.35 + c.rng.randf() * 1.1))
			WillamberBody.S.STRIKE:
				c.strike = sin(PI * clampf(c.state_k / 0.45, 0.0, 1.0))
				if c.state_t <= 0.0:
					c.strike = 0.0
					_from[i] = c.position
					_pick_spot(i)
					c.set_state(WillamberBody.S.DASH, 0.14)
		# Blick: im Angriff zum Ziel, sonst in Bewegungsrichtung
		var mv := _to[i] - c.position
		var to_t := target - c.position
		if attacking or c.state != WillamberBody.S.DASH or mv.length_squared() < 1e-4:
			c.face_yaw = atan2(-to_t.x, -to_t.z)
		else:
			c.face_yaw = atan2(-mv.x, -mv.z)
		c.pose(delta)
