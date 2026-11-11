class_name Spring
extends RefCounted
## Dynamik zweiter Ordnung (nach t3ssel8r, "Giving Personality to Procedural Animations").
## Folgt einem Zielwert wie eine gedämpfte Feder:
##   f    Frequenz (Hz): wie schnell reagiert wird
##   zeta Dämpfung: <1 schwingt nach, 1 kritisch gedämpft, >1 träge
##   r    Antwort: <0 holt aus (Antizipation), >1 schießt über, 1 neutral
## Funktioniert für float und Vector3.

var y: Variant
var yd: Variant
var _xp: Variant
var _k1 := 0.0
var _k2 := 0.0
var _k3 := 0.0


func _init(f: float, zeta: float, r: float, x0: Variant) -> void:
	set_params(f, zeta, r)
	y = x0
	_xp = x0
	yd = x0 * 0.0


func set_params(f: float, zeta: float, r: float) -> void:
	_k1 = zeta / (PI * f)
	_k2 = 1.0 / ((TAU * f) * (TAU * f))
	_k3 = r * zeta / (TAU * f)


func update(dt: float, x: Variant) -> Variant:
	if dt <= 0.0:
		return y
	var xd: Variant = (x - _xp) / dt
	_xp = x
	# stabil auch bei großen Zeitschritten
	var k2 := maxf(_k2, maxf(dt * dt / 2.0 + dt * _k1 / 2.0, dt * _k1))
	y = y + yd * dt
	yd = yd + (x + xd * _k3 - y - yd * _k1) * (dt / k2)
	return y


## Sofort auf einen Wert setzen (z.B. nach Teleport).
func reset(x: Variant) -> void:
	y = x
	_xp = x
	yd = x * 0.0


## Stoß, z.B. beim Landen.
func kick(v: Variant) -> void:
	yd = yd + v
