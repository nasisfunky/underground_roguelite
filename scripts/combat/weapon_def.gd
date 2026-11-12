class_name WeaponDef
extends RefCounted
## Waffenarten des Spielers. Jede Waffe verändert, wie die Kombo-Bausteine ausgeführt werden
## (Reichweite, Bogen, Tempo, Wucht) und bringt eigene Bausteine mit.
##
## Griff am Ursprung, Waffe entlang -Z (wie LowPoly.blade). Breite Seite in der Y-Ebene.

var id := &"sword"
var display_name := "Sword"
var grip := &"1h"  ## &"1h", &"versatile" (einhändig mit Zweithand-Teil, sonst beidhändig), &"2h"
var length := 0.78  ## Griff bis Spitze (m)
var two_hand_offset := 0.0  ## wo die linke Hand beidhändig greift (m hinter der rechten, Richtung Knauf)
var stow := &"belt"  ## &"belt" (linke Hüfte) oder &"back"
var damage := 1.0
var speed := 1.0  ## >1 = langsamer (Dauer der Animationen)
var reach := 0.0  ## zusätzliche Reichweite (m)
var arc := 1.0  ## Faktor auf den Trefferbogen
var poise := 1.0
var cost := 1.0
var stagger := 1.0  ## wie lange Treffer unterbrechen (Dolch kurz, Zweihandaxt lang)
var two_hand_stagger := 1.3
var own_modules: Array[StringName] = []  ## Bausteine, die nur mit dieser Waffe gehen
var culture := false  ## true = Modell der Kultur (Säbel/Axt/Stab aus dem Outfit)

## Werte, wenn eine Vielseitig-Waffe beidhändig geführt wird
var two_hand_damage := 1.0
var two_hand_reach := 0.0
var two_hand_speed := 1.0

const IDS: Array[StringName] = [&"sword", &"spear", &"greataxe", &"dagger"]


static func make(weapon_id: StringName) -> WeaponDef:
	var w := WeaponDef.new()
	w.id = weapon_id
	match weapon_id:
		&"spear":
			w.display_name = "Spear"
			w.grip = &"versatile"
			w.length = 1.42  # Griff sitzt im hinteren Drittel des 2-m-Schafts
			w.two_hand_offset = 0.42
			w.stow = &"back"
			w.damage = 1.0
			w.speed = 1.0
			w.reach = 0.9
			w.arc = 0.55
			w.poise = 0.9
			w.stagger = 1.0
			w.two_hand_damage = 1.25
			w.two_hand_reach = 1.15
			w.two_hand_speed = 0.95
			w.own_modules = [&"impale", &"haft_sweep"]
		&"greataxe":
			w.display_name = "Greataxe"
			w.grip = &"2h"
			w.length = 1.12
			w.two_hand_offset = 0.3
			w.stow = &"back"
			w.damage = 1.75
			w.speed = 1.28
			w.reach = 0.35
			w.arc = 1.1
			w.poise = 2.0
			w.stagger = 1.9
			w.cost = 1.35
			w.own_modules = [&"cleave", &"beard_hook"]
		&"dagger":
			w.display_name = "Dagger"
			w.length = 0.4
			w.damage = 0.62
			w.speed = 0.72
			w.reach = -0.35
			w.arc = 0.85
			w.poise = 0.6
			w.stagger = 0.45
			w.cost = 0.7
			w.own_modules = [&"flurry", &"slip"]
		_:
			w.id = &"sword"
			w.display_name = "Culture blade"
			w.culture = true
			w.own_modules = [&"riposte"]
	return w


## Beidhändig geführt? (Zweihänder immer; Vielseitig nur mit freier linker Hand)
## Mit Licht in der linken Hand wird auch der Zweihänder einhändig (und schwerfällig) geführt.
func two_handed(off_item: StringName) -> bool:
	return grip != &"1h" and off_item == &""


func eff_damage(off_item: StringName) -> float:
	return damage * (two_hand_damage if grip == &"versatile" and two_handed(off_item) else 1.0)


func eff_reach(off_item: StringName) -> float:
	return reach * (two_hand_reach if grip == &"versatile" and two_handed(off_item) else 1.0)


func eff_stagger(off_item: StringName) -> float:
	return stagger * (two_hand_stagger if grip == &"versatile" and two_handed(off_item) else 1.0)


## Wuchtige Waffe: einmal ausgeholt, lässt sich der Schlag nicht mehr abbrechen.
func is_heavy() -> bool:
	return grip == &"2h"


func eff_speed(off_item: StringName) -> float:
	return speed * (two_hand_speed if grip == &"versatile" and two_handed(off_item) else 1.0)


## Darf die linke Hand ein Teil (Schild/Dolch) führen? Licht geht immer (die Waffe wird dann einhändig geführt).
func allows_offhand() -> bool:
	return grip != &"2h"


# ------------------------------------------------------------------
# Modelle (Low-Poly, Griff am Ursprung, entlang -Z)
# ------------------------------------------------------------------

