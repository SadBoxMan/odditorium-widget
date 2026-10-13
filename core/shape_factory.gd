class_name ShapeFactory
extends RefCounted
## Builds visuals (and matching collision shapes) from a "shape spec":
##   {"shape": "square"|"triangle"|"circle", "color": "#rrggbb", "size": 40,
##    "sprite": "art/thing.png"}
## If "sprite" is set and loads, a Sprite2D scaled to `size` is used;
## otherwise the code-drawn ShapeNode is used. Callers can check which via
## node.get_meta("visual_kind") == "sprite" | "shape".

const SHAPES := ["square", "triangle", "circle"]
const DEFAULT_SPEC := {"shape": "square", "color": "#ffffff", "size": 32.0, "sprite": ""}


## Validates/fills a spec. Problems are appended to `warnings` (if given) and
## replaced with defaults; this never fails.
static func normalize_spec(spec: Variant, warnings: Array = [], context: String = "shape") -> Dictionary:
	var out := DEFAULT_SPEC.duplicate()
	if typeof(spec) != TYPE_DICTIONARY:
		warnings.append("%s: expected an object, using a white square" % context)
		return out
	var shape := str(spec.get("shape", "square")).to_lower()
	if shape in SHAPES:
		out["shape"] = shape
	else:
		warnings.append("%s: unknown shape '%s' (use square, triangle or circle)" % [context, shape])
	var col: Variant = spec.get("color", "#ffffff")
	if typeof(col) == TYPE_STRING and Color.html_is_valid(col):
		out["color"] = col
	else:
		warnings.append("%s: invalid color %s" % [context, JSON.stringify(col)])
	var size: Variant = spec.get("size", 32.0)
	if typeof(size) in [TYPE_INT, TYPE_FLOAT] and size > 0 and size <= 2000:
		out["size"] = float(size)
	else:
		warnings.append("%s: size must be a number between 1 and 2000" % context)
	var sprite: Variant = spec.get("sprite", "")
	if typeof(sprite) == TYPE_STRING:
		out["sprite"] = sprite
	elif sprite != null:
		warnings.append("%s: sprite must be a path string" % context)
	for extra in spec.keys():
		if not out.has(extra) and not str(extra).begins_with("_"):
			out[extra] = spec[extra]
	return out


## Returns a Node2D centred on its origin.
static func make_visual(spec: Dictionary, assets: AssetLoader) -> Node2D:
	var s := normalize_spec(spec)
	var tex: Texture2D = assets.load_texture(s["sprite"]) if assets != null and s["sprite"] != "" else null
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var tex_size := tex.get_size()
		var longest := maxf(tex_size.x, tex_size.y)
		if longest > 0.0:
			sprite.scale = Vector2.ONE * (s["size"] / longest)
		sprite.set_meta("visual_kind", "sprite")
		return sprite
	var node := ShapeNode.new()
	node.shape = s["shape"]
	node.color = Color.html(s["color"])
	node.size = s["size"]
	node.set_meta("visual_kind", "shape")
	return node


static func make_collision_shape(shape: String, size: float) -> Shape2D:
	match shape:
		"circle":
			var c := CircleShape2D.new()
			c.radius = size * 0.5
			return c
		"triangle":
			var p := ConvexPolygonShape2D.new()
			p.points = triangle_points(size)
			return p
		_:
			var r := RectangleShape2D.new()
			r.size = Vector2(size, size)
			return r


## Equilateral-ish triangle pointing up, centred on the origin.
static func triangle_points(size: float) -> PackedVector2Array:
	var h := size * 0.5
	return PackedVector2Array([Vector2(0, -h), Vector2(h, h), Vector2(-h, h)])


static func parse_color(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if typeof(value) == TYPE_STRING and Color.html_is_valid(value):
		return Color.html(value)
	return fallback
