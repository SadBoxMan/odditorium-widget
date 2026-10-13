class_name ChaosConfig
extends RefCounted
## Loads the JSON config, merges it over built-in defaults and validates it.
##
## Bad values never crash the overlay: each problem is recorded in `errors`
## (wrong type, out of range, unparseable file) or `warnings` (unknown keys)
## and the default is used instead.
##
## Keys starting with "_" are treated as comments and ignored silently, so the
## config file can carry "_comment" / "_help" entries.

const DEFAULTS := {
	"streamerbot": {
		"host": "127.0.0.1",
		"port": 8080,
		"endpoint": "/",
		"password": "",
		"reconnect_initial_s": 1.0,
		"reconnect_max_s": 30.0,
		"handshake_timeout_s": 10.0,
		"max_message_bytes": 65536,
	},
	"window": {
		"width": 1920,
		"height": 1080,
		"x": -1,
		"y": -1,
		"borderless": true,
		"transparent": true,
		"always_on_top": false,
		"click_through": true,
		"background_color": "#00000000",
		"max_fps": 60,
	},
	"chat": {
		"command_prefix": "!",
		"ignore_users": [],
		"max_message_length": 300,
		"max_name_length": 25,
	},
	"cooldowns": {
		"per_user_global_s": 2.0,
		"default_command_s": 10.0,
		"follow_global_s": 2.0,
		"raid_global_s": 30.0,
	},
	"queue": {
		"capacity": 50,
		"max_pending_per_user": 2,
		"dispatch_per_second": 4.0,
	},
	"redeems": {
		"enabled": false,
		"bypass_user_cooldowns": true,
		"rewards": {
			"Bonk the Streamer": {"command": "bonk", "args_from_input": true},
		},
	},
	"modules": {},
	"debug": {
		"show_regions": false,
		"log_events": false,
		"show_status": true,
	},
}

## Paths whose user value replaces the default wholesale (open-ended maps).
const OPEN_PATHS := ["redeems.rewards", "modules"]

const CONSTRAINTS := {
	"streamerbot.port": {"min": 1, "max": 65535},
	"streamerbot.reconnect_initial_s": {"min": 0.1},
	"streamerbot.reconnect_max_s": {"min": 0.1},
	"streamerbot.handshake_timeout_s": {"min": 1.0},
	"streamerbot.max_message_bytes": {"min": 1024, "max": 16777216},
	"window.width": {"min": 64, "max": 16384},
	"window.height": {"min": 64, "max": 16384},
	"window.background_color": {"color": true},
	"window.max_fps": {"min": 0, "max": 1000},
	"chat.command_prefix": {"min_length": 1, "max_length": 3},
	"chat.max_message_length": {"min": 10, "max": 2000},
	"chat.max_name_length": {"min": 1, "max": 100},
	"cooldowns.per_user_global_s": {"min": 0.0},
	"cooldowns.default_command_s": {"min": 0.0},
	"cooldowns.follow_global_s": {"min": 0.0},
	"cooldowns.raid_global_s": {"min": 0.0},
	"queue.capacity": {"min": 1, "max": 10000},
	"queue.max_pending_per_user": {"min": 1, "max": 1000},
	"queue.dispatch_per_second": {"min": 0.1, "max": 1000.0},
}

var data: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []
## File the config came from ("" when built from a dictionary).
var source_path: String = ""
## Directory used to resolve relative asset paths.
var base_dir: String = "res://"

var _raw_user: Dictionary = {}


static func load_file(path: String) -> ChaosConfig:
	var cfg := ChaosConfig.new()
	cfg.source_path = path
	cfg.base_dir = path.get_base_dir() if path != "" else "res://"
	if path == "" or not FileAccess.file_exists(path):
		cfg.warnings.append("config file '%s' not found; using built-in defaults" % path)
		cfg._apply({})
		return cfg
	var text := FileAccess.get_file_as_string(path)
	cfg._apply_text(text)
	return cfg


static func from_json_text(text: String, base_dir_path: String = "res://") -> ChaosConfig:
	var cfg := ChaosConfig.new()
	cfg.base_dir = base_dir_path
	cfg._apply_text(text)
	return cfg


