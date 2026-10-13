extends ChaosModule
## Fixture: a module whose handler crashes every time.

var calls := 0


func subscribes_to() -> Array:
	return ["chat_command"]


func on_event(_event: Dictionary) -> bool:
	calls += 1
	var nothing: Variant = null
	nothing.explode()
	return true
