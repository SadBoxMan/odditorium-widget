extends RefCounted
## Critter Race rules, with no rendering, so they can be unit-tested.
## Time only advances through step(delta), so runs are deterministic for a
## given RNG seed.
##
## IDLE --first !join--> LOBBY --enough humans / lobby timeout--> COUNTDOWN
##   --> RACING --all finished / max time--> RESULTS --> COOLDOWN --> IDLE
## (COOLDOWN goes straight to a new LOBBY when people joined mid-race.)

enum Phase { IDLE, LOBBY, COUNTDOWN, RACING, RESULTS, COOLDOWN }

var lanes := 6
var min_humans_to_start := 3
var lobby_timeout_s := 30.0
var countdown_s := 3.0
var results_s := 6.0
var cooldown_s := 10.0
var max_race_s := 45.0
var base_speed := 0.08  ## track lengths per second
var speed_jitter := 0.35  ## +/- fraction applied at each speed change
var speed_change_s := 0.6
var npc_names: Array = ["Pebble", "Noodle", "Biscuit", "Gizmo", "Waffle", "Pickle", "Mochi", "Sprout", "Bean", "Nugget"]
var rng := RandomNumberGenerator.new()

var phase: Phase = Phase.IDLE
var time := 0.0
var phase_ends_at := 0.0
## Each: {id, name, npc: bool, raider: bool, lane, progress, speed,
##        next_speed_change, finish_time, place}
var entrants: Array[Dictionary] = []
## Finish order (entrant ids).
var results: Array[String] = []
## Humans who joined while a race was running; they open the next lobby.
var next_up: Array[Dictionary] = []

var _events: Array[Dictionary] = []


func configure(cfg: Dictionary) -> void:
	lanes = cfg.get("lanes", lanes)
	min_humans_to_start = cfg.get("min_humans_to_start", min_humans_to_start)
	lobby_timeout_s = cfg.get("lobby_timeout_s", lobby_timeout_s)
	countdown_s = cfg.get("countdown_s", countdown_s)
	results_s = cfg.get("results_s", results_s)
	cooldown_s = cfg.get("cooldown_s", cooldown_s)
	max_race_s = cfg.get("max_race_s", max_race_s)
	base_speed = cfg.get("base_speed", base_speed)
	speed_jitter = cfg.get("speed_jitter", speed_jitter)
	var names: Variant = cfg.get("npc_names", npc_names)
	if typeof(names) == TYPE_ARRAY and not names.is_empty():
		npc_names = names


## Returns: joined | already_in | full | queued_next | next_full
func join(user_id: String, display_name: String) -> String:
	match phase:
		Phase.IDLE:
			_open_lobby()
			return _add_human(user_id, display_name)
		Phase.LOBBY, Phase.COUNTDOWN:
			return _add_human(user_id, display_name)
		_:
			for e in next_up:
				if e["id"] == user_id:
					return "already_in"
			if _find(user_id) != null:
				return "already_in"
			if next_up.size() >= lanes:
				return "next_full"
			next_up.append({"id": user_id, "name": display_name})
			_emit("queued_next", {"id": user_id, "name": display_name})
			return "queued_next"


## A raid starts a race right away (if one isn't already running) with the
## raider as a special critter. Returns true if it did anything.
func raid(raider_id: String, raider_name: String, viewers: int) -> bool:
	if phase in [Phase.RACING, Phase.RESULTS, Phase.COUNTDOWN]:
		return false
	if phase in [Phase.IDLE, Phase.COOLDOWN]:
		_open_lobby()
	# A full lobby of chatters keeps its lanes; the raid still starts the race.
	if _find(raider_id) == null and humans() < lanes:
		var e := _new_entrant(raider_id, raider_name, false)
		e["raider"] = true
		e["viewers"] = viewers
		entrants.append(e)
		_emit("joined", e)
	_start_countdown()
	return true


func humans() -> int:
	return entrants.filter(func(e): return not e["npc"]).size()


func step(delta: float) -> void:
	time += delta
	match phase:
		Phase.LOBBY:
			if time >= phase_ends_at:
				if humans() > 0:
					_start_countdown()
				else:
					_set_phase(Phase.IDLE, 0.0)
		Phase.COUNTDOWN:
			if time >= phase_ends_at:
				_start_race()
		Phase.RACING:
			_advance_racers(delta)
			if results.size() == entrants.size() or time >= phase_ends_at:
				_finish_race()
		Phase.RESULTS:
			if time >= phase_ends_at:
				entrants.clear()
				_set_phase(Phase.COOLDOWN, cooldown_s)
		Phase.COOLDOWN:
			if time >= phase_ends_at:
				if next_up.is_empty():
					_set_phase(Phase.IDLE, 0.0)
				else:
					var waiting := next_up.duplicate()
					next_up.clear()
					_open_lobby()
					for w in waiting:
						_add_human(w["id"], w["name"])


