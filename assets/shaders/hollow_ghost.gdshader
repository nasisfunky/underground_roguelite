// Geisterkörper der Hollow Ones: heller, durchscheinender Schleier mit leuchtendem Rand.
// Zusammen mit hollow_ghost_depth (vorher gezeichnet) wird nur die vorderste Fläche eingefärbt,
// so entstehen keine Linien, wo sich Glieder überschneiden.
// tail = true: Schweif statt Beinen, schwingt und löst sich nach unten auf (lokale y von 0 bis tail_len nach unten).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 core : source_color = vec3(0.604, 0.584, 0.722);
uniform vec3 rim : source_color = vec3(0.949, 0.945, 1.0);
uniform float vis = 1.0;
uniform bool tail = false;
uniform float tail_len = 0.97;

varying vec3 wpos;
varying float vk;

float gh(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float gn(vec3 x) {
	vec3 i = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gh(i), gh(i + vec3(1, 0, 0)), f.x), mix(gh(i + vec3(0, 1, 0)), gh(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(gh(i + vec3(0, 0, 1)), gh(i + vec3(1, 0, 1)), f.x), mix(gh(i + vec3(0, 1, 1)), gh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	float k = 0.0;
	if (tail) {
		k = clamp(-(VERTEX.y - 0.02) / tail_len, 0.0, 1.0);
		VERTEX.z += k * k * 0.34 + sin(TIME * 2.1 - k * 4.5) * 0.06 * k;
		VERTEX.x += sin(TIME * 1.6 - k * 5.0) * 0.07 * k * k;
		VERTEX.xz *= 1.0 + 0.25 * sin(TIME * 3.0 - k * 7.0) * k;
	}
	vk = k;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float f = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.4);
	float n = gn(wpos * vec3(9.0, 3.0, 9.0) - vec3(0.0, TIME * 1.1, 0.0)) * 0.7 + gn(wpos * vec3(23.0, 8.0, 23.0) - vec3(0.0, TIME * 2.3, 0.0)) * 0.3;
	float a = (0.42 + 0.5 * f) * (0.75 + 0.45 * n) * (1.0 - vk * vk * 0.95) * vis;
	if (vk > 0.2 && n < 0.25 + 0.5 * vk) {
		a *= 0.25;
	}
	ALBEDO = mix(core, rim, clamp(f * 1.2, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 0.95);
}
