extends TestCase
## One misbehaving module must not affect the core or other modules.

const FIX := "res://tests/fixtures/modules/"


func _make(script_path: String, id: String) -> ChaosModule:
	var m: ChaosModule = load(script_path).new()
	m.module_id = id
	m.name = id
	return m


func _registry(bus: ChaosEventBus, router: CommandRouter) -> ModuleRegistry:
	var reg := ModuleRegistry.new()
	reg._bus = bus
	reg._router = router
	bus.on_owner_failed = func(owner_id: String, reason: String) -> void: reg.disable(owner_id, reason)
	return reg


func test_crashing_handler_does_not_block_others() -> void:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var bus := ChaosEventBus.new()
	bus.max_failures = 3
	var router := CommandRouter.new()
	var reg := _registry(bus, router)
	var cfg := ChaosConfig.from_dict({})
	var crashy := _make(FIX + "crashy.gd", "crashy")
	var counter := _make(FIX + "counter.gd", "counter")
	check(reg.load_module(crashy, parent, cfg, AssetLoader.new(), Vector2(100, 100)))
	check(reg.load_module(counter, parent, cfg, AssetLoader.new(), Vector2(100, 100)))
	expect_errors(3)  # crashy errors 3 times, then gets disabled
	for i in 6:
		bus.emit("chat_command", {"type": "chat_command", "command": "count", "n": i})
	check_eq(counter.received.size(), 6, "healthy module got every event")
	check_eq(crashy.calls, 3, "crashy stopped receiving after being disabled")
	check(not reg.modules.has("crashy"), "crashy removed from registry")
	check(reg.rejected.has("crashy"))
	check(reg.modules.has("counter"))
	check_eq(bus.failed_total, 3)
	reg.shutdown()
	await tree.process_frame
	parent.free()


func test_handlers_get_independent_copies() -> void:
	var bus := ChaosEventBus.new()
	var seen: Array = []
	bus.subscribe("raid", "a", func(e): e["viewers"] = -1; return true)
	bus.subscribe("raid", "b", func(e): seen.append(e["viewers"]); return true)
	bus.emit("raid", {"viewers": 5})
	check_eq(seen, [5])


func test_setup_failure_disables_only_that_module() -> void:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var bus := ChaosEventBus.new()
	var router := CommandRouter.new()
	var reg := _registry(bus, router)
	var cfg := ChaosConfig.from_dict({})
	expect_errors(1)
	check(not reg.load_module(_make(FIX + "bad_setup.gd", "bad_setup"), parent, cfg, AssetLoader.new(), Vector2.ONE))
	check(reg.load_module(_make(FIX + "counter.gd", "counter"), parent, cfg, AssetLoader.new(), Vector2.ONE))
	check_eq(bus.subscriber_count("chat_command"), 1, "only the healthy module subscribed")
	check(router.has_command("count"))
	reg.shutdown()
	await tree.process_frame
	parent.free()


func test_module_disabled_in_config() -> void:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var bus := ChaosEventBus.new()
	var router := CommandRouter.new()
	var reg := _registry(bus, router)
	var cfg := ChaosConfig.from_dict({"modules": {"counter": {"enabled": false}}})
	check(not reg.load_module(_make(FIX + "counter.gd", "counter"), parent, cfg, AssetLoader.new(), Vector2.ONE))
	check_eq(reg.rejected.get("counter"), "disabled in config")
	check(not router.has_command("count"))
	reg.shutdown()
	parent.free()


func test_unknown_event_type_refused() -> void:
	var m := ChaosModule.new()
	m.module_id = "x"
	var script := GDScript.new()
	script.source_code = "extends ChaosModule\nfunc subscribes_to() -> Array:\n\treturn [\"chat_command\", \"teleport\"]\n"
	script.reload()
	var inst: ChaosModule = script.new()
	inst.module_id = "weird"
	var problems := ModuleRegistry.validate(inst)
	check_eq(problems.size(), 1)
	check("unknown event type 'teleport'" in problems[0])
	inst.free()
	m.free()
