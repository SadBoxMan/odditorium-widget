extends ChaosModule
## Fixture: a well-behaved module that counts what it receives.

var received: Array = []


func subscribes_to() -> Array:
	return ["chat_command", "raid", "follow"]


func get_commands() -> Array:
	return [{"name": "count", "cooldown_s": 0.0}]


func on_event(event: Dictionary) -> bool:
	received.append(event)
	return true
