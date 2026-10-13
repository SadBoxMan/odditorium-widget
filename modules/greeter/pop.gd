extends Node2D
## A shape + label that floats upward, fades out and frees itself.

var _life := 3.0
var _age := 0.0


func setup(visual: Node2D, text: String, duration_s: float) -> void:
	_life = duration_s
	add_child(visual)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 22)
	label.position = Vector2(-60, 30)
	add_child(label)


func _process(delta: float) -> void:
	_age += delta
	position.y -= 40.0 * delta
	modulate.a = clampf(1.0 - (_age / _life) ** 2, 0.0, 1.0)
	if _age >= _life:
		queue_free()
