extends Node2D
## "BONK!" text that pops up, grows a little and fades.

var _age := 0.0
const LIFE := 0.9


func setup(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("#ffe066"))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_font_size_override("font_size", 40)
	label.position = Vector2(-50, -24)
	add_child(label)


func _process(delta: float) -> void:
	_age += delta
	position.y -= 60.0 * delta
	scale = Vector2.ONE * (1.0 + _age * 0.4)
	modulate.a = clampf(1.0 - _age / LIFE, 0.0, 1.0)
	if _age >= LIFE:
		queue_free()
