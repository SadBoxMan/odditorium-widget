class_name ChaosModule
extends Node2D
## Base class for "shenanigan modules".
##
## A module lives in res://modules/<module_id>/module.gd and extends this
## class. The registry finds it automatically; no core code changes needed.
## Override the methods in the "override" section. Handlers MUST end with
## `return true`; a handler that errors (or forgets to return true) counts as
## a failure, and a module that keeps failing is disabled without affecting
## anything else.

## Set by the registry from the folder name.
var module_id := ""
## This module's merged + validated config section (modules.<module_id>).
var config: Dictionary = {}
## Whole app config (read-only use).
var app_config: ChaosConfig
## Shared loader for optional user sprites/sounds.
var assets: AssetLoader
## Size of the overlay canvas in pixels.
var overlay_size := Vector2(1920, 1080)
## Draw debug outlines for regions (config debug.show_regions).
var show_regions := false
## Seeded per module when the config has a non-zero "seed"; random otherwise.
var rng := RandomNumberGenerator.new()


# --- override -----------------------------------------------------------------

## Defaults for this module's config section. "enabled" is added automatically.
func get_default_config() -> Dictionary:
	return {}


## Config sub-paths (relative to the module section) that are open-ended maps
## the user may replace wholesale, e.g. ["objects"].
func get_config_open_paths() -> Array:
	return []


## Validation rules: {"path.in.section": {"min": .., "max": .., "enum": [..]}}.
func get_config_constraints() -> Dictionary:
	return {}


## Internal event types to receive. Allowed: SBProtocol.FREE_INTERNAL_TYPES
## ("chat_command", "raid", "follow"). Paid types are rejected.
func subscribes_to() -> Array:
	return []


## Chat commands this module owns:
## [{"name": "join", "cooldown_s": 5.0, "aliases": ["j"]}]. cooldown_s < 0 or
## missing = cooldowns.default_command_s.
func get_commands() -> Array:
	return []


## Called once after config is applied and the node is in the tree.
func setup() -> bool:
	return true


## Called before the module is removed (disabled or app exit).
func teardown() -> void:
	pass


## Receives subscribed events. chat_command events have "command", "args",
## "user_id", "user_login", "user_name", "via_redeem".
func on_event(_event: Dictionary) -> bool:
	return true


# --- helpers ------------------------------------------------------------------

func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Rect2 from a config value [x, y, w, h]; returns `fallback` if malformed.
static func rect_from(value: Variant, fallback: Rect2) -> Rect2:
	if typeof(value) == TYPE_ARRAY and value.size() == 4:
		for v in value:
			if not (typeof(v) in [TYPE_INT, TYPE_FLOAT]):
				return fallback
		if value[2] > 0 and value[3] > 0:
			return Rect2(value[0], value[1], value[2], value[3])
	return fallback
