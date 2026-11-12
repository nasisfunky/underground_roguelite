extends Node3D
## Testlevel: die ersten drei Hallen des Grimvault, direkt unter der Siedlung Vigil.
## Komplett per Code aus Low-Poly-Formen gebaut. Alles liegt im Untergrund und ist dunkel;
## die Laterne des Spielers reicht für die nähere Umgebung, nicht für den ganzen Raum.
##
##  Raum 1 "The Threshold"    – Tor nach Vigil, letztes Feuer, Parcours auf Trümmern, Rampe
##  Raum 2 "Wardens' Ring"    – Übungsring mit Puppen aus Wurzelholz
##  Raum 3 "The Sunken Gate"  – versiegeltes Tor nach unten, Willfaults (Hollowed, Splinterkin-Rudel) greifen an
##
## Die Räume liegen hintereinander Richtung -Z, Raum 3 liegt tiefer (es geht nach unten).

const WALL_H := 15.0

var _rng := RandomNumberGenerator.new()
var _geo: Node3D
var player: Player


func _ready() -> void:
	_rng.seed = 1337
	_geo = Node3D.new()
	_geo.name = "Geometry"
	add_child(_geo)
	_build_environment()
	_build_room_hall()
	_build_corridor(Vector3(0, 0, -13), Vector3(0, 0, -22), 6.0, 9.0)
	_build_room_training()
	_build_ramp_corridor()
	_build_room_sealed()
	_build_corridor_x(14.0, 21.0, -34.0, 0.0, 6.0, 9.0)
	_build_room_cistern()
	# Flächen, die exakt aufeinanderliegen, ein paar Millimeter auseinanderschieben (Z-Fighting)
	var bumped := ZFight.fix(_geo)
	if bumped > 0:
		print("[level] %d Kisten gegen Z-Fighting vergrößert" % bumped)
	_spawn_player(Vector3(0, 0.1, 9), 0.0)


# ==================================================================
# Umgebung: tief unter der Erde, kein Himmel, keine Sonne.
# Licht kommt nur von der Laterne des Spielers und von wenigen Quellen der Bright:
# Kristalle (kühles Cyan), Pilze (schwaches Glimmen), Feuer (warm, von den Wardens aus Vigil gehütet).
# ==================================================================

const FIRE := Color(1.0, 0.52, 0.2)
const SHROOM := Color(0.45, 1.0, 0.72)
const ROOTWOOD := Color(0.15, 0.10, 0.075)
const CLOTH_OLD := Color(0.13, 0.16, 0.16)
const METAL_OLD := Color(0.2, 0.21, 0.2)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.004, 0.007, 0.009)
	# Grundlicht fast null: Formen bleiben gerade so als Silhouette erahnbar
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.36, 0.38)
	e.ambient_light_energy = 0.075
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.15
	# dunkler Nebel schluckt alles, was die Laterne nicht erreicht
	e.fog_enabled = true
	e.fog_light_color = Color(0.012, 0.022, 0.026)
	e.fog_light_energy = 1.0
	e.fog_density = 0.05
	e.fog_aerial_perspective = 0.0
	e.fog_sky_affect = 1.0
	e.glow_enabled = true
	e.glow_intensity = 1.0
	e.glow_strength = 1.0
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.1
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.0
	# Volumetrischer Nebel nur für sichtbare Lichthöfe um Feuer, Kristalle und Laterne
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.018
	e.volumetric_fog_albedo = Color(0.6, 0.75, 0.75)
	e.volumetric_fog_length = 40.0
	e.volumetric_fog_ambient_inject = 0.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.05
	e.adjustment_contrast = 1.08
	we.environment = e
	add_child(we)


# ==================================================================
# Räume: die ersten Hallen hinter der Öffnung des Grimvault, gleich unter Vigil.
# ==================================================================

## Raum 1: Die Wardens von Vigil schließen das Wurzelholz-Tor hinter jedem, der hinabsteigt.
## Ein letztes Feuer brennt am Tor, danach nur noch Dunkelheit, Pilze und der Kristall auf den Trümmern.
func _build_room_hall() -> void:
	var c := Vector3(0, 0, 0)
	_room_shell(c, Vector2(26, 26), [Vector2(0, 6)], [Vector2(0, 6)], "The Threshold", true)
	_ward_gate(Vector3(0, 0, 14.0), 6.0)
	_fire_bowl(Vector3(3.6, 0, 11.2), 1.0)
	_gear_pile(Vector3(-3.2, 0, 10.6), 0.6, 1)
	# Monumentale Säulen des Grimvault
	for z in [6.0, -1.0, -8.0]:
		for x in [-6.5, 6.5]:
			if x > 0 and z == -1.0:
				continue  # Platz für den Parcours
			_pillar(Vector3(x, 0, z), 1.0, WALL_H + 2.0, 5)
	# eingestürztes Mauerwerk als Sprungparcours (Osten), oben wartet ein Kristall
	_block(Vector3(9.0, 0.3, 4.0), Vector3(2.6, 0.6, 2.6), LowPoly.STONE_LIGHT)
	_block(Vector3(9.5, 0.6, 0.5), Vector3(2.6, 1.2, 2.6), LowPoly.STONE_LIGHT)
	_block(Vector3(9.5, 0.95, -3.2), Vector3(2.6, 1.9, 2.6), LowPoly.STONE_LIGHT)
	_block(Vector3(4.6, 0.95, -6.8), Vector3(3.0, 1.9, 3.0), LowPoly.STONE_LIGHT)  # über eine Lücke
	_crystal_cluster(Vector3(4.6, 1.9, -6.8), 0.8)
	for p in [Vector3(10.8, 0.2, 2.2), Vector3(7.6, 0.2, -5.2), Vector3(8.0, 0.2, 6.0)]:
		_rock(p, _rng.randf_range(0.35, 0.6), true)
	# Rampe hoch zu einem Absatz (Westen): oben ist jemand verblasst
	_ramp(Vector3(-9.5, 0, 6.0), Vector3(-9.5, 2.2, -0.5), 3.4)
	_block(Vector3(-9.5, 1.1, -3.5), Vector3(4.5, 2.2, 6.0), LowPoly.STONE_LIGHT)
	_gear_pile(Vector3(-9.8, 2.2, -5.0), 0.0, 2)
	_mushrooms(Vector3(-11.0, 2.2, -2.2), 5, 0.8)
	# Pilze entlang der Wände: gerade genug, um Ecken zu erahnen
	_mushrooms(Vector3(-11.6, 0, 10.5), 6, 1.0)
	_mushrooms(Vector3(11.4, 0, -10.8), 7, 1.1)
	_mushrooms(Vector3(-4.0, 0, -11.4), 4, 0.7)
	_gear_pile(Vector3(2.0, 0, -9.8), 2.3, 0)
	for i in 7:
		var p := Vector3(_rng.randf_range(-11, 11), 0, _rng.randf_range(-11, 11))
		if absf(p.x) < 3.5 or (p.x > 6.0 and p.z < 6.0) or (p.x < -7.0 and p.z < 7.0):
			continue
		_rock(p + Vector3(0, 0.15, 0), _rng.randf_range(0.3, 0.7), false)
	_hanging_roots(Vector3(0, 0, 12.6), 10.0, 9)  # Wurzeln von Vigil wachsen durch die Decke
	_stalactites(c, 12.0, 12.0, 14)


