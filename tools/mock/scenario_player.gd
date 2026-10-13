class_name MockScenarioPlayer
extends Node
## Plays a JSON scenario against a MockStreamerBot. See tools/scenarios/*.json.
##
## Steps run in order; most accept an optional "wait" (seconds) applied after
## the step. Step kinds:
##   {"wait": 1.0}
##   {"await_subscribed": true, "timeout": 20}
##   {"chat": {"user": "alice", "text": "!join", "display": "Alice"}}
##   {"redeem": {"user": "bob", "title": "Bonk the Streamer", "input": "alice"}}
##   {"raid": {"from": "coolstreamer", "viewers": 42}}
##   {"follow": {"user": "newbie"}}
##   {"event": {"source": "Twitch", "type": "Cheer", "data": {}}, "force": true}
##   {"raw": "{not json"}
##   {"oversized": 200000}           # a valid-JSON message of ~N bytes
##   {"binary": true}
##   {"spam": {"user": "x", "text": "!bonk", "count": 50, "interval": 0.02}}
##   {"chatters": {"count": 30, "text": "!join", "interval": 0.05}}
##   {"disconnect": "abrupt" | "clean"}
##   {"server_down": 3.0}
##   {"log": "message"}

signal finished

var server: MockStreamerBot
var steps: Array = []
var loop := false
var scenario_name := ""
var errors: Array[String] = []


static func load_scenario(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("steps", null)) != TYPE_ARRAY:
		return {}
	return data


func play() -> void:
	while true:
		for i in steps.size():
			await _run_step(steps[i], i)
		if not loop:
			break
		print("[mock] scenario '%s' looping" % scenario_name)
	print("[mock] scenario '%s' finished; stats %s" % [scenario_name, JSON.stringify(server.stats)])
	finished.emit()


func _run_step(step: Variant, index: int) -> void:
	if typeof(step) != TYPE_DICTIONARY:
		errors.append("step %d is not an object" % index)
		return
	if step.has("log"):
		print("[mock] --- %s" % step["log"])
	if step.has("await_subscribed"):
		var timeout: float = step.get("timeout", 20.0)
		var start := Time.get_ticks_msec() / 1000.0
		while server.subscribed_client_count() == 0:
			if Time.get_ticks_msec() / 1000.0 - start > timeout:
				errors.append("step %d: no client subscribed within %.0fs" % [index, timeout])
				print("[mock] ERROR waiting for subscription timed out")
				break
			await get_tree().process_frame
	if step.has("chat"):
		var c: Dictionary = step["chat"]
		server.send_event("Twitch", "ChatMessage", MockStreamerBot.chat_data(c.get("user", "viewer"), c.get("text", ""), c.get("display", ""), c.get("user_id", "")))
	if step.has("redeem"):
		var r: Dictionary = step["redeem"]
		server.send_event("Twitch", "RewardRedemption", MockStreamerBot.redeem_data(r.get("user", "viewer"), r.get("title", ""), r.get("input", ""), r.get("display", "")), step.get("force", false))
	if step.has("raid"):
		var r: Dictionary = step["raid"]
		server.send_event("Twitch", "Raid", MockStreamerBot.raid_data(r.get("from", "raider"), int(r.get("viewers", 10))))
	if step.has("follow"):
		server.send_event("Twitch", "Follow", MockStreamerBot.follow_data(step["follow"].get("user", "follower")))
	if step.has("event"):
		var e: Dictionary = step["event"]
		var sent := server.send_event(e.get("source", "Twitch"), e.get("type", ""), e.get("data", {}), step.get("force", false))
		print("[mock] sent %s.%s to %d client(s)" % [e.get("source", "Twitch"), e.get("type", ""), sent])
	if step.has("raw"):
		server.send_raw(str(step["raw"]))
	if step.has("oversized"):
		var n: int = int(step["oversized"])
		server.send_raw(JSON.stringify({"event": {"source": "Twitch", "type": "ChatMessage"}, "data": MockStreamerBot.chat_data("biggy", "!join " + "x".repeat(n))}))
	if step.has("binary"):
		server.send_binary(PackedByteArray([0, 1, 2, 3, 255]))
	if step.has("spam"):
		var s: Dictionary = step["spam"]
		for i in int(s.get("count", 10)):
			server.send_event("Twitch", "ChatMessage", MockStreamerBot.chat_data(s.get("user", "spammer"), s.get("text", "!join")))
			await _sleep(float(s.get("interval", 0.0)))
	if step.has("chatters"):
		var s: Dictionary = step["chatters"]
		for i in int(s.get("count", 10)):
			server.send_event("Twitch", "ChatMessage", MockStreamerBot.chat_data("chatter%02d" % i, s.get("text", "!join")))
			await _sleep(float(s.get("interval", 0.0)))
	if step.has("disconnect"):
		server.disconnect_all(step["disconnect"] == "clean")
	if step.has("server_down"):
		server.go_down(float(step["server_down"]))
	var wait: float = float(step.get("wait", 0.0))
	if wait > 0.0:
		await _sleep(wait)
	else:
		await get_tree().process_frame


func _sleep(seconds: float) -> void:
	if seconds <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(seconds).timeout
