class_name ModuleRegistry
extends RefCounted
## Discovers, validates, configures and wires up modules.
##
## Discovery: every res://modules/<id>/module.gd. A module is refused (never
## loaded) if it subscribes to a paid event type or to an unknown type.
## A module whose setup() fails, or whose handlers keep failing, is disabled
## and removed; the rest keep running.

const MODULES_DIR := "res://modules"

## id -> ChaosModule (loaded and enabled)
var modules: Dictionary = {}
## id -> reason (refused or disabled)
var rejected: Dictionary = {}
var errors: Array[String] = []

var _bus: ChaosEventBus
var _router: CommandRouter


## Returns sorted paths of module scripts found under `dir`.
static func discover(dir: String = MODULES_DIR) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for sub in da.get_directories():
		var base := dir.path_join(sub).path_join("module.gd")
		# Exported builds keep scripts as .gd.remap / .gdc.
		if ResourceLoader.exists(base) or FileAccess.file_exists(base) or FileAccess.file_exists(base + ".remap"):
			out.append(base)
	out.sort()
	return out


## Instantiates a module script without configuring it. Returns null on
## failure (and records why in `errors`).
func instantiate(path: String) -> ChaosModule:
	var script: Variant = load(path)
	if script == null or not (script is Script) or not script.can_instantiate():
		errors.append("%s: could not load script" % path)
		return null
	var inst: Variant = script.new()
	if not (inst is ChaosModule):
		errors.append("%s: does not extend ChaosModule" % path)
		if inst is Node:
			inst.free()
		return null
	inst.module_id = path.get_base_dir().get_file()
	inst.name = inst.module_id
	return inst


## Validates subscriptions. Returns [] if the module may load.
static func validate(module: ChaosModule) -> Array[String]:
	var problems := PaidEvents.check_module(module)
	for t in module.subscribes_to():
		if typeof(t) == TYPE_STRING and not (t in SBProtocol.FREE_INTERNAL_TYPES) and not PaidEvents.is_paid_internal(t):
			problems.append("%s subscribes to unknown event type '%s' (allowed: %s)" % [module.module_id, t, ", ".join(SBProtocol.FREE_INTERNAL_TYPES)])
	return problems


func load_all(parent: Node, cfg: ChaosConfig, bus: ChaosEventBus, router: CommandRouter, assets: AssetLoader, overlay_size: Vector2, dir: String = MODULES_DIR) -> void:
	_bus = bus
	_router = router
	for path in discover(dir):
		var module := instantiate(path)
		if module == null:
			continue
		load_module(module, parent, cfg, assets, overlay_size)


## Configures, validates and starts one module instance.
func load_module(module: ChaosModule, parent: Node, cfg: ChaosConfig, assets: AssetLoader, overlay_size: Vector2) -> bool:
	var id := module.module_id
	var problems := validate(module)
	if not problems.is_empty():
		for p in problems:
			errors.append(p)
			push_error("[modules] REFUSED: " + p)
		rejected[id] = "; ".join(problems)
		module.free()
		return false
	var defaults: Dictionary = module.get_default_config().duplicate(true)
	if not defaults.has("enabled"):
		defaults["enabled"] = true
	module.config = cfg.apply_module_defaults(id, defaults, module.get_config_open_paths(), module.get_config_constraints())
	if not module.config["enabled"]:
		rejected[id] = "disabled in config"
		print("[modules] %s: disabled in config" % id)
		module.free()
		return false
	module.app_config = cfg
	module.assets = assets
	module.overlay_size = overlay_size
	module.show_regions = cfg.get_value("debug.show_regions", false)
	var seed_value: Variant = module.config.get("seed", 0)
	if typeof(seed_value) == TYPE_INT and seed_value != 0:
		module.rng.seed = seed_value
	else:
		module.rng.randomize()
	parent.add_child(module)
	if module.setup() != true:
		_remove(module, "setup() failed")
		return false
	for t in module.subscribes_to():
		_bus.subscribe(t, id, module.on_event)
	for cmd in module.get_commands():
		if typeof(cmd) != TYPE_DICTIONARY or typeof(cmd.get("name", null)) != TYPE_STRING:
			push_warning("[modules] %s: bad get_commands() entry %s" % [id, str(cmd)])
			continue
		var cd: Variant = cmd.get("cooldown_s", -1.0)
		_router.register_command(cmd["name"], id, float(cd) if typeof(cd) in [TYPE_INT, TYPE_FLOAT] else -1.0, cmd.get("aliases", []))
	modules[id] = module
	print("[modules] %s: loaded (events: %s, commands: %s)" % [id, ", ".join(module.subscribes_to()), ", ".join(module.get_commands().map(func(c): return str(c.get("name", "?"))))])
	return true


## Union of internal event types the loaded modules need.
func internal_types() -> Array:
	var out: Array = []
	for m in modules.values():
		for t in m.subscribes_to():
			if not (t in out):
				out.append(t)
	return out


func disable(id: String, reason: String) -> void:
	if modules.has(id):
		_remove(modules[id], reason)


## Tears down every module and breaks the bus <-> registry reference cycle.
func shutdown() -> void:
	for m in modules.values():
		m.teardown()
	modules.clear()
	if _bus:
		_bus.on_owner_failed = Callable()
	_bus = null
	_router = null


func _remove(module: ChaosModule, reason: String) -> void:
	var id := module.module_id
	push_warning("[modules] %s disabled: %s" % [id, reason])
	rejected[id] = reason
	modules.erase(id)
	if _bus:
		_bus.unsubscribe_owner(id)
	if _router:
		_router.unregister_module(id)
	module.teardown()
	if module.is_inside_tree():
		module.queue_free()
	else:
		module.free()
