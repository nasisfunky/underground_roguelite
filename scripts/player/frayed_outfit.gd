class_name FrayedOutfit
extends RefCounted
## Lädt die Kultur-Ausrüstungen der Frayed-Shades (assets/models/shade_<kultur>.glb + data/outfits/<kultur>.json).
## Die Modelle stammen aus der Konzeptseite "Frayed Cultures" (Export-Skript tools/frayed_export).
## GLB-Inhalt: S_<gelenk> = schwarzer Körper mit Flammenmaske (Vertex-Farbe a), G_<gelenk> = Ausrüstung,
## HeadHem = Kopfhülle mit Frisur, Weapon/Shield/Offhand = gehaltene Teile, C<n>_* = Stoffteile.

const CULTURES: Array[String] = ["kiln", "rimefall", "glowmire"]
const DISPLAY := {"kiln": "The Kiln", "rimefall": "Rimefall", "glowmire": "Glowmire"}
const HEM_SHADER := preload("res://assets/shaders/frayed_hem.gdshader")

static var _cache: Dictionary = {}


## {info: Dictionary, parts: Dictionary(Name -> Mesh), has_hem: Dictionary(Name -> bool)}
static func get_outfit(culture: String) -> Dictionary:
	if _cache.has(culture):
		return _cache[culture]
	var info: Dictionary = {}
	var f := FileAccess.open("res://data/outfits/%s.json" % culture, FileAccess.READ)
	if f:
		info = JSON.parse_string(f.get_as_text())
	else:
		push_error("Ausrüstung fehlt: " + culture)
	var parts := ModelParts.load_parts("res://assets/models/shade_%s.glb" % culture)
	var has_hem := {}
	var seen := {}
	for n in parts:
		var mesh: Mesh = parts[n]
		if String(n).begins_with("S_") or n == "HeadHem":
			var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var any := false
			for c in cols:
				if c.a > 0.5:
					any = true
					break
			has_hem[n] = any
		# Stoffe matt: kein Glanzlicht außer bei Metall und Keramik
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as StandardMaterial3D
			if m == null or seen.has(m) or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			seen[m] = true
			if m.metallic < 0.05:
				m.metallic_specular = 0.0
				m.roughness = 1.0
	var out := {"info": info, "parts": parts, "has_hem": has_hem}
	_cache[culture] = out
	return out


static func hex(s: String) -> Vector3:
	# Farben wie auf der Konzeptseite direkt als lineare Werte
	var c := Color.html(s)
	return Vector3(c.r, c.g, c.b)


## Kette aus Hüllen-Materialien (next_pass). Liefert [erstes Material, alle Materialien].
static func hem_chain(info: Dictionary, layers: int, head: bool, glow := 1.3, heat_override := "", hot_override := "") -> Array:
	var mats: Array[ShaderMaterial] = []
	var heat := hex(heat_override if heat_override != "" else info.get("heat", "#6e0f1e"))
	var hot := hex(hot_override if hot_override != "" else info.get("hot", "#ff5464"))
	for i in range(1, layers + 1):
		var m := ShaderMaterial.new()
		m.shader = HEM_SHADER
		m.set_shader_parameter("layer_k", float(i) / layers)
		m.set_shader_parameter("heat", heat)
		m.set_shader_parameter("hot", hot)
		m.set_shader_parameter("glow", glow)
		if head:
			m.set_shader_parameter("thick", 0.025)
			m.set_shader_parameter("rise", 0.05)
			m.set_shader_parameter("hair", info.get("hemH", 0.24))
			m.set_shader_parameter("head_mode", true)
		else:
			m.set_shader_parameter("thick", 0.011)
			m.set_shader_parameter("rise", 0.03)
		if not mats.is_empty():
			mats[mats.size() - 1].next_pass = m
		mats.append(m)
	return [mats[0], mats]
