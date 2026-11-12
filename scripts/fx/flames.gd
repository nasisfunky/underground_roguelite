class_name Flames
extends RefCounted
## Feuer nach dem Prinzip aus dem Shooter-Projekt (dort scripts/flames.gd):
##  - Flammenzungen: aufrechte Quads mit prozeduralen Flammen-Texturen (FxTex.flame), die sich
##    nur um ihre eigene Hochachse zur Kamera drehen, additiv, Farbverlauf über die Lebenszeit
##    (hell gelb-weiß beim Aufflammen, orange, zum Ende tiefrot)
##  - Kern: kurze weiß-gelbe Zungen tief im Feuer
##  - Glut: Funken und Ascheflocken, die im Aufwind wirbelnd aufsteigen und verglühen
##  - Rauch: dünne Säule aus denselben klumpigen Wolken wie bei den Explosionen
##  - Licht: flackert über zwei multiplizierte Sinuswellen, nie gleichmäßig
## fire() baut alles zusammen (Feuerschalen, später Fackel und brennende Gegner).

static var _flame_mats := {}
static var _quad: QuadMesh
static var _ember_quad: QuadMesh
static var _ember_mat: StandardMaterial3D


static func _mat(variant: int) -> StandardMaterial3D:
	if _flame_mats.has(variant):
		return _flame_mats[variant]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = FxTex.flame(variant)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.disable_fog = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_flame_mats[variant] = m
	return m


## count tongues of flame, size metres tall at most, rising from wherever the caller
## sets the emission shape (a point by default). Emitting is left to the caller.
static func emitter(variant: int, count: int, size: float) -> CPUParticles3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.78, 1.0)   # broad enough that the tongues run together into one fire
		_quad.center_offset = Vector3(0, 0.45, 0)   # rooted at the bottom, licking up
	var cp := CPUParticles3D.new()
	cp.mesh = _quad
	cp.material_override = _mat(variant % 4)
	cp.amount = count
	cp.lifetime = 0.55
	cp.randomness = 0.6
	cp.local_coords = false
	cp.direction = Vector3.UP
	cp.spread = 8.0
	cp.gravity = Vector3(0.25, 1.6, 0.1)   # licking up, leaning a little with the wind
	cp.initial_velocity_min = 0.25
	cp.initial_velocity_max = 0.75
	cp.angle_min = -12.0                   # not all standing straight: some lean, some twist
	cp.angle_max = 12.0
	cp.scale_amount_min = 0.55 * size
	cp.scale_amount_max = 1.2 * size
	cp.scale_amount_curve = Explosion._curve([Vector2(0.0, 0.35), Vector2(0.2, 1.0), Vector2(0.65, 0.75), Vector2(1.0, 0.1)])
	var g := Gradient.new()   # catching bright, burning orange, dying off deep red
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.8, 0.5, 0.0), Color(1.0, 0.72, 0.38, 0.95), Color(0.95, 0.46, 0.14, 0.75),
		Color(0.6, 0.16, 0.04, 0.35), Color(0.25, 0.05, 0.02, 0.0)])
	cp.color_ramp = g
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return cp


## The hot heart of a fire: short white-yellow tongues low down inside the others (rising
## from wherever the caller sets the emission shape). Emitting is left to the caller.
static func core(count: int, size: float) -> CPUParticles3D:
	var cp := emitter(2, count, size)
	cp.lifetime = 0.32
	cp.gravity = Vector3(0, 2.2, 0)
	cp.initial_velocity_min = 0.1
	cp.initial_velocity_max = 0.35
	cp.scale_amount_curve = Explosion._curve([Vector2(0.0, 0.5), Vector2(0.25, 1.0), Vector2(1.0, 0.2)])
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.75, 0.0), Color(1.0, 0.92, 0.65, 0.9), Color(1.0, 0.7, 0.3, 0.6), Color(0.8, 0.35, 0.08, 0.0)])
	cp.color_ramp = g
	return cp


