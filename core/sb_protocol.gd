class_name SBProtocol
extends RefCounted
## Pure (no I/O) helpers for the Streamer.bot WebSocket protocol.
##
## Protocol summary (verified against the official @streamerbot/client 2.0.1
## package; see docs/DECISIONS.md):
## - Server default: ws://127.0.0.1:8080/
## - On connect the server sends {"request":"Hello","info":{...},
##   "authentication":{"salt":..,"challenge":..}}; "authentication" is only
##   present when the server has authentication enabled.
## - Auth: secret = base64(sha256(password + salt));
##         authentication = base64(sha256(secret + challenge));
##   send {"request":"Authenticate","id":..,"authentication":..}.
## - Requests carry an "id"; responses echo it with "status":"ok"|"error".
## - Events are only delivered after a Subscribe request:
##   {"request":"Subscribe","id":..,"events":{"Twitch":["ChatMessage",...]}}.
## - Event messages: {"timeStamp":..,"event":{"source":..,"type":..},"data":{..}}.

## Internal event types that modules may subscribe to (all free).
const FREE_INTERNAL_TYPES := ["chat_command", "raid", "follow"]

## Internal type -> Streamer.bot events it needs.
const RAW_FOR_INTERNAL := {
	"chat_command": {"Twitch": ["ChatMessage"]},
	"raid": {"Twitch": ["Raid"]},
	"follow": {"Twitch": ["Follow"]},
}
const RAW_FOR_REDEEMS := {"Twitch": ["RewardRedemption"]}


static func build_request(request: String, id: String, extra: Dictionary = {}) -> String:
	var msg := {"request": request, "id": id}
	msg.merge(extra, true)
	return JSON.stringify(msg)


static func auth_string(password: String, salt: String, challenge: String) -> String:
	var secret := _sha256_b64(password + salt)
	return _sha256_b64(secret + challenge)


static func _sha256_b64(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return Marshalls.raw_to_base64(ctx.finish())


## Builds the Subscribe "events" object for the given internal types.
static func subscription_for(internal_types: Array, redeems_enabled: bool) -> Dictionary:
	var out := {}
	var parts: Array = []
	for t in internal_types:
		if RAW_FOR_INTERNAL.has(t):
			parts.append(RAW_FOR_INTERNAL[t])
	if redeems_enabled:
		parts.append(RAW_FOR_REDEEMS)
	for part in parts:
		for source in part.keys():
			if not out.has(source):
				out[source] = []
			for ev in part[source]:
				if not (ev in out[source]):
					out[source].append(ev)
	return out


## Classifies one raw WebSocket text frame.
## Returns {"kind": "hello"|"response"|"event"|"invalid", ...}.
static func parse_message(text: String, max_bytes: int = 65536) -> Dictionary:
	if text.length() > max_bytes or text.to_utf8_buffer().size() > max_bytes:
		return {"kind": "invalid", "reason": "message too large (%d chars)" % text.length()}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"kind": "invalid", "reason": "malformed JSON: %s" % json.get_error_message()}
	var msg: Variant = json.data
	if typeof(msg) != TYPE_DICTIONARY:
		return {"kind": "invalid", "reason": "message is not a JSON object"}
	if typeof(msg.get("event", null)) == TYPE_DICTIONARY:
		var ev: Dictionary = msg["event"]
		if typeof(ev.get("source", null)) != TYPE_STRING or typeof(ev.get("type", null)) != TYPE_STRING:
			return {"kind": "invalid", "reason": "event without source/type"}
		var data: Variant = msg.get("data", {})
		return {
			"kind": "event",
			"source": ev["source"],
			"type": ev["type"],
			"data": data if typeof(data) == TYPE_DICTIONARY else {},
		}
	if msg.get("request", "") == "Hello" or (msg.has("info") and not msg.has("id")):
		var auth: Variant = msg.get("authentication", null)
		return {
			"kind": "hello",
			"info": msg.get("info", {}),
			"auth_required": typeof(auth) == TYPE_DICTIONARY,
			"salt": str(auth.get("salt", "")) if typeof(auth) == TYPE_DICTIONARY else "",
			"challenge": str(auth.get("challenge", "")) if typeof(auth) == TYPE_DICTIONARY else "",
		}
	if msg.has("id"):
		return {"kind": "response", "id": str(msg["id"]), "status": str(msg.get("status", "")), "body": msg}
	return {"kind": "invalid", "reason": "unrecognised message"}


