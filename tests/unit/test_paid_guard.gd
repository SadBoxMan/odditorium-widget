extends TestCase
## The "everything is free" guard.
##
## test_no_module_uses_paid_events scans `modules_dir` (res://modules by
## default). Run it against the deliberately bad fixture to see it fail:
##   godot --headless --path . --script res://tests/run_tests.gd -- \
##       --filter=test_no_module_uses_paid_events \
##       --modules-dir=res://tests/fixtures/bad_modules

const BAD_DIR := "res://tests/fixtures/bad_modules"

## Quoted Streamer.bot type names that only make sense for paid events. A
## module mentioning one is talking to paid events behind the core's back.
const PAID_TYPE_WORDS := [
	"Cheer", "CoinCheer", "Sub", "ReSub", "GiftSub", "GiftBomb", "HypeTrainStart",
	"HypeTrainUpdate", "HypeTrainLevelUp", "HypeTrainEnd", "HypeChat",
	"CharityDonation", "PowerUp", "PowerUpRedemption", "AutomaticRewardRedemption",
	"SuperChat", "SuperSticker", "NewSponsor", "MembershipGift", "Donation", "Tip",
	"bits", "cheer", "sub", "resub", "gift_sub", "gift_bomb", "donation", "tip",
	"hype_train", "power_up", "super_chat",
]
## Modules must only receive events through the core bus.
const FORBIDDEN_REFERENCES := ["StreamerBotClient", "WebSocketPeer", "event_received"]


## Returns every violation found in modules under `dir`.
static func scan(dir: String) -> Array[String]:
	var violations: Array[String] = []
	var reg := ModuleRegistry.new()
	var paths := ModuleRegistry.discover(dir)
	for path in paths:
		var m := reg.instantiate(path)
		if m == null:
			violations.append("%s: could not instantiate" % path)
			continue
		violations.append_array(ModuleRegistry.validate(m))
		m.free()
		violations.append_array(scan_source(path))
	violations.append_array(reg.errors)
	return violations


static func scan_source(path: String) -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string(path)
	var line_no := 0
	for line in text.split("\n"):
		line_no += 1
		var code := line.get_slice("#", 0)
		for word in PAID_TYPE_WORDS:
			for q in ["\"", "'"]:
				if (q + word + q) in code:
					out.append("%s:%d mentions paid event type %s" % [path, line_no, q + word + q])
		for ref in FORBIDDEN_REFERENCES:
			if ref in code:
				out.append("%s:%d bypasses the core bus (%s)" % [path, line_no, ref])
	return out


func test_no_module_uses_paid_events() -> void:
	var found := ModuleRegistry.discover(modules_dir)
	var violations := scan(modules_dir)
	for v in violations:
		fail(v)
	if modules_dir == "res://modules":
		print("        (scanned %d module(s) in %s)" % [found.size(), modules_dir])


func test_guard_catches_the_bad_fixture() -> void:
	# Proves the guard above is not vacuous: the fixture must be flagged on
	# every axis (declared internal type, raw event, source-level mention).
	var violations := scan(BAD_DIR)
	check(violations.size() >= 3, "expected several violations, got %s" % str(violations))
	var joined := "\n".join(violations)
	check("'cheer'" in joined, "internal paid type flagged")
	check("Twitch.GiftSub" in joined, "raw paid event flagged")
	check("mentions paid event type" in joined, "source scan flagged")
	check("bypasses the core bus" in joined, "direct client access flagged")


func test_registry_refuses_paid_module() -> void:
	var reg := ModuleRegistry.new()
	var m := reg.instantiate(BAD_DIR.path_join("greedy/module.gd"))
	check(m != null)
	var parent := Node2D.new()
	tree.root.add_child(parent)
	reg._bus = ChaosEventBus.new()
	reg._router = CommandRouter.new()
	expect_errors(2)  # one push_error per violation
	var loaded := reg.load_module(m, parent, ChaosConfig.from_dict({}), AssetLoader.new(), Vector2(100, 100))
	check(not loaded, "paid module must be refused")
	check(reg.rejected.has("greedy"))
	check_eq(parent.get_child_count(), 0, "never added to the scene")
	parent.free()


func test_bus_refuses_paid_subscription() -> void:
	var bus := ChaosEventBus.new()
	expect_errors(1)
	bus.subscribe("cheer", "x", func(_e): return true)
	check_eq(bus.subscriber_count("cheer"), 0)
	check_eq(bus.emit("cheer", {}), 0)


func test_client_strips_paid_subscription() -> void:
	var client := StreamerBotClient.new()
	expect_errors(3)
	client.set_subscription({"Twitch": ["ChatMessage", "Cheer", "GiftSub"], "Kofi": ["Donation"]})
	check_eq(client.subscription, {"Twitch": ["ChatMessage"]})
	client.free()


func test_subscription_for_free_types_is_clean() -> void:
	var sub := SBProtocol.subscription_for(SBProtocol.FREE_INTERNAL_TYPES, true)
	check_eq(PaidEvents.check_subscription(sub), [] as Array[String])
	check_eq(sub, {"Twitch": ["ChatMessage", "Raid", "Follow", "RewardRedemption"]})


func test_paid_lookup() -> void:
	check(PaidEvents.is_paid_raw("Twitch.Cheer"))
	check(PaidEvents.is_paid_raw("twitch.giftbomb"), "case-insensitive")
	check(PaidEvents.is_paid_raw("Kofi.Anything"), "whole paid source")
	check(PaidEvents.is_paid_raw("Twitch.*"), "wildcards count as paid")
	check(not PaidEvents.is_paid_raw("Twitch.ChatMessage"))
	check(not PaidEvents.is_paid_raw("Twitch.RewardRedemption"), "channel points are free")
	check(PaidEvents.is_paid_internal("Gift_Sub"))
	check(not PaidEvents.is_paid_internal("chat_command"))


func test_normalizer_drops_paid_events() -> void:
	check_eq(SBProtocol.normalize_event("Twitch", "Cheer", {"bits": 100, "userId": "1", "username": "x"}), {})
	check_eq(SBProtocol.normalize_event("Twitch", "Sub", {"userId": "1"}), {})