## Raum 2: Übungsring der Wardens. Puppen aus Wurzelholz, behängt mit Ausrüstung verblasster Shades.
func _build_room_training() -> void:
	var c := Vector3(0, 0, -34)
	_room_shell(c, Vector2(26, 24), [Vector2(0, 6)], [Vector2(0, 6)], "Wardens' Ring", true, [], [Vector2(-34, 6)])
	for x in [-4.5, 0.0, 4.5]:
		var d := TrainingDummy.new()
		d.position = Vector3(x, 0.05, -34.0 - (1.5 if x == 0.0 else 0.0))
		d.rotation.y = PI
		add_child(d)
	# Steinring auf dem Boden
	for i in 22:
		var a := TAU * i / 22.0
		var st := LowPoly.mesh_instance(LowPoly.box(Vector3(0.9, 0.08, 0.45)), LowPoly.mat(_vary(LowPoly.STONE_LIGHT)), _geo, c + Vector3(cos(a) * 7.5, 0.03, sin(a) * 7.5))
		st.rotation.y = -a + _rng.randf_range(-0.1, 0.1)
	_fire_bowl(Vector3(-8.5, 0, -27.5), 0.9)
	_fire_bowl(Vector3(8.5, 0, -40.5), 0.9)
	# Puppengruppe für Bausteine gegen mehrere Ziele (Sweep verteilt Lichtmale, Kindle flammt auf Nachbarn über)
	for pos in [Vector3(-7.4, 0.05, -32.2), Vector3(-8.9, 0.05, -31.5), Vector3(-8.3, 0.05, -33.6)]:
		var gd := TrainingDummy.new()
		gd.position = pos
		gd.rotation.y = PI * 0.5
		add_child(gd)
	_weapon_rack(Vector3(10.6, 0, -27.0), -PI / 2)
	_gear_pile(Vector3(10.2, 0, -39.4), -1.2, 1)
	_gear_pile(Vector3(-10.4, 0, -38.5), 0.8, 0)
	for p in [Vector3(-11, 0, -24), Vector3(11, 0, -24), Vector3(-11, 0, -44), Vector3(11, 0, -44)]:
		_pillar(p, 1.1, WALL_H + 2.0, 6)
	_mushrooms(Vector3(-11.2, 0, -30.5), 5, 0.9)
	_mushrooms(Vector3(4.0, 0, -44.8), 4, 0.7)
	for i in 6:
		_rock(Vector3(_rng.randf_range(-11, 11), 0.15, _rng.randf_range(-44, -24)), _rng.randf_range(0.25, 0.5), false)
	_stalactites(c, 11.0, 12.0, 12)


## Abstieg: enger Schacht, nur Kristalladern in den Wänden glimmen.
func _build_ramp_corridor() -> void:
	# z -46 .. -59, y 0 .. -3
	var w := 6.0
	_ramp(Vector3(0, 0, -46.0), Vector3(0, -3.0, -59.0), w)
	for side in [-1.0, 1.0]:
		_block(Vector3(side * (w * 0.5 + 1.0), -1.5 + 4.0, -52.5), Vector3(2.0, 11.0, 13.0), LowPoly.STONE)
		for z in [-48.5, -52.5, -56.5]:
			_rock(Vector3(side * (w * 0.5 - 0.1), -3.0 + (z + 59.0) * 3.0 / 13.0 + 0.3, z), 0.6, true)
	for p in [Vector3(-2.75, 1.4, -49.5), Vector3(2.75, 0.2, -55.0)]:
		_crystal_vein(p, -signf(p.x))
	_block(Vector3(0, 7.0, -52.5), Vector3(w + 4.0, 1.5, 13.0), LowPoly.STONE_DARK)  # niedrige Decke
	for i in 6:
		var p := Vector3(_rng.randf_range(-2.4, 2.4), 6.25, _rng.randf_range(-58, -47))
		var st := LowPoly.mesh_instance(LowPoly.crystal(_rng.randf_range(0.6, 1.4), 0.18), LowPoly.mat(_vary(LowPoly.STONE_DARK)), _geo, p)
		st.rotation.x = PI


## Raum 3: das versiegelte Tor nach unten. Reines Grimvault-Mauerwerk, monumental und still.
## Der leuchtende Spalt im Tor ist von überall im Raum zu sehen und gibt die Richtung vor.
func _build_room_sealed() -> void:
	var y := -3.0
	var c := Vector3(0, y, -76)
	_room_shell(c, Vector2(34, 34), [Vector2(0, 6)], [], "The Sunken Gate")
	# Versiegeltes Tor in der Nordwand: zwei schräge Strebepfeiler, schwere Torflügel,
	# ein schmaler leuchtender Spalt dazwischen (Platzhalter für den Weg tiefer hinab).
	var gz := -92.2
	for side in [-1.0, 1.0]:
		var but := _block(Vector3(side * 4.2, y + 4.5, gz + 0.6), Vector3(1.8, 9.0, 2.4), LowPoly.STONE_DARK)
		but.rotation.z = side * 0.06
		_block(Vector3(side * 1.55, y + 3.6, gz), Vector3(3.0, 7.2, 0.9), LowPoly.STONE.darkened(0.2))
		for k in 3:
			_block(Vector3(side * 1.55, y + 1.4 + k * 2.2, gz + 0.5), Vector3(2.4, 0.18, 0.15), LowPoly.OCHRE.darkened(0.3))
	_block(Vector3(0, y + 7.8, gz + 0.4), Vector3(10.4, 1.4, 2.6), LowPoly.STONE_DARK)
	_block(Vector3(0, y + 8.9, gz + 0.4), Vector3(7.0, 0.8, 2.2), LowPoly.STONE.darkened(0.1))
	var seam := LowPoly.mesh_instance(LowPoly.box(Vector3(0.08, 7.0, 0.95)), LowPoly.mat(LowPoly.CYAN, 7.0), _geo, Vector3(0, y + 3.5, gz))
	seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light(Vector3(0, y + 3.0, gz + 2.0), LowPoly.CYAN, 3.0, 12.0)
	_block(Vector3(0, y + 0.2, gz + 2.0), Vector3(7.0, 0.4, 2.0), LowPoly.STONE_LIGHT)
	_block(Vector3(0, y + 0.1, gz + 3.4), Vector3(8.5, 0.2, 1.2), LowPoly.STONE_LIGHT.darkened(0.1))
	_floating_shards(Vector3(0, y + 6.0, gz + 4.0), 9, 4.5)
	# Säulen; die Feuerschalen sind längst erloschen (später: mit einer Fackel entzünden)
	for z in [-66.0, -76.0]:
		for x in [-11.0, 11.0]:
			_pillar(Vector3(x, y, z), 1.1, WALL_H + 2.0, 5)
	for x in [-6.0, 6.0]:
		_cold_brazier(Vector3(x, y, -82.0))
	_crystal_cluster(Vector3(-14.5, y, -63.0), 1.1)
	_mushrooms(Vector3(14.6, y, -71.0), 6, 1.0)
	_mushrooms(Vector3(-15.0, y, -86.0), 5, 0.9)
	_gear_pile(Vector3(-4.2, y, -70.5), 0.4, 2)
	_gear_pile(Vector3(7.5, y, -86.0), 2.0, 1)
	_gear_pile(Vector3(1.4, y, -88.6), -0.6, 0)
	for i in 8:
		_rock(Vector3(_rng.randf_range(-15, 15), y + 0.2, _rng.randf_range(-92, -61)), _rng.randf_range(0.3, 0.9), false)
	_stalactites(c, 15.0, 13.0, 16)
	# Gegner
	# Willfaults: zwei Hollowed in der Mitte, ein Splinterkin-Rudel lauert am Kristall (vom Licht angezogen)
	for p in [Vector3(-4, y + 0.1, -74), Vector3(5, y + 0.1, -80)]:
		_spawn_hollowed(Transform3D(Basis(Vector3.UP, 0.0), p))
	for i in 4:
		var a := TAU * i / 4.0
		_spawn_splinterkin(Transform3D(Basis(Vector3.UP, a), Vector3(-12.5 + cos(a) * 1.8, y + 0.1, -64.5 + sin(a) * 1.8)), a)


