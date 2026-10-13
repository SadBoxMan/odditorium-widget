class_name CommandRouter
extends RefCounted
## Turns normalized Streamer.bot events into queued internal events.
##
## chat_message -> "!cmd args" -> chat_command (if a module owns the command)
## redeem       -> mapped via config redeems.rewards -> chat_command (via_redeem)
## raid/follow  -> passed through with a channel-wide cooldown
##
## Cooldowns are checked BEFORE queueing so spam never fills the queue, and
## unknown commands never consume a cooldown.

const MAX_ARGS := 8

var prefix := "!"
var ignore_users: Array = []
var per_user_global_s := 2.0
var default_command_s := 10.0
var follow_global_s := 2.0
var raid_global_s := 30.0
var redeems_enabled := false
var redeem_bypass_cooldowns := true
## lower-case reward title -> {"command": String, "args_from_input": bool}
var rewards: Dictionary = {}

var cooldowns := CooldownManager.new()
var queue := ChaosEventQueue.new()

## command or alias -> {"command": canonical, "module": id, "cooldown_s": float}
var _commands: Dictionary = {}

var stats := {
	"queued": 0,
	"not_command": 0,
	"unknown_command": 0,
	"cooldown": 0,
	"queue_full": 0,
	"user_limit": 0,
	"ignored_user": 0,
	"redeems_disabled": 0,
	"unmapped_redeem": 0,
	"dropped": 0,
}


func configure(cfg: ChaosConfig) -> void:
	prefix = cfg.get_value("chat.command_prefix", "!")
	ignore_users = cfg.get_value("chat.ignore_users", [])
	per_user_global_s = cfg.get_value("cooldowns.per_user_global_s", 2.0)
	default_command_s = cfg.get_value("cooldowns.default_command_s", 10.0)
	follow_global_s = cfg.get_value("cooldowns.follow_global_s", 2.0)
	raid_global_s = cfg.get_value("cooldowns.raid_global_s", 30.0)
	redeems_enabled = cfg.get_value("redeems.enabled", false)
	redeem_bypass_cooldowns = cfg.get_value("redeems.bypass_user_cooldowns", true)
	rewards.clear()
	var raw_rewards: Dictionary = cfg.get_value("redeems.rewards", {})
	for title in raw_rewards.keys():
		rewards[str(title).strip_edges().to_lower()] = raw_rewards[title]
	queue = ChaosEventQueue.new(cfg.get_value("queue.capacity", 50), cfg.get_value("queue.max_pending_per_user", 2))


## cooldown_s < 0 means "use cooldowns.default_command_s".
func register_command(name: String, module_id: String, cooldown_s: float = -1.0, aliases: Array = []) -> void:
	var canonical := name.strip_edges().to_lower()
	var entry := {"command": canonical, "module": module_id, "cooldown_s": cooldown_s if cooldown_s >= 0.0 else default_command_s}
	for n in [canonical] + aliases:
		var key := str(n).strip_edges().to_lower()
		if _commands.has(key) and _commands[key]["module"] != module_id:
			push_warning("[router] command '%s' already owned by '%s'; '%s' ignored" % [key, _commands[key]["module"], module_id])
			continue
		_commands[key] = entry


func unregister_module(module_id: String) -> void:
	for key in _commands.keys():
		if _commands[key]["module"] == module_id:
			_commands.erase(key)


func has_command(name: String) -> bool:
	return _commands.has(name.to_lower())


func command_names() -> Array:
	return _commands.keys()


## Returns an outcome code (also counted in `stats`):
## queued, not_command, unknown_command, cooldown, queue_full, user_limit,
## ignored_user, redeems_disabled, unmapped_redeem, dropped.
func route(ev: Dictionary, now: float) -> String:
	var outcome := _route(ev, now)
	stats[outcome] = stats.get(outcome, 0) + 1
	return outcome


