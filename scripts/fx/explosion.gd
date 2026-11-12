class_name Explosion
extends Node3D
## Explosion nach dem Prinzip aus dem Shooter-Projekt (dort scripts/explosion.gd, Technik
## nach Le Lu, "Godot 4 - Explosion 3D for beginners"). Zeitlich gestaffelte Schichten:
##   0.00  Blitz: weißer Kern (ein Quad, 60 ms) und ein harter Lichtstoß, der abklingt
##   0.00  Feuerball: Low-Poly-Kugeln, im Shader per 3D-Rauschen entlang der Normalen
##         ausgebeult (Blumenkohl statt Ball). Farbe aus einer Hitze-Rampe: jung und tief im
##         Rauschen weiß-gelb, kühlt über Orange und Rot zu schwarzem Rauch ab; eine sterbende
##         Wolke frisst sich durch dasselbe Rauschen weg, statt auszublenden
##   0.00  Funkenstreifen: dünne, weißglühende Quads, entlang ihrer Flugbahn gestreckt
##   0.03  Gesteinssplitter, ein Staubring, der über den Boden läuft, ein Brandfleck, der bleibt
##   0.06  Rauchsäule rollt nach dem Feuer hoch
## Farben werden gestuft (floor(c * 10) / 10), damit die Wolken zu den harten Facetten passen.
## spawn() gibt den Knoten zurück; er räumt sich selbst weg, wenn der Rauch fort ist.

const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, blend_mix, depth_draw_never;

uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float displace = 0.6;
uniform float freq = 2.8;
uniform float glow = 1.3;

varying vec3 v_p;
varying float v_n;
varying float v_age;
varying float v_dens;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.03 + 11.0) * 0.3 + vnoise(p * 4.1 + 23.0) * 0.1;
}

