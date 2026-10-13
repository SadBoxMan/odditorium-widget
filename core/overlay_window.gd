class_name OverlayWindow
extends RefCounted
## Applies the window section of the config: size/position, borderless,
## per-pixel transparency (or a solid chroma-key background), always-on-top
## and mouse click-through. No-op under --headless.


static func apply(cfg: ChaosConfig, window: Window) -> void:
	var w := cfg.section("window")
	var bg := ShapeFactory.parse_color(w["background_color"], Color(0, 0, 0, 0))
	var transparent: bool = w["transparent"] and bg.a < 1.0
	RenderingServer.set_default_clear_color(Color(bg.r, bg.g, bg.b, 0.0) if transparent else Color(bg.r, bg.g, bg.b, 1.0))
	Engine.max_fps = w["max_fps"]
	if DisplayServer.get_name() == "headless":
		return
	window.transparent_bg = transparent
	window.transparent = transparent
	window.borderless = w["borderless"]
	window.always_on_top = w["always_on_top"]
	window.size = Vector2i(w["width"], w["height"])
	if w["x"] >= 0 and w["y"] >= 0:
		window.position = Vector2i(w["x"], w["y"])
	else:
		var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
		window.position = screen.position + (screen.size - window.size) / 2
	if w["click_through"]:
		# A tiny polygon in the corner keeps the window technically hit-testable
		# while letting every other click fall through to what's underneath.
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]), window.get_window_id())
