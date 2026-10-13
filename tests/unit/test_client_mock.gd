extends TestCase
## StreamerBotClient against the in-process MockStreamerBot.

var server: MockStreamerBot
var client: StreamerBotClient
var received: Array = []
var port := 0


func before_each() -> void:
	received = []
	port = 21000 + randi() % 20000
	server = MockStreamerBot.new()
	server.verbose = false
	tree.root.add_child(server)


func after_each() -> void:
	if client:
		client.stop()
		client.queue_free()
		client = null
	server.stop()
	server.queue_free()


func _start_client(password: String = "") -> void:
	client = StreamerBotClient.new()
	client.url = "ws://127.0.0.1:%d/" % port
	client.password = password
	client.reconnect_initial_s = 0.2
	client.reconnect_max_s = 0.5
	client.handshake_timeout_s = 3.0
	client.max_message_bytes = 4096
	client.set_subscription(SBProtocol.subscription_for(["chat_command", "raid"], true))
	client.event_received.connect(func(ev): received.append(ev))
	tree.root.add_child(client)
	client.start()


func _ready_state() -> bool:
	return client.state == StreamerBotClient.State.READY


func test_handshake_subscribe_and_receive() -> void:
	server.start(port)
	_start_client()
	check(await wait_until(_ready_state, 5.0), "client reached READY")
	check_eq(server.subscribed_client_count(), 1)
	server.send_event("Twitch", "ChatMessage", MockStreamerBot.chat_data("alice", "!join"))
	server.send_event("Twitch", "Raid", MockStreamerBot.raid_data("pal", 12))
	check(await wait_until(func(): return received.size() == 2, 3.0), "events delivered")
	if received.size() == 2:
		check_eq(received[0]["type"], "chat_message")
		check_eq(received[0]["text"], "!join")
		check_eq(received[1]["type"], "raid")
		check_eq(received[1]["viewers"], 12)


func test_unsubscribed_events_not_sent() -> void:
	server.start(port)
	_start_client()
	await wait_until(_ready_state, 5.0)
	check_eq(server.send_event("Twitch", "Follow", MockStreamerBot.follow_data("x")), 0, "follow wasn't subscribed")
	check_eq(server.send_event("Twitch", "Cheer", {"bits": 100}), 0, "paid event never subscribed")


func test_authentication_success() -> void:
	server.password = "s3cret"
	server.start(port)
	_start_client("s3cret")
	check(await wait_until(_ready_state, 5.0), "authenticated + subscribed")
	check_eq(client.stats["auth_failures"], 0)


func test_authentication_wrong_password() -> void:
	server.password = "s3cret"
	server.start(port)
	_start_client("nope")
	check(await wait_until(func(): return client.stats["auth_failures"] >= 1, 5.0), "auth failure detected")
	check(not _ready_state())
	check_eq(server.subscribed_client_count(), 0)


func test_authentication_required_but_no_password() -> void:
	server.password = "s3cret"
	server.start(port)
	_start_client("")
	check(await wait_until(func(): return client.stats["auth_failures"] >= 1, 5.0))
	check(not _ready_state())


func test_bad_payloads_are_survived() -> void:
	server.start(port)
	_start_client()
	await wait_until(_ready_state, 5.0)
	server.send_raw("{not json")
	server.send_raw("[]")
	server.send_raw('{"event":{"source":"Twitch"}}')
	server.send_raw(JSON.stringify({"event": {"source": "Twitch", "type": "ChatMessage"}, "data": MockStreamerBot.chat_data("big", "x".repeat(5000))}))
	server.send_binary(PackedByteArray([1, 2, 3]))
	server.send_event("Twitch", "Cheer", {"bits": 500, "message": {"userId": "1", "username": "rich"}}, true)
	server.send_event("Twitch", "ChatMessage", {"message": "not-an-object"})
	server.send_event("Twitch", "ChatMessage", MockStreamerBot.chat_data("ok", "!join"))
	check(await wait_until(func(): return received.size() >= 1, 3.0), "valid event after junk still arrives")
	check_eq(received.size(), 1, "only the valid event was emitted")
	check_eq(client.stats["invalid_messages"], 5)
	check_eq(client.stats["ignored_events"], 2, "forced paid event + shapeless chat ignored")
	check(_ready_state(), "still connected")


func test_reconnects_after_abrupt_disconnect() -> void:
	server.start(port)
	_start_client()
	await wait_until(_ready_state, 5.0)
	server.disconnect_all(false)
	check(await wait_until(func(): return not _ready_state(), 3.0), "noticed the drop")
	check(await wait_until(_ready_state, 5.0), "reconnected")
	check_eq(client.stats["connects"], 2)
	server.send_event("Twitch", "ChatMessage", MockStreamerBot.chat_data("back", "!join"))
	check(await wait_until(func(): return received.size() == 1, 3.0), "events flow after reconnect")


func test_reconnects_after_server_down() -> void:
	server.start(port)
	_start_client()
	await wait_until(_ready_state, 5.0)
	server.go_down(1.0)
	check(await wait_until(func(): return not _ready_state(), 3.0))
	check(await wait_until(_ready_state, 8.0), "reconnected once the server came back")


func test_connects_when_server_starts_late() -> void:
	_start_client()
	await wait_seconds(0.6)
	check(not _ready_state())
	server.start(port)
	check(await wait_until(_ready_state, 5.0), "picked up the late server")
