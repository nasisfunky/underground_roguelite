// Flammensaum ("Flame Hem") der Frayed-Shades: mehrere aufgeblähte Hüllen um den schwarzen Körper.
// Jede Hülle (layer_k 0..1) wird weiter nach außen geschoben und per Rauschen ausgedünnt,
// so entsteht ein flackernder schwarzer Flammensaum mit glimmenden Rändern.
// Vertex-Farbe: a = Maske (0 dort, wo Ausrüstung sitzt), rgb = Haarrichtung (nur Kopf), UV.x = Haarstärke.
shader_type spatial;
render_mode unshaded, cull_front, world_vertex_coords, shadows_disabled;

uniform float layer_k = 0.5;
uniform float thick = 0.011;
uniform float rise = 0.03;
uniform float hair = 0.0;
uniform bool head_mode = false;
uniform vec3 heat = vec3(0.43, 0.06, 0.12);
uniform vec3 hot = vec3(1.0, 0.33, 0.39);
uniform float glow = 1.3;
uniform vec3 origin = vec3(0.0); // Figurposition: Muster wandert mit der Figur statt durch sie hindurch

varying vec3 wp;
varying float vm;
varying float vup;
varying float vr;

float fh(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float fn3(vec3 x) {
	vec3 i = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(fh(i), fh(i + vec3(1, 0, 0)), f.x), mix(fh(i + vec3(0, 1, 0)), fh(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(fh(i + vec3(0, 0, 1)), fh(i + vec3(1, 0, 1)), f.x), mix(fh(i + vec3(0, 1, 1)), fh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float ffl(vec3 p) { return fn3(p) * 0.55 + fn3(p * 2.03 + 3.1) * 0.3 + fn3(p * 4.1 + 7.7) * 0.15; }

void vertex() {
	vec3 wn = normalize(NORMAL);
	float up = clamp(wn.y * 0.6 + 0.5, 0.0, 1.0);
	float m = COLOR.a;
	float k = layer_k * m;
	float r = 0.0;
	VERTEX += wn * (0.002 + thick * k) + vec3(0.0, 1.0, 0.0) * k * rise * up * up;
	if (head_mode) {
		r = UV.x;
		vec3 d = COLOR.rgb * 2.0 - 1.0;
		if (dot(d, d) > 1e-4) {
			VERTEX += normalize(mat3(MODEL_MATRIX) * d) * k * r * hair;
		}
	}
	wp = VERTEX - origin;
	vm = m;
	vup = up;
	vr = r;
}

void fragment() {
	if (vm < 0.5) {
		discard;
	}
	float hz = step(0.05, vr);
	vec3 fq = mix(vec3(11.0, 2.8, 11.0), vec3(17.0, 2.2, 17.0), hz);
	float n = ffl(wp * fq - vec3(0.0, TIME * (1.9 + 0.8 * hz), 0.0)) * 0.8 + ffl(wp * vec3(26.0, 7.0, 26.0) - vec3(0.0, TIME * 3.6, 0.0)) * 0.2;
	float thr = mix(0.27 + 0.62 * pow(layer_k, 1.3) - 0.05 * vup, 0.38 + 0.42 * layer_k, hz);
	if (n < thr) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.0, mix(0.045, 0.08, hz), n - thr);
	vec3 c = mix(vec3(0.0), mix(heat, hot, layer_k), smoothstep(0.5, 1.0, layer_k) * mix(0.55, 0.85, hz));
	c = mix(c, hot * mix(1.0, 1.4, hz), edge * smoothstep(0.2, 0.85, layer_k));
	ALBEDO = c * glow;
}