static func from_dict(user: Dictionary, base_dir_path: String = "res://") -> ChaosConfig:
	var cfg := ChaosConfig.new()
	cfg.base_dir = base_dir_path
	cfg._apply(user)
	return cfg


## Picks the config path: `--config=<path>` on the command line (after `--`),
## else `lucidin_chaos.local.json` (git-ignored), else `lucidin_chaos.json`,
## both looked up next to the project / executable.
static func find_config_path(user_args: PackedStringArray) -> String:
	for arg in user_args:
		if arg.begins_with("--config="):
			return arg.substr("--config=".length())
	var dirs: Array[String] = ["res://"]
	if not OS.has_feature("editor"):
		dirs.append(OS.get_executable_path().get_base_dir() + "/")
	for name in ["lucidin_chaos.local.json", "lucidin_chaos.json"]:
		for dir in dirs:
			var candidate: String = dir + name
			if FileAccess.file_exists(candidate):
				return candidate
	return "res://lucidin_chaos.json"


## Dotted lookup, e.g. get_value("queue.capacity").
func get_value(path: String, fallback: Variant = null) -> Variant:
	var node: Variant = data
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(part):
			return fallback
		node = node[part]
	return node


func section(name: String) -> Dictionary:
	var value: Variant = data.get(name, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


## Merges the user's `modules.<module_id>` section over the module's own
## defaults, validates it, stores the result in data.modules[module_id] and
## returns it. Problems are appended to errors/warnings with a module prefix.
func apply_module_defaults(module_id: String, defaults: Dictionary, open_paths: Array = [], constraints: Dictionary = {}) -> Dictionary:
	var raw_modules: Variant = _raw_user.get("modules", {})
	var user_section: Variant = null
	if typeof(raw_modules) == TYPE_DICTIONARY:
		user_section = raw_modules.get(module_id, null)
	var prefix := "modules." + module_id
	var full_open: Array = []
	for p in open_paths:
		full_open.append(prefix + "." + p)
	var full_constraints := {}
	for p in constraints:
		full_constraints[prefix + "." + p] = constraints[p]
	var merged := merge(defaults, user_section, prefix, full_open, full_constraints, errors, warnings)
	if not data.has("modules") or typeof(data["modules"]) != TYPE_DICTIONARY:
		data["modules"] = {}
	data["modules"][module_id] = merged
	return merged


## Returns true if the user config mentions modules.<id> at all.
func user_has_module_section(module_id: String) -> bool:
	var raw_modules: Variant = _raw_user.get("modules", {})
	return typeof(raw_modules) == TYPE_DICTIONARY and raw_modules.has(module_id)


func _apply_text(text: String) -> void:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		errors.append("config parse error at line %d: %s; using built-in defaults" % [json.get_error_line(), json.get_error_message()])
		_apply({})
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("config root must be a JSON object; using built-in defaults")
		_apply({})
		return
	_apply(json.data)


func _apply(user: Dictionary) -> void:
	_raw_user = user
	data = merge(DEFAULTS, user, "", OPEN_PATHS, CONSTRAINTS, errors, warnings)
	# Module sections are validated later by apply_module_defaults(); start
	# from an empty map so unvalidated user values never leak through.
	data["modules"] = {}
	_normalize()


func _normalize() -> void:
	var ignore: Array = []
	for name in data["chat"]["ignore_users"]:
		if typeof(name) == TYPE_STRING:
			ignore.append(name.strip_edges().to_lower().trim_prefix("@"))
		else:
			errors.append("chat.ignore_users: entries must be strings (got %s)" % type_string(typeof(name)))
	data["chat"]["ignore_users"] = ignore
	var rewards: Dictionary = data["redeems"]["rewards"]
	for title in rewards.keys():
		var entry: Variant = rewards[title]
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("command", null)) != TYPE_STRING or entry["command"].strip_edges() == "":
			errors.append("redeems.rewards.%s: needs {\"command\": \"<name>\"}; entry ignored" % title)
			rewards.erase(title)
			continue
		entry["command"] = entry["command"].strip_edges().to_lower()
		entry["args_from_input"] = bool(entry.get("args_from_input", true))


