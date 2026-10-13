extends TestCase
## Streamer.bot protocol helpers (pure functions).


func test_auth_string_matches_reference() -> void:
	# Reference value computed independently with Python:
	#   b64(sha256(b64(sha256("hunter2" + "c2FsdA==")) + "Y2hhbGxlbmdl")))
	check_eq(SBProtocol.auth_string("hunter2", "c2FsdA==", "Y2hhbGxlbmdl"), "HbemcTRAK8GnBZpkRzKZdmk94xa5VYtjm6/uKbA1epI=")


func test_build_request() -> void:
	var parsed: Dictionary = JSON.parse_string(SBProtocol.build_request("Subscribe", "7", {"events": {"Twitch": ["ChatMessage"]}}))
	check_eq(parsed["request"], "Subscribe")
	check_eq(parsed["id"], "7")
	check_eq(parsed["events"], {"Twitch": ["ChatMessage"]})


func test_subscription_mapping() -> void:
	check_eq(SBProtocol.subscription_for(["chat_command"], false), {"Twitch": ["ChatMessage"]})
	check_eq(SBProtocol.subscription_for(["chat_command", "raid"], true), {"Twitch": ["ChatMessage", "Raid", "RewardRedemption"]})
	check_eq(SBProtocol.subscription_for([], false), {})


func test_parse_hello_with_and_without_auth() -> void:
	var h := SBProtocol.parse_message('{"request":"Hello","info":{"version":"1.0.4"},"authentication":{"salt":"s","challenge":"c"}}')
	check_eq(h["kind"], "hello")
	check_eq(h["auth_required"], true)
	check_eq(h["salt"], "s")
	var h2 := SBProtocol.parse_message('{"request":"Hello","info":{"version":"1.0.4"}}')
	check_eq(h2["auth_required"], false)


func test_parse_response_and_event() -> void:
	var r := SBProtocol.parse_message('{"id":"lc-2","status":"ok","events":{}}')
	check_eq(r["kind"], "response")
	check_eq(r["status"], "ok")
	var e := SBProtocol.parse_message('{"timeStamp":"x","event":{"source":"Twitch","type":"Raid"},"data":{"viewers":3}}')
	check_eq(e["kind"], "event")
	check_eq(e["type"], "Raid")
	check_eq(e["data"]["viewers"], 3.0)


func test_parse_bad_payloads() -> void:
	check_eq(SBProtocol.parse_message("{not json")["kind"], "invalid")
	check_eq(SBProtocol.parse_message("[1,2]")["kind"], "invalid")
	check_eq(SBProtocol.parse_message('"just a string"')["kind"], "invalid")
	check_eq(SBProtocol.parse_message('{"event":{"source":1}}')["kind"], "invalid")
	check_eq(SBProtocol.parse_message('{"hello":"world"}')["kind"], "invalid")
	check_eq(SBProtocol.parse_message("x".repeat(100), 50)["kind"], "invalid", "oversized")
	check_eq(SBProtocol.parse_message("")["kind"], "invalid")
	# Event with data of the wrong type is tolerated (data becomes {}).
	var e := SBProtocol.parse_message('{"event":{"source":"Twitch","type":"Follow"},"data":"oops"}')
	check_eq(e["kind"], "event")
	check_eq(e["data"], {})


func test_normalize_chat_classic_shape() -> void:
	var data := MockStreamerBot.chat_data("alice", "!join now", "Alice")
	var ev := SBProtocol.normalize_event("Twitch", "ChatMessage", data)
	check_eq(ev["type"], "chat_message")
	check_eq(ev["user_login"], "alice")
	check_eq(ev["user_name"], "Alice")
	check_eq(ev["user_id"], "id-alice")
	check_eq(ev["text"], "!join now")


func test_normalize_chat_newer_shape() -> void:
	var ev := SBProtocol.normalize_event("Twitch", "ChatMessage", {"user": {"id": 42.0, "login": "Bob", "name": "BobTheBuilder"}, "text": "!bonk"})
	check_eq(ev["user_id"], "42")
	check_eq(ev["user_login"], "bob")
	check_eq(ev["text"], "!bonk")


func test_normalize_missing_fields() -> void:
	check_eq(SBProtocol.normalize_event("Twitch", "ChatMessage", {}), {})
	check_eq(SBProtocol.normalize_event("Twitch", "ChatMessage", {"message": {}}), {}, "no user at all")
	check_eq(SBProtocol.normalize_event("Twitch", "RewardRedemption", {"user_login": "x"}), {}, "no reward title")
	var raid := SBProtocol.normalize_event("Twitch", "Raid", {"from_broadcaster_user_login": "pal", "viewers": "lots"})
	check_eq(raid["viewers"], 0, "bad viewer count -> 0")
	check_eq(raid["user_name"], "pal")


func test_normalize_ignores_unknown_and_other_sources() -> void:
	check_eq(SBProtocol.normalize_event("Twitch", "PollCreated", {}), {})
	check_eq(SBProtocol.normalize_event("YouTube", "Message", {"user": {"id": "1"}}), {})


func test_sanitizes_names_and_text() -> void:
	var data := MockStreamerBot.chat_data("evil", "!join\u0001\nhi", "Ev​il\u0007Name_that_is_way_too_long_for_display")
	var ev := SBProtocol.normalize_event("Twitch", "ChatMessage", data, 10, 300)
	check_eq(ev["user_name"], "EvilName_t")
	check_eq(ev["text"], "!join  hi")


func test_redeem_and_follow() -> void:
	var r := SBProtocol.normalize_event("Twitch", "RewardRedemption", MockStreamerBot.redeem_data("carol", "Bonk the Streamer", "@dave"))
	check_eq(r["type"], "redeem")
	check_eq(r["reward_title"], "Bonk the Streamer")
	check_eq(r["text"], "@dave")
	var f := SBProtocol.normalize_event("Twitch", "Follow", MockStreamerBot.follow_data("erin"))
	check_eq(f["type"], "follow")
	check_eq(f["user_login"], "erin")
