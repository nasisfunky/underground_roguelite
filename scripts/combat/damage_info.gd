class_name DamageInfo
extends RefCounted
## Beschreibt einen einzelnen Treffer. Wird vom Angreifer gebaut und vom Ziel ausgewertet.

enum Result { HIT, BLOCKED, PARRIED, DODGED, IGNORED, GUARD_BREAK }

var amount: float = 10.0
var source: Node3D  ## Angreifer (für Block-Richtung, Parry-Rückmeldung)
var knockback: float = 3.0
var poise_damage: float = 10.0
var hitstop: float = 0.05
var heavy := false
var shake := 0.2


func duplicate_info() -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount
	d.source = source
	d.knockback = knockback
	d.poise_damage = poise_damage
	d.hitstop = hitstop
	d.heavy = heavy
	d.shake = shake
	return d
