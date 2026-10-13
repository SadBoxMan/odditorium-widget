extends TestCase

const RaceLogic := preload("res://modules/critter_race/race_logic.gd")


func _logic(overrides: Dictionary = {}) -> RaceLogic:
	var l := RaceLogic.new()
	var cfg := {"lanes": 6, "min_humans_to_start": 3, "lobby_timeout_s": 30.0, "countdown_s": 3.0, "results_s": 5.0, "cooldown_s": 10.0, "max_race_s": 60.0}
	cfg.merge(overrides, true)
	l.configure(cfg)
	l.rng.seed = 1234
	return l


func _run(l: RaceLogic, seconds: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		l.step(dt)
		t += dt


func test_first_join_opens_lobby() -> void:
	var l := _logic()
	check_eq(l.phase, RaceLogic.Phase.IDLE)
	check_eq(l.join("u1", "Alice"), "joined")
	check_eq(l.phase, RaceLogic.Phase.LOBBY)
	check_eq(l.humans(), 1)


func test_duplicate_join_ignored() -> void:
	var l := _logic()
	l.join("u1", "Alice")
	check_eq(l.join("u1", "Alice"), "already_in")
	check_eq(l.humans(), 1)


func test_auto_start_when_enough_humans() -> void:
	var l := _logic()
	l.join("u1", "A")
	l.join("u2", "B")
	check_eq(l.phase, RaceLogic.Phase.LOBBY)
	l.join("u3", "C")
	check_eq(l.phase, RaceLogic.Phase.COUNTDOWN, "3rd human triggers countdown")
	check_eq(l.entrants.size(), 6, "NPCs fill the remaining lanes")
	check_eq(l.entrants.filter(func(e): return e["npc"]).size(), 3)
	_run(l, 3.1)
	check_eq(l.phase, RaceLogic.Phase.RACING)


func test_single_chatter_gets_npc_race_after_timeout() -> void:
	var l := _logic()
	l.join("solo", "Solo")
	_run(l, 29.0)
	check_eq(l.phase, RaceLogic.Phase.LOBBY, "still waiting for others")
	_run(l, 1.1)
	check_eq(l.phase, RaceLogic.Phase.COUNTDOWN)
	check_eq(l.humans(), 1)
	check_eq(l.entrants.size(), 6)
	var lanes := l.entrants.map(func(e): return e["lane"])
	lanes.sort()
	check_eq(lanes, [0, 1, 2, 3, 4, 5], "each critter has its own lane")
	var names := l.entrants.map(func(e): return e["name"])
	for n in names:
		check_eq(names.count(n), 1, "unique names")


func test_full_race_runs_to_results_and_resets() -> void:
	var l := _logic()
	for i in 3:
		l.join("u%d" % i, "U%d" % i)
	_run(l, 3.1)
	check_eq(l.phase, RaceLogic.Phase.RACING)
	_run(l, 40.0)
	check(l.phase in [RaceLogic.Phase.RESULTS, RaceLogic.Phase.COOLDOWN, RaceLogic.Phase.IDLE], "race ended")
	check_eq(l.results.size(), 6, "every critter placed")
	var places := []
	for e in l.entrants:
		places.append(e["place"])
	places.sort()
	if not l.entrants.is_empty():
		check_eq(places, [1, 2, 3, 4, 5, 6])
	_run(l, 20.0)
	check_eq(l.phase, RaceLogic.Phase.IDLE, "back to idle after results + cooldown")
	check(l.entrants.is_empty())


func test_winner_reported_in_events() -> void:
	var l := _logic({"min_humans_to_start": 1})
	l.join("u1", "Alice")
	_run(l, 60.0)
	var over := l.take_events().filter(func(e): return e["type"] == "race_over")
	check_eq(over.size(), 1)
	if over.size() == 1:
		check(not over[0]["winner"].is_empty(), "a winner was named")


func test_max_race_time_ends_stalled_race() -> void:
	var l := _logic({"min_humans_to_start": 1, "max_race_s": 5.0, "base_speed": 0.005, "speed_jitter": 0.0})
	l.join("u1", "Slowpoke")
	_run(l, 3.1)
	_run(l, 5.1)
	check(l.phase != RaceLogic.Phase.RACING, "max_race_s forced an end")
	check_eq(l.results.size(), 6, "unfinished critters ranked by distance")


func test_lobby_full_of_humans_starts_immediately() -> void:
	var l := _logic({"lanes": 3, "min_humans_to_start": 10})
	l.join("a", "A")
	l.join("b", "B")
	l.join("c", "C")
	check_eq(l.phase, RaceLogic.Phase.COUNTDOWN)
	check_eq(l.join("d", "D"), "full")


func test_joins_during_race_go_to_next_race() -> void:
	var l := _logic({"min_humans_to_start": 1})
	l.join("a", "A")
	_run(l, 3.1)
	check_eq(l.phase, RaceLogic.Phase.RACING)
	check_eq(l.join("late", "Late"), "queued_next")
	check_eq(l.join("late", "Late"), "already_in")
	check_eq(l.join("a", "A"), "already_in", "already racing")
	# Step until the next race forms (results + cooldown, then a new lobby).
	var steps := 0
	while not (l.phase in [RaceLogic.Phase.LOBBY, RaceLogic.Phase.COUNTDOWN]) and steps < 2000:
		l.step(0.1)
		steps += 1
	check(l.entrants.any(func(e): return e["id"] == "late"), "late joiner is in the next race")
	check(l.next_up.is_empty())


func test_raid_starts_race_with_raider() -> void:
	var l := _logic()
	check(l.raid("r1", "CoolStreamer", 42))
	check_eq(l.phase, RaceLogic.Phase.COUNTDOWN)
	var raider := l.entrants.filter(func(e): return e["raider"])
	check_eq(raider.size(), 1)
	check_eq(l.entrants.size(), 6)
	_run(l, 3.1)
	check(not l.raid("r2", "Other", 3), "no second raid race while racing")


func test_deterministic_with_seed() -> void:
	var results := []
	for attempt in 2:
		var l := _logic({"min_humans_to_start": 1})
		l.join("a", "A")
		_run(l, 40.0)
		results.append(l.results.duplicate())
	check_eq(results[0], results[1])


func test_module_end_to_end() -> void:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var bus := ChaosEventBus.new()
	var router := CommandRouter.new()
	var cfg := ChaosConfig.from_dict({"modules": {"critter_race": {"seed": 7, "min_humans_to_start": 2, "countdown_s": 1.0}}})
	router.configure(cfg)
	var reg := ModuleRegistry.new()
	reg._bus = bus
	reg._router = router
	var m := reg.instantiate("res://modules/critter_race/module.gd")
	check(reg.load_module(m, parent, cfg, AssetLoader.new(), Vector2(1920, 1080)))
	check(router.has_command("join") and router.has_command("race"))
	for u in ["alice", "bob"]:
		var outcome := router.route({"type": "chat_message", "user_id": u, "user_login": u, "user_name": u.capitalize(), "text": "!join"}, 0.0)
		check_eq(outcome, "queued")
		bus.emit("chat_command", router.queue.pop())
	m._process(0.016)
	check(m.visible, "race panel visible")
	check_eq(m.logic.phase, RaceLogic.Phase.COUNTDOWN)
	check_eq(m._critters.size(), 6, "6 critter nodes on screen")
	var kinds: Array = m._critters.values().map(func(n): return n.get_child(0).get_meta("visual_kind"))
	check(kinds.all(func(k): return k == "shape"), "placeholder shapes without sprites")
	for i in 70 * 10:
		m._process(0.1)
		if m.logic.phase == RaceLogic.Phase.IDLE:
			break
	check_eq(m.logic.phase, RaceLogic.Phase.IDLE, "race finished and reset")
	check(not m.visible)
	reg.shutdown()
	await tree.process_frame
	parent.free()
