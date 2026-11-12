class_name WaterVolume
extends Node3D
## Wasserbecken: Oberfläche (Cel-Shader im Wind-Waker-Stil) + Volumen für das Schwimmen.
## Kein Tauchen: der Spieler fragt nur die Wasserhöhe ab (surface_at) und treibt an der Oberfläche.

const SHADER := preload("res://assets/shaders/water_toon.gdshader")

var size := Vector2(10, 10)  ## Ausdehnung der Oberfläche (x, z)
var depth := 3.0  ## Tiefe des Volumens unter der Oberfläche
var surface: MeshInstance3D


func _ready() -> void:
	add_to_group("water")
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = int(size.x * 2.0)
	pm.subdivide_depth = int(size.y * 2.0)
	surface = MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = SHADER
	surface.material_override = m
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)


## Liegt pos (Welt) in diesem Becken? Dann Höhe der Oberfläche, sonst NAN.
func surface_if_inside(pos: Vector3) -> float:
	var l := global_transform.affine_inverse() * pos
	if absf(l.x) > size.x * 0.5 or absf(l.z) > size.y * 0.5:
		return NAN
	if l.y > 2.5 or l.y < -depth:
		return NAN
	return global_position.y


## Wasseroberfläche über/unter pos oder NAN, wenn dort kein Wasser ist.
static func surface_at(tree: SceneTree, pos: Vector3) -> float:
	for w in tree.get_nodes_in_group("water"):
		var y: float = (w as WaterVolume).surface_if_inside(pos)
		if not is_nan(y):
			return y
	return NAN