## Raum 4 (Seitenhalle östlich des Übungsrings): "The Drowned Cistern".
## Alte Zisterne des Grimvault, in der die Wardens Klettern und Schwimmen üben:
## Becken mit flacher Rampe und niedriger Kante (Reinspringen, Schwimmen, Rausklettern),
## Turm mit Eisengitter (Klettern, oben Kante zum Hochziehen, Sprung ins Becken, Abrollen),
## Flechtenturm (7,5 m, Ausdauer reicht knapp), Flechtenwand ohne Ende (Ausdauer leer -> Sturz),
## enger Spalt zwischen Gitterturm und Nordwand (Sturz mit Wand vorn -> Rückwärtsrolle).
const CISTERN := Vector3(35, 0, -34)
const POOL_MIN := Vector2(-11, -12)  ## Becken (lokal zu CISTERN)
const POOL_MAX := Vector2(3, 0)
const WATER_Y := -0.4
const POOL_FLOOR := -2.8

func _build_room_cistern() -> void:
	var c := CISTERN
	_room_shell(c, Vector2(28, 28), [], [], "The Drowned Cistern", true, [Vector2(-34, 6)], [], false)
	var x0 := c.x + POOL_MIN.x
	var x1 := c.x + POOL_MAX.x
	var z0 := c.z + POOL_MIN.y
	var z1 := c.z + POOL_MAX.y
	# Boden um das Becken herum
	_slab_floor(Vector2(c.x - 14, z1), Vector2(c.x + 14, c.z + 14), 0.0)
	_slab_floor(Vector2(x1, c.z - 14), Vector2(c.x + 14, z1), 0.0)
	_slab_floor(Vector2(c.x - 14, c.z - 14), Vector2(x0, z1), 0.0)
	_slab_floor(Vector2(x0, c.z - 14), Vector2(x1, z0), 0.0)
	# Becken: Grund und Wände (Innenflächen 3 cm vor dem Bodenrand, nie bündig)
	var bc := Vector3((x0 + x1) * 0.5, POOL_FLOOR - 0.2, (z0 + z1) * 0.5)
	_block(bc, Vector3(x1 - x0 + 0.4, 0.4, z1 - z0 + 0.4), LowPoly.STONE_DARK)
	var wh := -0.2 - (POOL_FLOOR - 0.2)
	var wy := (POOL_FLOOR - 0.2 - 0.2) * 0.5
	_block(Vector3((x0 + x1) * 0.5, wy, z0 - 0.47), Vector3(x1 - x0 + 2.0, wh, 1.0), LowPoly.STONE)
	_block(Vector3((x0 + x1) * 0.5, wy, z1 + 0.47), Vector3(x1 - x0 + 2.0, wh, 1.0), LowPoly.STONE)
	_block(Vector3(x0 - 0.47, wy, (z0 + z1) * 0.5), Vector3(1.0, wh, z1 - z0 + 1.9), LowPoly.STONE)
	_block(Vector3(x1 + 0.47, wy, (z0 + z1) * 0.5), Vector3(1.0, wh, z1 - z0 + 1.9), LowPoly.STONE)
	# Einstiegsrampe im Südwesten (zum Hineinwaten und wieder Herauslaufen)
	var rx := c.x - 7.0
	_ramp(Vector3(rx, POOL_FLOOR, z1 - 5.6), Vector3(rx, -0.06, z1 - 0.25), 3.6)
	# Beckenrand: niedrige Steinkante (0,58 m über dem Wasser -> Rausklettern), Lücke für die Rampe
	var curb := LowPoly.STONE_LIGHT.darkened(0.08)
	_curb(Vector3(x0, 0, z0), Vector3(x1 - 0.3, 0, z0), curb)  # Nordkante bis zum Gitterturm
	_curb(Vector3(x0, 0, z0), Vector3(x0, 0, z1), curb)  # Westkante
	_curb(Vector3(x0, 0, z1), Vector3(rx - 1.9, 0, z1), curb)  # Südkante links der Rampe
	_curb(Vector3(rx + 1.9, 0, z1), Vector3(x1, 0, z1), curb)  # Südkante rechts der Rampe
	_curb(Vector3(x1, 0, z1), Vector3(x1, 0, z0 + 6.1), curb)  # Ostkante bis zum Turm
	var water := WaterVolume.new()
	water.name = "CisternWater"
	water.size = Vector2(x1 - x0, z1 - z0)
	water.depth = WATER_Y - POOL_FLOOR + 0.2
	water.position = Vector3((x0 + x1) * 0.5, WATER_Y, (z0 + z1) * 0.5)
	add_child(water)

	# Gitterturm am Nordostende des Beckens: Eisengitter an der Südseite, oben eine Plattform (4 m)
	var tw := Vector3(c.x + 5.0, 0, c.z - 9.0)
	_block(tw + Vector3(0, 1.75, 0), Vector3(4.0, 4.5, 6.0), LowPoly.STONE)  # reicht 0,5 m unter den Boden
	_block(tw + Vector3(0, 4.08, 0), Vector3(3.9, 0.2, 5.9), LowPoly.STONE_LIGHT)  # Plattform-Abschluss (eingerückt: keine Kante über dem Gitter)
	_grate(tw + Vector3(0, 0, 3.0), 3.0, 3.98, Vector3(0, 0, 1))
	_crystal_cluster(tw + Vector3(1.2, 4.2, -2.2), 0.5)
	# Flechtenturm im Südosten: 7,5 m, Flechten an der Westseite, oben ein Kristall als Lohn
	var lt := Vector3(c.x + 10.0, 0, c.z + 8.0)
	_block(lt + Vector3(0, 3.5, 0), Vector3(3.0, 8.0, 3.0), LowPoly.STONE)
	_block(lt + Vector3(0, 7.58, 0), Vector3(2.9, 0.2, 2.9), LowPoly.STONE_LIGHT)
	_lichen(lt + Vector3(-1.5, 0, 0), 2.6, 7.45, Vector3(-1, 0, 0))
	_crystal_cluster(lt + Vector3(0.6, 7.7, 0.6), 0.6)
	# Flechtenwand an der Nordwand: reicht bis unter die Decke, oben gibt es keine Kante -> Ausdauer leer = Sturz
	_lichen(Vector3(c.x + 11.2, 0, c.z - 14.0), 4.0, 12.5, Vector3(0, 0, 1))
	# Licht: Kristalle am Becken (kühl), Feuerschale am Eingang (warm), Pilze
	_crystal_cluster(Vector3(x0 - 1.6, 0, z0 - 0.8), 1.0)
	_crystal_vein(Vector3(x0 - 2.65, 2.2, (z0 + z1) * 0.5), 1.0)
	_fire_bowl(Vector3(c.x - 11.5, 0, c.z + 4.0), 0.9)
	_mushrooms(Vector3(c.x + 12.0, 0, c.z - 4.0), 5, 0.9)
	_mushrooms(Vector3(c.x - 3.0, 0, c.z + 12.0), 4, 0.8)
	_gear_pile(Vector3(c.x + 2.5, 0, c.z + 9.5), 0.5, 0)
	var d := TrainingDummy.new()
	d.position = Vector3(c.x + 1.0, 0.05, c.z + 6.0)
	d.rotation.y = PI * 0.5
	add_child(d)
	_hanging_roots(Vector3(c.x - 4.0, 0, z0 + 2.0), 6.0, 6)
	_stalactites(c, 12.0, 12.0, 10)


