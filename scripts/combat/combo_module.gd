class_name ComboModule
extends RefCounted
## Ein Baustein der Kombo-Kette (Linksklick spielt die Kette der Reihe nach ab).
##
## Prinzip: Es gibt keine richtige oder falsche Reihenfolge. Bausteine ERZEUGEN Zustände am Gegner
## (taumelnd, gebunden, Lichtmal) oder verändern den Abstand (heranziehen, wegstoßen), und jeder Baustein
## REAGIERT auf das, was gerade da ist. Ohne passenden Zustand macht er einfach seinen normalen Schlag.
## Zustände bleiben einige Sekunden am Gegner, auch wenn dazwischen andere Bausteine kommen.

var id := &""
var display_name := ""
var short_name := ""
var desc := ""  ## was der Baustein immer tut
var creates := ""  ## erzeugt (Text fürs Menü)
var reacts := ""  ## reagiert auf (Text fürs Menü)
var weapon := &""  ## leer = jede Waffe; sonst nur mit dieser Waffe
var finisher := false  ## nur Kennzeichnung (schwer, langer Nachlauf); darf überall in der Kette stehen

var clip := "swing_0"  ## Animation aus AnimLibrary
var body_action := &"swing"
var cost := 14.0
var damage := 9.0
var reach := 0.3  ## zusätzlich zur Nahkampfreichweite (bei fixed_reach: absolut)
var fixed_reach := false  ## true = Reichweite unabhängig von der Waffe (z. B. Schattenranke)
var arc := 80.0
var knockback := 1.5
var poise := 8.0
var hitstop := 0.06
var shake := 0.12
var lunge := 1.6  ## Vorwärtsschub kurz vor dem Treffer (m/s)
var single := false  ## trifft nur das nächste Ziel
var hits: Array[float] = []  ## Trefferzeitpunkte (normiert); leer = aus dem Clip

# Laufzeit
var duration := 0.95
var window := 0.68  ## ab hier (normiert) darf der nächste Baustein anschließen
var _target: Enemy


static var _gold := Color(1.0, 0.82, 0.42)


## Vor dem Start: Dauer/Trefferzeit aus dem Clip, skaliert mit dem Tempo der Waffe.
func setup(p: Player) -> void:
	var c: Dictionary = AnimLibrary.clip(clip) if clip != "" else {"duration": 0.8, "hit": 0.3}
	duration = c.duration * p.weapon.eff_speed(p.body.off_item)
	if hits.is_empty():
		hits = [c.hit]
	window = clampf(hits[hits.size() - 1] + 0.24, 0.55, 0.8)


## Beim Start (nach setup): Ziele wählen, Bewegung planen.
func begin(_p: Player) -> void:
	pass


## Vorwärtsgeschwindigkeit (m/s) zur normierten Zeit t.
func move_speed(_p: Player, t: float) -> float:
	var h: float = hits[0]
	var a := h - 0.16
	if t < a or t > h + 0.04:
		return 0.0
	return lunge * sin(clampf((t - a) / 0.2, 0.0, 1.0) * PI)


## Zusätzliche Bewegung in Weltkoordinaten (z. B. seitlich um den Gegner), m/s.
func extra_velocity(_p: Player, _t: float) -> Vector3:
	return Vector3.ZERO


## Treffer Nummer `i` auslösen.
func strike(p: Player, _i: int) -> void:
	var targets: Array[Enemy] = p.targets_in_cone(eff_reach(p), arc * p.weapon.arc, single)
	_strike_targets(p, targets)


func _strike_targets(p: Player, targets: Array[Enemy]) -> void:
	for e in targets:
		var info := p.module_info(self)
		react(p, e, info)
		if p._deal_damage(e, info) == DamageInfo.Result.HIT:
			after(p, e, info)
	finish_strike(p, targets)


## Reichweite des Treffers (m): Nahkampfreichweite + Baustein + Waffe; fixed_reach = absolut.
func eff_reach(p: Player) -> float:
	return reach if fixed_reach else p.melee_range + reach + p.weapon.eff_reach(p.body.off_item)


## Vor dem Schaden: auf Zustände reagieren (info anpassen, Reaktion anzeigen).
func react(_p: Player, _e: Enemy, _info: DamageInfo) -> void:
	pass


## Nach einem Treffer: Zustände setzen, Gegner bewegen.
func after(_p: Player, _e: Enemy, _info: DamageInfo) -> void:
	pass


## Nach allen Treffern eines Schlags.
func finish_strike(_p: Player, _targets: Array[Enemy]) -> void:
	pass


static func reaction(e: Enemy, text: String) -> void:
	FX.number(e, e.target_point() + Vector3.UP * 0.55, text, _gold, true)


## Gegner auf Abstand `dist` vor den Spieler ziehen bzw. wegstoßen (entlang der Linie Spieler -> Gegner).
static func set_distance(p: Player, e: Enemy, dist: float, time: float) -> void:
	var to := e.global_position - p.global_position
	to.y = 0.0
	var d := to.length()
	var dir := to / d if d > 0.01 else p.forward()
	e.force_move(dir * (dist - d), time)


static func push(p: Player, e: Enemy, extra: float, time: float) -> void:
	var to := e.global_position - p.global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.05 else p.forward()
	e.force_move(dir * extra, time)


static func flat_dist(p: Player, e: Enemy) -> float:
	var to := e.global_position - p.global_position
	to.y = 0.0
	return to.length()
