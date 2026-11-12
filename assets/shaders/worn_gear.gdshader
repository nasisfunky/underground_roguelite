// Verbrauchte Ausrüstung der Hollow Ones: ersetzt das Material eines Ausrüstungsteils.
// Farben verblassen (Richtung Grau-Braun), dazu Schmutz- und Rostflecken und abgewetzte Stellen.
// Das Muster klebt am Teil (lokale Koordinaten) und wandert nicht.
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool has_tex = false;
uniform float metallic = 0.0;
uniform float fade = 0.55;  // wie stark die Farben verblassen
uniform vec3 grime : source_color = vec3(0.42, 0.38, 0.34);
uniform vec3 rust : source_color = vec3(0.45, 0.27, 0.16);
uniform float seed = 0.0;

varying vec3 lp;

float gh(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float gn(vec3 x) {
	vec3 i = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gh(i), gh(i + vec3(1, 0, 0)), f.x), mix(gh(i + vec3(0, 1, 0)), gh(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(gh(i + vec3(0, 0, 1)), gh(i + vec3(1, 0, 1)), f.x), mix(gh(i + vec3(0, 1, 1)), gh(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX + vec3(seed * 3.7);
}

void fragment() {
	vec3 c = albedo.rgb;
	if (has_tex) {
		c *= texture(albedo_tex, UV).rgb;
	}
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	c = mix(c, vec3(lum) * vec3(1.0, 0.95, 0.86), fade) * 0.8;
	float n = gn(lp * 7.0) * 0.6 + gn(lp * 23.0) * 0.4;
	c *= mix(vec3(1.0), grime / 0.45, smoothstep(0.4, 0.75, n) * 0.85) * mix(1.0, 0.75, smoothstep(0.4, 0.75, n));
	float spots = smoothstep(0.58, 0.72, gn(lp * 41.0 + 5.0));
	c = mix(c, rust * 0.8, spots * (metallic > 0.2 ? 0.75 : 0.35));
	ALBEDO = c;
	METALLIC = metallic * (1.0 - spots);
	ROUGHNESS = mix(0.75, 1.0, n);
	SPECULAR = 0.2;
}
