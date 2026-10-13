extends TestCase

const BonkModule := preload("res://modules/bonk/module.gd")
const TMP_DIR := "user://test_bonk"

var parent: Node2D
var reg: ModuleRegistry
var bus: ChaosEventBus
var router: CommandRouter


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	parent = Node2D.new()
	tree.root.add_child(parent)
	bus = ChaosEventBus.new()
	router = CommandRouter.new()
	reg = ModuleRegistry.new()
	reg._bus = bus
	reg._router = router


func after_each() -> void:
	reg.shutdown()
	parent.queue_free()


func _load(module_cfg: Dictionary) -> ChaosModule:
	var base := {"seed": 99}
	base.merge(module_cfg, true)
	var cfg := ChaosConfig.from_dict({"modules": {"bonk": base}})
	router.configure(cfg)
	var m := reg.instantiate("res://modules/bonk/module.gd")
	check(reg.load_module(m, parent, cfg, AssetLoader.new(cfg.base_dir), Vector2(1920, 1080)), "bonk loaded")
	return m


func _cmd(user: String, args: Array, via_redeem := false) -> Dictionary:
	return {"type": "chat_command", "command": "bonk", "args": args, "user_id": user, "user_login": user, "user_name": user.capitalize(), "via_redeem": via_redeem}


func test_parse_args() -> void:
	var names := ["ball", "brick"]
	check_eq(BonkModule.parse_args(["@Dave", "brick"], names), {"target": "dave", "object": "brick"})
	check_eq(BonkModule.parse_args(["brick"], names), {"target": "", "object": "brick"})
	check_eq(BonkModule.parse_args(["Brick", "@dave"], names), {"target": "dave", "object": "brick"})
	check_eq(BonkModule.parse_args([], names), {"target": "", "object": ""})
	check_eq(BonkModule.parse_args(["@dave", "anvil"], names), {"target": "dave", "object": ""}, "unknown object ignored")


func test_parse_objects_validation() -> void:
	var warnings: Array = []
	var objs := BonkModule.parse_objects({
		"Good": {"shape": "circle", "color": "#123456", "size": 30, "mass": 2, "bounce": 5, "sound": "a.ogg"},
		"bad_entry": "nope",
		"weird": {"shape": "star", "mass": "heavy"},
		"_comment": "ignored",
	}, warnings)
	check_eq(objs.keys().size(), 2)
	check(objs.has("good"), "names lower-cased")
	check_eq(objs["good"]["bounce"], 1.0, "bounce clamped")
	check_eq(objs["good"]["mass"], 2.0)
	check_eq(objs["good"]["sound"], "a.ogg")
	check_eq(objs["weird"]["shape"], "square", "bad shape falls back")
	check_eq(objs["weird"]["mass"], 1.0, "bad mass falls back")
	check_eq(warnings.size(), 2, str(warnings))


func test_launch_velocity_reaches_target() -> void:
	var from := Vector2(-50, 300)
	var to := Vector2(1600, 800)
	var g := 980.0
	var v := BonkModule.launch_velocity(from, to, 1300.0, g)
	var t := from.distance_to(to) / 1300.0
	var landed := from + v * t + Vector2(0, 0.5 * g * t * t)
	check(landed.distance_to(to) < 0.5, "analytic arc lands on target: %s" % landed)


func test_command_spawns_shape_object() -> void:
	var m := _load({})
	check(router.has_command("bonk") and router.has_command("yeet"))
	bus.emit("chat_command", _cmd("alice", ["@bob", "brick"]))
	check_eq(m.live_count(), 1)
	var body: RigidBody2D = m._live[0]
	check_eq(body.get_meta("object_name"), "brick")
	check(body.get_child(0).shape is RectangleShape2D, "square collision for brick")
	check_eq(body.get_child(1).get_meta("visual_kind"), "shape", "no sprite -> shape")
	check(body.linear_velocity.length() > 100.0, "launched")


