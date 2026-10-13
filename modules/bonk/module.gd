extends ChaosModule
## Bonk Physics: `!bonk <user> [object]` (or a mapped channel point redeem)
## flings a physics object at the cam region. It bounces off and despawns.
##
## Every object type lives in config `modules.bonk.objects`:
##   "brick": {"shape": "square", "color": "#c97c5d", "size": 44,
##             "sprite": "art/brick.png", "sound": "sfx/bonk.ogg",
##             "mass": 2.5, "bounce": 0.25, "weight": 2}
## sprite/sound are optional; leave them "" to use the shape / no sound.

const BonkObject := preload("res://modules/bonk/bonk_object.gd")
const PopText := preload("res://modules/bonk/pop_text.gd")

const LAYER_TARGET := 1
const LAYER_OBJECTS := 2
const LAYER_BOUNDS := 4

var objects: Dictionary = {}  # name -> normalized spec
var _weights_total := 0.0
var _target_rect := Rect2()
var _target_body: StaticBody2D
var _audio: AudioStreamPlayer
var _live: Array = []  # BonkObject nodes still in flight
var spawned_total := 0
## Objects that reached the cam region (each counted once).
var hits_total := 0


func get_default_config() -> Dictionary:
	return {
		"target_region": [1460, 640, 400, 380],
		"bonk_cooldown_s": 20.0,
		"allow_object_choice": true,
		"streamer_name": "the streamer",
		"throw_speed": 1300.0,
		"spin": 10.0,
		"gravity_scale": 1.0,
		"lifetime_s": 4.0,
		"fade_s": 0.6,
		"max_objects": 15,
		"show_labels": true,
		"hit_text": "BONK!",
		"volume_db": -6.0,
		"default_sound": "",
		"follow_bonk": false,
		"follow_object": "pillow",
		"raid_barrage": true,
		"raid_barrage_max": 10,
		"screen_floor": true,
		"screen_walls": false,
		"z_index": 10,
		"objects": {
			"ball": {"shape": "circle", "color": "#ff595e", "size": 48, "sprite": "", "sound": "", "mass": 1.0, "bounce": 0.7, "weight": 3},
			"brick": {"shape": "square", "color": "#c97c5d", "size": 44, "sprite": "", "sound": "", "mass": 2.5, "bounce": 0.25, "weight": 2},
			"wedge": {"shape": "triangle", "color": "#ffca3a", "size": 52, "sprite": "", "sound": "", "mass": 1.5, "bounce": 0.45, "weight": 2},
			"pillow": {"shape": "square", "color": "#f4f1de", "size": 70, "sprite": "", "sound": "", "mass": 0.5, "bounce": 0.1, "weight": 1},
		},
		"seed": 0,
	}


func get_config_open_paths() -> Array:
	return ["objects"]


func get_config_constraints() -> Dictionary:
	return {
		"bonk_cooldown_s": {"min": 0.0},
		"throw_speed": {"min": 100.0, "max": 10000.0},
		"spin": {"min": 0.0, "max": 100.0},
		"gravity_scale": {"min": 0.0, "max": 10.0},
		"lifetime_s": {"min": 0.5, "max": 60.0},
		"fade_s": {"min": 0.0, "max": 10.0},
		"max_objects": {"min": 1, "max": 200},
		"volume_db": {"min": -80.0, "max": 24.0},
		"raid_barrage_max": {"min": 0, "max": 100},
	}


func subscribes_to() -> Array:
	return ["chat_command", "follow", "raid"]


func get_commands() -> Array:
	return [{"name": "bonk", "cooldown_s": config["bonk_cooldown_s"], "aliases": ["yeet"]}]


