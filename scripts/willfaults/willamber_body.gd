class_name WillamberBody
extends Node3D
## Willamber: hageres Wesen aus wabernden Schatten mit leuchtenden Augen. Steigt aus einer Schattenlache,
## bewegt sich in schnellen, sprunghaften Stößen, schlägt mit langen Armen zu und taucht zur Verteidigung
## zurück in den Schatten. Zustände steuert der Schwarm (WillamberSwarm); hier nur Körper und Haltung.
## Animation von der Konzeptseite übernommen (willfaults3.js, buildWillamber).

const MODEL := "res://assets/models/willfaults/willamber.glb"
const WISP_COLOR := Color(0.015, 0.01, 0.03)

enum S { HIDDEN, RISE, LURK, DASH, STRIKE, SINK }

var state: S = S.HIDDEN
var state_t := 0.0  ## Restzeit des Zustands
var state_k := 0.0  ## vergangene Zeit im Zustand
var strike := 0.0
var yaw := 0.0
var face_yaw := 0.0  ## Blickrichtung, zu der gedreht wird
var index := 0
var rng := RandomNumberGenerator.new()

var _m: Dictionary
var j: Dictionary
var _rise: Node3D
var _pool: MeshInstance3D
var _halos: Array[MeshInstance3D] = []
var _wisps: CPUParticles3D
var _puff: CPUParticles3D
var _look := Vector2.ZERO
var _look_t := Vector2.ZERO
var _tw_t := 0.0
var _t := 0.0
var _prev_pos := Vector3.ZERO
var _strand_v := Vector2.ZERO


func _ready() -> void:
	_rise = Node3D.new()
	add_child(_rise)
	_m = WillfaultModel.spawn(MODEL, _rise)
	j = WillfaultModel.joints(_m.root)
	_build_pool()
	_build_eyes()
	_build_wisps()
	_prev_pos = global_position


func set_state(s: S, duration: float) -> void:
	state = s
	state_t = duration
	state_k = 0.0
	if s == S.LURK or s == S.RISE:
		_puff.restart()


func visible_amount() -> float:
	return 1.0 - _sink()


func _sink() -> float:
	match state:
		S.HIDDEN:
			return 1.0
		S.RISE:
			return 1.0 - WillfaultModel.ease_back(state_k / 0.45)
		S.SINK:
			return WillfaultModel.sm(state_k / 0.4)
	return 0.0


## Haltung für diesen Schritt. Zeit und Zustand zählt der Schwarm weiter.
func pose(delta: float) -> void:
	_t += delta
	var t := _t
	var sink := _sink()
	# Drehung schnappt fast sofort auf die neue Richtung
	yaw += angle_difference(yaw, face_yaw) * minf(1.0, delta * 18.0)
	(_m.root as Node3D).rotation.y = yaw
	# Kopf zuckt in kurzen, harten Sprüngen
	_tw_t -= delta
	if _tw_t <= 0.0:
		_tw_t = 0.1 + rng.randf() * 0.45
		_look_t = Vector2((rng.randf() - 0.5) * 0.9, (rng.randf() - 0.5) * 1.4)
	_look += (_look_t - _look) * minf(1.0, delta * 30.0)
	# Haltung: tief geduckt, Rücken stark gekrümmt, lange Arme hängen fast bis zum Boden
	var dashing := state == S.DASH
	var dash_lean := 0.35 if dashing else 0.0
	var cr := (0.65 + 0.1 * sin(t * 9.0 + index)) if state == S.LURK else 0.5
	var th_x := 0.7 + cr * 0.5
	var sh_x := -(1.3 + cr * 0.6)
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		WillfaultModel.rot(j["leg%s_th" % s], th_x + (0.4 * sin(t * 40.0 + sx) if dashing else 0.0), 0.0, sx * 0.12)
		WillfaultModel.rot(j["leg%s_sh" % s], sh_x, 0.0, 0.0)
		WillfaultModel.rot(j["leg%s_ft" % s], PI / 2.0 - (th_x + sh_x), 0.0, 0.0)
	(j["hips"] as Node3D).position.y = 0.26 * cos(th_x) + 0.28 * cos(th_x + sh_x) + 0.02
	WillfaultModel.rot(j["spine"], -1.05 - dash_lean - 0.25 * strike, 0.0, 0.06 * sin(t * 13.0 + index))
	WillfaultModel.rot(j["neck"], 0.85 + dash_lean + 0.2 * strike + _look.x * 0.4, _look.y * 0.5, 0.0)
	WillfaultModel.rot(j["head"], _look.x * 0.5, _look.y * 0.5, _look.y * 0.3)
	for s in ["L", "R"]:
		var sx := -1.0 if s == "L" else 1.0
		var swing := strike * (1.0 if sx > 0.0 else 0.7)
		WillfaultModel.rot(j["arm%s_up" % s], 0.95 + dash_lean - 2.4 * swing + 0.08 * sin(t * 17.0 + sx), 0.0, sx * (0.12 + 0.3 * swing))
		WillfaultModel.rot(j["arm%s_lo" % s], 0.35 + 0.9 * swing, 0.0, 0.0)
	# Schattenfäden schwingen der Bewegung nach
	var vel := (global_position - _prev_pos) / maxf(delta, 1e-4)
	_prev_pos = global_position
	var local_v := vel.rotated(Vector3.UP, -yaw)
	_strand_v = _strand_v.lerp(Vector2(local_v.z, -local_v.x) * 0.25, minf(1.0, delta * 8.0))
	for s in ["L", "R"]:
		WillfaultModel.rot(j["strand" + s], clampf(_strand_v.x, -1.2, 1.2) + 0.25 * sin(t * 7.0 + (1.0 if s == "L" else 2.0)), 0.0, clampf(_strand_v.y, -0.8, 0.8))
	# Auftauchen/Abtauchen: unter den Boden sinken, dabei gestaucht
	_rise.position.y = -0.85 * sink
	_rise.scale = Vector3(1.0 - 0.3 * sink, 1.0 + 0.25 * sink, 1.0 - 0.3 * sink)
	_pool.scale = Vector3.ONE * (0.45 + 0.65 * maxf(sink, 0.1 if state == S.LURK else 0.2))
	var vis := 1.0 - sink
	for h in _halos:
		h.scale = Vector3.ONE * (0.7 + 0.3 * sin(t * 6.0 + index)) * (1.6 if state == S.STRIKE else 1.0) * (1.0 if vis > 0.3 else 0.0)
	_wisps.emitting = vis > 0.5