func seconds_left() -> float:
	return maxf(0.0, phase_ends_at - time)


func winner() -> Dictionary:
	if results.is_empty():
		return {}
	return _find(results[0])


## Events since the last call: [{"type": "...", ...}].
func take_events() -> Array[Dictionary]:
	var out := _events.duplicate()
	_events.clear()
	return out


# --- internals ----------------------------------------------------------------

func _open_lobby() -> void:
	entrants.clear()
	results.clear()
	_set_phase(Phase.LOBBY, lobby_timeout_s)


func _add_human(user_id: String, display_name: String) -> String:
	if _find(user_id) != null:
		return "already_in"
	if humans() >= lanes:
		return "full"
	var e := _new_entrant(user_id, display_name, false)
	entrants.append(e)
	_emit("joined", e)
	if phase == Phase.LOBBY and (humans() >= min_humans_to_start or humans() >= lanes):
		_start_countdown()
	return "joined"


func _start_countdown() -> void:
	if phase == Phase.COUNTDOWN:
		return
	_fill_npcs()
	_set_phase(Phase.COUNTDOWN, countdown_s)


func _fill_npcs() -> void:
	var used := entrants.map(func(e): return e["name"])
	var pool := npc_names.filter(func(n): return not (n in used))
	var i := 0
	while entrants.size() < lanes:
		var name: String = pool[i] if i < pool.size() else "Critter %d" % (i + 1)
		var e := _new_entrant("npc:%s:%d" % [name, i], name, true)
		entrants.append(e)
		_emit("joined", e)
		i += 1
	# Shuffle lanes so humans aren't always on top.
	var order := range(entrants.size())
	for j in range(order.size() - 1, 0, -1):
		var k := rng.randi_range(0, j)
		var tmp: int = order[j]
		order[j] = order[k]
		order[k] = tmp
	for idx in entrants.size():
		entrants[idx]["lane"] = order[idx]


func _start_race() -> void:
	for e in entrants:
		e["progress"] = 0.0
		e["speed"] = _roll_speed()
		e["next_speed_change"] = time + rng.randf_range(0.2, speed_change_s)
	_set_phase(Phase.RACING, max_race_s)


func _advance_racers(delta: float) -> void:
	for e in entrants:
		if e["finish_time"] >= 0.0:
			continue
		if time >= e["next_speed_change"]:
			e["speed"] = _roll_speed()
			e["next_speed_change"] = time + rng.randf_range(0.2, speed_change_s)
		e["progress"] = minf(1.0, e["progress"] + e["speed"] * delta)
		if e["progress"] >= 1.0:
			e["finish_time"] = time
			results.append(e["id"])
			e["place"] = results.size()
			_emit("finished", e)


func _finish_race() -> void:
	# Anyone still running (max_race_s hit) is ranked by distance.
	var unfinished := entrants.filter(func(e): return e["finish_time"] < 0.0)
	unfinished.sort_custom(func(a, b): return a["progress"] > b["progress"])
	for e in unfinished:
		results.append(e["id"])
		e["place"] = results.size()
	_emit("race_over", {"winner": winner()})
	_set_phase(Phase.RESULTS, results_s)


func _roll_speed() -> float:
	var s := base_speed * rng.randf_range(1.0 - speed_jitter, 1.0 + speed_jitter)
	# Small chance of a nap or a zoomies burst, for drama.
	var roll := rng.randf()
	if roll < 0.06:
		s *= 0.15
	elif roll > 0.95:
		s *= 2.0
	return maxf(0.005, s)


func _new_entrant(id: String, display_name: String, npc: bool) -> Dictionary:
	return {"id": id, "name": display_name, "npc": npc, "raider": false, "lane": entrants.size(),
		"progress": 0.0, "speed": 0.0, "next_speed_change": 0.0, "finish_time": -1.0, "place": 0}


func _find(id: String) -> Variant:
	for e in entrants:
		if e["id"] == id:
			return e
	return null


func _set_phase(p: Phase, duration: float) -> void:
	phase = p
	phase_ends_at = time + duration
	_emit("phase", {"phase": Phase.keys()[p]})


func _emit(type: String, data: Dictionary) -> void:
	var ev := data.duplicate()
	ev["type"] = type
	_events.append(ev)
