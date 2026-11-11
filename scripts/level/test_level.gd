extends Node3D
## Testlevel mit drei Räumen, komplett per Code aus Low-Poly-Formen gebaut.
##
##  Raum 1 "Säulenhalle"      – Laufen, Springen, Rampe, Plattform-Parcours
##  Raum 2 "Übungshof"        – Trainingspuppen für Auto-Angriff und Fähigkeiten
##  Raum 3 "Sealed Hall"      – Hollow Shades, die zurückschlagen (Blocken, Parieren, Rollen)
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
	_spawn_player(Vector3(0, 0.1, 9), 0.0)


# ==================================================================
# Umgebung
# ==================================================================

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.12, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.36, 0.56, 0.56)
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.fog_enabled = true
	e.fog_light_color = Color(0.17, 0.29, 0.30)
	e.fog_light_energy = 1.0
	e.fog_density = 0.016
	e.fog_aerial_perspective = 0.25
	e.fog_sky_affect = 1.0
	e.fog_height = 6.0
	e.fog_height_density = 0.05
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_strength = 1.0
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 0.9
	e.ssao_enabled = true
	e.ssao_radius = 1.6
	e.ssao_intensity = 2.2
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.012
	e.volumetric_fog_albedo = Color(0.55, 0.78, 0.78)
	e.volumetric_fog_length = 60.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.05
	e.adjustment_contrast = 1.05
	we.environment = e
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(28), 0)
	sun.light_color = Color(0.78, 0.96, 0.95)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


# ==================================================================
# Räume
# ==================================================================

func _build_room_hall() -> void:
	var c := Vector3(0, 0, 0)
	_room_shell(c, Vector2(26, 26), [Vector2(0, 6)], [], "Hall of Pillars")
	# Monumentale Säulen
	for z in [6.0, -1.0, -8.0]:
		for x in [-6.5, 6.5]:
			if x > 0 and z == -1.0:
				continue  # Platz für den Parcours
			_pillar(Vector3(x, 0, z), 1.0, WALL_H + 2.0, 5)
	# Sprungparcours (Osten)
	_block(Vector3(9.0, 0.3, 4.0), Vector3(2.6, 0.6, 2.6), LowPoly.STONE_LIGHT)
	_block(Vector3(9.5, 0.6, 0.5), Vector3(2.6, 1.2, 2.6), LowPoly.STONE_LIGHT)
	_block(Vector3(9.5, 0.95, -3.2), Vector3(2.6, 1.9, 2.6), LowPoly.STONE_LIGHT)
	_block(Vector3(4.6, 0.95, -6.8), Vector3(3.0, 1.9, 3.0), LowPoly.STONE_LIGHT)  # über eine Lücke
	_crystal_cluster(Vector3(4.6, 1.9, -6.8), 0.8, false)
	# Rampe hoch zu einem Absatz (Westen)
	_ramp(Vector3(-9.5, 0, 6.0), Vector3(-9.5, 2.2, -0.5), 3.4)
	_block(Vector3(-9.5, 1.1, -3.5), Vector3(4.5, 2.2, 6.0), LowPoly.STONE_LIGHT)
	_brazier(Vector3(-9.5, 2.2, -5.0))
	# Deko: Geröll, Splitter
	for i in 7:
		var p := Vector3(_rng.randf_range(-11, 11), 0, _rng.randf_range(-11, 11))
		if absf(p.x) < 3.5 or (p.x > 6.0 and p.z < 6.0) or (p.x < -7.0 and p.z < 7.0):
			continue
		_rock(p + Vector3(0, 0.15, 0), _rng.randf_range(0.3, 0.7), false)
	_floating_shards(c + Vector3(0, 10, 0), 12, 11.0)
	_crystal_cluster(Vector3(-11.5, 0, 11.5), 1.2)
	_crystal_cluster(Vector3(11.5, 0, 11.5), 1.0)


func _build_room_training() -> void:
	var c := Vector3(0, 0, -34)
	_room_shell(c, Vector2(26, 24), [Vector2(0, 6)], [Vector2(0, 6)], "Training Yard")
	for x in [-4.5, 0.0, 4.5]:
		var d := TrainingDummy.new()
		d.position = Vector3(x, 0.05, -34.0 - (1.5 if x == 0.0 else 0.0))
		d.rotation.y = PI
		add_child(d)
	for z in [-27.0, -41.0]:
		for x in [-9.0, 9.0]:
			_brazier(Vector3(x, 0, z))
	for p in [Vector3(-11, 0, -24), Vector3(11, 0, -24), Vector3(-11, 0, -44), Vector3(11, 0, -44)]:
		_pillar(p, 1.1, WALL_H + 2.0, 6)
	for i in 6:
		_rock(Vector3(_rng.randf_range(-11, 11), 0.15, _rng.randf_range(-44, -24)) * Vector3(1, 1, 1), _rng.randf_range(0.25, 0.5), false)
	_floating_shards(c + Vector3(0, 11, 0), 9, 9.0)


func _build_ramp_corridor() -> void:
	# Abstieg: z -46 .. -59, y 0 .. -3
	var w := 6.0
	_ramp(Vector3(0, 0, -46.0), Vector3(0, -3.0, -59.0), w)
	for side in [-1.0, 1.0]:
		_block(Vector3(side * (w * 0.5 + 1.0), -1.5 + 4.0, -52.5), Vector3(2.0, 11.0, 13.0), LowPoly.STONE)
		for z in [-48.5, -52.5, -56.5]:
			_rock(Vector3(side * (w * 0.5 - 0.1), -3.0 + (z + 59.0) * 3.0 / 13.0 + 0.3, z), 0.6, true)
	_lamp(Vector3(0, 4.5, -52.5))
	_block(Vector3(0, 8.5, -52.5), Vector3(w + 4.0, 1.5, 13.0), LowPoly.STONE_DARK)  # Decke -> Tunnelgefühl


