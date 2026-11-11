class_name HeavyStrike
extends Ability
## Taste 1: Wuchtiger Hieb von oben. Trifft alle Gegner in einem Kegel, bricht deren Haltung.

const HIT_AT := 0.5
var _hit_done := false


func _init() -> void:
	display_name = "Heavy Strike"
	short_name = "Strike"
	cooldown = 5.0
	stamina_cost = 20.0
	duration = 1.2
	cancel_at = 0.78


func start(_p: Player) -> void:
	_hit_done = false


func update(p: Player, t: float, delta: float) -> bool:
	# kurzer Ausfallschritt, danach fest am Boden
	var lunge := 4.0 if t > 0.3 and t < HIT_AT else 0.0
	var dir := p.forward()
	p._horizontal_move(dir * lunge, delta * (3.0 if lunge > 0.0 else 1.0))
	if not _hit_done and t >= HIT_AT:
		_hit_done = true
		var info := DamageInfo.new()
		info.amount = 26.0
		info.source = p
		info.knockback = 6.0
		info.poise_damage = 35.0
		info.hitstop = 0.1
		info.heavy = true
		info.shake = 0.4
		p.hit_cone(2.9, 70.0, info)
		var impact := p.global_position + dir * 1.4
		FX.ring(p, impact, Color(0.5, 0.95, 1.0, 0.9), 2.4, 0.3)
		FX.dust(p, impact, 8, 1.2)
		if p.cam:
			p.cam.add_trauma(0.22)
	return t >= duration


func animate(_p: Player, body: ShadowBody, t: float) -> void:
	body.action = &"swing"
	body.swing_index = 2
	body.action_t = t / duration
