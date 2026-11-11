class_name AbilitySlot
extends Control
## Ein Feld der Aktionsleiste: Tastennummer, Kürzel, Abklingzeit als dunkle Füllung.

var key_text := "1"
var label_text := ""
var cooldown_frac := 0.0
var cooldown_left := 0.0
var flash := 0.0
var empty := true


func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(flash - delta * 4.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.03, 0.05, 0.06, 0.75))
	var f := get_theme_default_font()
	if not empty:
		draw_rect(r.grow(-3), Color(0.12, 0.24, 0.26, 0.95))
		var ts := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, size.y * 0.62), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.97, 0.97))
		if cooldown_frac > 0.0:
			var h := (size.y - 6) * cooldown_frac
			draw_rect(Rect2(3, size.y - 3 - h, size.x - 6, h), Color(0, 0, 0, 0.65))
			var cd := "%.0f" % ceilf(cooldown_left) if cooldown_left >= 1.0 else "%.1f" % cooldown_left
			var cs := f.get_string_size(cd, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			draw_string(f, Vector2((size.x - cs.x) * 0.5, size.y * 0.62), cd, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.6))
	if flash > 0.0:
		draw_rect(r, Color(0.6, 1.0, 1.0, flash * 0.5))
	draw_rect(r, Color(0.55, 0.85, 0.85, 0.4 if not empty else 0.18), false, 1.0)
	draw_string(f, Vector2(5, 15), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.7))
