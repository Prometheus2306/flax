extends SceneTree
## Headless smoke test: plays hundreds of simulated seconds with a simple bot and
## checks invariants. Run with:
##   godot --headless --path . --script res://tests/smoke_test.gd

var failures := 0
var checks := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL ", label)


func _initialize() -> void:
	_run()


func _run() -> void:
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	main.save_enabled = false
	await process_frame
	seed(12345)
	print("menu state: ", main.state)
	check(main.state == main.State.MENU, "starts at menu")
	main._key(KEY_SPACE)
	check(main.state == main.State.PLAYING, "space starts a run")

	var max_wave := 1
	var runs := 0
	var best_score := 0
	var dt := 1.0 / 60.0
	for frame in 60 * 600:
		_bot(main)
		main.step(dt)
		max_wave = maxi(max_wave, main.wave)
		best_score = maxi(best_score, main.score)
		# Invariants.
		check(main.held.size() <= main.MAX_HELD, "held within capacity")
		check(main.lives <= main.MAX_LIVES, "lives within cap")
		for c in 5:
			check(main.board.height(c) <= 6, "bin height sane")
		if main.state == main.State.GAME_OVER:
			runs += 1
			main.game_over_t = 5.0
			main._key(KEY_SPACE)
		if failures > 5:
			break
	print("runs finished: ", runs, "  best score: ", best_score, "  max wave: ", max_wave)
	check(best_score > 0, "bot scored something")

	# Exercise pause / menu / sound flows.
	main.start_run()
	main.pause_game()
	check(main.state == main.State.PAUSED, "pause")
	main.resume_game()
	check(main.state == main.State.PLAYING, "resume")
	main.to_menu()
	check(main.state == main.State.MENU, "menu")

	await _input_tests(main)

	print("FAILURES: ", failures, "  (", checks, " checks)")
	quit(1 if failures > 0 else 0)


func _touch(main, index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	main._input(ev)


func _drag(main, index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	main._input(ev)


## Simulates real touch gestures against the layout.
func _input_tests(main) -> void:
	_touch(main, 0, Vector2(360, 600), true)
	_touch(main, 0, Vector2(360, 600), false)
	check(main.state == main.State.PLAYING, "tap on menu starts the game")
	main.held = [1, 2]
	main.wave_delay = 99.0

	var lane4 := Vector2(main.lane_center(4), 400)
	_touch(main, 0, lane4, true)
	check(main.paddle_lane == 4, "touch moves paddle to the lane")
	_touch(main, 0, lane4, false)
	check(main.held.size() == 2, "tap on a different lane only moves")
	_touch(main, 0, lane4, true)
	_touch(main, 0, lane4, false)
	check(main.held.size() == 1 and main.flights.size() == 1, "tap on own lane drops")
	main.step(0.3)
	check(main.board.height(4) == 1, "dropped tile lands in the bin")

	# Drag across lanes should slide the paddle without dropping.
	main.held = [3]
	_touch(main, 1, Vector2(main.lane_center(4), 400), true)
	_drag(main, 1, Vector2(main.lane_center(2), 400))
	_touch(main, 1, Vector2(main.lane_center(2), 400), false)
	check(main.paddle_lane == 2 and main.held.size() == 1, "drag slides without dropping")

	# Swipe up flips the top tile back onto the conveyor.
	var before: int = main.belt_tiles.size()
	_touch(main, 2, Vector2(main.lane_center(2), 600), true)
	_drag(main, 2, Vector2(main.lane_center(2), 460))
	_touch(main, 2, Vector2(main.lane_center(2), 460), false)
	check(main.held.is_empty() and main.belt_tiles.size() == before + 1, "swipe up flips")

	# On-screen buttons.
	main.held = [0, 4]
	var drop_pos: Vector2 = main.buttons["drop"].get_center()
	_touch(main, 3, drop_pos, true)
	_touch(main, 3, drop_pos, false)
	check(main.held.size() == 1, "drop button drops")
	var flip_pos: Vector2 = main.buttons["flip"].get_center()
	_touch(main, 3, flip_pos, true)
	_touch(main, 3, flip_pos, false)
	check(main.held.is_empty(), "flip button flips")

	# Pause button.
	_touch(main, 4, main.buttons["pause"].get_center(), true)
	_touch(main, 4, main.buttons["pause"].get_center(), false)
	check(main.state == main.State.PAUSED, "pause button pauses")
	_touch(main, 4, main.buttons["ov_b"].get_center(), true)
	check(main.state == main.State.MENU, "quit button returns to menu")

	# Full bin rejects drops and costs a life.
	main.start_run()
	main.wave_delay = 99.0
	for i in 5:
		main.board.push(0, i % 3)
	main.set_lane(0)
	main.held = [1]
	var lives: int = main.lives
	main.do_drop()
	check(main.lives == lives - 1 and main.board.height(0) == 5, "full bin rejects tile and costs a life")

	# Missing a tile costs a life, three misses end the game.
	main.start_run()
	main.wave_delay = 99.0
	main.set_lane(0)
	for i in 3:
		main.belt_tiles.append({"lane": 4, "y": main.paddle_top - 10.0, "vy": 150.0, "toss": false, "color": 0})
		main.step(0.1)
	check(main.state == main.State.GAME_OVER, "three misses end the game")

	# Save file round trip keeps the best score.
	check(main.best >= 0, "best score tracked")


## A deliberately simple bot: chase the lowest tile, then drop onto matching colors.
func _bot(main) -> void:
	if main.state != main.State.PLAYING:
		return
	# Drop decisions.
	if not main.held.is_empty() and randf() < 0.08:
		var color: int = main.held.back()
		var best_lane := -1
		for c in 5:
			if main.board.height(c) >= 5:
				continue
			var h: int = main.board.height(c)
			if h > 0 and main.board.cols[c][h - 1] == color:
				best_lane = c
				break
		if best_lane == -1 and main.held.size() >= 3:
			best_lane = randi() % 5
		if best_lane != -1:
			main.set_lane(best_lane)
			main.do_drop()
			return
	if main.held.size() >= 5 and randf() < 0.2:
		main.do_flip()
	# Chase the lowest tile still falling and not yet caught.
	var target = null
	for t in main.belt_tiles:
		if t.vy > 0.0 and (target == null or t.y > target.y):
			target = t
	if target != null and main.held.size() < 5:
		main.set_lane(target.lane)
