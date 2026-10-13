extends ChaosModule
## Greeter: the smallest useful module, and the template for writing your own
## (see README "Adding a module").
##
## !hi (aliases !hello, !wave) pops a shape with the viewer's name that floats
## up and fades. Follows and raids get a pop too (both optional).

const POP_SCRIPT := preload("res://modules/greeter/pop.gd")


func get_default_config() -> Dictionary:
	return {
		"region": [60, 160, 1800, 300],
		"duration_s": 3.0,
		"cooldown_s": 30.0,
		"show_follows": true,
		"show_raids": true,
		"max_on_screen": 12,
		"shapes": [
			{"shape": "circle", "color": "#ffd166", "size": 36, "sprite": ""},
			{"shape": "square", "color": "#06d6a0", "size": 32, "sprite": ""},
			{"shape": "triangle", "color": "#118ab2", "size": 40, "sprite": ""},
		],
		"follow_shape": {"shape": "circle", "color": "#ef476f", "size": 44, "sprite": ""},
		"raid_shape": {"shape": "triangle", "color": "#f78c6b", "size": 90, "sprite": ""},
		"seed": 0,
	}


func get_config_constraints() -> Dictionary:
	return {
		"duration_s": {"min": 0.5, "max": 30.0},
		"cooldown_s": {"min": 0.0},
		"max_on_screen": {"min": 1, "max": 200},
	}


func subscribes_to() -> Array:
	return ["chat_command", "follow", "raid"]


func get_commands() -> Array:
	return [{"name": "hi", "cooldown_s": config["cooldown_s"], "aliases": ["hello", "wave"]}]


func on_event(event: Dictionary) -> bool:
	match event["type"]:
		"chat_command":
			if event["command"] == "hi":
				var shapes: Array = config["shapes"]
				var spec: Variant = shapes[rng.randi() % shapes.size()] if not shapes.is_empty() else {}
				_pop(spec, "hi, %s!" % event["user_name"])
		"follow":
			if config["show_follows"]:
				_pop(config["follow_shape"], "thanks for the follow, %s!" % event["user_name"])
		"raid":
			if config["show_raids"]:
				_pop(config["raid_shape"], "RAID! %s +%d" % [event["user_name"], event.get("viewers", 0)])
	return true


func _pop(spec: Variant, text: String) -> void:
	if get_child_count() >= config["max_on_screen"]:
		get_child(0).queue_free()
	var region := rect_from(config["region"], Rect2(Vector2.ZERO, overlay_size))
	var pop: Node2D = POP_SCRIPT.new()
	pop.position = Vector2(rng.randf_range(region.position.x, region.end.x), rng.randf_range(region.position.y, region.end.y))
	add_child(pop)
	pop.setup(ShapeFactory.make_visual(ShapeFactory.normalize_spec(spec), assets), text, config["duration_s"])
