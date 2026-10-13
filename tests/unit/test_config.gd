extends TestCase


func test_defaults_when_empty() -> void:
	var cfg := ChaosConfig.from_dict({})
	check_eq(cfg.errors.size(), 0)
	check_eq(cfg.get_value("streamerbot.port"), 8080)
	check_eq(cfg.get_value("chat.command_prefix"), "!")
	check_eq(cfg.get_value("redeems.enabled"), false, "redeems off by default")


func test_valid_overrides_and_int_from_float() -> void:
	var cfg := ChaosConfig.from_json_text('{"streamerbot": {"port": 9090, "host": "10.0.0.5"}, "queue": {"dispatch_per_second": 2}}')
	check_eq(cfg.errors.size(), 0, "no errors: %s" % str(cfg.errors))
	check_eq(cfg.get_value("streamerbot.port"), 9090)
	check_eq(typeof(cfg.get_value("streamerbot.port")), TYPE_INT, "JSON float coerced to int")
	check_eq(cfg.get_value("streamerbot.host"), "10.0.0.5")
	check_eq(cfg.get_value("queue.dispatch_per_second"), 2.0)
	check_eq(typeof(cfg.get_value("queue.dispatch_per_second")), TYPE_FLOAT, "int coerced to float")
	check_eq(cfg.get_value("streamerbot.endpoint"), "/", "untouched keys keep defaults")


func test_wrong_types_fall_back_with_errors() -> void:
	var cfg := ChaosConfig.from_dict({"streamerbot": {"port": "eighty"}, "redeems": {"enabled": "yes"}, "queue": {"capacity": 2.5}})
	check_eq(cfg.get_value("streamerbot.port"), 8080)
	check_eq(cfg.get_value("redeems.enabled"), false)
	check_eq(cfg.get_value("queue.capacity"), 50, "non-integral float rejected for int")
	check_eq(cfg.errors.size(), 3, "one error per bad value: %s" % str(cfg.errors))


func test_out_of_range() -> void:
	var cfg := ChaosConfig.from_dict({"streamerbot": {"port": 70000}, "queue": {"capacity": 0}, "cooldowns": {"per_user_global_s": -1}})
	check_eq(cfg.get_value("streamerbot.port"), 8080)
	check_eq(cfg.get_value("queue.capacity"), 50)
	check_eq(cfg.get_value("cooldowns.per_user_global_s"), 2.0)
	check_eq(cfg.errors.size(), 3)


func test_bad_color_rejected() -> void:
	var cfg := ChaosConfig.from_dict({"window": {"background_color": "not-a-color"}})
	check_eq(cfg.get_value("window.background_color"), "#00000000")
	check_eq(cfg.errors.size(), 1)


func test_missing_keys_and_unknown_keys() -> void:
	var cfg := ChaosConfig.from_dict({"streamerbot": {"prot": 1}, "mystery": true, "_comment": "ignored silently"})
	check_eq(cfg.errors.size(), 0)
	check_eq(cfg.warnings.size(), 2, "two unknown keys warned: %s" % str(cfg.warnings))
	check_eq(cfg.get_value("streamerbot.port"), 8080)


func test_section_of_wrong_type() -> void:
	var cfg := ChaosConfig.from_dict({"chat": "loud"})
	check_eq(cfg.get_value("chat.command_prefix"), "!")
	check_eq(cfg.errors.size(), 1)


func test_malformed_json() -> void:
	var cfg := ChaosConfig.from_json_text('{"streamerbot": {"port": 8080,,}')
	check_eq(cfg.errors.size(), 1)
	check("parse error" in cfg.errors[0], cfg.errors[0] if not cfg.errors.is_empty() else "")
	check_eq(cfg.get_value("streamerbot.port"), 8080, "defaults used")


func test_non_object_root() -> void:
	var cfg := ChaosConfig.from_json_text('[1, 2, 3]')
	check_eq(cfg.errors.size(), 1)
	check_eq(cfg.get_value("queue.capacity"), 50)


func test_missing_file_uses_defaults() -> void:
	var cfg := ChaosConfig.load_file("res://does/not/exist.json")
	check_eq(cfg.errors.size(), 0)
	check_eq(cfg.warnings.size(), 1)
	check_eq(cfg.get_value("streamerbot.port"), 8080)


func test_ignore_users_normalized() -> void:
	var cfg := ChaosConfig.from_dict({"chat": {"ignore_users": ["@StreamElements", " Nightbot ", 5]}})
	check_eq(cfg.get_value("chat.ignore_users"), ["streamelements", "nightbot"])
	check_eq(cfg.errors.size(), 1, "non-string entry reported")


func test_rewards_open_map_and_validation() -> void:
	var cfg := ChaosConfig.from_dict({"redeems": {"rewards": {"Yeet": {"command": "BONK"}, "Broken": {"nope": 1}, "_comment": "x"}}})
	var rewards: Dictionary = cfg.get_value("redeems.rewards")
	check(rewards.has("Yeet"))
	check(not rewards.has("Bonk the Streamer"), "user map replaces default map")
	check(not rewards.has("Broken"), "invalid reward dropped")
	check(not rewards.has("_comment"))
	check_eq(rewards["Yeet"]["command"], "bonk")
	check_eq(rewards["Yeet"]["args_from_input"], true)
	check_eq(cfg.errors.size(), 1)


func test_module_section_merge() -> void:
	var cfg := ChaosConfig.from_dict({"modules": {"thing": {"speed": 3, "bogus": 1, "objects": {"a": {"shape": "circle"}}}}})
	var merged := cfg.apply_module_defaults("thing", {"enabled": true, "speed": 1.5, "objects": {"default": {}}}, ["objects"], {"speed": {"max": 10.0}})
	check_eq(merged["speed"], 3.0)
	check_eq(merged["enabled"], true)
	check(merged["objects"].has("a") and not merged["objects"].has("default"), "open map replaced")
	check_eq(cfg.warnings.size(), 1, "unknown module key warned")
	check_eq(cfg.get_value("modules.thing.speed"), 3.0)
	var cfg2 := ChaosConfig.from_dict({"modules": {"thing": {"speed": 99}}})
	cfg2.apply_module_defaults("thing", {"speed": 1.5}, [], {"speed": {"max": 10.0}})
	check_eq(cfg2.get_value("modules.thing.speed"), 1.5, "module constraint enforced")
	check_eq(cfg2.errors.size(), 1)


func test_shipped_config_file_is_clean() -> void:
	var cfg := ChaosConfig.load_file("res://lucidin_chaos.json")
	check_eq(cfg.source_path, "res://lucidin_chaos.json")
	check(FileAccess.file_exists("res://lucidin_chaos.json"), "shipped config exists")
	check_eq(cfg.errors, [] as Array[String], "shipped config has no errors")
	check_eq(cfg.warnings, [] as Array[String], "shipped config has no unknown keys")
	for path in ModuleRegistry.discover():
		var reg := ModuleRegistry.new()
		var m := reg.instantiate(path)
		var defaults := m.get_default_config()
		defaults["enabled"] = true
		defaults["z_index"] = defaults.get("z_index", 0)
		cfg.apply_module_defaults(m.module_id, defaults, m.get_config_open_paths(), m.get_config_constraints())
		m.free()
	check_eq(cfg.errors, [] as Array[String], "shipped module sections have no errors")
	check_eq(cfg.warnings, [] as Array[String], "shipped module sections have no unknown keys")


func test_find_config_path_cli() -> void:
	check_eq(ChaosConfig.find_config_path(PackedStringArray(["--config=/tmp/x.json"])), "/tmp/x.json")
