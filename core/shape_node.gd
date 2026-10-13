class_name ShapeNode
extends Node2D
## Placeholder art: a square, triangle or circle drawn in code, centred on the
## node's origin. `size` is the side length / diameter in pixels.

@export_enum("square", "triangle", "circle") var shape: String = "square":
	set(v):
		shape = v
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()
@export var size: float = 32.0:
	set(v):
		size = maxf(1.0, v)
		queue_redraw()
@export var outline_color: Color = Color(0, 0, 0, 0.6)
@export var outline_width: float = 2.0


func _draw() -> void:
	var h := size * 0.5
	match shape:
		"circle":
			draw_circle(Vector2.ZERO, h, color)
			if outline_width > 0.0:
				draw_arc(Vector2.ZERO, h, 0.0, TAU, 32, outline_color, outline_width, true)
		"triangle":
			var pts := ShapeFactory.triangle_points(size)
			draw_colored_polygon(pts, color)
			if outline_width > 0.0:
				var loop := pts.duplicate()
				loop.append(pts[0])
				draw_polyline(loop, outline_color, outline_width, true)
		_:
			var rect := Rect2(-h, -h, size, size)
			draw_rect(rect, color)
			if outline_width > 0.0:
				draw_rect(rect, outline_color, false, outline_width)