static func build_mesh(weapon_id: StringName, parent: Node3D) -> void:
	var wood := LowPoly.mat(Color(0.2, 0.13, 0.08))
	var wrap := LowPoly.mat(Color(0.1, 0.07, 0.05))
	var metal := LowPoly.mat(Color(0.42, 0.46, 0.47), 0.0, 0.55)
	var dark_metal := LowPoly.mat(Color(0.2, 0.22, 0.23), 0.0, 0.6)
	var glow := LowPoly.mat(LowPoly.CYAN, 1.6)
	match weapon_id:
		&"spear":
			# Schaft 2 m: 0.58 m hinter dem Griff bis 1.42 m davor, Blattspitze vorn, Kristallring
			var shaft := LowPoly.prism(0.018, 0.016, 1.92, 5)
			var s := LowPoly.mesh_instance(shaft, wood, parent, Vector3(0, 0, -0.38))
			s.rotation.x = -PI * 0.5
			var grip_w := LowPoly.mesh_instance(LowPoly.prism(0.024, 0.024, 0.22, 5), wrap, parent, Vector3(0, 0, 0.0))
			grip_w.rotation.x = -PI * 0.5
			var grip2 := LowPoly.mesh_instance(LowPoly.prism(0.023, 0.023, 0.16, 5), wrap, parent, Vector3(0, 0, 0.42))
			grip2.rotation.x = -PI * 0.5
			var socket := LowPoly.mesh_instance(LowPoly.prism(0.03, 0.02, 0.1, 5), dark_metal, parent, Vector3(0, 0, -1.08))
			socket.rotation.x = -PI * 0.5
			var head := LowPoly.mesh_instance(LowPoly.blade(0.34, 0.085, 0.025), metal, parent, Vector3(0, 0, -1.08))
			head.name = "Head"
			LowPoly.mesh_instance(LowPoly.crystal(0.05, 0.016), glow, parent, Vector3(0, 0.0, -1.06)).rotation.x = -PI * 0.5
			var butt := LowPoly.mesh_instance(LowPoly.prism(0.026, 0.012, 0.08, 5), dark_metal, parent, Vector3(0, 0, 0.6))
			butt.rotation.x = PI * 0.5
		&"greataxe":
			# langer Stiel, großer Bartkopf vorn, Knauf hinten
			var haft := LowPoly.mesh_instance(LowPoly.prism(0.024, 0.02, 1.32, 5), wood, parent, Vector3(0, 0, -0.42))
			haft.rotation.x = -PI * 0.5
			for z in [0.0, 0.3]:
				var w := LowPoly.mesh_instance(LowPoly.prism(0.03, 0.03, 0.14, 5), wrap, parent, Vector3(0, 0, z))
				w.rotation.x = -PI * 0.5
			var pommel := LowPoly.mesh_instance(LowPoly.prism(0.035, 0.02, 0.07, 5), dark_metal, parent, Vector3(0, 0, 0.27))
			pommel.rotation.x = PI * 0.5
			# Kopf: Bart nach unten-vorn (in +Y liegt die Schneide), Rückenzapfen hinten
			var head := Node3D.new()
			head.name = "Head"
			head.position = Vector3(0, 0, -0.98)
			parent.add_child(head)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var t := 0.022
			var pts: Array[Vector3] = [Vector3(0, 0.05, 0.07), Vector3(0, 0.3, 0.14), Vector3(0, 0.36, -0.02), Vector3(0, 0.28, -0.2), Vector3(0, 0.05, -0.09)]
			var c := Vector3(0, 0.18, -0.02)
			for i in pts.size():
				var a: Vector3 = pts[i]
				var b: Vector3 = pts[(i + 1) % pts.size()]
				LowPoly.tri_out(st, c + Vector3(t, 0, 0), a + Vector3(t * 0.4, 0, 0), b + Vector3(t * 0.4, 0, 0), c)
				LowPoly.tri_out(st, c - Vector3(t, 0, 0), b - Vector3(t * 0.4, 0, 0), a - Vector3(t * 0.4, 0, 0), c)
				LowPoly.tri_out(st, a + Vector3(t * 0.4, 0, 0), a - Vector3(t * 0.4, 0, 0), b - Vector3(t * 0.4, 0, 0), c)
				LowPoly.tri_out(st, a + Vector3(t * 0.4, 0, 0), b - Vector3(t * 0.4, 0, 0), b + Vector3(t * 0.4, 0, 0), c)
			LowPoly.mesh_instance(st.commit(), metal, head)
			LowPoly.mesh_instance(LowPoly.box(Vector3(0.06, 0.12, 0.1)), dark_metal, head, Vector3(0, 0.0, -0.01))
			LowPoly.mesh_instance(LowPoly.box(Vector3(0.04, 0.1, 0.06)), dark_metal, head, Vector3(0, -0.1, -0.01))
			LowPoly.mesh_instance(LowPoly.crystal(0.06, 0.018), glow, head, Vector3(0.03, 0.12, -0.02)).rotation.z = -PI * 0.5
		&"dagger", &"off_dagger":
			LowPoly.mesh_instance(LowPoly.blade(0.4, 0.05, 0.014), metal, parent)
			var g := LowPoly.mesh_instance(LowPoly.prism(0.017, 0.017, 0.1, 5), wrap, parent, Vector3(0, 0, 0.04))
			g.rotation.x = -PI * 0.5
			LowPoly.mesh_instance(LowPoly.box(Vector3(0.022, 0.1, 0.02)), dark_metal, parent, Vector3(0, 0, -0.03))
			LowPoly.mesh_instance(LowPoly.crystal(0.03, 0.012), glow, parent, Vector3(0, 0, 0.1)).rotation.x = PI * 0.5
