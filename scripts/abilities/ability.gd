class_name Ability
extends RefCounted
## Basis für Fähigkeiten auf der Aktionsleiste (Tasten 1-9).
## Eine Fähigkeit übernimmt für ihre Dauer den Charakter und ersetzt den Auto-Angriff.

var display_name := "Ability"
var short_name := "?"  ## Kürzel für die Aktionsleiste
var cooldown := 5.0
var cooldown_left := 0.0
var stamina_cost := 0.0
var needs_target := false
var snap_to_target := true  ## dreht sich beim Auslösen zum Ziel (außer bei Mouselook)
var cancel_at := 0.5  ## ab hier darf eine Rolle abbrechen
var duration := 0.6


func start(_p: Player) -> void:
	pass


## Pro Physik-Tick. true = fertig.
func update(_p: Player, t: float, _delta: float) -> bool:
	return t >= duration


func animate(_p: Player, body: ShadowBody, _t: float) -> void:
	body.action = &""
