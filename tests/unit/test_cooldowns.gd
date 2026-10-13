extends TestCase


func test_ready_when_never_used() -> void:
	var cd := CooldownManager.new()
	check(cd.is_ready("alice", "join", 0.0))
	check_eq(cd.remaining("alice", "join", 0.0), 0.0)


func test_trigger_blocks_until_expiry() -> void:
	var cd := CooldownManager.new()
	cd.trigger("alice", "join", 10.0, 100.0)
	check(not cd.is_ready("alice", "join", 100.0), "blocked right after trigger")
	check_approx(cd.remaining("alice", "join", 104.0), 6.0)
	check(not cd.is_ready("alice", "join", 109.99), "still blocked just before expiry")
	check(cd.is_ready("alice", "join", 110.0), "ready at expiry")


func test_per_user_isolation() -> void:
	var cd := CooldownManager.new()
	cd.trigger("alice", "bonk", 30.0, 0.0)
	check(cd.is_ready("bob", "bonk", 1.0), "bob unaffected by alice")
	check(cd.is_ready("alice", "join", 1.0), "other command unaffected")


func test_case_insensitive_keys() -> void:
	var cd := CooldownManager.new()
	cd.trigger("Alice", "BONK", 5.0, 0.0)
	check(not cd.is_ready("alice", "bonk", 1.0))


func test_zero_duration_never_blocks() -> void:
	var cd := CooldownManager.new()
	cd.trigger("alice", "join", 0.0, 0.0)
	check(cd.is_ready("alice", "join", 0.0))
	check_eq(cd.size(), 0)


func test_try_consume_all_or_nothing() -> void:
	var cd := CooldownManager.new()
	var checks := [[CooldownManager.ANY_COMMAND, 2.0], ["bonk", 10.0]]
	check_eq(cd.try_consume("alice", checks, 0.0), 0.0, "first use passes")
	# Global 2 s expired, command 10 s not: rejected, and the global cooldown
	# must NOT be restarted by the rejected attempt.
	var wait := cd.try_consume("alice", checks, 3.0)
	check_approx(wait, 7.0, 0.001, "reports longest wait")
	check(cd.is_ready("alice", CooldownManager.ANY_COMMAND, 3.0), "rejected attempt didn't re-arm global")
	check_eq(cd.try_consume("alice", checks, 10.0), 0.0, "passes after expiry")


func test_global_user_cooldown_is_channel_wide() -> void:
	var cd := CooldownManager.new()
	check_eq(cd.try_consume(CooldownManager.GLOBAL_USER, [["follow", 2.0]], 0.0), 0.0)
	check(cd.try_consume(CooldownManager.GLOBAL_USER, [["follow", 2.0]], 1.0) > 0.0)


func test_trigger_never_shortens_existing() -> void:
	var cd := CooldownManager.new()
	cd.trigger("a", "x", 30.0, 0.0)
	cd.trigger("a", "x", 1.0, 5.0)
	check_approx(cd.remaining("a", "x", 5.0), 25.0)


func test_prune_and_reset() -> void:
	var cd := CooldownManager.new()
	cd.trigger("a", "x", 1.0, 0.0)
	cd.trigger("b", "x", 100.0, 0.0)
	cd.prune(50.0)
	check_eq(cd.size(), 1, "expired entry pruned")
	cd.reset()
	check_eq(cd.size(), 0)