func _route(ev: Dictionary, now: float) -> String:
	var login := str(ev.get("user_login", "")).to_lower()
	var user_id := str(ev.get("user_id", login)).to_lower()
	match ev.get("type", ""):
		"chat_message":
			if login in ignore_users:
				return "ignored_user"
			var parsed := parse_command(str(ev.get("text", "")), prefix)
			if parsed.is_empty():
				return "not_command"
			var entry: Variant = _commands.get(parsed["command"], null)
			if entry == null:
				return "unknown_command"
			var wait := cooldowns.try_consume(user_id, [
				[CooldownManager.ANY_COMMAND, per_user_global_s],
				[entry["command"], entry["cooldown_s"]],
			], now)
			if wait > 0.0:
				return "cooldown"
			return _push(_command_event(ev, entry, parsed["args"], false))
		"redeem":
			if not redeems_enabled:
				return "redeems_disabled"
			var reward: Variant = rewards.get(str(ev.get("reward_title", "")).strip_edges().to_lower(), null)
			if reward == null:
				return "unmapped_redeem"
			var entry: Variant = _commands.get(reward["command"], null)
			if entry == null:
				return "unknown_command"
			if not redeem_bypass_cooldowns:
				if cooldowns.try_consume(user_id, [[entry["command"], entry["cooldown_s"]]], now) > 0.0:
					return "cooldown"
			var args: Array = split_args(str(ev.get("text", ""))) if reward.get("args_from_input", true) else []
			return _push(_command_event(ev, entry, args, true))
		"raid":
			if cooldowns.try_consume(CooldownManager.GLOBAL_USER, [["raid", raid_global_s]], now) > 0.0:
				return "cooldown"
			return _push(ev.duplicate())
		"follow":
			if cooldowns.try_consume(CooldownManager.GLOBAL_USER, [["follow", follow_global_s]], now) > 0.0:
				return "cooldown"
			return _push(ev.duplicate())
	return "dropped"


func _command_event(ev: Dictionary, entry: Dictionary, args: Array, via_redeem: bool) -> Dictionary:
	return {
		"type": "chat_command",
		"command": entry["command"],
		"module": entry["module"],
		"args": args,
		"user_id": ev.get("user_id", ""),
		"user_login": ev.get("user_login", ""),
		"user_name": ev.get("user_name", ""),
		"text": ev.get("text", ""),
		"via_redeem": via_redeem,
		"reward_title": ev.get("reward_title", ""),
	}


func _push(ev: Dictionary) -> String:
	match queue.push(ev):
		ChaosEventQueue.Result.ACCEPTED:
			return "queued"
		ChaosEventQueue.Result.REJECTED_FULL:
			return "queue_full"
		_:
			return "user_limit"


## "!Bonk @Someone hard" -> {"command": "bonk", "args": ["@Someone", "hard"]}
## Returns {} when the text isn't a command.
static func parse_command(text: String, cmd_prefix: String) -> Dictionary:
	var t := text.strip_edges()
	if cmd_prefix == "" or not t.begins_with(cmd_prefix):
		return {}
	var parts := split_args(t.substr(cmd_prefix.length()))
	if parts.is_empty():
		return {}
	var command: String = parts[0].to_lower()
	if not command.is_valid_ascii_identifier() and not _is_simple_word(command):
		return {}
	return {"command": command, "args": parts.slice(1)}


static func split_args(text: String) -> Array:
	var out: Array = []
	for p in text.strip_edges().split(" ", false):
		var s := p.strip_edges()
		if s != "":
			out.append(s)
		if out.size() > MAX_ARGS:
			break
	return out


## "@SomeUser," -> "someuser" (login-ish form of a user argument).
static func clean_user_arg(arg: String) -> String:
	var s := arg.strip_edges().trim_prefix("@")
	var out := ""
	for c in s:
		if c.is_valid_ascii_identifier() or c.is_valid_int():
			out += c
	return out.to_lower().substr(0, 25)


static func _is_simple_word(s: String) -> bool:
	if s.length() == 0 or s.length() > 32:
		return false
	for c in s:
		if not (c.is_valid_ascii_identifier() or c.is_valid_int() or c == "-"):
			return false
	return true
