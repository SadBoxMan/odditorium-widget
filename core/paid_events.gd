class_name PaidEvents
extends RefCounted
## The "everything is free" guard.
##
## Lists every internal and Streamer.bot event type that involves money
## (bits, subs, gifts, donations, tips, paid power-ups, memberships, ...).
## Modules may not subscribe to any of them; the registry refuses such
## modules at load time and tests/unit/test_paid_guard.gd fails if one exists.
## The Streamer.bot client also refuses to send a Subscribe request that
## contains any of them.

## Internal event types (what modules subscribe to).
const INTERNAL := [
	"cheer", "bits", "sub", "resub", "gift_sub", "gift_bomb", "subscription",
	"hype_train", "hype_chat", "donation", "tip", "charity", "power_up",
	"merch", "order", "pledge", "membership", "super_chat", "super_sticker",
	"treat", "paid_upgrade",
]

## Streamer.bot event sources that are entirely about money.
const RAW_SOURCES := [
	"Kofi", "Patreon", "Streamlabs", "StreamElements", "TipeeeStream",
	"DonorDrive", "TreatStream", "Fourthwall", "Shopify", "Pallygg",
]

## Paid event types inside mixed sources ("Source.Type").
const RAW_EVENTS := [
	"Twitch.Cheer", "Twitch.CoinCheer", "Twitch.Sub", "Twitch.ReSub",
	"Twitch.GiftSub", "Twitch.GiftBomb", "Twitch.SubCounterRollover",
	"Twitch.HypeTrainStart", "Twitch.HypeTrainUpdate", "Twitch.HypeTrainLevelUp",
	"Twitch.HypeTrainEnd", "Twitch.HypeChat", "Twitch.HypeChatLevel",
	"Twitch.CharityDonation", "Twitch.CharityStarted", "Twitch.CharityProgress",
	"Twitch.CharityCompleted", "Twitch.PowerUp", "Twitch.PowerUpRedemption",
	"Twitch.AutomaticRewardRedemption", "Twitch.BitsBadgeTier",
	"Twitch.PrimePaidUpgrade", "Twitch.GiftPaidUpgrade", "Twitch.PayItForward",
	"Twitch.SharedChatSub", "Twitch.SharedChatResub", "Twitch.SharedChatSubGift",
	"Twitch.SharedChatCommunitySubGift", "Twitch.SharedChatPrimePaidUpgrade",
	"Twitch.SharedChatGiftPaidUpgrade", "Twitch.SharedChatPayItForward",
	"YouTube.SuperChat", "YouTube.SuperSticker", "YouTube.NewSponsor",
	"YouTube.MemberMileStone", "YouTube.MembershipGift",
	"YouTube.GiftMembershipReceived",
	"Trovo.Subscription", "Trovo.Resubscription", "Trovo.GiftSubscription",
	"Trovo.MassGiftSubscription", "Trovo.SpellCast", "Trovo.CustomSpellCast",
	"Kick.Subscription", "Kick.Resubscription", "Kick.GiftSubscription",
	"Kick.MassGiftSubscription",
	"CrowdControl.CoinExchange", "CrowdControl.EffectRequest",
]


static func is_paid_internal(event_type: String) -> bool:
	return event_type.strip_edges().to_lower() in INTERNAL


## `name` is "Source.Type". Wildcards ("Twitch.*", "*") count as paid because
## they would include paid events.
static func is_paid_raw(name: String) -> bool:
	var n := name.strip_edges()
	if n == "*" or n.ends_with(".*"):
		return true
	var source := n.get_slice(".", 0)
	for s in RAW_SOURCES:
		if s.to_lower() == source.to_lower():
			return true
	for e in RAW_EVENTS:
		if e.to_lower() == n.to_lower():
			return true
	return false


## Checks a module instance. Returns human-readable violations ([] = clean).
static func check_module(module: Object) -> Array[String]:
	var violations: Array[String] = []
	var id := str(module.get("module_id")) if module.get("module_id") != null else str(module)
	if module.has_method("subscribes_to"):
		for t in module.subscribes_to():
			if typeof(t) != TYPE_STRING:
				violations.append("%s: subscribes_to() returned a non-string entry %s" % [id, str(t)])
			elif is_paid_internal(t) or is_paid_raw(t):
				violations.append("%s subscribes to paid event type '%s'" % [id, t])
	if module.has_method("raw_events"):
		for t in module.raw_events():
			if typeof(t) != TYPE_STRING or is_paid_raw(t):
				violations.append("%s requests paid Streamer.bot event '%s'" % [id, str(t)])
	return violations


## Checks a Streamer.bot Subscribe "events" object {"Twitch": ["ChatMessage"]}.
static func check_subscription(events: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	for source in events.keys():
		var types: Variant = events[source]
		if typeof(types) != TYPE_ARRAY:
			violations.append("subscription for '%s' is not a list" % source)
			continue
		for t in types:
			var name := "%s.%s" % [source, t]
			if is_paid_raw(name):
				violations.append("subscription includes paid event '%s'" % name)
	return violations
