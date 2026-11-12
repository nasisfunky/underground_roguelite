class_name ComboModules
extends RefCounted
## Alle Kombo-Bausteine. Allgemeine gehen mit jeder Waffe, waffeneigene nur mit ihrer Waffe.
## Zustände: reeling (taumelt), bound (Klinge gebunden), marked (Lichtmal, bis 3 Stapel).

const GENERAL: Array[StringName] = [&"cut", &"backcut", &"sweep", &"shove", &"hook", &"bind", &"lunge", &"kindle", &"sever"]
const WEAPON_OWN: Array[StringName] = [&"riposte", &"impale", &"haft_sweep", &"cleave", &"beard_hook", &"flurry", &"slip"]
const DEFAULT_CHAIN: Array[StringName] = [&"bind", &"shove", &"lunge", &"hook", &"kindle"]


static func all_ids() -> Array[StringName]:
	var a: Array[StringName] = []
	a.append_array(GENERAL)
	a.append_array(WEAPON_OWN)
	return a


static func make(id: StringName) -> ComboModule:
	match id:
		&"cut": return Cut.new()
		&"backcut": return Backcut.new()
		&"sweep": return Sweep.new()
		&"shove": return Shove.new()
		&"hook": return Hook.new()
		&"bind": return Bind.new()
		&"lunge": return Lunge.new()
		&"kindle": return Kindle.new()
		&"sever": return Sever.new()
		&"riposte": return Riposte.new()
		&"impale": return Impale.new()
		&"haft_sweep": return HaftSweep.new()
		&"cleave": return Cleave.new()
		&"beard_hook": return BeardHook.new()
		&"flurry": return Flurry.new()
		&"slip": return Slip.new()
	return null


## Letzter Trefferzeitpunkt eines Clips: Bausteine mit mehreren Treffern (z. B. Flurry) legen sie selbst fest.
static func last_hit_for_clip(clip_name: String, fallback: float) -> float:
	var best := -1.0
	for id in all_ids():
		var m := make(id)
		if m.clip == clip_name and not m.hits.is_empty():
			best = maxf(best, m.hits[m.hits.size() - 1])
	return best if best >= 0.0 else fallback


## Darf der Baustein mit dieser Waffe benutzt werden?
static func usable(id: StringName, weapon: WeaponDef) -> bool:
	var m := make(id)
	return m != null and (m.weapon == &"" or m.weapon == weapon.id)


# ------------------------------------------------------------------
# Allgemeine Bausteine
# ------------------------------------------------------------------

class Cut extends ComboModule:
	func _init() -> void:
		id = &"cut"
		display_name = "Cut"
		short_name = "Cut"
		desc = "A clean forehand cut."
		reacts = "Reeling: Opening, x1.6 damage"
		clip = "swing_0"

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"reeling"):
			info.amount *= 1.6
			reaction(e, "Opening")


