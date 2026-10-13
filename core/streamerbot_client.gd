class_name StreamerBotClient
extends Node
## WebSocket client for Streamer.bot's WebSocket server.
##
## Handles Hello / optional Authenticate / Subscribe, reconnects with
## exponential backoff, and turns raw events into internal events via
## SBProtocol.normalize_event(). Malformed or oversized messages are counted
## and dropped; they never crash the overlay.

signal event_received(event: Dictionary)
signal status_changed(status: String, detail: String)

enum State { IDLE, CONNECTING, AWAIT_HELLO, AUTHENTICATING, SUBSCRIBING, READY, WAIT_RETRY, STOPPED }

var url := "ws://127.0.0.1:8080/"
var password := ""
var subscription: Dictionary = {}
var reconnect_initial_s := 1.0
var reconnect_max_s := 30.0
var handshake_timeout_s := 10.0
var max_message_bytes := 65536
var max_name_length := 25
var max_text_length := 300
var log_events := false

var state: State = State.IDLE
var stats := {
	"connects": 0,
	"disconnects": 0,
	"messages": 0,
	"events": 0,
	"ignored_events": 0,
	"invalid_messages": 0,
	"auth_failures": 0,
}

var _ws: WebSocketPeer
var _backoff := 1.0
var _retry_at := 0.0
var _state_since := 0.0
var _pending_id := ""
var _next_id := 1
var _last_invalid_log := -1000.0
var _suppressed_invalid := 0


func configure(cfg: ChaosConfig, internal_types: Array) -> void:
	var sb := cfg.section("streamerbot")
	var endpoint: String = sb["endpoint"]
	if not endpoint.begins_with("/"):
		endpoint = "/" + endpoint
	url = "ws://%s:%d%s" % [sb["host"], sb["port"], endpoint]
	password = sb["password"]
	reconnect_initial_s = sb["reconnect_initial_s"]
	reconnect_max_s = maxf(sb["reconnect_max_s"], reconnect_initial_s)
	handshake_timeout_s = sb["handshake_timeout_s"]
	max_message_bytes = sb["max_message_bytes"]
	max_name_length = cfg.get_value("chat.max_name_length", 25)
	max_text_length = cfg.get_value("chat.max_message_length", 300)
	log_events = cfg.get_value("debug.log_events", false)
	set_subscription(SBProtocol.subscription_for(internal_types, cfg.get_value("redeems.enabled", false)))


## Sets the Subscribe payload, stripping (and loudly reporting) any paid event.
func set_subscription(events: Dictionary) -> void:
	var violations := PaidEvents.check_subscription(events)
	for v in violations:
		push_error("[streamerbot] refusing: " + v)
	var clean := {}
	for source in events.keys():
		if typeof(events[source]) != TYPE_ARRAY:
			continue
		var types: Array = events[source].filter(func(t): return not PaidEvents.is_paid_raw("%s.%s" % [source, t]))
		if not types.is_empty():
			clean[source] = types
	subscription = clean


func start() -> void:
	_backoff = reconnect_initial_s
	_open()


func stop() -> void:
	_set_state(State.STOPPED, "stopped")
	if _ws:
		_ws.close()
	_ws = null


func is_ready() -> bool:
	return state == State.READY


func _exit_tree() -> void:
	if _ws:
		_ws.close()
		_ws = null


func _process(_delta: float) -> void:
	poll()


## Public so tests can drive the client deterministically.
func poll() -> void:
	if state == State.STOPPED or state == State.IDLE:
		return
	var now := _now()
	if state == State.WAIT_RETRY:
		if now >= _retry_at:
			_open()
		return
	if _ws == null:
		_schedule_retry("no socket")
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if now - _state_since > handshake_timeout_s:
				_drop("connect timeout")
		WebSocketPeer.STATE_OPEN:
			if state == State.CONNECTING:
				stats["connects"] += 1
				_set_state(State.AWAIT_HELLO, "connected, waiting for Hello")
			while _ws != null and _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				if not _ws.was_string_packet():
					_invalid("binary frame")
					continue
				_handle_text(packet.get_string_from_utf8())
			if state in [State.AWAIT_HELLO, State.AUTHENTICATING, State.SUBSCRIBING] and now - _state_since > handshake_timeout_s:
				_drop("handshake timeout in state %s" % State.keys()[state])
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			var reason := _ws.get_close_reason()
			stats["disconnects"] += 1 if state != State.CONNECTING else 0
			_ws = null
			_schedule_retry("closed (code %d %s)" % [code, reason])


