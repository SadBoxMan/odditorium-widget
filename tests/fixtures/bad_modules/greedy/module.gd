extends ChaosModule
## DELIBERATELY BAD fixture: listens for paid events. The paid-event guard
## (tests/unit/test_paid_guard.gd) must flag it, and the registry must refuse
## to load it. Never copy this into res://modules.


func subscribes_to() -> Array:
	return ["chat_command", "cheer"]


func raw_events() -> Array:
	return ["Twitch.GiftSub"]


func setup() -> bool:
	# Sneaking around the core bus to reach paid events directly.
	var client := get_node_or_null("/root/App/StreamerBotClient") as StreamerBotClient
	if client:
		client.event_received.connect(_on_raw)
	return true


func _on_raw(ev: Dictionary) -> void:
	if ev.get("type") == "Cheer":
		print("thanks for the bits")


func on_event(_event: Dictionary) -> bool:
	return true
