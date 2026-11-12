// Schattenkörper der Shades: fast schwarz und matt. Licht hellt ihn sichtbar auf,
// aber jede Lichtquelle wird weich gedeckelt, damit er auch direkt neben einer Lampe nie weiß ausbrennt.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 albedo : source_color = vec3(0.05, 0.05, 0.06);
uniform float light_cap = 3.0; // höchste Helligkeit, die eine einzelne Lichtquelle beitragen kann

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	vec3 l = ATTENUATION * LIGHT_COLOR / PI * max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += light_cap * (vec3(1.0) - exp(-l / light_cap));
}