class Backcut extends ComboModule:
	func _init() -> void:
		id = &"backcut"
		display_name = "Backcut"
		short_name = "Back"
		desc = "A wide backhand cut."
		reacts = "Bound: Wrench, tears the bind open (Reeling)"
		clip = "swing_1"
		damage = 8.0
		arc = 110.0

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"bound"):
			info.amount += 6.0
			info.poise_damage += 20.0
			info.set_meta("wrench", true)
			reaction(e, "Wrench")

	func after(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if info.has_meta("wrench"):
			e.clear_status(&"bound")
			e.add_status(&"reeling", 1.6)


class Sweep extends ComboModule:
	func _init() -> void:
		id = &"sweep"
		display_name = "Low Sweep"
		short_name = "Sweep"
		desc = "A low, wide sweep that catches everyone around you."
		creates = "Reeling (short) on all hit"
		reacts = "Marked: the light jumps over, every other target hit gains a mark"
		clip = "sweep"
		damage = 5.0
		arc = 160.0
		reach = 0.6
		cost = 16.0
		lunge = 0.8
		poise = 12.0

	func finish_strike(_p: Player, targets: Array[Enemy]) -> void:
		var marked := false
		for e in targets:
			if e.status_stacks(&"marked") > 0:
				marked = true
		for e in targets:
			if e.is_dead():
				continue
			if marked and e.status_stacks(&"marked") == 0:
				e.add_status(&"marked", 6.0)
				reaction(e, "Spread")
			if not e.has_status(&"bound"):
				e.add_status(&"reeling", 1.3)


class Shove extends ComboModule:
	func _init() -> void:
		id = &"shove"
		display_name = "Shove"
		short_name = "Shove"
		desc = "Shoulder or shield into them: pushes the target 3 m away."
		creates = "Distance, Reeling (short)"
		reacts = "Bound: Throw, hurled 5.5 m and Reeling long"
		clip = "shove"
		damage = 4.0
		arc = 60.0
		reach = 2.5
		fixed_reach = true
		cost = 15.0
		knockback = 0.0
		poise = 25.0
		lunge = 4.0
		hitstop = 0.08
		shake = 0.25

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"bound"):
			info.set_meta("throw", true)
			reaction(e, "Throw")

	func after(p: Player, e: Enemy, info: DamageInfo) -> void:
		if info.has_meta("throw"):
			e.clear_status(&"bound")
			push(p, e, 5.5, 0.45)
			e.add_status(&"reeling", 2.0)
		else:
			push(p, e, 3.0, 0.32)
			e.add_status(&"reeling", 0.8)


class Hook extends ComboModule:
	var _range := 7.0

	func _init() -> void:
		id = &"hook"
		display_name = "Shadow Hook"
		short_name = "Hook"
		desc = "Your flame lashes out up to 7 m and drags the first enemy in front of you."
		creates = "Pulls close"
		reacts = "Far away (over 3.5 m): Snap, arrives Reeling"
		clip = "hook"
		damage = 3.0
		arc = 22.0
		reach = 7.0
		fixed_reach = true
		single = true
		cost = 14.0
		lunge = 0.0
		knockback = 0.0
		poise = 4.0

	func strike(p: Player, _i: int) -> void:
		var targets: Array[Enemy] = p.targets_in_cone(_range, arc, true)
		var to := p.global_position + p.forward() * _range + Vector3.UP * 1.2
		if not targets.is_empty():
			to = targets[0].target_point() - Vector3.UP * 0.8
		p.spawn_tendril(to, not targets.is_empty())
		_strike_targets(p, targets)

	func react(p: Player, e: Enemy, info: DamageInfo) -> void:
		if flat_dist(p, e) > 3.5:
			info.set_meta("snap", true)
			reaction(e, "Snap")

	func after(p: Player, e: Enemy, info: DamageInfo) -> void:
		set_distance(p, e, 1.35 + e.radius, 0.3)
		if info.has_meta("snap"):
			e.add_status(&"reeling", 1.5)


class Bind extends ComboModule:
	func _init() -> void:
		id = &"bind"
		display_name = "Bind"
		short_name = "Bind"
		desc = "Press your weapon against theirs and hold it there."
		creates = "Bound (2.5 s): cannot attack"
		reacts = "Reeling: Pinned, bound for 4 s"
		clip = "bind"
		damage = 2.0
		arc = 55.0
		reach = 0.25
		single = true
		cost = 12.0
		knockback = 0.0
		poise = 0.0
		lunge = 2.0

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"reeling"):
			info.set_meta("pin", true)
			reaction(e, "Pinned")

	func after(_p: Player, e: Enemy, info: DamageInfo) -> void:
		e.add_status(&"bound", 4.0 if info.has_meta("pin") else 2.5)


