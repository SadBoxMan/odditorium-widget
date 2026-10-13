class_name ChaosEventBus
extends RefCounted
## Routes internal events to subscribers by type, isolating failures.
##
## Handlers must return `true` when they ran to completion. GDScript has no
## exceptions: a runtime error aborts the handler and the call returns null.
## The bus counts that as a failure; after `max_failures` consecutive failures
## the subscriber's owner is reported via `on_owner_failed` so the registry
## can disable it. One broken module never stops the others from receiving
## the event.

## Called as on_owner_failed.call(owner_id: String, reason: String).
var on_owner_failed: Callable = Callable()
var max_failures := 5

## type -> Array of {owner: String, handler: Callable}
var _subs: Dictionary = {}
var _consecutive_failures: Dictionary = {}
var _disabled: Dictionary = {}

var delivered_total := 0
var failed_total := 0


func subscribe(event_type: String, owner_id: String, handler: Callable) -> void:
	if PaidEvents.is_paid_internal(event_type):
		push_error("[bus] refusing paid event subscription '%s' from '%s'" % [event_type, owner_id])
		return
	if not _subs.has(event_type):
		_subs[event_type] = []
	_subs[event_type].append({"owner": owner_id, "handler": handler})


func unsubscribe_owner(owner_id: String) -> void:
	for t in _subs.keys():
		_subs[t] = _subs[t].filter(func(s): return s["owner"] != owner_id)


func is_disabled(owner_id: String) -> bool:
	return _disabled.has(owner_id)


func subscriber_count(event_type: String) -> int:
	return _subs.get(event_type, []).size()


## Returns the number of handlers that completed successfully.
func emit(event_type: String, event: Dictionary) -> int:
	if PaidEvents.is_paid_internal(event_type):
		return 0
	var ok_count := 0
	for sub in _subs.get(event_type, []).duplicate():
		var owner: String = sub["owner"]
		if _disabled.has(owner):
			continue
		var handler: Callable = sub["handler"]
		if not handler.is_valid():
			_record_failure(owner, "handler no longer valid")
			continue
		# Each handler gets its own copy so one module can't mutate what the
		# next one sees.
		var result: Variant = handler.call(event.duplicate(true))
		if result == true:
			ok_count += 1
			delivered_total += 1
			_consecutive_failures.erase(owner)
		else:
			_record_failure(owner, "handler for '%s' errored or did not return true" % event_type)
	return ok_count


func _record_failure(owner: String, reason: String) -> void:
	failed_total += 1
	var n: int = _consecutive_failures.get(owner, 0) + 1
	_consecutive_failures[owner] = n
	push_warning("[bus] module '%s' failure %d/%d: %s" % [owner, n, max_failures, reason])
	if n >= max_failures and not _disabled.has(owner):
		_disabled[owner] = true
		push_warning("[bus] module '%s' disabled after %d consecutive failures" % [owner, n])
		if on_owner_failed.is_valid():
			on_owner_failed.call(owner, reason)
