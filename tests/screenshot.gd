extends SceneTree
## Renders a few representative frames to PNG for visual review. Needs a real window:
##   godot --path . --resolution 720x1280 --script res://tests/screenshot.gd -- <output_dir>

var out_dir := "res://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	_run()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name, " ", img.get_size())


func _sim(main, seconds: float, bot: bool) -> void:
	var dt := 1.0 / 60.0
	for i in int(seconds * 60.0):
		if bot:
			_bot(main)
		main.step(dt)


func _run() -> void:
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.save_enabled = false
	await process_frame
	seed(7)
	await _shot("1_menu")

	main.start_run()
	_sim(main, 0.6, false)
	await _shot("2_wave_banner")

	_sim(main, 25.0, true)
	await _shot("3_playing")

	# Force a clear moment for the effects frame.
	main.board.reset()
	for c in 3:
		main.board.push(c, 1)
	main.check_pending = true
	_sim(main, 0.12, false)
	await _shot("4_clearing")

	main.board.reset()
	main.board.push(0, 0)
	main.board.push(0, 1)
	main.board.push(0, 2)
	main.board.push(0, 3)
	main.board.push(0, 4)
	main.board.push(1, 4)
	main.board.push(1, 3)
	main.board.push(1, 0)
	main.board.push(1, 1)
	main.held = [2, 1, 4, 0]
	await _shot("5_danger")

	main.pause_game()
	await _shot("6_pause")
	main.resume_game()

	main.lives = 1
	main._lose_life()
	main.game_over_t = 2.0
	await _shot("7_gameover")
	quit()


func _bot(main) -> void:
	if main.state != main.State.PLAYING:
		return
	if not main.held.is_empty() and randf() < 0.08:
		var color: int = main.held.back()
		var lane := -1
		for c in 5:
			var h: int = main.board.height(c)
			if h < 5 and h > 0 and main.board.cols[c][h - 1] == color:
				lane = c
				break
		if lane == -1 and main.held.size() >= 3:
			lane = randi() % 5
		if lane != -1:
			main.set_lane(lane)
			main.do_drop()
			return
	var target = null
	for t in main.belt_tiles:
		if t.vy > 0.0 and (target == null or t.y > target.y):
			target = t
	if target != null and main.held.size() < 5:
		main.set_lane(target.lane)
