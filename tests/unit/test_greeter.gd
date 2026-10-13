extends TestCase


func _load(module_cfg: Dictionary = {}) -> Array:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var bus := ChaosEventBus.new()
	var router := CommandRouter.new()
	var reg := ModuleRegistry.new()
	reg._bus = bus
	reg._router = router
	var cfg := ChaosConfig.from_dict({"modules": {"greeter": module_cfg}})
	var m := reg.instantiate("res://modules/greeter/module.gd")
	check(reg.load_module(m, parent, cfg, AssetLoader.new(), Vector2(1920, 1080)))
	return [m, bus, reg, parent]


func _cleanup(ctx: Array) -> void:
	ctx[2].shutdown()
	ctx[3].queue_free()


func test_hi_pops_named_shape() -> void:
	var ctx := _load()
	ctx[1].emit("chat_command", {"type": "chat_command", "command": "hi", "args": [], "user_id": "a", "user_login": "a", "user_name": "Alice"})
	check_eq(ctx[0].get_child_count(), 1)
	_cleanup(ctx)


func test_raid_and_follow_pops() -> void:
	var ctx := _load()
	ctx[1].emit("raid", {"type": "raid", "user_id": "r", "user_login": "r", "user_name": "Raider", "viewers": 12})
	ctx[1].emit("follow", {"type": "follow", "user_id": "f", "user_login": "f", "user_name": "Fol"})
	check_eq(ctx[0].get_child_count(), 2)
	_cleanup(ctx)


func test_other_commands_ignored() -> void:
	var ctx := _load()
	ctx[1].emit("chat_command", {"type": "chat_command", "command": "bonk", "args": [], "user_id": "a", "user_login": "a", "user_name": "A"})
	check_eq(ctx[0].get_child_count(), 0)
	_cleanup(ctx)


func test_max_on_screen() -> void:
	var ctx := _load({"max_on_screen": 3})
	for i in 10:
		ctx[1].emit("follow", {"type": "follow", "user_id": "f%d" % i, "user_login": "f", "user_name": "F"})
	await tree.process_frame
	check(ctx[0].get_child_count() <= 3, "capped, got %d" % ctx[0].get_child_count())
	_cleanup(ctx)
