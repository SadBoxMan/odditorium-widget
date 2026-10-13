extends TestCase
## Shape -> sprite fallback.

const TMP_DIR := "user://test_art"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)


func _make_png(path: String, w: int, h: int) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	img.save_png(path)


func test_no_sprite_uses_shape() -> void:
	var assets := AssetLoader.new()
	var node := ShapeFactory.make_visual({"shape": "circle", "color": "#ff0000", "size": 40}, assets)
	check_eq(node.get_meta("visual_kind"), "shape")
	check(node is ShapeNode)
	check_eq((node as ShapeNode).shape, "circle")
	check_eq((node as ShapeNode).size, 40.0)
	check((node as ShapeNode).color.is_equal_approx(Color.RED))
	node.free()


func test_sprite_set_and_found_uses_sprite_scaled_to_size() -> void:
	var path := TMP_DIR.path_join("thing.png")
	_make_png(path, 100, 50)
	var assets := AssetLoader.new()
	var node := ShapeFactory.make_visual({"shape": "square", "size": 40, "sprite": path}, assets)
	check_eq(node.get_meta("visual_kind"), "sprite")
	check(node is Sprite2D)
	check_approx(node.scale.x, 0.4, 0.0001, "longest side scaled to size")
	node.free()


func test_sprite_relative_to_config_dir() -> void:
	_make_png(TMP_DIR.path_join("rel.png"), 8, 8)
	var assets := AssetLoader.new(TMP_DIR)
	check_eq(assets.resolve("rel.png"), TMP_DIR.path_join("rel.png"))
	var node := ShapeFactory.make_visual({"shape": "square", "sprite": "rel.png"}, assets)
	check_eq(node.get_meta("visual_kind"), "sprite")
	node.free()


func test_sprite_set_but_missing_falls_back() -> void:
	var assets := AssetLoader.new()
	var node := ShapeFactory.make_visual({"shape": "triangle", "color": "#00ff00", "size": 30, "sprite": "user://nope/missing.png"}, assets)
	check_eq(node.get_meta("visual_kind"), "shape", "missing sprite -> shape")
	check_eq((node as ShapeNode).shape, "triangle")
	node.free()


func test_sprite_unreadable_falls_back() -> void:
	var path := TMP_DIR.path_join("garbage.png")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is not a png")
	f.close()
	var assets := AssetLoader.new()
	expect_errors(-1)  # the image decoder logs its own error for the bad file
	var node := ShapeFactory.make_visual({"shape": "circle", "sprite": path}, assets)
	check_eq(node.get_meta("visual_kind"), "shape")
	node.free()


func test_unsupported_extension_falls_back() -> void:
	var assets := AssetLoader.new()
	var node := ShapeFactory.make_visual({"shape": "square", "sprite": "art/thing.gif"}, assets)
	check_eq(node.get_meta("visual_kind"), "shape")
	node.free()


func test_texture_cache() -> void:
	var path := TMP_DIR.path_join("cached.png")
	_make_png(path, 4, 4)
	var assets := AssetLoader.new()
	check(assets.load_texture(path) == assets.load_texture(path), "same texture instance")


func test_normalize_spec_bad_values() -> void:
	var warnings: Array = []
	var s := ShapeFactory.normalize_spec({"shape": "hexagon", "color": "nope", "size": -3, "sprite": 7}, warnings)
	check_eq(s["shape"], "square")
	check_eq(s["color"], "#ffffff")
	check_eq(s["size"], 32.0)
	check_eq(s["sprite"], "")
	check_eq(warnings.size(), 4)


func test_normalize_spec_non_dict() -> void:
	var warnings: Array = []
	check_eq(ShapeFactory.normalize_spec("circle", warnings)["shape"], "square")
	check_eq(warnings.size(), 1)


func test_collision_shapes_match() -> void:
	check(ShapeFactory.make_collision_shape("circle", 40) is CircleShape2D)
	check_approx((ShapeFactory.make_collision_shape("circle", 40) as CircleShape2D).radius, 20.0)
	check(ShapeFactory.make_collision_shape("triangle", 40) is ConvexPolygonShape2D)
	check(ShapeFactory.make_collision_shape("square", 40) is RectangleShape2D)


func test_missing_audio_is_null() -> void:
	var assets := AssetLoader.new()
	check(assets.load_audio("") == null)
	check(assets.load_audio("user://nope.ogg") == null)
	check(assets.load_audio("user://nope.flac") == null)
