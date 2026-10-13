extends ChaosModule
## Critter Race: chatters type !join to enter a race of little shapes.
## Races auto-start once enough people join (or when the lobby timer runs
## out), and NPC critters fill the empty lanes so it's fun with 1-3 chatters.
## A raid kicks off a race with the raider as a big special critter.

const RaceLogic := preload("res://modules/critter_race/race_logic.gd")

var logic: RaceLogic
var _region := Rect2()
var _critters: Dictionary = {}  # entrant id -> Node2D
var _header: Label
var _anim_time := 0.0


func get_default_config() -> Dictionary:
	return {
		"region": [60, 760, 1340, 300],
		"lanes": 6,
		"min_humans_to_start": 3,
		"lobby_timeout_s": 30.0,
		"countdown_s": 3.0,
		"results_s": 6.0,
		"cooldown_s": 10.0,
		"max_race_s": 45.0,
		"base_speed": 0.08,
		"speed_jitter": 0.35,
		"join_cooldown_s": 5.0,
		"raid_race": true,
		"panel_color": "#00000066",
		"text_color": "#ffffff",
		"npc_names": ["Pebble", "Noodle", "Biscuit", "Gizmo", "Waffle", "Pickle", "Mochi", "Sprout", "Bean", "Nugget"],
		"critters": [
			{"shape": "circle", "color": "#ff6b6b", "size": 34, "sprite": ""},
			{"shape": "square", "color": "#ffd93d", "size": 30, "sprite": ""},
			{"shape": "triangle", "color": "#6bcb77", "size": 38, "sprite": ""},
			{"shape": "circle", "color": "#4d96ff", "size": 28, "sprite": ""},
			{"shape": "square", "color": "#c77dff", "size": 36, "sprite": ""},
			{"shape": "triangle", "color": "#ff9f1c", "size": 32, "sprite": ""},
			{"shape": "circle", "color": "#2ec4b6", "size": 40, "sprite": ""},
			{"shape": "square", "color": "#f15bb5", "size": 26, "sprite": ""},
			{"shape": "triangle", "color": "#e0e0e0", "size": 34, "sprite": ""},
		],
		"npc_critters": [
			{"shape": "circle", "color": "#8d99ae", "size": 26, "sprite": ""},
			{"shape": "square", "color": "#adb5bd", "size": 24, "sprite": ""},
			{"shape": "triangle", "color": "#6c757d", "size": 28, "sprite": ""},
		],
		"raider_critter": {"shape": "triangle", "color": "#ff5d8f", "size": 56, "sprite": ""},
		"seed": 0,
	}


func get_config_constraints() -> Dictionary:
	return {
		"lanes": {"min": 2, "max": 12},
		"min_humans_to_start": {"min": 1, "max": 12},
		"lobby_timeout_s": {"min": 1.0, "max": 600.0},
		"countdown_s": {"min": 0.0, "max": 30.0},
		"results_s": {"min": 0.5, "max": 60.0},
		"cooldown_s": {"min": 0.0, "max": 3600.0},
		"max_race_s": {"min": 5.0, "max": 600.0},
		"base_speed": {"min": 0.005, "max": 2.0},
		"speed_jitter": {"min": 0.0, "max": 0.95},
		"join_cooldown_s": {"min": 0.0},
		"panel_color": {"color": true},
		"text_color": {"color": true},
	}


func subscribes_to() -> Array:
	return ["chat_command", "raid"]


func get_commands() -> Array:
	return [{"name": "join", "cooldown_s": config["join_cooldown_s"], "aliases": ["race"]}]


func setup() -> bool:
	logic = RaceLogic.new()
	logic.configure(config)
	logic.rng = rng
	_region = rect_from(config["region"], Rect2(100, overlay_size.y - 340, overlay_size.x - 200, 320))
	_header = Label.new()
	_header.add_theme_color_override("font_color", ShapeFactory.parse_color(config["text_color"]))
	_header.add_theme_color_override("font_outline_color", Color.BLACK)
	_header.add_theme_constant_override("outline_size", 6)
	_header.add_theme_font_size_override("font_size", 28)
	_header.position = _region.position + Vector2(12, -44)
	add_child(_header)
	visible = false
	return true


func on_event(event: Dictionary) -> bool:
	match event["type"]:
		"chat_command":
			if event["command"] == "join":
				logic.join(str(event["user_id"]), str(event["user_name"]))
		"raid":
			if config["raid_race"]:
				logic.raid(str(event["user_id"]), str(event["user_name"]), int(event.get("viewers", 0)))
	return true


func _process(delta: float) -> void:
	if logic == null:
		return
	_anim_time += delta
	logic.step(delta)
	for ev in logic.take_events():
		_on_logic_event(ev)
	if not visible:
		return
	_layout_critters()
	_header.text = _header_text()
	queue_redraw()