class Lunge extends ComboModule:
	var _pursue := 0.0

	func _init() -> void:
		id = &"lunge"
		display_name = "Brand Lunge"
		short_name = "Lunge"
		desc = "A long thrust that burns a mark of the Bright into the target."
		creates = "Mark of light (+1)"
		reacts = "Target 2.6 to 7 m away: Pursuit, you dash after it, +2 marks"
		clip = "thrust"
		damage = 12.0
		arc = 25.0
		reach = 1.3
		cost = 20.0
		lunge = 3.2
		knockback = 2.2
		poise = 14.0
		hitstop = 0.08
		shake = 0.16

	func begin(p: Player) -> void:
		_pursue = 0.0
		var far: Array[Enemy] = p.targets_in_cone(7.0, 28.0, true, p.camera_forward())
		if not far.is_empty():
			var d := flat_dist(p, far[0]) - far[0].radius
			var r := eff_reach(p) - 0.4
			if d > 2.6 and d > r:
				_target = far[0]
				_pursue = d - r + 0.3

	## Verfolgung: kräftiger Satz nach vorn vom Ausholen bis zum Treffer.
	func move_speed(p: Player, t: float) -> float:
		if _pursue <= 0.0:
			return super.move_speed(p, t)
		var h: float = hits[0]
		var a := 0.12
		if t < a or t > h + 0.02:
			return 0.0
		var span := (h + 0.02 - a) * duration
		return _pursue / (span * 0.637) * sin((t - a) / (h + 0.02 - a) * PI)

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if _pursue > 0.0 and e == _target:
			info.set_meta("pursuit", true)
			reaction(e, "Pursuit")

	func after(_p: Player, e: Enemy, info: DamageInfo) -> void:
		e.add_status(&"marked", 6.0, 2 if info.has_meta("pursuit") else 1)


class Kindle extends ComboModule:
	func _init() -> void:
		id = &"kindle"
		display_name = "Kindle"
		short_name = "Kindle"
		finisher = true
		desc = "A heavy overhead blow."
		reacts = "Marked: ignites all marks, +10 damage each, the flare burns everyone near the target"
		clip = "heavy"
		damage = 14.0
		arc = 70.0
		cost = 24.0
		knockback = 3.0
		poise = 30.0
		hitstop = 0.1
		shake = 0.35
		lunge = 3.0

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		var n := e.status_stacks(&"marked")
		if n > 0:
			info.amount += 10.0 * n
			info.heavy = true
			info.set_meta("marks", n)
			reaction(e, "Kindle x%d" % n)

	func after(p: Player, e: Enemy, info: DamageInfo) -> void:
		if not info.has_meta("marks"):
			return
		var n: int = info.get_meta("marks")
		e.clear_status(&"marked")
		e.add_status(&"reeling", 1.2)
		var at := e.global_position + Vector3.UP * 1.0
		FX.ring(p, e.global_position + Vector3.UP * 0.1, Color(1.0, 0.85, 0.45), 2.6, 0.35)
		FX.sparks(p, at, Color(1.0, 0.85, 0.4), 10 + 4 * n, 1.6)
		p.flash_light(at, Color(1.0, 0.8, 0.45), 2.0 + n)
		for o in p.get_tree().get_nodes_in_group("enemies"):
			var other := o as Enemy
			if other == null or other == e or other.is_dead():
				continue
			if other.global_position.distance_to(e.global_position) < 2.6:
				var burn := DamageInfo.new()
				burn.source = p
				burn.amount = 5.0 * n
				burn.knockback = 2.5
				burn.poise_damage = 10.0 * n
				burn.hitstop = 0.0
				other.receive_hit(burn)