func _open() -> void:
	_ws = WebSocketPeer.new()
	# Leave headroom over max_message_bytes so our own size check (which
	# reports nicely) runs before the engine's buffer limit.
	_ws.inbound_buffer_size = maxi(max_message_bytes * 2, 65536)
	var err := _ws.connect_to_url(url)
	if err != OK:
		_ws = null
		_schedule_retry("connect_to_url failed (%s)" % error_string(err))
		return
	_set_state(State.CONNECTING, "connecting to " + url)


func _handle_text(text: String) -> void:
	stats["messages"] += 1
	var msg := SBProtocol.parse_message(text, max_message_bytes)
	match msg["kind"]:
		"invalid":
			_invalid(msg["reason"])
		"hello":
			_on_hello(msg)
		"response":
			_on_response(msg)
		"event":
			_on_event(msg)


func _on_hello(msg: Dictionary) -> void:
	if state != State.AWAIT_HELLO:
		return
	var info: Variant = msg.get("info", {})
	var version := str(info.get("version", "?")) if typeof(info) == TYPE_DICTIONARY else "?"
	if msg["auth_required"]:
		if password == "":
			stats["auth_failures"] += 1
			push_warning("[streamerbot] server requires authentication but streamerbot.password is empty")
			_backoff = reconnect_max_s
			_drop("authentication required; set streamerbot.password")
			return
		_pending_id = _new_id()
		_send(SBProtocol.build_request("Authenticate", _pending_id, {"authentication": SBProtocol.auth_string(password, msg["salt"], msg["challenge"])}))
		_set_state(State.AUTHENTICATING, "authenticating (Streamer.bot %s)" % version)
	else:
		_subscribe()


func _on_response(msg: Dictionary) -> void:
	if msg["id"] != _pending_id:
		return
	_pending_id = ""
	var ok: bool = msg["status"] == "ok"
	match state:
		State.AUTHENTICATING:
			if ok:
				_subscribe()
			else:
				stats["auth_failures"] += 1
				push_warning("[streamerbot] authentication failed; check streamerbot.password")
				_backoff = reconnect_max_s
				_drop("authentication failed")
		State.SUBSCRIBING:
			if ok:
				_backoff = reconnect_initial_s
				_set_state(State.READY, "ready, subscribed to %s" % JSON.stringify(subscription))
			else:
				_drop("subscribe failed: %s" % str(msg["body"].get("error", "?")))


func _on_event(msg: Dictionary) -> void:
	var ev := SBProtocol.normalize_event(msg["source"], msg["type"], msg["data"], max_name_length, max_text_length)
	if ev.is_empty():
		stats["ignored_events"] += 1
		return
	stats["events"] += 1
	if log_events:
		print("[streamerbot] event %s.%s -> %s" % [msg["source"], msg["type"], JSON.stringify(ev)])
	event_received.emit(ev)


func _subscribe() -> void:
	if subscription.is_empty():
		_set_state(State.READY, "ready (no events requested)")
		return
	_pending_id = _new_id()
	_send(SBProtocol.build_request("Subscribe", _pending_id, {"events": subscription}))
	_set_state(State.SUBSCRIBING, "subscribing")


func _send(text: String) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(text)


func _drop(reason: String) -> void:
	if _ws:
		_ws.close()
		_ws = null
	stats["disconnects"] += 1
	_schedule_retry(reason)


func _schedule_retry(reason: String) -> void:
	if state == State.STOPPED:
		return
	_retry_at = _now() + _backoff
	_set_state(State.WAIT_RETRY, "%s; retrying in %.1fs" % [reason, _backoff])
	_backoff = minf(_backoff * 2.0, reconnect_max_s)


func _invalid(reason: String) -> void:
	stats["invalid_messages"] += 1
	# Rate-limit the log so a flood of junk can't spam the console.
	var now := _now()
	if now - _last_invalid_log >= 5.0:
		var extra := " (+%d more suppressed)" % _suppressed_invalid if _suppressed_invalid > 0 else ""
		push_warning("[streamerbot] dropped invalid message: %s%s" % [reason, extra])
		_last_invalid_log = now
		_suppressed_invalid = 0
	else:
		_suppressed_invalid += 1


func _set_state(new_state: State, detail: String) -> void:
	state = new_state
	_state_since = _now()
	print("[streamerbot] %s: %s" % [State.keys()[new_state], detail])
	status_changed.emit(State.keys()[new_state], detail)


func _new_id() -> String:
	_next_id += 1
	return "lc-%d" % _next_id


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