## Gang entlang X (zwischen zwei Räumen nebeneinander).
func _build_corridor_x(x_from: float, x_to: float, z: float, y: float, width: float, height: float) -> void:
	var length := x_to - x_from
	var mx := (x_from + x_to) * 0.5
	_slab_floor(Vector2(x_from, z - width * 0.5), Vector2(x_to, z + width * 0.5), y)
	for side in [-1.0, 1.0]:
		_block(Vector3(mx, y + height * 0.5, z + side * (width * 0.5 + 1.0)), Vector3(length - 2.2, height, 2.0), LowPoly.STONE)
	_block(Vector3(mx, y + height + 0.75, z), Vector3(length - 2.2, 1.5, width + 4.0), LowPoly.STONE_DARK)
	_mushrooms(Vector3(mx, y, z - width * 0.5 + 0.5), 3, 0.6)


## Niedrige Steinkante am Beckenrand (sitzt 2 cm im Boden, ragt 6 cm über das Becken).
func _curb(a: Vector3, b: Vector3, color: Color) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.3:
		return
	var dir := along / length
	var out := Vector3(-dir.z, 0, dir.x)  # zeigt je nach Richtung ins Becken oder heraus -> Mitte prüfen
	var pool_c := CISTERN + Vector3((POOL_MIN.x + POOL_MAX.x) * 0.5, 0, (POOL_MIN.y + POOL_MAX.y) * 0.5)
	if out.dot(pool_c - (a + b) * 0.5) > 0.0:
		out = -out
	var w := 0.5
	var center := (a + b) * 0.5 + out * (w * 0.5 - 0.06) + Vector3(0, 0.08, 0)
	var size := Vector3(length + w, 0.2, w) if absf(dir.x) > 0.5 else Vector3(w, 0.2, length + w)
	_block(center, size, color)


## Eisengitter zum Klettern vor einer Wand (normal zeigt von der Wand weg).
func _grate(base: Vector3, width: float, height: float, normal: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "Grate"
	sb.collision_layer = Game.LAYER_WORLD
	sb.add_to_group("climbable")
	sb.position = base + normal * 0.06
	sb.basis = Basis(Vector3.UP, atan2(normal.x, normal.z))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.08)
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	sb.add_child(cs)
	var iron := LowPoly.mat(Color(0.24, 0.22, 0.19), 0.0, 0.5)
	var rust := LowPoly.mat(Color(0.34, 0.17, 0.08), 0.0, 0.8)
	# Rahmen, senkrechte und waagrechte Stäbe (waagrechte liegen vorn: sichtbar versetzt, nie bündig)
	for sx in [-1.0, 1.0]:
		LowPoly.mesh_instance(LowPoly.box(Vector3(0.1, height, 0.1)), iron, sb, Vector3(sx * (width * 0.5 - 0.05), height * 0.5, 0.0))
	LowPoly.mesh_instance(LowPoly.box(Vector3(width, 0.1, 0.12)), iron, sb, Vector3(0, height - 0.05, 0.0))
	var nv := int(width / 0.3)
	for i in range(1, nv):
		var x := -width * 0.5 + width * float(i) / nv
		LowPoly.mesh_instance(LowPoly.box(Vector3(0.055, height - 0.1, 0.05)), iron, sb, Vector3(x, (height - 0.1) * 0.5, -0.015))
	var nh := int(height / 0.4)
	for i in range(1, nh):
		var y := height * float(i) / nh
		LowPoly.mesh_instance(LowPoly.box(Vector3(width - 0.12, 0.06, 0.05)), rust if i % 3 == 0 else iron, sb, Vector3(0, y, 0.03))
	_geo.add_child(sb)


## Flechtenvorhang zum Klettern: dichte, hängende Strähnen in gedämpftem Grün-Grau.
func _lichen(base: Vector3, width: float, height: float, normal: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "Lichen"
	sb.collision_layer = Game.LAYER_WORLD
	sb.add_to_group("climbable")
	sb.position = base + normal * 0.05
	sb.basis = Basis(Vector3.UP, atan2(normal.x, normal.z))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.06)
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	sb.add_child(cs)
	var cols := [Color(0.16, 0.2, 0.14), Color(0.2, 0.24, 0.16), Color(0.13, 0.17, 0.15), Color(0.22, 0.22, 0.13)]
	var mats: Array = []
	for col in cols:
		mats.append(LowPoly.mat(col))
	var glow := LowPoly.mat(SHROOM.darkened(0.5), 0.6)
	# Strähnen: schmale, nach unten spitz zulaufende Bänder in mehreren Lagen
	var n := int(width / 0.16)
	var rows := int(height / 1.4) + 1
	for r in rows:
		var top := height - r * 1.35 + _rng.randf_range(-0.1, 0.1)
		for i in n:
			var x := -width * 0.5 + (i + 0.5) * width / n + _rng.randf_range(-0.05, 0.05)
			var length := _rng.randf_range(0.9, 1.7)
			var t := minf(top, height)
			if t - length < 0.0:
				length = t
			if length < 0.2:
				continue
			var strand := LowPoly.mesh_instance(LowPoly.prism(0.05, 0.11, length, 3), mats[_rng.randi() % mats.size()], sb, Vector3(x, t - length * 0.5, 0.02 + 0.025 * (i % 2) + 0.01 * r))
			strand.rotation = Vector3(_rng.randf_range(-0.08, 0.08), _rng.randf() * TAU, _rng.randf_range(-0.05, 0.05))
			strand.scale = Vector3(1.0, 1.0, 0.45)
			if _rng.randf() < 0.06:
				LowPoly.mesh_instance(LowPoly.crystal(0.08, 0.03), glow, sb, Vector3(x, t - length * 0.8, 0.07))
	_geo.add_child(sb)


## F4: Test-Explosion ein paar Meter vor dem Spieler (zum Begutachten der Effekte).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F4 and player:
		var at := player.global_position + player.forward() * 4.0
		Explosion.spawn(self, at, 1.0)


