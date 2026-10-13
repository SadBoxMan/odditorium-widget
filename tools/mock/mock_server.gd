class_name MockStreamerBot
extends Node
## A small stand-in for Streamer.bot's WebSocket server, for local testing
## and automated tests. Implements Hello, optional Authenticate, Subscribe,
## UnSubscribe, GetInfo and GetEvents, and only forwards events a client has
## subscribed to (unless forced), like the real server.

signal client_subscribed(peer_index: int, events: Dictionary)
signal log_line(text: String)

var port := 8080
var password := ""
var verbose := true

var _server: TCPServer
var _clients: Array = []  # [{tcp, ws, authed, subs: Dictionary, open: bool}]
var _down_until := 0.0

var stats := {"connections": 0, "requests": 0, "events_sent": 0, "subscribes": 0, "auth_failures": 0}


func start(p_port: int = 8080) -> Error:
	port = p_port
	_server = TCPServer.new()
	var err := _server.listen(port, "127.0.0.1")
	if err == OK:
		_log("listening on ws://127.0.0.1:%d/%s" % [port, " (auth on)" if password != "" else ""])
	else:
		_log("FAILED to listen on port %d: %s" % [port, error_string(err)])
	return err


func stop() -> void:
	for c in _clients:
		c["ws"].close()
	_clients.clear()
	if _server:
		_server.stop()


## Simulates Streamer.bot going away for `seconds` (drops everyone).
func go_down(seconds: float) -> void:
	disconnect_all(false)
	if _server:
		_server.stop()
	_down_until = _now() + seconds
	_log("server DOWN for %.1fs" % seconds)


func subscribed_client_count() -> int:
	var n := 0
	for c in _clients:
		if c["open"] and not c["subs"].is_empty():
			n += 1
	return n


func open_client_count() -> int:
	return _clients.filter(func(c): return c["open"]).size()


func _process(_delta: float) -> void:
	poll()


func poll() -> void:
	if _down_until > 0.0 and _now() >= _down_until:
		_down_until = 0.0
		start(port)
	if _server and _server.is_listening():
		while _server.is_connection_available():
			var tcp := _server.take_connection()
			var ws := WebSocketPeer.new()
			ws.inbound_buffer_size = 1 << 20
			ws.outbound_buffer_size = 1 << 20
			ws.accept_stream(tcp)
			_clients.append({"tcp": tcp, "ws": ws, "authed": password == "", "subs": {}, "open": false, "challenge": "", "salt": ""})
			stats["connections"] += 1
	for c in _clients.duplicate():
		var ws: WebSocketPeer = c["ws"]
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			if not c["open"]:
				c["open"] = true
				_send_hello(c)
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				_handle(c, pkt.get_string_from_utf8())
		elif st == WebSocketPeer.STATE_CLOSED:
			if c["open"]:
				_log("client disconnected")
			_clients.erase(c)


func _send_hello(c: Dictionary) -> void:
	var hello := {
		"request": "Hello",
		"info": {"instanceId": "00000000-mock-mock-mock-000000000000", "name": "Mock Streamer.bot", "os": "linux", "osVersion": "mock", "version": "1.0.0-mock", "source": "websocketServer"},
		"timestamp": Time.get_datetime_string_from_system(true),
		"session": "mock-session",
	}
	if password != "":
		c["salt"] = _random_b64()
		c["challenge"] = _random_b64()
		hello["authentication"] = {"salt": c["salt"], "challenge": c["challenge"]}
	_send(c, hello)
	_log("client connected, Hello sent")


func _handle(c: Dictionary, text: String) -> void:
	stats["requests"] += 1
	var msg: Variant = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var id := str(msg.get("id", ""))
	var req := str(msg.get("request", ""))
	if req == "Authenticate":
		var expected := SBProtocol.auth_string(password, c["salt"], c["challenge"])
		if password != "" and str(msg.get("authentication", "")) == expected:
			c["authed"] = true
			_send(c, {"id": id, "status": "ok"})
			_log("client authenticated")
		else:
			stats["auth_failures"] += 1
			_send(c, {"id": id, "status": "error", "error": "Authentication failed"})
			_log("client authentication FAILED")
		return
	if not c["authed"]:
		_send(c, {"id": id, "status": "error", "error": "Authentication required"})
		return
	match req:
		"Subscribe":
			var events: Variant = msg.get("events", {})
			if typeof(events) != TYPE_DICTIONARY:
				_send(c, {"id": id, "status": "error", "error": "Invalid events"})
				return
			for source in events.keys():
				if typeof(events[source]) != TYPE_ARRAY:
					continue
				if not c["subs"].has(source):
					c["subs"][source] = []
				for t in events[source]:
					if not (t in c["subs"][source]):
						c["subs"][source].append(t)
			stats["subscribes"] += 1
			_send(c, {"id": id, "status": "ok", "events": c["subs"]})
			_log("client subscribed to %s" % JSON.stringify(c["subs"]))
			client_subscribed.emit(_clients.find(c), c["subs"].duplicate(true))
		"UnSubscribe":
			_send(c, {"id": id, "status": "ok", "events": c["subs"]})
		"GetInfo":
			_send(c, {"id": id, "status": "ok", "info": {"name": "Mock Streamer.bot", "version": "1.0.0-mock"}})
		"GetEvents":
			_send(c, {"id": id, "status": "ok", "events": {"Twitch": ["ChatMessage", "RewardRedemption", "Raid", "Follow", "Cheer", "Sub"]}})
		_:
			_send(c, {"id": id, "status": "error", "error": "Unknown request"})


