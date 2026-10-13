extends Node2D
## Entry point: wires config -> modules -> Streamer.bot client -> router ->
## queue -> event bus.
##
## Command-line options (after `--`):
##   --config=<path>          config file to use
##   --port=<n>               override streamerbot.port (handy for the mock)
##   --run-seconds=<s>        quit after s seconds and print a STATS line
##   --screenshot=<s>:<path>  save a PNG of the overlay at s seconds
##                            (repeatable; needs a real or virtual display)
##   --screenshot-bg=<color>  composite screenshots onto this colour instead
##                            of keeping transparency (e.g. #303846)

var cfg: ChaosConfig
var bus: ChaosEventBus
var router: CommandRouter
var client: StreamerBotClient
var registry: ModuleRegistry
var assets: AssetLoader
var modules_root: Node2D

var _status_label: Label
var _error_counter := ErrorCounter.new()
var _dispatch_budget := 0.0
var _dispatch_rate := 4.0
var _elapsed := 0.0
var _last_prune := 0.0
var _run_seconds := -1.0
var _screenshots: Array = []
var _screenshot_bg: Variant = null
var _dispatched := 0


## Counts engine/script errors so --run-seconds runs can report them.
class ErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var errors := 0
	var script_errors := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			script_errors += 1
		elif error_type != ERROR_TYPE_WARNING:
			errors += 1
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	OS.add_logger(_error_counter)
	var args := OS.get_cmdline_user_args()
	cfg = ChaosConfig.load_file(ChaosConfig.find_config_path(args))
	_apply_cli_overrides(args)
	print("[lucidin-chaos] config: %s" % (cfg.source_path if cfg.source_path != "" else "<defaults>"))
	_report_config_problems()

	OverlayWindow.apply(cfg, get_window())
	var overlay_size := Vector2(cfg.get_value("window.width"), cfg.get_value("window.height"))

	assets = AssetLoader.new(cfg.base_dir)
	bus = ChaosEventBus.new()
	router = CommandRouter.new()
	router.configure(cfg)
	_dispatch_rate = cfg.get_value("queue.dispatch_per_second", 4.0)

	modules_root = Node2D.new()
	modules_root.name = "Modules"
	add_child(modules_root)
	registry = ModuleRegistry.new()
	bus.on_owner_failed = func(owner_id: String, reason: String) -> void: registry.disable(owner_id, reason)
	registry.load_all(modules_root, cfg, bus, router, assets, overlay_size)
	_report_config_problems()

	_build_status_label()
	client = StreamerBotClient.new()
	client.name = "StreamerBotClient"
	add_child(client)
	client.configure(cfg, registry.internal_types())
	client.event_received.connect(_on_streamerbot_event)
	client.status_changed.connect(_on_status_changed)
	client.start()


func _apply_cli_overrides(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--port="):
			cfg.data["streamerbot"]["port"] = int(arg.substr(7))
		elif arg.begins_with("--run-seconds="):
			_run_seconds = float(arg.substr(14))
		elif arg.begins_with("--screenshot="):
			var spec := arg.substr(13)
			var at := float(spec.get_slice(":", 0))
			_screenshots.append({"at": at, "path": spec.substr(spec.find(":") + 1), "done": false})
		elif arg.begins_with("--screenshot-bg="):
			_screenshot_bg = ShapeFactory.parse_color(arg.substr(16), Color(0.19, 0.22, 0.27))


var _reported_errors := 0
var _reported_warnings := 0


func _report_config_problems() -> void:
	for i in range(_reported_errors, cfg.errors.size()):
		push_warning("[config] " + cfg.errors[i])
	for i in range(_reported_warnings, cfg.warnings.size()):
		print("[config] note: " + cfg.warnings[i])
	_reported_errors = cfg.errors.size()
	_reported_warnings = cfg.warnings.size()


func _on_streamerbot_event(ev: Dictionary) -> void:
	var outcome := router.route(ev, _now())
	if cfg.get_value("debug.log_events", false):
		print("[router] %s %s from %s -> %s" % [ev.get("type"), ev.get("text", ""), ev.get("user_login"), outcome])


func _process(delta: float) -> void:
	_elapsed += delta
	# Token bucket: at most dispatch_per_second events reach modules, with a
	# burst of at most one second's worth.
	_dispatch_budget = minf(_dispatch_budget + delta * _dispatch_rate, maxf(1.0, _dispatch_rate))
	while _dispatch_budget >= 1.0 and not router.queue.is_empty():
		var ev := router.queue.pop()
		_dispatch_budget -= 1.0
		_dispatched += 1
		bus.emit(ev.get("type", ""), ev)
	if _elapsed - _last_prune > 60.0:
		_last_prune = _elapsed
		router.cooldowns.prune(_now())
	for shot in _screenshots:
		if not shot["done"] and _elapsed >= shot["at"]:
			shot["done"] = true
			_take_screenshot(shot["path"])
	if _run_seconds > 0.0 and _elapsed >= _run_seconds:
		_run_seconds = -1.0
		_quit_with_stats()


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_warning("[screenshot] no image (headless?) for " + path)
		return
	if _screenshot_bg != null:
		var bg := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		bg.fill(_screenshot_bg)
		img.convert(Image.FORMAT_RGBA8)
		bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		img = bg
	var err := img.save_png(path)
	print("[screenshot] %s -> %s" % [path, error_string(err)])


func stats() -> Dictionary:
	return {
		"elapsed_s": snappedf(_elapsed, 0.01),
		"client_state": StreamerBotClient.State.keys()[client.state] if client else "none",
		"client": client.stats if client else {},
		"router": router.stats,
		"queue": {"size": router.queue.size(), "accepted": router.queue.accepted_total, "rejected_full": router.queue.rejected_full_total, "rejected_user": router.queue.rejected_user_total},
		"dispatched": _dispatched,
		"bus": {"delivered": bus.delivered_total, "failed": bus.failed_total},
		"modules": registry.modules.keys(),
		"rejected_modules": registry.rejected,
		"config_errors": cfg.errors.size(),
		"engine_errors": _error_counter.errors,
		"script_errors": _error_counter.script_errors,
	}


func _quit_with_stats() -> void:
	print("[lucidin-chaos] STATS " + JSON.stringify(stats()))
	_shutdown()
	get_tree().quit(0)


var _is_shut_down := false


func _shutdown() -> void:
	if _is_shut_down:
		return
	_is_shut_down = true
	if client:
		client.stop()
	if registry:
		registry.shutdown()
	OS.remove_logger(_error_counter)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


func _build_status_label() -> void:
	_status_label = Label.new()
	_status_label.position = Vector2(12, 8)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 4)
	_status_label.visible = false
	add_child(_status_label)


func _on_status_changed(status: String, detail: String) -> void:
	if _status_label == null:
		return
	# Only visible while something is wrong, so it never clutters the stream.
	_status_label.visible = cfg.get_value("debug.show_status", true) and status != "READY"
	_status_label.text = "Streamer.bot: %s — %s" % [status, detail]


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
