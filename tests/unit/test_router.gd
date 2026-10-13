extends TestCase
## Command parsing + cooldowns + queue working together.


func _router(overrides: Dictionary = {}) -> CommandRouter:
	var r := CommandRouter.new()
	r.configure(ChaosConfig.from_dict(overrides))
	r.register_command("join", "race", 5.0, ["j"])
	r.register_command("bonk", "bonk", 20.0)
	return r


func _chat(user: String, text: String) -> Dictionary:
	return {"type": "chat_message", "user_id": "id-" + user, "user_login": user, "user_name": user, "text": text}


func test_parse_command() -> void:
	check_eq(CommandRouter.parse_command("!Join", "!"), {"command": "join", "args": []})
	check_eq(CommandRouter.parse_command("  !bonk @Dave hard ", "!"), {"command": "bonk", "args": ["@Dave", "hard"]})
	check_eq(CommandRouter.parse_command("hello !join", "!"), {})
	check_eq(CommandRouter.parse_command("!", "!"), {})
	check_eq(CommandRouter.parse_command("!!!", "!"), {})
	check_eq(CommandRouter.parse_command("!<script>", "!"), {})
	check_eq(CommandRouter.parse_command("~join", "~"), {"command": "join", "args": []})
	check_eq(CommandRouter.parse_command("!a " + "x ".repeat(50), "!")["args"].size(), CommandRouter.MAX_ARGS)


func test_clean_user_arg() -> void:
	check_eq(CommandRouter.clean_user_arg("@Some_User,"), "some_user")
	check_eq(CommandRouter.clean_user_arg("@@@"), "")


func test_routes_known_command_and_alias() -> void:
	var r := _router()
	check_eq(r.route(_chat("alice", "!join"), 0.0), "queued")
	var ev := r.queue.pop()
	check_eq(ev["command"], "join")
	check_eq(ev["module"], "race")
	check_eq(r.route(_chat("bob", "!J"), 0.0), "queued", "alias works")
	check_eq(r.queue.pop()["command"], "join", "alias resolved to canonical")


func test_unknown_and_plain_chat_cost_nothing() -> void:
	var r := _router()
	check_eq(r.route(_chat("alice", "hello"), 0.0), "not_command")
	check_eq(r.route(_chat("alice", "!dance"), 0.0), "unknown_command")
	check_eq(r.route(_chat("alice", "!join"), 0.0), "queued", "no cooldown was consumed by the unknown command")


func test_per_user_cooldowns() -> void:
	var r := _router({"cooldowns": {"per_user_global_s": 2.0}, "queue": {"max_pending_per_user": 10}})
	check_eq(r.route(_chat("alice", "!join"), 0.0), "queued")
	check_eq(r.route(_chat("alice", "!bonk"), 1.0), "cooldown", "global per-user cooldown")
	check_eq(r.route(_chat("alice", "!bonk"), 2.5), "queued")
	check_eq(r.route(_chat("alice", "!join"), 4.0), "cooldown", "command cooldown 5s")
	check_eq(r.route(_chat("alice", "!join"), 5.1), "queued")
	check_eq(r.route(_chat("bob", "!join"), 0.5), "queued", "other users unaffected")


func test_spam_is_contained() -> void:
	var r := _router()
	var outcomes := {}
	for i in 100:
		var o := r.route(_chat("spammer", "!join"), i * 0.01)
		outcomes[o] = outcomes.get(o, 0) + 1
	check_eq(outcomes.get("queued", 0), 1, "one spammer gets one event through")
	check_eq(outcomes.get("cooldown", 0), 99)
	check_eq(r.queue.size(), 1)


func test_queue_full_and_user_limit() -> void:
	var r := _router({"queue": {"capacity": 3, "max_pending_per_user": 1}, "cooldowns": {"per_user_global_s": 0.0}})
	r.register_command("free", "x", 0.0)
	check_eq(r.route(_chat("a", "!free"), 0.0), "queued")
	check_eq(r.route(_chat("a", "!free"), 0.0), "user_limit")
	check_eq(r.route(_chat("b", "!free"), 0.0), "queued")
	check_eq(r.route(_chat("c", "!free"), 0.0), "queued")
	check_eq(r.route(_chat("d", "!free"), 0.0), "queue_full")


func test_ignored_users() -> void:
	var r := _router({"chat": {"ignore_users": ["Nightbot"]}})
	check_eq(r.route(_chat("nightbot", "!join"), 0.0), "ignored_user")


func test_redeems_disabled_by_default() -> void:
	var r := _router()
	var ev := {"type": "redeem", "user_id": "1", "user_login": "a", "user_name": "a", "reward_title": "Bonk the Streamer", "text": ""}
	check_eq(r.route(ev, 0.0), "redeems_disabled")


func test_redeem_mapping() -> void:
	var r := _router({"redeems": {"enabled": true, "rewards": {"Bonk the Streamer": {"command": "bonk"}, "Join Race": {"command": "join", "args_from_input": false}}}})
	var ev := {"type": "redeem", "user_id": "1", "user_login": "a", "user_name": "A", "reward_title": "bonk THE streamer", "text": "@dave please"}
	check_eq(r.route(ev, 0.0), "queued", "title match is case-insensitive")
	var q := r.queue.pop()
	check_eq(q["command"], "bonk")
	check_eq(q["via_redeem"], true)
	check_eq(q["args"], ["@dave", "please"])
	check_eq(r.route(ev, 0.1), "queued", "redeems bypass per-user cooldowns by default")
	r.queue.clear()
	ev["reward_title"] = "Join Race"
	r.route(ev, 0.2)
	check_eq(r.queue.pop()["args"], [], "args_from_input=false")
	ev["reward_title"] = "Hydrate"
	check_eq(r.route(ev, 0.3), "unmapped_redeem")


func test_redeem_cooldowns_when_not_bypassed() -> void:
	var r := _router({"redeems": {"enabled": true, "bypass_user_cooldowns": false}})
	var ev := {"type": "redeem", "user_id": "1", "user_login": "a", "user_name": "A", "reward_title": "Bonk the Streamer", "text": ""}
	check_eq(r.route(ev, 0.0), "queued")
	check_eq(r.route(ev, 1.0), "cooldown")


func test_raid_and_follow_channel_cooldowns() -> void:
	var r := _router({"cooldowns": {"follow_global_s": 2.0, "raid_global_s": 30.0}})
	var follow := {"type": "follow", "user_id": "f1", "user_login": "f1", "user_name": "f1"}
	check_eq(r.route(follow, 0.0), "queued")
	follow["user_id"] = "f2"
	check_eq(r.route(follow, 1.0), "cooldown", "follow-bot burst throttled")
	check_eq(r.route(follow, 2.5), "queued")
	var raid := {"type": "raid", "user_id": "r", "user_login": "r", "user_name": "r", "viewers": 5}
	check_eq(r.route(raid, 0.0), "queued")
	check_eq(r.route(raid, 10.0), "cooldown")


func test_command_conflict_keeps_first_owner() -> void:
	var r := _router()
	r.register_command("join", "other")
	r.route(_chat("a", "!join"), 0.0)
	check_eq(r.queue.pop()["module"], "race")
	r.unregister_module("race")
	check(not r.has_command("join"))
	check(not r.has_command("j"))