## Sparks and glowing flecks of ash thrown up out of a fire, spinning off on the hot air
## and going out a metre or two up; spread: how wide the fire they rise from is.
static func embers(count: int, spread: float) -> CPUParticles3D:
	if _ember_quad == null:
		_ember_quad = QuadMesh.new()
		_ember_quad.size = Vector2(0.025, 0.025)
		_ember_mat = StandardMaterial3D.new()
		_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ember_mat.vertex_color_use_as_albedo = true
		_ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_ember_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_ember_mat.disable_fog = false
	var cp := CPUParticles3D.new()
	cp.mesh = _ember_quad
	cp.material_override = _ember_mat
	cp.amount = count
	cp.lifetime = 1.6
	cp.randomness = 0.8
	cp.explosiveness = 0.1
	cp.local_coords = false
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cp.emission_sphere_radius = maxf(spread, 0.05)
	cp.direction = Vector3.UP
	cp.spread = 25.0
	cp.initial_velocity_min = 0.6
	cp.initial_velocity_max = 2.0
	cp.gravity = Vector3(0.3, 0.9, 0.1)   # the hot air carries them up and off with the wind
	cp.damping_min = 0.3
	cp.damping_max = 0.8
	cp.tangential_accel_min = -1.5           # swirling as they go
	cp.tangential_accel_max = 1.5
	cp.scale_amount_min = 0.6
	cp.scale_amount_max = 1.6
	cp.scale_amount_curve = Explosion._curve([Vector2(0.0, 1.0), Vector2(0.7, 0.8), Vector2(1.0, 0.0)])
	var g := Gradient.new()   # white-hot, orange, a dull red spark going out
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.6, 0.2, 1.0), Color(0.8, 0.22, 0.05, 0.8), Color(0.3, 0.05, 0.0, 0.0)])
	cp.color_ramp = g
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return cp


## A thin column of dark smoke rolling up from a fire, size the width of its clouds.
static func smoke(count: int, size: float) -> CPUParticles3D:
	Explosion._init_materials()
	var cp := CPUParticles3D.new()
	cp.mesh = Explosion._cloud_mesh
	cp.material_override = Explosion._smoke_mat
	cp.amount = count
	cp.lifetime = 4.0
	cp.randomness = 0.5
	cp.local_coords = false
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cp.emission_sphere_radius = 0.25 * size
	cp.direction = Vector3.UP
	cp.spread = 12.0
	cp.initial_velocity_min = 0.5
	cp.initial_velocity_max = 0.9
	cp.damping_min = 0.1
	cp.damping_max = 0.3
	cp.gravity = Vector3(0.18, 0.35, 0.06)   # rising, drawn off by the wind
	cp.scale_amount_min = 0.35 * size
	cp.scale_amount_max = 0.6 * size
	cp.scale_amount_curve = Explosion._curve([Vector2(0.0, 0.4), Vector2(0.3, 1.0), Vector2(1.0, 2.4)])
	var g := Gradient.new()   # no glow from inside (age starts past the ember), thin
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(0.2, 0.2, 0.2, 0.0), Color(0.4, 0.4, 0.4, 0.7), Color(1, 1, 1, 0)])
	cp.color_ramp = g
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return cp


## Ein komplettes Feuer an pos: zwei Zungen-Varianten, Kern, Glut, Rauch und flackerndes Licht.
## size ~1 = Feuerschale. Gibt den Wurzelknoten zurück (enthält das Licht als "Light").
static func fire(parent: Node, pos: Vector3, size := 1.0, with_smoke := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	parent.add_child(root)
	root.position = pos
	for v in 2:
		var cp := emitter(v, int(14 * size) + 6, 0.55 * size)
		cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		cp.emission_sphere_radius = 0.22 * size
		root.add_child(cp)
		cp.emitting = true
	var hot := core(int(8 * size) + 4, 0.38 * size)
	hot.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	hot.emission_sphere_radius = 0.12 * size
	root.add_child(hot)
	hot.emitting = true
	var sparks := embers(int(10 * size) + 4, 0.25 * size)
	sparks.position = Vector3(0, 0.3 * size, 0)
	root.add_child(sparks)
	sparks.emitting = true
	if with_smoke:
		var sm := smoke(int(6 * size) + 3, 0.9 * size)
		sm.position = Vector3(0, 0.9 * size, 0)
		root.add_child(sm)
		sm.emitting = true
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.52, 0.2)
	light.omni_range = 9.0 * size
	light.omni_attenuation = 1.2
	light.light_energy = 2.4 * size
	light.light_volumetric_fog_energy = 2.0
	light.shadow_enabled = true
	light.shadow_blur = 2.0
	light.position = Vector3(0, 0.6 * size, 0)
	light.add_to_group("light_sources")
	root.add_child(light)
	var flick := _Flicker.new()
	flick.light = light
	flick.base = light.light_energy
	root.add_child(flick)
	return root


## Flackern wie im Shooter: Produkt zweier Sinuswellen mit krummen Frequenzen.
class _Flicker extends Node:
	var light: OmniLight3D
	var base := 1.0
	var _t := randf() * 10.0

	func _process(delta: float) -> void:
		_t += delta
		light.light_energy = base * (0.78 + 0.22 * sin(_t * 19.0) * sin(_t * 6.1) + 0.06 * sin(_t * 41.0))