func _spawn_hollowed(xf: Transform3D) -> void:
	var h := Hollowed.new()
	h.transform = xf
	h.respawn_requested.connect(func(_old): get_tree().create_timer(2.0).timeout.connect(func(): _spawn_hollowed(xf)))
	add_child(h)


func _spawn_splinterkin(xf: Transform3D, angle: float) -> void:
	var k := Splinterkin.new()
	k.transform = xf
	k.pack_angle = angle
	k.respawn_requested.connect(func(_old): get_tree().create_timer(4.0).timeout.connect(func(): _spawn_splinterkin(xf, angle)))
	add_child(k)


func _spawn_player(pos: Vector3, yaw: float) -> void:
	player = Player.new()
	player.name = "Player1"
	player.position = pos
	player.rotation.y = yaw
	add_child(player)
	var hud := HUD.new()
	add_child(hud)
	hud.setup(player)


# ==================================================================
# Bausteine
# ==================================================================

## Boden + vier Wände. Öffnungen: Vector2(x-Mitte, Breite) an der Süd- (+Z) bzw. Nordwand (-Z).
func _room_shell(c: Vector3, size: Vector2, south_open: Array, north_open: Array, room_name: String, cave := false, west_open: Array = [], east_open: Array = [], with_floor := true) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	if with_floor:
		_slab_floor(Vector2(c.x - hx, c.z - hz), Vector2(c.x + hx, c.z + hz), c.y)
	_wall_x(c.z + hz + 1.0, c.x - hx - 2.0, c.x + hx + 2.0, c.y, south_open)
	_wall_x(c.z - hz - 1.0, c.x - hx - 2.0, c.x + hx + 2.0, c.y, north_open)
	for side in [-1.0, 1.0]:
		var x: float = c.x + side * (hx + 1.0)
		var opens: Array = west_open if side < 0.0 else east_open
		_wall_z(x, c.z - hz, c.z + hz, c.y, opens)
		# Wandpfeiler für die monumentale Silhouette
		var n := int(size.y / 5.0)
		for i in n + 1:
			var z: float = c.z - hz + size.y * float(i) / n
			if _in_opening(z, opens, 1.3):
				continue
			_block(Vector3(x - side * 0.6, c.y + WALL_H * 0.5, z), Vector3(1.4, WALL_H, 1.4), LowPoly.STONE_DARK)
		for i in 4:
			var rz := c.z + _rng.randf_range(-hz, hz)
			var rr := _rng.randf_range(0.5, 1.1)
			if not _in_opening(rz, opens, rr + 0.6):
				_rock(Vector3(x - side * 1.0, c.y + 0.2, rz), rr, true)
		if cave:
			# natürlicher Fels bricht durch das Mauerwerk
			for i in int(size.y / 3.0):
				var z := c.z - hz + (i + 0.5) * size.y / int(size.y / 3.0) + _rng.randf_range(-0.8, 0.8)
				var r := _rng.randf_range(1.2, 2.2)
				var mesh := LowPoly.rock(r, _rng.randi(), 6, 4, 0.35)
				var col := _vary(LowPoly.STONE.darkened(0.1))
				var ry := _rng.randf_range(0.5, 9.0)
				var sy := _rng.randf_range(1.0, 2.0)
				var rot := _rng.randf() * TAU
				if _in_opening(z, opens, r + 0.5) and ry < 9.0:
					continue
				var mi := LowPoly.mesh_instance(mesh, LowPoly.mat(col), _geo, Vector3(x - side * 0.2, c.y + ry, z))
				mi.scale = Vector3(0.6, sy, 1.0)
				mi.rotation.y = rot
	_room_trigger(c, size, room_name)


func _wall_x(z: float, x0: float, x1: float, y: float, openings: Array) -> void:
	var cuts: Array = [[x0, x1]]
	for o in openings:
		var ox: float = o.x
		var hw: float = o.y * 0.5
		var next: Array = []
		for seg in cuts:
			if ox + hw <= seg[0] or ox - hw >= seg[1]:
				next.append(seg)
			else:
				if ox - hw > seg[0]:
					next.append([seg[0], ox - hw])
				if ox + hw < seg[1]:
					next.append([ox + hw, seg[1]])
		cuts = next
		# Torbogen über der Öffnung
		_arch(Vector3(ox, y, z), o.y, 7.0)
	for seg in cuts:
		var w: float = seg[1] - seg[0]
		_block(Vector3((seg[0] + seg[1]) * 0.5, y + WALL_H * 0.5, z), Vector3(w, WALL_H, 2.0), LowPoly.STONE)


func _in_opening(z: float, opens: Array, margin: float) -> bool:
	for o in opens:
		if absf(z - (o as Vector2).x) < (o as Vector2).y * 0.5 + margin:
			return true
	return false


## Seitenwand entlang Z mit Öffnungen Vector2(z-Mitte, Breite).
func _wall_z(x: float, z0: float, z1: float, y: float, openings: Array) -> void:
	var cuts: Array = [[z0, z1]]
	for o in openings:
		var oz: float = o.x
		var hw: float = o.y * 0.5
		var next: Array = []
		for seg in cuts:
			if oz + hw <= seg[0] or oz - hw >= seg[1]:
				next.append(seg)
			else:
				if oz - hw > seg[0]:
					next.append([seg[0], oz - hw])
				if oz + hw < seg[1]:
					next.append([oz + hw, seg[1]])
		cuts = next
		var h := 7.0
		for sd in [-1.0, 1.0]:
			_block(Vector3(x, y + h * 0.5, oz + sd * (hw + 0.6)), Vector3(2.6, h, 1.2), LowPoly.STONE_DARK)
		_block(Vector3(x, y + h + 0.7, oz), Vector3(2.6, 1.4, o.y + 2.4), LowPoly.STONE_DARK)
		_block(Vector3(x, y + h + 0.05, oz), Vector3(2.2, 0.3, o.y + 0.4), LowPoly.STONE_LIGHT)
		_block(Vector3(x, y + (h + 1.4 + WALL_H) * 0.5, oz), Vector3(2.0, WALL_H - h - 1.4, o.y + 2.4), LowPoly.STONE)
	for seg in cuts:
		var w: float = seg[1] - seg[0]
		_block(Vector3(x, y + WALL_H * 0.5, (seg[0] + seg[1]) * 0.5), Vector3(2.0, WALL_H, w), LowPoly.STONE)


func _arch(pos: Vector3, width: float, height: float) -> void:
	for side in [-1.0, 1.0]:
		_block(pos + Vector3(side * (width * 0.5 + 0.6), height * 0.5, 0), Vector3(1.2, height, 2.6), LowPoly.STONE_DARK)
	_block(pos + Vector3(0, height + 0.7, 0), Vector3(width + 2.4, 1.4, 2.6), LowPoly.STONE_DARK)
	_block(pos + Vector3(0, height + 0.05, 0), Vector3(width + 0.4, 0.3, 2.2), LowPoly.STONE_LIGHT)
	# Füllwand über dem Bogen bis zur Raumhöhe
	_block(pos + Vector3(0, (height + 1.4 + WALL_H) * 0.5, 0), Vector3(width + 2.4, WALL_H - height - 1.4, 2.0), LowPoly.STONE)