func _build_pool() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := 22
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n
		var r := 0.32 * (0.72 + 0.4 * rng.randf())
		pts.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for i in n:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[(i + 1) % n])
		st.add_vertex(pts[i])
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0.92)
	m.render_priority = -2
	_pool = MeshInstance3D.new()
	_pool.mesh = st.commit()
	_pool.material_override = m
	_pool.position.y = 0.004
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)


## Lichthöfe um die leuchtenden Augen
func _build_eyes() -> void:
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.albedo_color = Color(0.79, 0.64, 1.0)
	halo_mat.albedo_texture = HollowOneBody._halo_tex()
	for mi: MeshInstance3D in (j["head"] as Node).find_children("*", "MeshInstance3D", true, false):
		var mat := mi.mesh.surface_get_material(0)
		if mat == null or mat.resource_name != "Eye":
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var h := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.11, 0.11)
		h.mesh = q
		h.material_override = halo_mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.get_parent().add_child(h)
		h.position = mi.position + Vector3(0, 0, -0.01)
		_halos.append(h)


## Schattenschwaden: steigen ständig vom Körper auf, beim Auftauchen ein Schwall
func _build_wisps() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex()
	m.render_priority = 1
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	q.material = m
	var ramp := Gradient.new()
	ramp.set_color(0, Color(WISP_COLOR, 0.0))
	ramp.add_point(0.18, Color(WISP_COLOR, 0.45))
	ramp.set_color(ramp.get_point_count() - 1, Color(WISP_COLOR, 0.0))
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.5))
	for k in 2:
		var p := CPUParticles3D.new()
		p.mesh = q
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.15, 0.28, 0.15)
		p.position = Vector3(0, 0.35, 0)
		p.direction = Vector3.UP
		p.spread = 25.0 if k == 0 else 80.0
		p.gravity = Vector3.ZERO
		p.damping_min = 0.3
		p.damping_max = 0.6
		p.color_ramp = ramp
		p.scale_amount_curve = grow
		if k == 0:
			p.amount = 45
			p.lifetime = 1.2
			p.initial_velocity_min = 0.12
			p.initial_velocity_max = 0.27
			_wisps = p
		else:
			p.amount = 14
			p.lifetime = 1.0
			p.one_shot = true
			p.explosiveness = 0.9
			p.emitting = false
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.6
			_puff = p
		_rise.add_child(p)


static var _soft: GradientTexture2D


static func _soft_tex() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(0.5, 0.0)
		_soft.width = 32
		_soft.height = 32
	return _soft
