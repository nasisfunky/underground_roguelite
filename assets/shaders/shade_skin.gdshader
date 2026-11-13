// Schattenkörper der Shades: immer tiefschwarz und matt wie im Konzept (User-Entscheidung 2026-11-13).
// Licht hellt ihn nicht auf; lesbar ist die Figur über Silhouette, Ausrüstung, Augen und Glimmspitzen.
shader_type spatial;
render_mode unshaded;

uniform vec3 albedo : source_color = vec3(0.0);

void fragment() {
	ALBEDO = albedo;
}
