class_name FxTex
extends RefCounted
## Kleine prozedurale Texturen für Effekte (aus dem Shooter-Projekt übernommen):
## Funkenstreifen, Staubring einer Druckwelle, Brandfleck, Flammenzungen.
## Einmal beim ersten Gebrauch erzeugt und behalten; niedrige Auflösung und harte
## Alpha-Stufen, damit sie zum kantigen Low-Poly-Look passen.

static var _cache := {}


static func _noise(seed_value: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = 3
	return n


static func _done(key: String, img: Image) -> ImageTexture:
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## A spark or shard of fire seen in flight: white-hot head at the top, a tail that
## thins and fades towards the bottom.
static func streak() -> ImageTexture:
	if _cache.has("streak"):
		return _cache["streak"]
	var w := 8
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)          # 0 head .. 1 tail end
		var width := lerpf(1.0, 0.25, t)
		for x in w:
			var d := absf((x + 0.5) / float(w) - 0.5) * 2.0 / width
			var a := clampf(1.0 - d, 0.0, 1.0) * pow(1.0 - t, 1.4)
			var c := Color(1.0, 0.95, 0.8).lerp(Color(1.0, 0.45, 0.1), t)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, round(a * 6.0) / 6.0))
	return _done("streak", img)


## The blast wave kicking up dust: a soft ragged ring.
static func ring() -> ImageTexture:
	if _cache.has("ring"):
		return _cache["ring"]
	var s := 64
	var n := _noise(41, 0.09)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var v := Vector2(x - 31.5, y - 31.5) / 31.5
			var d := v.length() + n.get_noise_2d(x, y) * 0.12
			var a := clampf(1.0 - absf(d - 0.78) / 0.2, 0.0, 1.0)
			a *= 0.6 + 0.4 * n.get_noise_2d(x * 2.0 + 50.0, y * 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, round(clampf(a, 0.0, 1.0) * 5.0) / 5.0))
	return _done("ring", img)


## Burnt ground where something went up: black at the heart, ragged and streaked
## outwards, fading into the mud.
static func scorch() -> ImageTexture:
	if _cache.has("scorch"):
		return _cache["scorch"]
	var s := 64
	var n := _noise(77, 0.08)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var v := Vector2(x - 31.5, y - 31.5) / 31.5
			var a := atan2(v.y, v.x)
			var rays := 0.12 * sin(a * 7.0 + 1.3) + 0.08 * sin(a * 13.0)
			var d := v.length() + n.get_noise_2d(x, y) * 0.25 - rays
			var k := clampf(1.0 - d, 0.0, 1.0)
			var c := Color(0.05, 0.04, 0.035).lerp(Color(0.13, 0.1, 0.08), clampf(d, 0.0, 1.0))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, round(clampf(k * 1.6, 0.0, 0.92) * 6.0) / 6.0))
	return _done("scorch", img)


## A flame tongue, white-yellow at the root, licking up into a ragged tip. Four
## variants so a fire never shows the same shape twice in a row.
static func flame(variant: int) -> ImageTexture:
	var key := "flame%d" % variant
	if _cache.has(key):
		return _cache[key]
	var w := 24
	var h := 40
	var n := _noise(300 + variant, 0.16)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := 1.0 - float(y) / float(h - 1)     # 0 root (bottom) .. 1 tip
		var width := sin(clampf(t * 1.15, 0.0, 1.0) * PI * 0.92 + 0.25) * (1.0 - t * 0.55)
		var lean := n.get_noise_2d(0.0, y * 1.5) * 0.25 * t
		for x in w:
			var u := (x + 0.5) / float(w) * 2.0 - 1.0 - lean
			var d := absf(u) / maxf(width, 0.01) + n.get_noise_2d(x * 1.7, y) * 0.35 * t
			var a := clampf(1.0 - d, 0.0, 1.0)
			a *= clampf((1.0 - t) * 2.5, 0.0, 1.0) if t > 0.6 else 1.0
			a = clampf(a * 1.6, 0.0, 1.0)
			var heat := clampf(a * (1.2 - t), 0.0, 1.0)
			var c := Color(0.75, 0.16, 0.03).lerp(Color(1.0, 0.62, 0.18), heat).lerp(Color(1.0, 0.95, 0.75), clampf(heat * 2.0 - 1.0, 0.0, 1.0))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, round(a * 6.0) / 6.0))
	return _done(key, img)


## Weicher, leicht ausgefranster Fleck (der weiße Blitzkern einer Explosion).
static func puff() -> ImageTexture:
	if _cache.has("puff"):
		return _cache["puff"]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var wobble := 0.12 * sin(atan2(y - 15.5, x - 15.5) * 5.0) + rng.randf_range(-0.08, 0.08)
			var a := clampf(1.0 - (d + wobble), 0.0, 1.0)
			a = round(a * a * 6.0) / 6.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return _done("puff", img)
