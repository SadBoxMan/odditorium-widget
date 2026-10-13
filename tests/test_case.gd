class_name TestCase
extends RefCounted
## Minimal test base for tests/run_tests.gd. Methods named test_* run in
## alphabetical order; they may `await`. Any engine/script error logged during
## a test fails it unless the test calls expect_errors() first.

var tree: SceneTree
## Directory scanned by the paid-event guard (overridable from the CLI so the
## guard can be demonstrated failing on tests/fixtures/bad_modules).
var modules_dir := "res://modules"

var _failures: Array[String] = []
var _expected_errors := 0
var _allow_any_errors := false


func fail(msg: String) -> void:
	_failures.append(msg)


func check(cond: bool, msg: String = "expected true") -> bool:
	if not cond:
		fail(msg)
	return cond


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	if typeof(actual) == typeof(expected) and actual == expected:
		return true
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT] and is_equal_approx(float(actual), float(expected)):
		return true
	fail("%sexpected %s, got %s" % [msg + ": " if msg != "" else "", var_to_str(expected), var_to_str(actual)])
	return false


func check_approx(actual: float, expected: float, eps: float = 0.001, msg: String = "") -> bool:
	if absf(actual - expected) <= eps:
		return true
	fail("%sexpected ~%s, got %s" % [msg + ": " if msg != "" else "", expected, actual])
	return false


## Declares that this test deliberately triggers `count` engine errors
## (e.g. a module that crashes on purpose). -1 = any number.
func expect_errors(count: int = -1) -> void:
	if count < 0:
		_allow_any_errors = true
	else:
		_expected_errors += count


## Awaits frames until `cond.call()` is true or `timeout_s` passes.
func wait_until(cond: Callable, timeout_s: float = 5.0) -> bool:
	var start := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - start > timeout_s * 1000.0:
			return false
		await tree.process_frame
	return true


func wait_frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func wait_seconds(s: float) -> void:
	await tree.create_timer(s).timeout


func _reset() -> void:
	_failures.clear()
	_expected_errors = 0
	_allow_any_errors = false
