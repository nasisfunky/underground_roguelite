shader_type spatial;
// Wasser im Cel-Look (Vorbild: Wind Waker): klare Farbflächen statt Realismus.
//  - zwei Farbstufen (flach am Rand, tief in der Mitte) nach Wassertiefe
//  - harter weißer Schaumrand dort, wo Wasser auf Wände, Treppen und Figuren trifft
//  - wandernde Schaumlinien aus Zellkanten (Voronoi), nur in einzelnen Feldern
//  - harte Glanzpunkte von Lichtern (Toon-Specular), sanfte Wellen
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

uniform vec4 deep_color : source_color = vec4(0.015, 0.11, 0.15, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.05, 0.33, 0.38, 1.0);
uniform vec4 foam_color : source_color = vec4(0.82, 0.96, 1.0, 1.0);
uniform float foam_band = 0.09;
uniform float foam_glow = 0.12; // Schaum glimmt leicht, damit er im Dunkeln lesbar bleibt
uniform float cell_scale = 0.8;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Abstand zur nächsten Zellkante (0 = auf der Kante)
float cell_edge(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			o = 0.5 + 0.45 * sin(t + 6.2831 * o);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.9 + TIME * 1.3) * 0.02 + sin(wpos.z * 1.1 - TIME * 1.05) * 0.02;
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, depth), 1.0);
	view.xyz /= view.w;
	float thick = max(-view.z - (-VERTEX.z), 0.0);
	// Schaumrand: harte Kante plus ein zweiter, dünner Ring etwas weiter draußen
	float wob = sin(wpos.x * 3.1 + TIME * 1.7) * 0.02 + sin(wpos.z * 2.7 - TIME * 1.3) * 0.02;
	float shore = step(thick, foam_band + wob);
	float ring2 = step(abs(thick - (foam_band * 3.0 + wob)), 0.015) * step(thick, 0.6);
	// wandernde Schaumlinien
	vec2 uv = wpos.xz * cell_scale + vec2(sin(wpos.z * 0.7 + TIME * 0.4), cos(wpos.x * 0.6 + TIME * 0.35)) * 0.25;
	float edge = cell_edge(uv, TIME * 0.6);
	// dünne, wellige Linien, nur in einzelnen Feldern und dort zum Rand hin ausdünnend
	float fields = smoothstep(0.5, 0.75, sin(wpos.x * 0.37 + TIME * 0.21) * sin(wpos.z * 0.31 - TIME * 0.17) * 0.5 + 0.5);
	float lines = 1.0 - step(0.022 * fields, edge);
	float foam = max(max(shore, ring2 * 0.9), lines * fields);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, step(1.1, thick));
	ALBEDO = mix(col, foam_color.rgb, foam);
	ALPHA = mix(0.9, 1.0, foam);
	ROUGHNESS = mix(0.18, 0.9, foam);
	SPECULAR = mix(0.7, 0.1, foam);
	EMISSION = foam_color.rgb * foam * foam_glow + col * 0.03;
}
