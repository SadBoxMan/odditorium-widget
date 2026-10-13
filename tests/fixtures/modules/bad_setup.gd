extends ChaosModule
## Fixture: setup() crashes.


func subscribes_to() -> Array:
	return ["chat_command"]


func setup() -> bool:
	var nothing: Variant = null
	return nothing.boom()
