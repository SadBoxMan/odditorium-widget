extends SceneTree
## Mock Streamer.bot WebSocket server.
##
## godot --headless --path . --script res://tools/mock_streamerbot.gd -- \
##     [--scenario=res://tools/scenarios/demo.json] [--port=8080] \
##     [--password=secret] [--loop] [--exit-when-done]
##
## Without --exit-when-done the server keeps running after the scenario so
## you can watch the overlay; stop it with Ctrl+C.

var _exit_when_done := false


func _initialize() -> void:
	var scenario_path := "res://tools/scenarios/demo.json"
	var port := 8080
	var password := ""
	var loop := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario_path = arg.substr(11)
		elif arg.begins_with("--port="):
			port = int(arg.substr(7))
		elif arg.begins_with("--password="):
			password = arg.substr(11)
		elif arg == "--loop":
			loop = true
		elif arg == "--exit-when-done":
			_exit_when_done = true

	var scenario := MockScenarioPlayer.load_scenario(scenario_path)
	if scenario.is_empty():
		printerr("[mock] could not load scenario %s" % scenario_path)
		quit(2)
		return

	var server := MockStreamerBot.new()
	server.password = password
	root.add_child(server)
	if server.start(port) != OK:
		quit(3)
		return

	var player := MockScenarioPlayer.new()
	player.server = server
	player.steps = scenario["steps"]
	player.loop = loop
	player.scenario_name = scenario.get("name", scenario_path.get_file())
	root.add_child(player)
	player.finished.connect(_on_finished.bind(player))
	print("[mock] playing scenario '%s' (%d steps)" % [player.scenario_name, player.steps.size()])
	# Nodes added in _initialize enter the tree on the first frame.
	player.play.call_deferred()


func _on_finished(player: MockScenarioPlayer) -> void:
	for e in player.errors:
		printerr("[mock] scenario error: " + e)
	if _exit_when_done:
		await create_timer(1.0).timeout
		quit(1 if not player.errors.is_empty() else 0)