func setup() -> bool:
	objects = parse_objects(config["objects"])
	if objects.is_empty():
		push_warning("[bonk] no valid objects configured; using a default ball")
		objects = parse_objects({"ball": {"shape": "circle", "color": "#ff595e", "size": 48}})
	_weights_total = 0.0
	for spec in objects.values():
		_weights_total += spec["weight"]
	_target_rect = rect_from(config["target_region"], Rect2(overlay_size.x - 460, overlay_size.y - 440, 400, 380))
	_target_body = StaticBody2D.new()
	_target_body.name = "CamTarget"
	_target_body.collision_layer = LAYER_TARGET
	_target_body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _target_rect.size
	cs.shape = rect
	_target_body.position = _target_rect.get_center()
	_target_body.add_child(cs)
	add_child(_target_body)
	# Optional invisible floor/walls at the screen edges so objects bounce
	# around and settle instead of dropping straight out of view.
	if config["screen_floor"]:
		_add_boundary(Vector2(0, overlay_size.y), Vector2.UP)
	if config["screen_walls"]:
		_add_boundary(Vector2(0, 0), Vector2.RIGHT)
		_add_boundary(Vector2(overlay_size.x, 0), Vector2.LEFT)
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = config["volume_db"]
	_audio.max_polyphony = 8
	add_child(_audio)
	return true


