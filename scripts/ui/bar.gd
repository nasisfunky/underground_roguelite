class_name UIBar
extends Control
## Schlichter, kantiger Balken mit verzögertem "Schaden"-Anteil (zeigt, wie viel gerade verloren ging).

var value := 1.0  # 0..1
var fill_color := Color(0.8, 0.3, 0.2)
var back_color := Color(0.03, 0.05, 0.06, 0.8)
var lag_color := Color(1.0, 0.95, 0.8, 0.7)
var text := ""
var _lag := 1.0


func set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _lag > value:
		_lag = maxf(value, _lag - delta * 0.8)
		queue_redraw()
	elif _lag < value:
		_lag = value


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, back_color)
	var inner := r.grow(-2)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * _lag, inner.size.y)), lag_color)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * value, inner.size.y)), fill_color)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * value, inner.size.y * 0.35)), Color(1, 1, 1, 0.12))
	draw_rect(r, Color(0.55, 0.85, 0.85, 0.35), false, 1.0)
	if text != "":
		var f := get_theme_default_font()
		var fs := 13
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, (size.y + fs * 0.7) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