class Sever extends ComboModule:
	func _init() -> void:
		id = &"sever"
		display_name = "Sever"
		short_name = "Sever"
		finisher = true
		desc = "A heavy diagonal cut from high to low."
		reacts = "Bound: Disarm, +25 damage, Reeling 3 s.  Reeling: Topple, x2 damage"
		clip = "sever"
		damage = 15.0
		arc = 90.0
		cost = 24.0
		knockback = 2.5
		poise = 25.0
		hitstop = 0.1
		shake = 0.3
		lunge = 2.4

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"bound"):
			info.amount += 25.0
			info.heavy = true
			info.set_meta("disarm", true)
			reaction(e, "Disarm")
		elif e.has_status(&"reeling"):
			info.amount *= 2.0
			info.heavy = true
			info.set_meta("topple", true)
			reaction(e, "Topple")

	func after(p: Player, e: Enemy, info: DamageInfo) -> void:
		if info.has_meta("disarm"):
			e.clear_status(&"bound")
			e.add_status(&"reeling", 3.0)
		elif info.has_meta("topple"):
			e.clear_status(&"reeling")
			push(p, e, 1.2, 0.25)
			e.add_status(&"reeling", 2.2)


# ------------------------------------------------------------------
# Waffeneigene Bausteine
# ------------------------------------------------------------------

class Riposte extends ComboModule:
	func _init() -> void:
		id = &"riposte"
		weapon = &"sword"
		display_name = "Riposte"
		short_name = "Ripo"
		desc = "Sword only. A fast answer cut."
		reacts = "Right after you blocked (1 s) or target Reeling: x2.2 damage"
		clip = "swing_1"
		damage = 9.0
		arc = 70.0
		cost = 12.0
		lunge = 2.6

	func setup(p: Player) -> void:
		super.setup(p)
		duration *= 0.85

	func react(p: Player, e: Enemy, info: DamageInfo) -> void:
		if p.time_since_block() < 1.0 or e.has_status(&"reeling"):
			info.amount *= 2.2
			info.heavy = true
			reaction(e, "Riposte")


class Impale extends ComboModule:
	func _init() -> void:
		id = &"impale"
		weapon = &"spear"
		display_name = "Impale"
		short_name = "Impale"
		desc = "Spear only. A very long thrust that pins the target where it stands."
		creates = "Bound at range (2 s)"
		reacts = "Marked: Skewer, +6 damage per mark (marks stay)"
		clip = "thrust"
		damage = 13.0
		arc = 14.0
		reach = 0.9
		single = true
		cost = 18.0
		lunge = 2.4
		poise = 10.0
		knockback = 0.0

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		var n := e.status_stacks(&"marked")
		if n > 0:
			info.amount += 6.0 * n
			reaction(e, "Skewer")

	func after(_p: Player, e: Enemy, _info: DamageInfo) -> void:
		e.add_status(&"bound", 2.0)


class HaftSweep extends ComboModule:
	func _init() -> void:
		id = &"haft_sweep"
		weapon = &"spear"
		display_name = "Haft Sweep"
		short_name = "Haft"
		desc = "Spear only. The shaft whirls around you and clears space."
		creates = "Distance (2 m out), Reeling (short) on all hit"
		reacts = "Bound: the bind holds, the target is not pushed"
		clip = "sweep"
		damage = 6.0
		arc = 200.0
		reach = 0.2
		cost = 16.0
		lunge = 0.6
		knockback = 0.0
		poise = 14.0

	func after(p: Player, e: Enemy, _info: DamageInfo) -> void:
		if e.has_status(&"bound"):
			return
		push(p, e, 2.0, 0.3)
		e.add_status(&"reeling", 0.8)


class Cleave extends ComboModule:
	func _init() -> void:
		id = &"cleave"
		weapon = &"greataxe"
		display_name = "Cleave"
		short_name = "Cleave"
		finisher = true
		desc = "Greataxe only. A crushing overhead blow, the ground cracks around the impact."
		creates = "Reeling on everyone within 2 m of the impact"
		reacts = "Reeling: Split, x1.8 damage"
		clip = "heavy"
		damage = 14.0
		arc = 60.0
		cost = 22.0
		knockback = 2.0
		poise = 30.0
		hitstop = 0.12
		shake = 0.45
		lunge = 2.0

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"reeling"):
			info.amount *= 1.8
			info.heavy = true
			reaction(e, "Split")

	func finish_strike(p: Player, _targets: Array[Enemy]) -> void:
		var at := p.global_position + p.forward() * (p.melee_range + 0.4)
		FX.ring(p, at + Vector3.UP * 0.05, Color(1.0, 0.7, 0.35), 2.2, 0.3)
		FX.dust(p, at, 10, 1.4)
		for o in p.get_tree().get_nodes_in_group("enemies"):
			var e := o as Enemy
			if e and not e.is_dead() and e.global_position.distance_to(at) < 2.0 and not e.has_status(&"bound"):
				e.add_status(&"reeling", 1.2)