func _build_corridor(from: Vector3, to: Vector3, width: float, height: float) -> void:
	var mid := (from + to) * 0.5
	var length := absf(to.z - from.z)
	_slab_floor(Vector2(mid.x - width * 0.5, to.z), Vector2(mid.x + width * 0.5, from.z), from.y)
	for side in [-1.0, 1.0]:
		_block(Vector3(mid.x + side * (width * 0.5 + 1.0), from.y + height * 0.5, mid.z), Vector3(2.0, height, length), LowPoly.STONE)
	_block(Vector3(mid.x, from.y + height + 0.75, mid.z), Vector3(width + 4.0, 1.5, length), LowPoly.STONE_DARK)
	_mushrooms(Vector3(mid.x + width * 0.5 - 0.5, from.y, mid.z + 1.0), 4, 0.7)


func _room_trigger(c: Vector3, size: Vector2, room_name: String) -> void:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = Game.LAYER_PLAYERS
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(size.x, 8.0, size.y - 2.0)
	cs.shape = b
	a.add_child(cs)
	a.position = c + Vector3(0, 3.0, 0)
	add_child(a)
	var spawn := Transform3D(Basis.IDENTITY, c + Vector3(0, 0.2, size.y * 0.5 - 2.5))
	a.body_entered.connect(func(body):
		if body is Player:
			if body.checkpoint.origin.distance_to(spawn.origin) > 1.0:
				body.checkpoint = spawn
				Game.room_entered.emit(room_name))


func _block(center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "Block_%d_%d_%d" % [roundi(center.x), roundi(center.y), roundi(center.z)]
	sb.collision_layer = Game.LAYER_WORLD
	sb.collision_mask = 0
	sb.position = center
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	LowPoly.mesh_instance(LowPoly.box(size), LowPoly.mat(_vary(color)), sb)
	_geo.add_child(sb)
	return sb


func _ramp(bottom: Vector3, top: Vector3, width: float) -> void:
	var run := Vector3(top.x - bottom.x, 0, top.z - bottom.z)
	var rise := top.y - bottom.y
	var length := sqrt(run.length_squared() + rise * rise)
	var thick := 0.6
	var sb := StaticBody3D.new()
	sb.collision_layer = Game.LAYER_WORLD
	var mid := (bottom + top) * 0.5
	var yaw := atan2(-run.x, -run.z)
	var pitch := atan2(rise, run.length())
	sb.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	sb.position = mid - sb.basis.y * thick * 0.5
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thick, length + 0.4)
	cs.shape = shape
	sb.add_child(cs)
	LowPoly.mesh_instance(LowPoly.box(shape.size), LowPoly.mat(LowPoly.FLOOR.darkened(0.05)), sb)
	_geo.add_child(sb)
	# Unterbau, damit die Rampe nicht schwebt
	if rise > 0.5:
		var lo := minf(bottom.y, top.y)
		var hi := maxf(bottom.y, top.y)
		var under := Vector3(width * 0.96, hi - lo, run.length() * 0.5)
		var hp := (top if top.y > bottom.y else bottom)
		var lp := (bottom if top.y > bottom.y else top)
		var c := lp.lerp(hp, 0.75)
		LowPoly.mesh_instance(LowPoly.box(under), LowPoly.mat(LowPoly.STONE), _geo, Vector3(c.x, lo + under.y * 0.5 - 0.3, c.z))


func _pillar(base: Vector3, radius: float, height: float, sides: int) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = Game.LAYER_WORLD
	sb.position = base
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position.y = height * 0.5
	sb.add_child(cs)
	var col := _vary(LowPoly.STONE)
	var rot := _rng.randf() * TAU
	# Sockel, Schaft, Kapitell
	var foot := LowPoly.mesh_instance(LowPoly.prism(radius * 1.35, radius * 1.2, 0.8, sides), LowPoly.mat(col.darkened(0.15)), sb, Vector3(0, 0.4, 0))
	foot.rotation.y = rot
	var shaft := LowPoly.mesh_instance(LowPoly.prism(radius, radius * 0.9, height - 1.6, sides), LowPoly.mat(col), sb, Vector3(0, 0.8 + (height - 1.6) * 0.5, 0))
	shaft.rotation.y = rot
	var cap := LowPoly.mesh_instance(LowPoly.prism(radius * 1.0, radius * 1.4, 0.8, sides), LowPoly.mat(col.darkened(0.15)), sb, Vector3(0, height - 0.4, 0))
	cap.rotation.y = rot
	# Leuchtende Rune
	var rune := LowPoly.mesh_instance(LowPoly.box(Vector3(0.12, 0.5, 0.05)), LowPoly.mat(LowPoly.CYAN, 1.6), sb, Vector3(0, 2.2, -radius * 0.92))
	rune.rotation.y = 0.0
	_geo.add_child(sb)


func _rock(pos: Vector3, radius: float, solid: bool) -> void:
	var mesh := LowPoly.rock(radius, _rng.randi(), 6, 4, 0.3)
	var col := _vary(LowPoly.STONE.lerp(LowPoly.STONE_LIGHT, 0.3))
	if solid or radius > 0.45:
		var sb := StaticBody3D.new()
		sb.collision_layer = Game.LAYER_WORLD
		sb.position = pos
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_convex_shape()
		sb.add_child(cs)
		var mi := LowPoly.mesh_instance(mesh, LowPoly.mat(col), sb)
		mi.rotation.y = _rng.randf() * TAU
		cs.rotation.y = mi.rotation.y
		sb.scale = Vector3(1.0, _rng.randf_range(0.6, 1.0), 1.0)
		_geo.add_child(sb)
	else:
		var mi := LowPoly.mesh_instance(mesh, LowPoly.mat(col), _geo, pos)
		mi.scale = Vector3(1.0, 0.7, 1.0)


func _crystal_cluster(base: Vector3, size: float, with_light := true) -> void:
	var root := Node3D.new()
	root.position = base
	_geo.add_child(root)
	var mat := LowPoly.mat(LowPoly.CYAN, 3.5)
	for i in 5:
		var h := _rng.randf_range(0.6, 1.4) * size
		var mi := LowPoly.mesh_instance(LowPoly.crystal(h, h * 0.16), mat, root)
		mi.rotation = Vector3(_rng.randf_range(-0.45, 0.45), _rng.randf() * TAU, _rng.randf_range(-0.45, 0.45))
		mi.position = Vector3(_rng.randf_range(-0.25, 0.25), 0, _rng.randf_range(-0.25, 0.25)) * size
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if with_light:
		_light(base + Vector3(0, 1.0 * size, 0), LowPoly.CYAN, 2.2, 9.0 * size)