## Recursive merge + validation. Exposed as static so modules and tests can
## reuse it.
static func merge(defaults: Dictionary, user: Variant, prefix: String, open_paths: Array, constraints: Dictionary, errs: Array[String], warns: Array[String]) -> Dictionary:
	var out := defaults.duplicate(true)
	if user == null:
		return out
	if typeof(user) != TYPE_DICTIONARY:
		errs.append("%s: expected an object, got %s; using defaults" % [prefix if prefix != "" else "<root>", type_string(typeof(user))])
		return out
	for key in user.keys():
		var skey := str(key)
		if skey.begins_with("_"):
			continue
		var path := skey if prefix == "" else prefix + "." + skey
		if not defaults.has(skey):
			warns.append("%s: unknown key (ignored)" % path)
			continue
		var dv: Variant = defaults[skey]
		var uv: Variant = user[key]
		if typeof(dv) == TYPE_DICTIONARY:
			if path in open_paths:
				if typeof(uv) == TYPE_DICTIONARY:
					out[skey] = _strip_comments(uv)
				else:
					errs.append("%s: expected an object, got %s; using default" % [path, type_string(typeof(uv))])
			else:
				out[skey] = merge(dv, uv, path, open_paths, constraints, errs, warns)
			continue
		var coerced := coerce(dv, uv)
		if not coerced[0]:
			errs.append("%s: expected %s, got %s (%s); using default %s" % [path, type_string(typeof(dv)), type_string(typeof(uv)), JSON.stringify(uv), JSON.stringify(dv)])
			continue
		var value: Variant = coerced[1]
		var problem := check_constraint(constraints.get(path, {}), value)
		if problem != "":
			errs.append("%s: %s; using default %s" % [path, problem, JSON.stringify(dv)])
			continue
		out[skey] = value
	return out


## Returns [ok: bool, value]. JSON numbers always parse as float, so whole
## floats are accepted where an int is expected.
static func coerce(default_value: Variant, value: Variant) -> Array:
	match typeof(default_value):
		TYPE_INT:
			if typeof(value) == TYPE_INT:
				return [true, value]
			if typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value):
				return [true, int(value)]
			return [false, null]
		TYPE_FLOAT:
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
				var f := float(value)
				return [is_finite(f), f]
			return [false, null]
		TYPE_BOOL:
			return [typeof(value) == TYPE_BOOL, value]
		TYPE_STRING:
			return [typeof(value) == TYPE_STRING, value]
		TYPE_ARRAY:
			return [typeof(value) == TYPE_ARRAY, value]
	return [typeof(value) == typeof(default_value), value]


static func check_constraint(rule: Dictionary, value: Variant) -> String:
	if rule.is_empty():
		return ""
	if rule.has("min") and (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value < rule["min"]:
		return "must be >= %s (got %s)" % [rule["min"], value]
	if rule.has("max") and (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and value > rule["max"]:
		return "must be <= %s (got %s)" % [rule["max"], value]
	if rule.has("enum") and not (value in rule["enum"]):
		return "must be one of %s (got %s)" % [JSON.stringify(rule["enum"]), JSON.stringify(value)]
	if rule.get("color", false) and not (typeof(value) == TYPE_STRING and Color.html_is_valid(value)):
		return "must be a color like \"#ff8800\" (got %s)" % JSON.stringify(value)
	if typeof(value) == TYPE_STRING:
		if rule.has("min_length") and value.length() < rule["min_length"]:
			return "must be at least %d characters" % rule["min_length"]
		if rule.has("max_length") and value.length() > rule["max_length"]:
			return "must be at most %d characters" % rule["max_length"]
	return ""


static func _strip_comments(value: Dictionary) -> Dictionary:
	var out := {}
	for key in value.keys():
		if str(key).begins_with("_"):
			continue
		out[key] = value[key].duplicate(true) if typeof(value[key]) in [TYPE_DICTIONARY, TYPE_ARRAY] else value[key]
	return out