class BeardHook extends ComboModule:
	func _init() -> void:
		id = &"beard_hook"
		weapon = &"greataxe"
		display_name = "Beard Hook"
		short_name = "Beard"
		desc = "Greataxe only. Hook the axe beard behind them and rip them towards you."
		creates = "Pulls close, Reeling (short)"
		reacts = "Bound: Haul, you swing them past you, 2.5 m behind"
		clip = "rake"
		damage = 6.0
		arc = 60.0
		reach = 0.5
		single = true
		cost = 14.0
		knockback = 0.0
		poise = 12.0
		lunge = 2.6

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"bound"):
			info.set_meta("haul", true)
			reaction(e, "Haul")

	func after(p: Player, e: Enemy, info: DamageInfo) -> void:
		if info.has_meta("haul"):
			e.clear_status(&"bound")
			set_distance(p, e, -2.5, 0.42)
			e.add_status(&"reeling", 1.6)
		else:
			set_distance(p, e, 1.1 + e.radius, 0.25)
			e.add_status(&"reeling", 0.9)


class Flurry extends ComboModule:
	var _shown := false

	func _init() -> void:
		id = &"flurry"
		weapon = &"dagger"
		display_name = "Flurry"
		short_name = "Flurry"
		desc = "Dagger only. Three quick stabs."
		reacts = "Bound or Reeling: Riddle, every stab +4 damage"
		clip = "flurry"
		damage = 5.0
		arc = 50.0
		cost = 16.0
		lunge = 1.2
		knockback = 0.5
		poise = 5.0
		hitstop = 0.04
		hits = [0.3, 0.46, 0.62]

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"bound") or e.has_status(&"reeling"):
			info.amount += 4.0
			if not _shown:
				_shown = true
				reaction(e, "Riddle")


class Slip extends ComboModule:
	var _side := 1.0

	func _init() -> void:
		id = &"slip"
		weapon = &"dagger"
		display_name = "Slip"
		short_name = "Slip"
		desc = "Dagger only. Slip around the target and stab it from behind."
		reacts = "Bound or Reeling: Backstab, x2.5 damage"
		clip = "thrust"
		damage = 9.0
		arc = 70.0
		reach = 0.4
		single = true
		cost = 15.0
		lunge = 0.0
		knockback = 1.0

	func begin(p: Player) -> void:
		var t: Array[Enemy] = p.targets_in_cone(3.2, 60.0, true, p.camera_forward())
		_target = t[0] if not t.is_empty() else null
		_side = 1.0 if randf() < 0.5 else -1.0

	## Halbkreis um das Ziel bis hinter seine Schulter, dann der Stich.
	func extra_velocity(p: Player, t: float) -> Vector3:
		if _target == null or not is_instance_valid(_target) or t > hits[0]:
			return Vector3.ZERO
		var to := _target.global_position - p.global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.05:
			return Vector3.ZERO
		var side := to.normalized().cross(Vector3.UP) * _side
		var radial := to.normalized() * (d - 1.0) * 4.0
		var w := sin(clampf(t / hits[0], 0.0, 1.0) * PI)
		p.face_toward(_target.global_position)
		return side * 6.5 * w + radial

	func react(_p: Player, e: Enemy, info: DamageInfo) -> void:
		if e.has_status(&"bound") or e.has_status(&"reeling"):
			info.amount *= 2.5
			info.heavy = true
			reaction(e, "Backstab")