func _light(pos: Vector3, color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.light_volumetric_fog_energy = 1.5
	l.add_to_group("light_sources")  # für spätere Licht-/Schatten-Mechaniken
	_geo.add_child(l)
	return l


## Schwebende Felssplitter, die langsam treiben.
func _floating_shards(center: Vector3, count: int, spread: float) -> void:
	for i in count:
		var r := _rng.randf_range(0.3, 1.1)
		var mi := LowPoly.mesh_instance(LowPoly.rock(r, _rng.randi(), 4, 3, 0.4), LowPoly.mat(_vary(LowPoly.STONE_DARK)), _geo)
		mi.position = center + Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(-2.0, 4.0), _rng.randf_range(-spread, spread))
		mi.scale = Vector3(0.7, 1.6, 0.7)
		mi.rotation = Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf() * TAU, _rng.randf_range(-0.6, 0.6))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # wird per Tween bewegt
		var tw := mi.create_tween().set_loops()
		var dy := _rng.randf_range(0.3, 0.8)
		var t := _rng.randf_range(2.5, 4.5)
		tw.tween_property(mi, "position:y", mi.position.y + dy, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(mi, "position:y", mi.position.y, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Boden aus leicht unregelmäßigen Steinplatten, als ein einziges Mesh (schnell).
func _slab_floor(min_xz: Vector2, max_xz: Vector2, y: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = Game.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var size := Vector3(max_xz.x - min_xz.x, 1.0, max_xz.y - min_xz.y)
	shape.size = size
	cs.shape = shape
	cs.position = Vector3((min_xz.x + max_xz.x) * 0.5, y - 0.5, (min_xz.y + max_xz.y) * 0.5)
	sb.add_child(cs)
	_geo.add_child(sb)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile := 2.0
	var nx := int(ceil(size.x / tile))
	var nz := int(ceil(size.z / tile))
	for ix in nx:
		for iz in nz:
			var x0 := min_xz.x + ix * tile
			var z0 := min_xz.y + iz * tile
			var x1 := minf(x0 + tile, max_xz.x)
			var z1 := minf(z0 + tile, max_xz.y)
			var gap := 0.05
			var top := y + _rng.randf_range(-0.03, 0.0)
			var col := LowPoly.FLOOR.darkened(_rng.randf_range(0.0, 0.14)).lerp(LowPoly.STONE_LIGHT, _rng.randf_range(0.0, 0.3))
			st.set_color(col)
			var a := Vector3(x0 + gap, top, z0 + gap)
			var b := Vector3(x1 - gap, top, z0 + gap)
			var c := Vector3(x1 - gap, top, z1 - gap)
			var d := Vector3(x0 + gap, top, z1 - gap)
			var center := Vector3((x0 + x1) * 0.5, top - 1.0, (z0 + z1) * 0.5)
			LowPoly.tri_out(st, a, b, c, center)
			LowPoly.tri_out(st, a, c, d, center)
			# Fugen: abgeschrägte Kanten nach unten
			st.set_color(col.darkened(0.45))
			var lo := top - 0.12
			var ring := [a, b, c, d]
			for k in 4:
				var p0: Vector3 = ring[k]
				var p1: Vector3 = ring[(k + 1) % 4]
				var out0 := p0 + (p0 - Vector3(center.x, top, center.z)).normalized() * gap
				var out1 := p1 + (p1 - Vector3(center.x, top, center.z)).normalized() * gap
				out0.y = lo
				out1.y = lo
				LowPoly.tri_out(st, p0, p1, out1, center)
				LowPoly.tri_out(st, p0, out1, out0, center)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_geo.add_child(mi)
	# dunkle Unterlage unter den Fugen
	LowPoly.mesh_instance(LowPoly.box(Vector3(size.x, 0.2, size.z)), LowPoly.mat(LowPoly.STONE_DARK), _geo, Vector3(cs.position.x, y - 0.2, cs.position.z))


# ------------------------------------------------------------------
# Lore-Bausteine
# ------------------------------------------------------------------

## Feuerschale mit flackernden Flammen (warme Bright, von den Wardens gehütet).
func _fire_bowl(base: Vector3, size: float) -> void:
	_block(base + Vector3(0, 0.45 * size, 0), Vector3(0.8, 0.9, 0.8) * size, LowPoly.STONE_DARK)
	var bowl := LowPoly.mesh_instance(LowPoly.prism(0.32 * size, 0.85 * size, 0.32 * size, 8), LowPoly.mat(LowPoly.OCHRE.darkened(0.35)), _geo, base + Vector3(0, 1.05 * size, 0))
	bowl.rotation.y = PI / 8
	var top := base + Vector3(0, 1.2 * size, 0)
	for i in 5:  # Glutstücke in der Schale
		var e := LowPoly.mesh_instance(LowPoly.rock(0.08 * size, _rng.randi(), 4, 3, 0.3), LowPoly.mat(FIRE.darkened(0.3), 2.0), _geo, top + Vector3(_rng.randf_range(-0.3, 0.3), -0.02, _rng.randf_range(-0.3, 0.3)) * size)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Flammen nach dem Shooter-Prinzip: Zungen, Kern, Glut, Rauch, flackerndes Licht
	Flames.fire(_geo, top, size)


## Erloschene Feuerschale: Asche, kein Licht.
func _cold_brazier(base: Vector3) -> void:
	_block(base + Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9), LowPoly.STONE_DARK)
	var bowl := LowPoly.mesh_instance(LowPoly.prism(0.35, 1.0, 0.35, 8), LowPoly.mat(LowPoly.OCHRE.darkened(0.55)), _geo, base + Vector3(0, 1.17, 0))
	bowl.rotation.y = PI / 8
	for i in 6:
		LowPoly.mesh_instance(LowPoly.rock(0.11, _rng.randi(), 4, 3, 0.3), LowPoly.mat(Color(0.12, 0.12, 0.12)), _geo, base + Vector3(_rng.randf_range(-0.4, 0.4), 1.36, _rng.randf_range(-0.4, 0.4)))


## Leuchtpilze: nur ein schwaches Glimmen in der Umgebung.
func _mushrooms(base: Vector3, count: int, size: float) -> void:
	var root := Node3D.new()
	root.position = base
	_geo.add_child(root)
	var stem_mat := LowPoly.mat(Color(0.5, 0.55, 0.5))
	var cap_mat := LowPoly.mat(SHROOM, 2.2)
	for i in count:
		var h := _rng.randf_range(0.12, 0.45) * size
		var r := _rng.randf_range(0.07, 0.2) * size
		var p := Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6)) * size
		var tilt := Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf() * TAU, _rng.randf_range(-0.25, 0.25))
		var stem := LowPoly.mesh_instance(LowPoly.prism(r * 0.25, r * 0.18, h, 5), stem_mat, root, p + Vector3(0, h * 0.5, 0))
		stem.rotation = tilt
		var cap := LowPoly.mesh_instance(LowPoly.prism(r, r * 0.25, r * 0.55, 6), cap_mat, root, p + Vector3(0, h, 0))
		cap.rotation = tilt
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := _light(base + Vector3(0, 0.4 * size, 0), SHROOM, 0.45 * size, 3.2 * size)
	l.light_volumetric_fog_energy = 0.5


## Kristallader in einer Wand: schmale Splitter, die seitlich herauswachsen.
func _crystal_vein(pos: Vector3, outward: float) -> void:
	var root := Node3D.new()
	root.position = pos
	_geo.add_child(root)
	var mat := LowPoly.mat(LowPoly.CYAN, 3.0)
	for i in 6:
		var h := _rng.randf_range(0.3, 0.8)
		var mi := LowPoly.mesh_instance(LowPoly.crystal(h, h * 0.15), mat, root, Vector3(0, _rng.randf_range(-0.8, 0.8), _rng.randf_range(-1.0, 1.0)))
		mi.rotation = Vector3(_rng.randf_range(-0.4, 0.4), 0, -outward * _rng.randf_range(0.9, 1.5))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light(pos + Vector3(outward * 0.6, 0, 0), LowPoly.CYAN, 0.9, 4.5)


