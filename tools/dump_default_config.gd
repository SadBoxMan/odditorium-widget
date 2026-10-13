extends SceneTree
## Prints the complete default config (core + every module) as JSON, e.g. to
## rebuild lucidin_chaos.json or check the config reference:
##   godot --headless --path . --script res://tools/dump_default_config.gd


func _initialize() -> void:
	var out := ChaosConfig.DEFAULTS.duplicate(true)
	var modules := {}
	var reg := ModuleRegistry.new()
	for path in ModuleRegistry.discover():
		var m := reg.instantiate(path)
		if m == null:
			continue
		var defaults := {"enabled": true}
		defaults.merge(m.get_default_config(), true)
		if not defaults.has("z_index"):
			defaults["z_index"] = 0
		modules[m.module_id] = defaults
		m.free()
	out["modules"] = modules
	print(JSON.stringify(out, "  ", false))
	quit()
