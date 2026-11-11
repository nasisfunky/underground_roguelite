class_name ShieldBash
extends Ability
## Taste 2: Schildstoß. Kurzer Vorstoß, wenig Schaden, bringt Gegner sicher ins Taumeln.

const HIT_AT := 0.24
var _hit_done := false


func _init() -> void:
	display_name = "Shield Bash"
	short_name = "Bash"
	cooldown = 7.0
	stamina_cost = 15.0
	duration = 0.72
	cancel_at = 0.38


func start(_p: Player) -> void:
	_hit_done = false


func update(p: Player, t: float, delta: float) -> bool:
	var spd := 8.0 if t < HIT_AT + 0.04 else 0.0
	p._horizontal_move(p.forward() * spd, delta * 4.0)
	if not _hit_done and t >= HIT_AT:
		_hit_done = true
		var info := DamageInfo.new()
		info.amount = 6.0
		info.source = p
		info.knockback = 7.0
		info.poise_damage = 60.0
		info.hitstop = 0.08
		info.shake = 0.3
		if p.hit_cone(1.9, 55.0, info) > 0:
			FX.sparks(p, p.global_position + p.forward() * 0.9 + Vector3.UP * 1.2, Color(0.9, 0.95, 1.0), 10, 1.2)
	return t >= duration


func animate(_p: Player, body: ShadowBody, t: float) -> void:
	body.action = &"bash"
	body.action_t = t / duration
