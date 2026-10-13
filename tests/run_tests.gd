extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --script res://tests/run_tests.gd -- [options]
##
## Options:
##   --filter=<text>        only run test files/methods containing <text>
##   --modules-dir=<path>   directory the paid-event guard scans
##                          (default res://modules; point it at
##                          res://tests/fixtures/bad_modules to watch it fail)
## Exit code: 0 = all passed, 1 = failures.

const TEST_DIR := "res://tests/unit"


class ErrorCapture extends Logger:
	var _mutex := Mutex.new()
	var errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors.append("%s (%s:%d)" % [rationale if rationale != "" else code, file, line])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[String]:
		_mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return out


var _capture := ErrorCapture.new()


func _initialize() -> void:
	OS.add_logger(_capture)
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var modules_dir := "res://modules"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
		elif arg.begins_with("--modules-dir="):
			modules_dir = arg.substr(14)

	var files: Array[String] = []
	var da := DirAccess.open(TEST_DIR)
	for f in da.get_files():
		var name := f.trim_suffix(".remap")
		if name.begins_with("test_") and name.ends_with(".gd"):
			files.append(TEST_DIR.path_join(name))
	files.sort()

	var passed := 0
	var failed: Array[String] = []
	var started := Time.get_ticks_msec()
	for path in files:
		var script: Variant = load(path)
		if script == null:
			failed.append("%s: failed to load" % path)
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if m["name"].begins_with("test_") and not (m["name"] in methods):
				methods.append(m["name"])
		methods.sort()
		for method in methods:
			var full := "%s::%s" % [path.get_file().get_basename(), method]
			if filter != "" and not (filter in full):
				continue
			var t: TestCase = script.new()
			t.tree = self
			t.modules_dir = modules_dir
			t._reset()
			_capture.take()
			if t.has_method("before_each"):
				await t.before_each()
			await t.call(method)
			if t.has_method("after_each"):
				await t.after_each()
			# Let queued frees / deferred calls settle inside the test window.
			await process_frame
			var errs := _capture.take()
			var problems: Array[String] = t._failures.duplicate()
			if not t._allow_any_errors and errs.size() != t._expected_errors:
				problems.append("engine errors: expected %d, got %d: %s" % [t._expected_errors, errs.size(), "; ".join(errs)])
			if problems.is_empty():
				passed += 1
				print("  PASS  " + full)
			else:
				failed.append(full)
				print("  FAIL  " + full)
				for p in problems:
					print("        - " + p)

	var secs := (Time.get_ticks_msec() - started) / 1000.0
	print("")
	print("%d passed, %d failed (%.1fs)" % [passed, failed.size(), secs])
	for f in failed:
		print("FAILED: " + f)
	OS.remove_logger(_capture)
	quit(1 if not failed.is_empty() else 0)
