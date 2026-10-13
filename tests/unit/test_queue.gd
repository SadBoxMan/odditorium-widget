extends TestCase


func _ev(user: String, n: int = 0) -> Dictionary:
	return {"type": "chat_command", "user_id": user, "n": n}


func test_fifo_order() -> void:
	var q := ChaosEventQueue.new(10, 10)
	for i in 5:
		q.push(_ev("u%d" % i, i))
	for i in 5:
		check_eq(q.pop()["n"], i)
	check(q.is_empty())


func test_pop_empty_returns_empty_dict() -> void:
	var q := ChaosEventQueue.new()
	check_eq(q.pop(), {})


func test_capacity_rejects_newest() -> void:
	var q := ChaosEventQueue.new(3, 10)
	for i in 3:
		check_eq(q.push(_ev("u%d" % i, i)), ChaosEventQueue.Result.ACCEPTED)
	check_eq(q.push(_ev("late", 99)), ChaosEventQueue.Result.REJECTED_FULL)
	check_eq(q.size(), 3)
	check_eq(q.pop()["n"], 0, "earliest event kept its place")
	check_eq(q.rejected_full_total, 1)


func test_per_user_pending_limit() -> void:
	var q := ChaosEventQueue.new(50, 2)
	check_eq(q.push(_ev("spammer")), ChaosEventQueue.Result.ACCEPTED)
	check_eq(q.push(_ev("spammer")), ChaosEventQueue.Result.ACCEPTED)
	check_eq(q.push(_ev("spammer")), ChaosEventQueue.Result.REJECTED_USER_LIMIT)
	check_eq(q.push(_ev("polite")), ChaosEventQueue.Result.ACCEPTED, "others still get in")
	check_eq(q.pending_for("spammer"), 2)
	q.pop()
	check_eq(q.pending_for("spammer"), 1, "slot freed after pop")
	check_eq(q.push(_ev("spammer")), ChaosEventQueue.Result.ACCEPTED)


func test_user_id_case_insensitive() -> void:
	var q := ChaosEventQueue.new(50, 1)
	q.push(_ev("Alice"))
	check_eq(q.push(_ev("alice")), ChaosEventQueue.Result.REJECTED_USER_LIMIT)


func test_falls_back_to_login_when_no_id() -> void:
	var q := ChaosEventQueue.new(50, 1)
	q.push({"user_login": "bob"})
	check_eq(q.push({"user_login": "bob"}), ChaosEventQueue.Result.REJECTED_USER_LIMIT)


func test_spam_cannot_starve_others() -> void:
	# One spammer floods 100 events into a queue of 10: they get at most 2
	# slots and everybody else still fits.
	var q := ChaosEventQueue.new(10, 2)
	for i in 100:
		q.push(_ev("spammer", i))
	for i in 8:
		check_eq(q.push(_ev("viewer%d" % i)), ChaosEventQueue.Result.ACCEPTED)
	check_eq(q.size(), 10)
	check_eq(q.rejected_user_total, 98)


func test_clear() -> void:
	var q := ChaosEventQueue.new(5, 1)
	q.push(_ev("a"))
	q.clear()
	check(q.is_empty())
	check_eq(q.pending_for("a"), 0)
