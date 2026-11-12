// Wabernder Schatten der Willambers: Oberfläche zittert per Rauschen, Ränder lösen sich weich auf,
// am Umriss ein Hauch Violett. Schreibt Tiefe, damit sich die Glieder sauber überdecken.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, world_vertex_coords, shadows_disabled;

uniform vec3 rim : source_color = vec3(0.17, 0.1, 0.3);
uniform float wobble = 0.045;
uniform float fade = 1.0;

varying vec3 wpos;

float gh(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float gn(vec3 x) {
	vec3 i = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gh(i), gh(i + vec3(1, 0, 0)), f.x), mix(gh(i + vec3(0, 1, 0)), gh(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(gh(i + vec3(0, 0, 1)), gh(i + vec3(1, 0, 1)), f.x), mix(gh(i + vec3(0, 1, 1)), gh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 wn = normalize(NORMAL);
	float w = gn(VERTEX * 7.0 + vec3(0.0, TIME * 3.1, TIME * 1.3)) - 0.5;
	VERTEX += wn * w * wobble + vec3(0.0, 0.02, 0.0) * max(w, 0.0);
	wpos = VERTEX;
}

void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float n = gn(wpos * vec3(14.0, 6.0, 14.0) - vec3(0.0, TIME * 2.2, 0.0));
	float a = (1.0 - smoothstep(0.45, 0.95, f + (n - 0.5) * 0.55)) * fade;
	if (a < 0.04) {
		discard;
	}
	ALBEDO = mix(vec3(0.004, 0.003, 0.008), rim, smoothstep(0.35, 0.9, f) * 0.4);
	ALPHA = a;
}