func _on_logic_event(ev: Dictionary) -> void:
	match ev["type"]:
		"phase":
			match ev["phase"]:
				"LOBBY":
					_clear_critters()
					visible = true
				"IDLE", "COOLDOWN":
					_clear_critters()
					visible = false
		"joined":
			_add_critter(ev)
		"race_over":
			for e in logic.entrants:
				if _critters.has(e["id"]) and e["place"] >= 1 and e["place"] <= 3:
					var label: Label = _critters[e["id"]].get_node("Name")
					label.text = "#%d %s" % [e["place"], e["name"]]
			# Finishers sit by the line: move every name to the critter's left.
			for node in _critters.values():
				var label: Label = node.get_node("Name")
				label.position = Vector2(-label.get_minimum_size().x - 28.0, -label.get_minimum_size().y * 0.5)


func _add_critter(e: Dictionary) -> void:
	if _critters.has(e["id"]):
		return
	var spec: Variant
	if e.get("raider", false):
		spec = config["raider_critter"]
	elif e["npc"]:
		spec = _pick(config["npc_critters"], e["name"])
	else:
		spec = _pick(config["critters"], e["id"])
	var holder := Node2D.new()
	holder.add_child(ShapeFactory.make_visual(ShapeFactory.normalize_spec(spec), assets))
	var label := Label.new()
	label.name = "Name"
	label.text = e["name"] + (" (raid!)" if e.get("raider", false) else "")
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8) if e["npc"] else Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 16)
	label.position = Vector2(-20, -42)
	holder.add_child(label)
	add_child(holder)
	_critters[e["id"]] = holder


## Same viewer -> same critter every race.
func _pick(options: Variant, key: String) -> Variant:
	if typeof(options) != TYPE_ARRAY or options.is_empty():
		return {}
	return options[absi(hash(key)) % options.size()]


func _clear_critters() -> void:
	for node in _critters.values():
		node.queue_free()
	_critters.clear()


func _lane_y(lane: int) -> float:
	var lane_h := _region.size.y / maxf(1.0, float(logic.lanes))
	return _region.position.y + lane_h * (lane + 0.5)


func _track_x(progress: float) -> float:
	var start := _region.position.x + 40.0
	var finish := _region.end.x - 70.0
	return lerpf(start, finish, progress)


func _layout_critters() -> void:
	for e in logic.entrants:
		var node: Node2D = _critters.get(e["id"])
		if node == null:
			continue
		var hop := 0.0
		if logic.phase == RaceLogic.Phase.RACING and e["finish_time"] < 0.0:
			hop = -absf(sin(_anim_time * 10.0 + e["lane"])) * 8.0
		node.position = Vector2(_track_x(e["progress"]), _lane_y(e["lane"]) + hop)


func _header_text() -> String:
	var prefix: String = app_config.get_value("chat.command_prefix", "!") if app_config else "!"
	match logic.phase:
		RaceLogic.Phase.LOBBY:
			return "CRITTER RACE! type %sjoin  (%d/%d)  starts in %ds" % [prefix, logic.humans(), logic.min_humans_to_start, ceili(logic.seconds_left())]
		RaceLogic.Phase.COUNTDOWN:
			return "Get ready... %d" % ceili(logic.seconds_left())
		RaceLogic.Phase.RACING:
			return "GO GO GO!"
		RaceLogic.Phase.RESULTS:
			var w := logic.winner()
			return "Winner: %s!" % w.get("name", "?") if not w.is_empty() else "Race over!"
	return ""


func _draw() -> void:
	if logic == null or logic.phase in [RaceLogic.Phase.IDLE, RaceLogic.Phase.COOLDOWN]:
		return
	draw_rect(_region, ShapeFactory.parse_color(config["panel_color"], Color(0, 0, 0, 0.4)))
	var lane_h := _region.size.y / maxf(1.0, float(logic.lanes))
	for i in range(1, logic.lanes):
		var y := _region.position.y + lane_h * i
		draw_line(Vector2(_region.position.x, y), Vector2(_region.end.x, y), Color(1, 1, 1, 0.15), 1.0)
	# Checkered finish line made of small squares.
	var fx := _track_x(1.0) + 20.0
	var cell := 10.0
	var rows := int(_region.size.y / cell)
	for r in rows:
		for c in 2:
			var white := (r + c) % 2 == 0
			draw_rect(Rect2(fx + c * cell, _region.position.y + r * cell, cell, cell), Color.WHITE if white else Color.BLACK)
	if show_regions:
		draw_rect(_region, Color.YELLOW, false, 2.0)