## Ausrüstungshaufen eines verblassten Shades (später: lootbar, mit Echo).
## kind 0: Schwert + Mantel, 1: Helm + Schild, 2: alles + Rucksack
func _gear_pile(base: Vector3, yaw: float, kind: int) -> void:
	var root := Node3D.new()
	root.position = base
	root.rotation.y = yaw
	_geo.add_child(root)
	var cloth := LowPoly.mesh_instance(LowPoly.rock(0.42, _rng.randi(), 7, 3, 0.35), LowPoly.mat(_vary(CLOTH_OLD)), root, Vector3(0, 0.05, 0))
	cloth.scale = Vector3(1.3, 0.28, 1.0)
	var metal := LowPoly.mat(_vary(METAL_OLD), 0.0, 0.55)
	if kind != 1:
		var blade := LowPoly.mesh_instance(LowPoly.blade(0.78, 0.07, 0.02), metal, root, Vector3(0.25, 0.1, 0.1))
		blade.rotation = Vector3(-PI / 2 + 0.08, 0.6, 0.1)
	if kind != 0:
		var helm := LowPoly.mesh_instance(LowPoly.prism(0.17, 0.06, 0.2, 6), metal, root, Vector3(-0.25, 0.16, -0.1))
		helm.rotation = Vector3(0.5, 0.3, 0.9)
		var sh := LowPoly.mesh_instance(LowPoly.prism(0.3, 0.27, 0.05, 7), LowPoly.mat(_vary(LowPoly.STONE_DARK)), root, Vector3(0.1, 0.12, -0.35))
		sh.rotation = Vector3(0.25, 0, 0.12)
	if kind == 2:
		LowPoly.mesh_instance(LowPoly.box(Vector3(0.32, 0.24, 0.22)), LowPoly.mat(ROOTWOOD.lightened(0.15)), root, Vector3(-0.45, 0.13, 0.3)).rotation.y = 0.4
	for n in root.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Tor aus Wurzelholz-Pfählen: Vigil liegt dahinter. Warmes Licht fällt durch die Ritzen.
func _ward_gate(pos: Vector3, width: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = Game.LAYER_WORLD
	sb.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 6.0, 0.7)
	cs.shape = shape
	cs.position.y = 3.0
	sb.add_child(cs)
	_geo.add_child(sb)
	var wood := LowPoly.mat(ROOTWOOD)
	var n := int(width / 0.42)
	for i in n:
		var x := -width * 0.5 + (i + 0.5) * width / n
		var h := _rng.randf_range(4.2, 5.4)
		var r := _rng.randf_range(0.13, 0.18)
		var stake := LowPoly.mesh_instance(LowPoly.prism(r, r * 0.85, h, 6), LowPoly.mat(_vary(ROOTWOOD)), sb, Vector3(x, h * 0.5, 0))
		stake.rotation = Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf() * TAU, _rng.randf_range(-0.04, 0.04))
		var tip := LowPoly.mesh_instance(LowPoly.prism(r * 0.85, 0.01, 0.45, 6), wood, sb, Vector3(x, h + 0.22, 0))
		tip.rotation.y = stake.rotation.y
	for y in [1.1, 3.4]:
		var beam := LowPoly.mesh_instance(LowPoly.box(Vector3(width + 0.6, 0.22, 0.24)), LowPoly.mat(ROOTWOOD.lightened(0.08)), sb, Vector3(0, y, -0.28))
		beam.rotation.z = _rng.randf_range(-0.05, 0.05)
	# dahinter: ein Stück Boden und das warme Licht von Vigil
	_slab_floor(Vector2(pos.x - width * 0.5, pos.z), Vector2(pos.x + width * 0.5, pos.z + 6.0), pos.y)
	var l := _light(pos + Vector3(0, 3.0, 3.5), FIRE.lerp(Color(1, 0.8, 0.6), 0.3), 2.2, 9.0)
	l.shadow_enabled = true
	l.light_volumetric_fog_energy = 2.5


## Waffenständer der Wardens mit alten Klingen.
func _weapon_rack(base: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = base
	root.rotation.y = yaw
	_geo.add_child(root)
	var wood := LowPoly.mat(ROOTWOOD.lightened(0.05))
	for x in [-0.9, 0.9]:
		LowPoly.mesh_instance(LowPoly.prism(0.08, 0.07, 1.3, 5), wood, root, Vector3(x, 0.65, 0))
	LowPoly.mesh_instance(LowPoly.box(Vector3(2.0, 0.1, 0.12)), wood, root, Vector3(0, 1.2, 0))
	LowPoly.mesh_instance(LowPoly.box(Vector3(2.0, 0.08, 0.3)), wood, root, Vector3(0, 0.25, 0))
	var metal := LowPoly.mat(METAL_OLD, 0.0, 0.5)
	for i in 4:
		var b := LowPoly.mesh_instance(LowPoly.blade(0.78, 0.07, 0.02), metal, root, Vector3(-0.6 + i * 0.4, 0.3, 0.05))
		b.rotation = Vector3(-PI / 2 - 0.12, 0, _rng.randf_range(-0.05, 0.05))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 1.3, 0.5)
	col.shape = shape
	col.position = Vector3(0, 0.65, 0)
	var sb := StaticBody3D.new()
	sb.collision_layer = Game.LAYER_WORLD
	sb.add_child(col)
	root.add_child(sb)


## Herabhängende Wurzeln an der Südwand.
func _hanging_roots(center: Vector3, spread: float, count: int) -> void:
	var mat := LowPoly.mat(ROOTWOOD.lightened(0.05))
	for i in count:
		var top := center + Vector3(_rng.randf_range(-spread, spread), WALL_H - 1.0, _rng.randf_range(-0.4, 0.3))
		var segs := _rng.randi_range(3, 5)
		var p := top
		var r := _rng.randf_range(0.08, 0.14)
		for k in segs:
			var l := _rng.randf_range(1.2, 2.4)
			var dir := Vector3(_rng.randf_range(-0.3, 0.3), -1.0, _rng.randf_range(-0.35, 0.1)).normalized()
			var mi := LowPoly.mesh_instance(LowPoly.prism(r * 0.75, r, l, 5), mat, _geo, p + dir * l * 0.5)
			mi.basis = Basis(Quaternion(Vector3.UP, -dir))
			p += dir * l
			r *= 0.75


## Tropfsteine hoch oben, an der Grenze dessen, was das Licht erreicht.
func _stalactites(center: Vector3, spread: float, height: float, count: int) -> void:
	for i in count:
		var h := _rng.randf_range(1.0, 3.5)
		var p := center + Vector3(_rng.randf_range(-spread, spread), height + _rng.randf_range(0.0, 3.0), _rng.randf_range(-spread, spread))
		var mi := LowPoly.mesh_instance(LowPoly.crystal(h, h * 0.16), LowPoly.mat(_vary(LowPoly.STONE)), _geo, p)
		mi.rotation = Vector3(PI + _rng.randf_range(-0.1, 0.1), _rng.randf() * TAU, 0)


func _vary(c: Color) -> Color:
	return c.darkened(_rng.randf_range(-0.06, 0.1))