## Sends an event to every client subscribed to source.type (or to all open
## clients when `force` is true). Returns how many clients got it.
func send_event(source: String, type: String, data: Dictionary, force: bool = false) -> int:
	var payload := {"timeStamp": Time.get_datetime_string_from_system(true), "event": {"source": source, "type": type}, "data": data}
	var n := 0
	for c in _clients:
		if not c["open"] or not c["authed"]:
			continue
		if force or type in c["subs"].get(source, []):
			_send(c, payload)
			n += 1
	stats["events_sent"] += n
	return n


## Sends arbitrary text (for malformed-payload tests).
func send_raw(text: String) -> void:
	for c in _clients:
		if c["open"]:
			c["ws"].send_text(text)


func send_binary(bytes: PackedByteArray) -> void:
	for c in _clients:
		if c["open"]:
			c["ws"].send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


## clean=true sends a proper close frame; false just drops the TCP socket.
func disconnect_all(clean: bool) -> void:
	for c in _clients:
		if clean:
			c["ws"].close(1001, "mock going away")
		else:
			c["tcp"].disconnect_from_host()
			c["open"] = false
	if not clean:
		_clients.clear()
	_log("disconnected all clients (%s)" % ("clean" if clean else "abrupt"))


# --- payload builders (shapes match @streamerbot/client 2.0.1 typings) -------

static func chat_data(login: String, text: String, display: String = "", user_id: String = "") -> Dictionary:
	return {"message": {
		"internal": false, "msgId": "mock-%d" % randi(), "userId": user_id if user_id != "" else "id-" + login,
		"username": login, "role": 1, "subscriber": false, "displayName": display if display != "" else login,
		"color": "#8888FF", "channel": "lucidin", "message": text, "isHighlighted": false, "isMe": false,
		"isCustomReward": false, "isAnonymous": false, "isReply": false, "bits": 0, "firstMessage": false,
		"hasBits": false, "emotes": [], "cheerEmotes": [], "badges": [], "monthsSubscribed": 0, "isTest": true,
	}}


static func redeem_data(login: String, title: String, user_input: String = "", display: String = "") -> Dictionary:
	return {
		"id": "redeem-%d" % randi(), "user_id": "id-" + login, "user_login": login,
		"user_name": display if display != "" else login, "user_input": user_input, "status": "unfulfilled",
		"reward": {"id": "reward-" + title.to_lower().replace(" ", "-"), "title": title, "cost": 100, "prompt": ""},
		"redeemed_at": Time.get_datetime_string_from_system(true),
	}


static func raid_data(from_login: String, viewers: int) -> Dictionary:
	return {
		"from_broadcaster_user_id": "id-" + from_login, "from_broadcaster_user_login": from_login,
		"from_broadcaster_user_name": from_login, "to_broadcaster_user_id": "id-lucidin",
		"to_broadcaster_user_login": "lucidin", "to_broadcaster_user_name": "Lucidin", "viewers": viewers,
	}


static func follow_data(login: String) -> Dictionary:
	return {"user_id": "id-" + login, "user_login": login, "user_name": login, "followed_at": Time.get_datetime_string_from_system(true)}


func _send(c: Dictionary, obj: Dictionary) -> void:
	c["ws"].send_text(JSON.stringify(obj))


func _random_b64() -> String:
	var bytes := PackedByteArray()
	for i in 16:
		bytes.append(randi() % 256)
	return Marshalls.raw_to_base64(bytes)


func _log(text: String) -> void:
	if verbose:
		print("[mock] " + text)
	log_line.emit(text)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
