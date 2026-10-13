class_name ChaosEventQueue
extends RefCounted
## Shared, bounded FIFO queue for viewer-triggered events.
##
## Overflow policy: reject the NEW event (what's already queued keeps its
## place), so a burst can't push out other viewers' earlier requests.
## Fairness: each user may have at most `max_pending_per_user` events waiting.

enum Result { ACCEPTED, REJECTED_FULL, REJECTED_USER_LIMIT }

var capacity: int
var max_pending_per_user: int

var _items: Array[Dictionary] = []
var _pending_by_user: Dictionary = {}

## Counters for status/diagnostics.
var accepted_total := 0
var rejected_full_total := 0
var rejected_user_total := 0


func _init(p_capacity: int = 50, p_max_pending_per_user: int = 2) -> void:
	capacity = maxi(1, p_capacity)
	max_pending_per_user = maxi(1, p_max_pending_per_user)


## `event` must be a Dictionary; its "user_id" (or "user_login") key is used
## for the per-user limit. System events (raids, follows) may use any id.
func push(event: Dictionary) -> Result:
	var user := _user_of(event)
	if _pending_by_user.get(user, 0) >= max_pending_per_user:
		rejected_user_total += 1
		return Result.REJECTED_USER_LIMIT
	if _items.size() >= capacity:
		rejected_full_total += 1
		return Result.REJECTED_FULL
	_items.append(event)
	_pending_by_user[user] = _pending_by_user.get(user, 0) + 1
	accepted_total += 1
	return Result.ACCEPTED


## Removes and returns the oldest event, or an empty Dictionary if none.
func pop() -> Dictionary:
	if _items.is_empty():
		return {}
	var event: Dictionary = _items.pop_front()
	var user := _user_of(event)
	var left: int = _pending_by_user.get(user, 1) - 1
	if left <= 0:
		_pending_by_user.erase(user)
	else:
		_pending_by_user[user] = left
	return event


func size() -> int:
	return _items.size()


func is_empty() -> bool:
	return _items.is_empty()


func pending_for(user: String) -> int:
	return _pending_by_user.get(user.to_lower(), 0)


func clear() -> void:
	_items.clear()
	_pending_by_user.clear()


static func _user_of(event: Dictionary) -> String:
	var user := str(event.get("user_id", ""))
	if user == "":
		user = str(event.get("user_login", "?"))
	return user.to_lower()