func _build_room_sealed() -> void:
	var y := -3.0
	var c := Vector3(0, y, -76)
	_room_shell(c, Vector2(34, 34), [], [Vector2(0, 6)], "Sealed Hall")
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
	var seam := LowPoly.mesh_instance(LowPoly.box(Vector3(0.08, 7.0, 0.95)), LowPoly.mat(LowPoly.CYAN, 5.0), _geo, Vector3(0, y + 3.5, gz))
	seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light(Vector3(0, y + 3.0, gz + 2.0), LowPoly.CYAN, 2.5, 10.0)
	_block(Vector3(0, y + 0.2, gz + 2.0), Vector3(7.0, 0.4, 2.0), LowPoly.STONE_LIGHT)
	_block(Vector3(0, y + 0.1, gz + 3.4), Vector3(8.5, 0.2, 1.2), LowPoly.STONE_LIGHT.darkened(0.1))
	# Säulen und Kristallschalen
	for z in [-66.0, -76.0]:
		for x in [-11.0, 11.0]:
			_pillar(Vector3(x, y, z), 1.1, WALL_H + 2.0, 5)
	for x in [-6.0, 6.0]:
		_brazier(Vector3(x, y, -82.0))
	_light(Vector3(0, y + 3.0, -72.0), Color(1.0, 0.6, 0.3), 1.2, 14.0)
	for i in 8:
		_rock(Vector3(_rng.randf_range(-15, 15), y + 0.2, _rng.randf_range(-92, -61)), _rng.randf_range(0.3, 0.9), false)
	_floating_shards(c + Vector3(0, 12, -4), 16, 13.0)
	# Gegner
	for p in [Vector3(-5, y + 0.1, -72), Vector3(5, y + 0.1, -74), Vector3(0, y + 0.1, -80)]:
		_spawn_husk(Transform3D(Basis(Vector3.UP, 0.0), p))


func _spawn_husk(xf: Transform3D) -> void:
	var h := Husk.new()
	h.transform = xf
	h.respawn_requested.connect(func(_old): get_tree().create_timer(2.0).timeout.connect(func(): _spawn_husk(xf)))
	add_child(h)


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
func _room_shell(c: Vector3, size: Vector2, south_open: Array, north_open: Array, room_name: String) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_slab_floor(Vector2(c.x - hx, c.z - hz), Vector2(c.x + hx, c.z + hz), c.y)
	_wall_x(c.z + hz + 1.0, c.x - hx - 2.0, c.x + hx + 2.0, c.y, south_open)
	_wall_x(c.z - hz - 1.0, c.x - hx - 2.0, c.x + hx + 2.0, c.y, north_open)
	for side in [-1.0, 1.0]:
		var x: float = c.x + side * (hx + 1.0)
		_block(Vector3(x, c.y + WALL_H * 0.5, c.z), Vector3(2.0, WALL_H, size.y), LowPoly.STONE)
		# Wandpfeiler für die monumentale Silhouette
		var n := int(size.y / 5.0)
		for i in n + 1:
			var z: float = c.z - hz + size.y * float(i) / n
			_block(Vector3(x - side * 0.6, c.y + WALL_H * 0.5, z), Vector3(1.4, WALL_H, 1.4), LowPoly.STONE_DARK)
		for i in 4:
			_rock(Vector3(x - side * 1.0, c.y + 0.2, c.z + _rng.randf_range(-hz, hz)), _rng.randf_range(0.5, 1.1), true)
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
	_lamp(Vector3(mid.x, from.y + height - 1.6, mid.z))


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
	var rune := LowPoly.mesh_instance(LowPoly.box(Vector3(0.12, 0.5, 0.05)), LowPoly.mat(LowPoly.CYAN, 2.5), sb, Vector3(0, 2.2, -radius * 0.92))
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


func _brazier(base: Vector3) -> void:
	_block(base + Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.9), LowPoly.STONE_DARK)
	var bowl := LowPoly.mesh_instance(LowPoly.prism(0.35, 1.0, 0.35, 8), LowPoly.mat(LowPoly.OCHRE.darkened(0.1)), _geo, base + Vector3(0, 1.17, 0))
	bowl.rotation.y = PI / 8
	_crystal_cluster(base + Vector3(0, 1.3, 0), 0.9)


func _lamp(pos: Vector3) -> void:
	var cage := LowPoly.mesh_instance(LowPoly.prism(0.32, 0.22, 0.7, 4), LowPoly.mat(Color(0.12, 0.16, 0.17)), _geo, pos)
	cage.rotation.y = PI / 4
	var core := LowPoly.mesh_instance(LowPoly.crystal(0.6, 0.12), LowPoly.mat(LowPoly.CYAN, 5.0), _geo, pos + Vector3(0, -0.3, 0))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	LowPoly.mesh_instance(LowPoly.box(Vector3(0.06, 3.0, 0.06)), LowPoly.mat(Color(0.1, 0.12, 0.12)), _geo, pos + Vector3(0, 1.8, 0))
	_light(pos + Vector3(0, -0.5, 0), LowPoly.CYAN, 2.5, 10.0)


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


func _vary(c: Color) -> Color:
	return c.darkened(_rng.randf_range(-0.06, 0.1))