## Turns a parsed Streamer.bot event into an internal event Dictionary, or {}
## if it should be ignored (unknown/paid type, missing fields).
##
## Internal shapes:
##   chat_message: user_id, user_login, user_name, text
##   redeem:       user_id, user_login, user_name, reward_title, reward_id, text
##   raid:         user_id, user_login, user_name (the raider), viewers
##   follow:       user_id, user_login, user_name
static func normalize_event(source: String, type: String, data: Dictionary, max_name_length: int = 25, max_text_length: int = 300) -> Dictionary:
	if PaidEvents.is_paid_raw("%s.%s" % [source, type]):
		return {}
	if source != "Twitch":
		return {}
	var out := {}
	match type:
		"ChatMessage":
			# Classic shape: data.message.{userId, username, displayName, message}.
			# Newer builds may also send data.user.{id, login, name} + data.text,
			# so both are accepted.
			var m: Variant = data.get("message", null)
			var u: Variant = data.get("user", null)
			if typeof(m) == TYPE_DICTIONARY:
				out = {
					"type": "chat_message",
					"user_id": _s(m.get("userId", "")),
					"user_login": _s(m.get("username", "")),
					"user_name": _s(m.get("displayName", m.get("username", ""))),
					"text": _s(m.get("message", "")),
				}
			elif typeof(u) == TYPE_DICTIONARY:
				out = {
					"type": "chat_message",
					"user_id": _s(u.get("id", "")),
					"user_login": _s(u.get("login", "")),
					"user_name": _s(u.get("name", u.get("login", ""))),
					"text": _s(data.get("text", data.get("message", ""))),
				}
			else:
				return {}
		"RewardRedemption":
			var reward: Variant = data.get("reward", {})
			out = {
				"type": "redeem",
				"user_id": _s(data.get("user_id", "")),
				"user_login": _s(data.get("user_login", "")),
				"user_name": _s(data.get("user_name", data.get("user_login", ""))),
				"reward_title": _s(reward.get("title", "")) if typeof(reward) == TYPE_DICTIONARY else "",
				"reward_id": _s(reward.get("id", "")) if typeof(reward) == TYPE_DICTIONARY else "",
				"text": _s(data.get("user_input", "")),
			}
			if out["reward_title"] == "":
				return {}
		"Raid":
			out = {
				"type": "raid",
				"user_id": _s(data.get("from_broadcaster_user_id", "")),
				"user_login": _s(data.get("from_broadcaster_user_login", "")),
				"user_name": _s(data.get("from_broadcaster_user_name", data.get("from_broadcaster_user_login", ""))),
				"viewers": maxi(0, int(data.get("viewers", 0))) if typeof(data.get("viewers", 0)) in [TYPE_INT, TYPE_FLOAT] else 0,
			}
		"Follow":
			out = {
				"type": "follow",
				"user_id": _s(data.get("user_id", "")),
				"user_login": _s(data.get("user_login", "")),
				"user_name": _s(data.get("user_name", data.get("user_login", ""))),
			}
		_:
			return {}
	out["user_login"] = sanitize_name(out["user_login"], max_name_length).to_lower()
	out["user_name"] = sanitize_name(out["user_name"], max_name_length)
	if out["user_name"] == "":
		out["user_name"] = out["user_login"]
	if out["user_id"] == "":
		out["user_id"] = out["user_login"]
	if out["user_id"] == "":
		return {}
	if out.has("text"):
		out["text"] = sanitize_text(out["text"], max_text_length)
	return out


## Keeps printable characters only and trims to `max_length`.
static func sanitize_name(name: String, max_length: int) -> String:
	var out := ""
	for c in name.strip_edges():
		var code := c.unicode_at(0)
		# Control chars, zero-width chars and bidi overrides (which can flip the
		# rest of the overlay text) are dropped.
		if code < 32 or code == 127 or (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069) or code == 0xFEFF:
			continue
		out += c
	return out.substr(0, max_length)


static func sanitize_text(text: String, max_length: int) -> String:
	var out := ""
	for c in text:
		var code := c.unicode_at(0)
		if code < 32 or code == 127:
			out += " "
		else:
			out += c
	return out.strip_edges().substr(0, max_length)


static func _s(v: Variant) -> String:
	if v == null:
		return ""
	if typeof(v) == TYPE_FLOAT and v == floorf(v):
		return str(int(v))
	return str(v)
