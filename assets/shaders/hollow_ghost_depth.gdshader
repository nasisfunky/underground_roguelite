// Tiefen-Durchgang für den Geisterkörper: unsichtbar, schreibt nur Tiefe (render_priority niedriger
// als die Farbe), damit der Schleier danach nur auf der vordersten Fläche erscheint.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform bool tail = false;
uniform float tail_len = 0.97;

void vertex() {
	if (tail) {
		float k = clamp(-(VERTEX.y - 0.02) / tail_len, 0.0, 1.0);
		VERTEX.z += k * k * 0.34 + sin(TIME * 2.1 - k * 4.5) * 0.06 * k;
		VERTEX.x += sin(TIME * 1.6 - k * 5.0) * 0.07 * k * k;
		VERTEX.xz *= 1.0 + 0.25 * sin(TIME * 3.0 - k * 7.0) * k;
	}
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