func test_object_choice_can_be_disabled() -> void:
	var m := _load({"allow_object_choice": false, "objects": {"ball": {"shape": "circle", "weight": 1}, "brick": {"shape": "square", "weight": 0}}})
	for i in 5:
		bus.emit("chat_command", _cmd("u%d" % i, ["brick"]))
	for b in m._live:
		check_eq(b.get_meta("object_name"), "ball", "weight 0 never picked; choice ignored")


func test_sprite_and_sound_mapping() -> void:
	var png := TMP_DIR.path_join("duck.png")
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.YELLOW)
	img.save_png(png)
	var wav_path := TMP_DIR.path_join("bonk.wav")
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	wav.save_to_wav(wav_path)
	var m := _load({"objects": {
		"duck": {"shape": "circle", "size": 64, "sprite": png, "sound": wav_path},
		"ghost": {"shape": "triangle", "size": 40, "sprite": TMP_DIR.path_join("missing.png"), "sound": TMP_DIR.path_join("missing.ogg")},
	}})
	var duck: RigidBody2D = m.bonk("duck")
	check_eq(duck.get_child(1).get_meta("visual_kind"), "sprite", "sprite path used")
	check(duck.get_child(0).shape is CircleShape2D, "collision still from shape type")
	var ghost: RigidBody2D = m.bonk("ghost")
	check_eq(ghost.get_child(1).get_meta("visual_kind"), "shape", "missing sprite -> shape fallback")
	check(m.assets.load_audio(wav_path) != null, "wav loads")
	check(m.assets.load_audio(TMP_DIR.path_join("missing.ogg")) == null, "missing sound -> silence")


func test_object_hits_cam_region_and_despawns() -> void:
	var m := _load({"lifetime_s": 2.5, "fade_s": 0.5, "throw_speed": 2000.0})
	var body: RigidBody2D = m.bonk("ball", "test")
	var hit := await wait_until(func(): return m.hits_total >= 1, 3.0)
	check(hit, "object collided with the cam region")
	check(await wait_until(func(): return m.live_count() == 0, 4.0), "object despawned after its lifetime")
	check(not is_instance_valid(body) or not body.is_inside_tree())


func test_max_objects_cap() -> void:
	var m := _load({"max_objects": 5})
	for i in 20:
		m.bonk()
	check_eq(m.live_count(), 5, "oldest removed beyond max_objects")
	check_eq(m.spawned_total, 20)


func test_raid_barrage_capped() -> void:
	var m := _load({"raid_barrage_max": 4})
	bus.emit("raid", {"type": "raid", "user_id": "r", "user_login": "r", "user_name": "Raider", "viewers": 500})
	check_eq(m.live_count(), 4)


func test_follow_bonk_off_by_default() -> void:
	var m := _load({})
	bus.emit("follow", {"type": "follow", "user_id": "f", "user_login": "f", "user_name": "F"})
	check_eq(m.live_count(), 0)


func test_follow_bonk_when_enabled() -> void:
	var m := _load({"follow_bonk": true})
	bus.emit("follow", {"type": "follow", "user_id": "f", "user_login": "f", "user_name": "F"})
	check_eq(m.live_count(), 1)
	check_eq(m._live[0].get_meta("object_name"), "pillow")


func test_empty_objects_falls_back() -> void:
	var m := _load({"objects": {}})
	check_eq(m.objects.keys(), ["ball"])
	check(m.bonk() != null)


func test_redeem_path_end_to_end() -> void:
	var cfg := ChaosConfig.from_dict({"redeems": {"enabled": true}, "modules": {"bonk": {"seed": 1}}})
	router.configure(cfg)
	var m := reg.instantiate("res://modules/bonk/module.gd")
	reg.load_module(m, parent, cfg, AssetLoader.new(), Vector2(1920, 1080))
	var redeem := {"type": "redeem", "user_id": "c", "user_login": "carol", "user_name": "Carol", "reward_title": "Bonk the Streamer", "text": "pillow"}
	check_eq(router.route(redeem, 0.0), "queued")
	bus.emit("chat_command", router.queue.pop())
	check_eq(m.live_count(), 1)
	check_eq(m._live[0].get_meta("object_name"), "pillow", "redeem input picks the object")