// pushes the vertex out along its normal by the noise and tilts the normal to match
// the lumps, so the light shows them
void lump(inout vec3 v, inout vec3 n, vec3 off, float h0) {
	vec3 t = normalize(cross(n, abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 b = cross(n, t);
	float e = 0.06;
	float h1 = fbm((v + t * e) * freq + off);
	float h2 = fbm((v + b * e) * freq + off);
	vec3 p0 = v + n * (h0 - 0.45) * displace;
	vec3 p1 = v + t * e + n * (h1 - 0.45) * displace;
	vec3 p2 = v + b * e + n * (h2 - 0.45) * displace;
	vec3 m = normalize(cross(p1 - p0, p2 - p0));
	n = dot(m, n) < 0.0 ? -m : m;
	v = p0;
}


void vertex() {
	// the particle colour carries its age (r) and how much of it is left (a)
	v_age = COLOR.r;
	v_dens = COLOR.a;
	float id = float(INSTANCE_ID);
	vec3 off = vec3(id * 7.13, id * 3.71, id * 1.37) - vec3(0.0, TIME * 0.55, 0.0);
	v_p = VERTEX * freq + off;
	v_n = fbm(v_p);
	lump(VERTEX, NORMAL, off, v_n);
}

void fragment() {
	float d2 = fbm(v_p * 2.2 + 5.0);
	float heat = clamp(1.05 - v_age * 2.1 + (v_n - 0.5) * 1.3 + (d2 - 0.5) * 0.6, 0.0, 1.0);
	vec3 c = texture(ramp, vec2(1.0 - heat, 0.5)).rgb;
	// rounder: the rim of each lump darker than its face
	c *= mix(0.4, 1.0, clamp(dot(NORMAL, VIEW), 0.0, 1.0));
	c *= 1.0 + glow * heat * heat;
	ALBEDO = floor(c * 10.0 + 0.5) / 10.0;   // stepped like the 15-bit textures
	// see-through where it thins out (its edges, and as it burns away); blended, since
	// a dither pattern showed as a raster over the clouds
	float cover = d2 * 0.55 + v_n * 0.45 - (1.0 - v_dens);
	ALPHA = clamp(cover * 3.5, 0.0, 1.0) * smoothstep(0.02, 0.4, dot(NORMAL, VIEW));
}
"""

## The same clouds as smoke: lit by the lanterns and the fire under it, grey-black,
## glowing from inside for a moment at first.
const SMOKE_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, blend_mix, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.13, 0.11, 0.095, 1.0);
uniform vec4 ember : source_color = vec4(1.0, 0.42, 0.12, 1.0);
uniform float displace = 0.75;
uniform float freq = 2.8;

varying vec3 v_p;
varying float v_n;
varying float v_age;
varying float v_dens;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.03 + 11.0) * 0.3 + vnoise(p * 4.1 + 23.0) * 0.1;
}

// pushes the vertex out along its normal by the noise and tilts the normal to match
// the lumps, so the light shows them
void lump(inout vec3 v, inout vec3 n, vec3 off, float h0) {
	vec3 t = normalize(cross(n, abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 b = cross(n, t);
	float e = 0.06;
	float h1 = fbm((v + t * e) * freq + off);
	float h2 = fbm((v + b * e) * freq + off);
	vec3 p0 = v + n * (h0 - 0.45) * displace;
	vec3 p1 = v + t * e + n * (h1 - 0.45) * displace;
	vec3 p2 = v + b * e + n * (h2 - 0.45) * displace;
	vec3 m = normalize(cross(p1 - p0, p2 - p0));
	n = dot(m, n) < 0.0 ? -m : m;
	v = p0;
}


void vertex() {
	v_age = COLOR.r;
	v_dens = COLOR.a;
	float id = float(INSTANCE_ID);
	vec3 off = vec3(id * 5.3, id * 2.9, id * 4.1) - vec3(0.0, TIME * 0.3, 0.0);
	v_p = VERTEX * freq + off;
	v_n = fbm(v_p);
	lump(VERTEX, NORMAL, off, v_n);
}

void fragment() {
	float d2 = fbm(v_p * 2.0 + 3.0);
	ALBEDO = tint.rgb * floor((0.6 + v_n * 0.8) * 6.0 + 0.5) / 6.0;
	ROUGHNESS = 1.0;
	EMISSION = ember.rgb * max(0.0, 0.1 - v_age) * 14.0 * clamp(1.0 - v_n * 1.3, 0.0, 1.0);
	float cover = d2 * 0.5 + v_n * 0.5 - (1.0 - v_dens);
	ALPHA = clamp(cover * 2.5, 0.0, 0.9) * smoothstep(0.0, 0.55, dot(NORMAL, VIEW));
}
"""

## Sparks drawn as quads stretched along their own flight (the particle's Y axis, set by
## align_y) and turned to face the camera round that axis.
const STREAK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, fog_disabled, depth_draw_never;

uniform sampler2D tex : source_color, filter_nearest;
uniform float boost = 1.6;

void vertex() {
	vec3 ax = MODEL_MATRIX[1].xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 side = cross(normalize(ax), to_cam);
	side = (length(side) < 0.001 ? vec3(1.0, 0.0, 0.0) : normalize(side)) * length(MODEL_MATRIX[0].xyz);
	vec3 world = origin + side * VERTEX.x + ax * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * boost;
	ALPHA = t.a * COLOR.a;
}
"""

static var _fire_mat: ShaderMaterial
static var _smoke_mat: ShaderMaterial
static var _streak_mat: ShaderMaterial
static var _cloud_mesh: SphereMesh
static var _ring_mat: StandardMaterial3D
static var _scorch_mat: StandardMaterial3D
static var _core_mat: StandardMaterial3D


## A blast at pos. size 1 is a demolition charge; mines are about 0.8, the bombs 1.5.
## dirt: thrown up out of the ground (mines, bombs, charges in the mud).
static func spawn(parent: Node, pos: Vector3, size := 1.0, debris := true) -> Explosion:
	_init_materials()
	var e := Explosion.new()
	parent.add_child(e)
	e.global_position = pos
	e._go(size, debris)
	return e


static func _init_materials() -> void:
	if _fire_mat:
		return
	var sh := Shader.new()
	sh.code = FIRE_SHADER
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = sh
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.4, 0.6, 0.78, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.86, 0.6), Color(0.95, 0.6, 0.26), Color(0.78, 0.32, 0.1),
		Color(0.36, 0.12, 0.05), Color(0.11, 0.075, 0.055), Color(0.05, 0.042, 0.036)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 64
	_fire_mat.set_shader_parameter("ramp", gt)
	var ss := Shader.new()
	ss.code = SMOKE_SHADER
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = ss
	var st := Shader.new()
	st.code = STREAK_SHADER
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = st
	_streak_mat.set_shader_parameter("tex", FxTex.streak())
	_cloud_mesh = SphereMesh.new()
	_cloud_mesh.radius = 0.5
	_cloud_mesh.height = 1.0
	_cloud_mesh.radial_segments = 16
	_cloud_mesh.rings = 10
	_ring_mat = _flat_mat(FxTex.ring(), Color(0.42, 0.37, 0.31, 0.8))
	_scorch_mat = _flat_mat(FxTex.scorch(), Color(1, 1, 1, 1))
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_core_mat.albedo_texture = FxTex.puff()
	_core_mat.albedo_color = Color(0.9, 0.7, 0.45)
	_core_mat.disable_fog = true
	_core_mat.no_depth_test = false


static func _flat_mat(tex: Texture2D, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Age in r, what is left in a: the clouds' shaders read both.
static func _life_ramp(hold: float) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, hold, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 1), Color(hold, hold, hold, 0.92), Color(1, 1, 1, 0)])
	return g


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	for p: Vector2 in points:
		c.add_point(p)
	return c


func _go(size: float, dirt: bool) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var pos := global_position
	var ground := _ground_under(pos)
	# 0.00  the flash: a white core, a hard burst of light
	var core := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 2.4 * size
	core.mesh = q
	core.material_override = _core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	core.position = Vector3(0, 0.5 * size, 0)
	var ct := core.create_tween()
	ct.tween_property(core, "scale", Vector3.ONE * 1.5, 0.06)
	ct.tween_callback(core.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.36)
	light.omni_range = 18.0 * size
	light.omni_attenuation = 1.4
	light.light_energy = 26.0 * size
	light.position = Vector3(0, 0.9 * size, 0)
	light.shadow_enabled = true
	light.add_to_group("light_sources")
	add_child(light)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 5.0 * size, 0.1)
	lt.tween_property(light, "light_color", Color(1.0, 0.45, 0.18), 0.3)
	lt.parallel().tween_property(light, "light_energy", 1.5 * size, 0.5)
	lt.tween_property(light, "light_energy", 0.0, 0.5)
	# 0.00  the fireball and the white-hot streaks thrown out of it
	_fireball(size)
	_streaks(size)
	# 0.03  Gesteinssplitter fliegen, ein Staubring läuft über den Boden
	if dirt:
		_debris(size)
	if not ground.is_empty() and (ground.position as Vector3).distance_to(pos) < 2.5 * size:
		_ring(ground.position + ground.normal * 0.05, ground.normal, size)
		_scorch(ground.position + ground.normal * 0.025, ground.normal, size)
	# 0.06  die Rauchsäule rollt nach dem Feuer hoch
	get_tree().create_timer(0.06).timeout.connect(_smoke.bind(size))
	var cam := get_viewport().get_camera_3d()
	if cam:
		var near := 1.0 - cam.global_position.distance_to(pos) / (12.0 * size)
		if near > 0.0 and cam.get_parent() and cam.get_parent().get_parent() is PlayerCamera:
			(cam.get_parent().get_parent() as PlayerCamera).add_trauma(0.6 * near)
	get_tree().create_timer(7.5).timeout.connect(queue_free)


func _ground_under(pos: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.6, 0), pos + Vector3(0, -2.5, 0), Game.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _clouds(mat: Material, amount: int, life: float, hold: float) -> CPUParticles3D:
	var cp := CPUParticles3D.new()
	cp.mesh = _cloud_mesh
	cp.material_override = mat
	cp.amount = amount
	cp.lifetime = life
	cp.one_shot = true
	cp.explosiveness = 0.95
	cp.randomness = 0.4
	cp.local_coords = false
	cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	cp.direction = Vector3.UP
	cp.color_ramp = _life_ramp(hold)
	cp.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH   # see-through clouds drawn back to front
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cp)
	return cp


func _fireball(size: float) -> void:
	var cp := _clouds(_fire_mat, int(10 * clampf(size, 0.7, 1.6)), 1.0, 0.4)
	cp.emission_sphere_radius = 0.35 * size
	cp.spread = 80.0
	cp.initial_velocity_min = 1.5 * size
	cp.initial_velocity_max = 6.0 * size
	cp.damping_min = 3.5
	cp.damping_max = 6.0
	cp.gravity = Vector3(0, 1.6, 0)    # hot air rises
	cp.scale_amount_min = 0.75 * size
	cp.scale_amount_max = 1.35 * size
	cp.scale_amount_curve = _curve([Vector2(0.0, 0.3), Vector2(0.12, 1.0), Vector2(1.0, 1.6)])
	cp.emitting = true
	# a second, smaller burst a breath later keeps it boiling
	var late := _clouds(_fire_mat, 4, 0.8, 0.35)
	late.emission_sphere_radius = 0.5 * size
	late.spread = 50.0
	late.initial_velocity_min = 1.0 * size
	late.initial_velocity_max = 3.0 * size
	late.damping_min = 2.0
	late.damping_max = 4.0
	late.gravity = Vector3(0, 2.5, 0)
	late.scale_amount_min = 0.5 * size
	late.scale_amount_max = 0.9 * size
	late.scale_amount_curve = _curve([Vector2(0.0, 0.4), Vector2(0.2, 1.0), Vector2(1.0, 1.4)])
	late.position = Vector3(0, 0.6 * size, 0)
	get_tree().create_timer(0.08).timeout.connect(func() -> void: late.emitting = true)


func _smoke(size: float) -> void:
	var cp := _clouds(_smoke_mat, int(26 * clampf(size, 0.7, 1.6)), 6.0, 0.5)
	cp.position = Vector3(0, 0.5 * size, 0)
	cp.emission_sphere_radius = 0.6 * size
	cp.spread = 45.0
	cp.explosiveness = 0.8
	cp.initial_velocity_min = 0.6 * size
	cp.initial_velocity_max = 2.4 * size
	cp.damping_min = 0.8
	cp.damping_max = 1.6
	cp.gravity = Vector3(0.25, 0.7, 0.1)   # rising, drifting off a little in the wind
	cp.scale_amount_min = 0.8 * size
	cp.scale_amount_max = 1.4 * size
	cp.scale_amount_curve = _curve([Vector2(0.0, 0.5), Vector2(0.3, 1.1), Vector2(1.0, 2.6)])
	cp.emitting = true


func _streaks(size: float) -> void:
	var cp := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.8)
	cp.mesh = q
	cp.material_override = _streak_mat
	cp.amount = int(16 * size)
	cp.lifetime = 0.45
	cp.one_shot = true
	cp.explosiveness = 1.0
	cp.randomness = 0.5
	cp.local_coords = false
	cp.particle_flag_align_y = true
	cp.direction = Vector3.UP
	cp.spread = 95.0
	cp.initial_velocity_min = 14.0 * size
	cp.initial_velocity_max = 30.0 * size
	cp.damping_min = 25.0
	cp.damping_max = 45.0
	cp.gravity = Vector3(0, -6.0, 0)
	cp.scale_amount_min = 0.6 * size
	cp.scale_amount_max = 1.3 * size
	cp.scale_amount_curve = _curve([Vector2(0.0, 1.0), Vector2(0.5, 0.7), Vector2(1.0, 0.0)])
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.85, 0.6, 1), Color(0.9, 0.5, 0.2, 0.85), Color(0.6, 0.2, 0.05, 0.0)])
	cp.color_ramp = g
	cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cp)
	cp.position = Vector3(0, 0.25, 0)
	cp.emitting = true


func _ring(at: Vector3, nrm: Vector3, size: float) -> void:
	var mi := _flat(_ring_mat.duplicate() as StandardMaterial3D, at, nrm, 1.0)
	var m := mi.material_override as StandardMaterial3D
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 8.0 * size, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.6)


## The burnt patch stays a while after the smoke has gone: it outlives this node.
func _scorch(at: Vector3, nrm: Vector3, size: float) -> void:
	var mi := _flat(_scorch_mat.duplicate() as StandardMaterial3D, at, nrm, 2.8 * size)
	mi.reparent(get_parent())
	var m := mi.material_override as StandardMaterial3D
	var tw := mi.create_tween()
	tw.tween_interval(40.0)
	tw.tween_property(m, "albedo_color:a", 0.0, 6.0)
	tw.tween_callback(mi.queue_free)


func _flat(mat: StandardMaterial3D, at: Vector3, nrm: Vector3, scale_k: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var up := nrm.normalized()
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x, up, x.cross(up)).rotated(up, randf() * TAU), at)
	mi.scale = Vector3.ONE * scale_k
	return mi


## Kantige Felssplitter (passend zum Low-Poly-Look) fliegen in einem Bogen davon.
func _debris(size: float) -> void:
	var cp := CPUParticles3D.new()
	cp.mesh = LowPoly.rock(0.07, 7, 4, 3, 0.4)
	cp.material_override = LowPoly.mat(LowPoly.STONE.lerp(LowPoly.STONE_LIGHT, 0.3))
	cp.amount = int(22 * size)
	cp.lifetime = 1.4
	cp.one_shot = true
	cp.explosiveness = 0.95
	cp.randomness = 0.5
	cp.local_coords = false
	cp.direction = Vector3.UP
	cp.spread = 70.0
	cp.initial_velocity_min = 3.0 * size
	cp.initial_velocity_max = 8.0 * size
	cp.gravity = Vector3(0, -16.0, 0)
	cp.angular_velocity_min = -400.0
	cp.angular_velocity_max = 400.0
	cp.scale_amount_min = 0.6 * size
	cp.scale_amount_max = 1.8 * size
	add_child(cp)
	cp.position = Vector3(0, 0.2, 0)
	cp.emitting = true