func _add_boundary(pos: Vector2, normal: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = LAYER_BOUNDS
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape2D.new()
	var shape := WorldBoundaryShape2D.new()
	shape.normal = normal
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Validates the user's object map. Bad entries are skipped with a warning.
static func parse_objects(raw: Variant, warnings: Array = []) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		warnings.append("objects must be a map of name -> object")
		return out
	for key in raw.keys():
		var obj_name := str(key).strip_edges().to_lower()
		if obj_name.begins_with("_"):
			continue
		var entry: Variant = raw[key]
		if typeof(entry) != TYPE_DICTIONARY:
			warnings.append("objects.%s must be an object" % obj_name)
			continue
		var spec := ShapeFactory.normalize_spec(entry, warnings, "objects." + obj_name)
		spec["sound"] = str(entry.get("sound", "")) if typeof(entry.get("sound", "")) == TYPE_STRING else ""
		spec["mass"] = _num(entry.get("mass", 1.0), 1.0, 0.05, 100.0)
		spec["bounce"] = _num(entry.get("bounce", 0.5), 0.5, 0.0, 1.0)
		spec["weight"] = _num(entry.get("weight", 1.0), 1.0, 0.0, 1000.0)
		out[obj_name] = spec
	for w in warnings:
		push_warning("[bonk] " + w)
	return out


## "!bonk @Dave brick" -> {"target": "dave", "object": "brick"}.
## The target may be omitted ("!bonk brick") and defaults to "".
static func parse_args(args: Array, object_names: Array) -> Dictionary:
	var target := ""
	var object := ""
	for a in args:
		var word := str(a).strip_edges().to_lower()
		if object == "" and word in object_names:
			object = word
		elif target == "":
			target = CommandRouter.clean_user_arg(str(a))
	return {"target": target, "object": object}


func on_event(event: Dictionary) -> bool:
	match event["type"]:
		"chat_command":
			if event["command"] == "bonk":
				var parsed := parse_args(event.get("args", []), objects.keys())
				var object: String = parsed["object"] if config["allow_object_choice"] else ""
				var target: String = parsed["target"] if parsed["target"] != "" else config["streamer_name"]
				bonk(object, "%s -> %s" % [event["user_name"], target])
		"follow":
			if config["follow_bonk"]:
				bonk(str(config["follow_object"]), "welcome, %s!" % event["user_name"])
		"raid":
			if config["raid_barrage"]:
				var count := clampi(int(event.get("viewers", 1)), 1, config["raid_barrage_max"])
				for i in count:
					bonk("", "%s's raid" % event["user_name"] if i == 0 else "")
	return true


## Spawns one object (random weighted pick when `object_name` is empty or
## unknown). Returns the new body.
func bonk(object_name: String = "", label_text: String = "") -> RigidBody2D:
	var obj_name := object_name if objects.has(object_name) else pick_object()
	var spec: Dictionary = objects[obj_name]
	while _live.size() >= config["max_objects"]:
		var oldest: Node = _live.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var body: RigidBody2D = BonkObject.new()
	body.name = "Bonk_%s_%d" % [obj_name, spawned_total]
	body.collision_layer = LAYER_OBJECTS
	body.collision_mask = LAYER_TARGET | LAYER_OBJECTS | LAYER_BOUNDS
	body.mass = spec["mass"]
	body.gravity_scale = config["gravity_scale"]
	var mat := PhysicsMaterial.new()
	mat.bounce = spec["bounce"]
	mat.friction = 0.4
	body.physics_material_override = mat
	var cs := CollisionShape2D.new()
	cs.shape = ShapeFactory.make_collision_shape(spec["shape"], spec["size"])
	body.add_child(cs)
	body.add_child(ShapeFactory.make_visual(spec, assets))
	body.set_meta("object_name", obj_name)
	var start := _spawn_point(spec["size"])
	var aim := _target_rect.get_center() + Vector2(rng.randf_range(-0.3, 0.3) * _target_rect.size.x, rng.randf_range(-0.3, 0.2) * _target_rect.size.y)
	body.position = start
	body.linear_velocity = launch_velocity(start, aim, config["throw_speed"], _gravity() * config["gravity_scale"])
	body.angular_velocity = rng.randf_range(-1.0, 1.0) * config["spin"]
	body.setup(config["lifetime_s"], config["fade_s"], label_text if config["show_labels"] else "")
	body.hit.connect(_on_hit.bind(spec))
	body.tree_exited.connect(func() -> void: _live.erase(body))
	add_child(body)
	_live.append(body)
	spawned_total += 1
	return body


func pick_object() -> String:
	if _weights_total <= 0.0:
		return objects.keys()[rng.randi() % objects.size()]
	var roll := rng.randf() * _weights_total
	for n in objects.keys():
		roll -= objects[n]["weight"]
		if roll <= 0.0:
			return n
	return objects.keys().back()


func live_count() -> int:
	return _live.size()


## Initial velocity so a projectile from `from` reaches `to` after flying
## |to - from| / speed seconds under `gravity` (px/s^2, downward).
static func launch_velocity(from: Vector2, to: Vector2, speed: float, gravity: float) -> Vector2:
	var t := maxf(0.15, from.distance_to(to) / maxf(1.0, speed))
	var v := (to - from) / t
	v.y -= 0.5 * gravity * t
	return v


func _spawn_point(size: float) -> Vector2:
	var margin := size + 20.0
	var y := rng.randf_range(overlay_size.y * 0.15, overlay_size.y * 0.6)
	# Throw from the side farther from the target so the arc reads well.
	if _target_rect.get_center().x > overlay_size.x * 0.5:
		return Vector2(-margin, y)
	return Vector2(overlay_size.x + margin, y)


func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))


func _on_hit(body: RigidBody2D, other: Node, spec: Dictionary) -> void:
	if other != _target_body or body.bonked:
		return
	body.bonked = true
	hits_total += 1
	var sound_path: String = spec["sound"] if spec["sound"] != "" else config["default_sound"]
	var stream := assets.load_audio(sound_path) if sound_path != "" else null
	if stream != null:
		_audio.stream = stream
		_audio.play()
	if config["hit_text"] != "":
		var pop: Node2D = PopText.new()
		pop.position = body.position + Vector2(0, -40)
		add_child(pop)
		pop.setup(config["hit_text"])


func _draw() -> void:
	if show_regions:
		draw_rect(_target_rect, Color(1, 0.3, 0.3, 0.8), false, 3.0)


func teardown() -> void:
	for b in _live:
		if is_instance_valid(b):
			b.queue_free()
	_live.clear()


static func _num(v: Variant, fallback: float, lo: float, hi: float) -> float:
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return clampf(float(v), lo, hi)
	return fallback
