class_name CooldownManager
extends RefCounted
## Per-user and per-command cooldowns.
##
## Time is always passed in (seconds, monotonic) so tests can drive it.
## Keys are lower-cased user ids; GLOBAL_USER is used for channel-wide
## cooldowns such as "one follow celebration every N seconds".

const GLOBAL_USER := "*"
const ANY_COMMAND := "*"

## key "user|command" -> time the cooldown ends.
var _ready_at: Dictionary = {}


## Returns seconds left before `user` may run `command` again (0 = ready).
func remaining(user: String, command: String, now: float) -> float:
	var key := _key(user, command)
	if not _ready_at.has(key):
		return 0.0
	return maxf(0.0, _ready_at[key] - now)


func is_ready(user: String, command: String, now: float) -> bool:
	return remaining(user, command, now) <= 0.0


## Starts a cooldown of `duration_s` for user+command.
func trigger(user: String, command: String, duration_s: float, now: float) -> void:
	if duration_s <= 0.0:
		return
	var key := _key(user, command)
	_ready_at[key] = maxf(_ready_at.get(key, 0.0), now + duration_s)


## Checks every (command, duration) pair in `checks` for the user and, only if
## all are ready, starts all of them. Returns 0.0 on success, otherwise the
## longest remaining wait in seconds (and starts nothing).
##
## `checks` is an Array of [command: String, duration_s: float].
func try_consume(user: String, checks: Array, now: float) -> float:
	var wait := 0.0
	for check in checks:
		wait = maxf(wait, remaining(user, check[0], now))
	if wait > 0.0:
		return wait
	for check in checks:
		trigger(user, check[0], check[1], now)
	return 0.0


func reset(user: String = "", command: String = "") -> void:
	if user == "" and command == "":
		_ready_at.clear()
		return
	_ready_at.erase(_key(user, command))


## Drops expired entries so long streams don't grow the table forever.
func prune(now: float) -> void:
	for key in _ready_at.keys():
		if _ready_at[key] <= now:
			_ready_at.erase(key)


func size() -> int:
	return _ready_at.size()


static func _key(user: String, command: String) -> String:
	return user.to_lower() + "|" + command.to_lower()
