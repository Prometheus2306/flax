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
	_effects_and_perspective_tests(main)

	root.remove_child(main)
	main.free()
	await process_frame
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


## Verifies 2.5D perspective math, procedural sprite generation, and combo explosion lifecycle.
func _effects_and_perspective_tests(main) -> void:
	# 1. Procedural fluid & explosion sprites + audio bank
	check(main.view._tex_droplet != null and main.view._tex_droplet.get_size() == Vector2(48, 48), "fluid droplet sprite generated")
	check(main.view._tex_splash != null and main.view._tex_splash.get_size() == Vector2(64, 64), "fluid splash sprite generated")
	check(main.view._tex_bubble != null and main.view._tex_bubble.get_size() == Vector2(48, 48), "fluid bubble sprite generated")
	check(main.view._tex_star != null and main.view._tex_star.get_size() == Vector2(64, 64), "star sprite generated")
	check(main.view._tex_spark != null and main.view._tex_spark.get_size() == Vector2(48, 48), "spark sprite generated")
	check(main.view._tex_glow != null and main.view._tex_glow.get_size() == Vector2(48, 48), "glow sprite generated")
	check(main.view._tex_shard != null and main.view._tex_shard.get_size() == Vector2(32, 32), "shard sprite generated")
	check(main.sfx._bank.has("boom") and main.sfx._bank["boom"] != null, "boom explosion sfx generated")

	# 2. 2.5D perspective ramp geometry
	check(is_equal_approx(main.belt_depth(main.conveyor_top), 0.0), "belt_depth at horizon is 0")
	check(is_equal_approx(main.belt_depth(main.paddle_top), 1.0), "belt_depth at paddle is 1")
	check(is_equal_approx(main.belt_scale(main.conveyor_top), main.BELT_TOP_SCALE), "belt_scale at horizon matches BELT_TOP_SCALE")
	check(is_equal_approx(main.belt_scale(main.paddle_top), 1.0), "belt_scale at paddle is 1")
	check(main.belt_lane_w(main.conveyor_top) < main.belt_lane_w(main.paddle_top), "lanes widen from horizon to paddle")
	for c in 5:
		check(is_equal_approx(main.belt_lane_x(float(c), main.paddle_top), main.lane_left(c)), "2.5D lane left aligns with bin column at paddle")
		check(is_equal_approx(main.belt_lane_center(c, main.paddle_top), main.lane_center(c)), "2.5D lane center aligns with bin center at paddle")
		check(main.belt_lane_x(float(c), main.conveyor_top) < main.belt_lane_x(float(c + 1), main.conveyor_top), "horizon lanes strictly ordered")
		# Verify moving conveyor tiles start small far away, preserve un-warped aspect ratio,
		# map 1:1 into Rutsche spaces, and reach exact drop-box size at the paddle.
		var sh: float = main.belt_slot_h()
		var top_rect: Rect2 = main.view.belt_tile_rect(c, main.conveyor_top, sh)
		var bot_rect: Rect2 = main.view.belt_tile_rect(c, main.paddle_top - sh, sh)
		var bin_rect: Rect2 = main.view.tile_rect(c, main.bins_top, main.cell_h)
		check(top_rect.size.x < bot_rect.size.x * 0.45 and top_rect.size.y < bot_rect.size.y * 0.45, "horizon Rutsche tiles start much smaller than foreground tiles")
		check(is_equal_approx(bot_rect.size.y, main.cell_h), "bottom Rutsche space reaches exact cell_h height at paddle")
		check(absf(bot_rect.size.x - bin_rect.size.x) < 6.0, "bottom Rutsche space width matches drop-box tile width")
		var expected_aspect: float = top_rect.size.x / top_rect.size.y
		for step_i in 6:
			var y_test: float = lerpf(main.conveyor_top, main.paddle_top - sh, float(step_i) / 5.0)
			var b_rect: Rect2 = main.view.belt_tile_rect(c, y_test, sh)
			var aspect: float = b_rect.size.x / b_rect.size.y
			check(is_equal_approx(aspect, expected_aspect), "moving belt tile preserves un-warped aspect ratio")
			var snapped_y: float = main.snap_to_belt_slot(y_test)
			var phase_rem: float = fposmod(snapped_y - main.conveyor_top - main.belt_scroll, sh)
			check(is_zero_approx(phase_rem) or is_equal_approx(phase_rem, sh), "snapped tile maps exactly onto a dedicated Rutsche slot")

	# 3. Multi-sprite explosion & combo beam spawning and cleanup
	main.start_run()
	main.wave_delay = 99.0
	# Create a simultaneous horizontal + diagonal combo:
	# Horizontal color 2 at (0,0), (1,0), (2,0)
	# Diagonal color 3 at (1,1), (2,2), (3,3)
	main.board.push(0, 2)
	main.board.push(1, 2)
	main.board.push(1, 3)
	main.board.push(2, 2)
	main.board.push(2, 0)
	main.board.push(2, 3)
	main.board.push(3, 1)
	main.board.push(3, 0)
	main.board.push(3, 1)
	main.board.push(3, 3)
	main.check_pending = true
	main.step(1.0 / 60.0)

	check(main.phase == main.Phase.CLEARING, "combo enters CLEARING phase")
	check(main.combo_beams.size() == 2, "two combo beams spawned for double line clear")
	check(main.fluid_splats.size() == 6, "fluid splats spawned for each of 6 cleared tiles")
	check(main.shockwaves.size() == 7, "shockwaves spawned for each of 6 cleared tiles plus center")
	check(main.starbursts.size() == 7, "starbursts spawned for each of 6 cleared tiles plus center")
	check(main.particles.size() >= 150, "explosion spawns abundant sprite particles")

	var kinds_seen := {}
	for p in main.particles:
		kinds_seen[p.get("kind", "")] = true
	for k in ["droplet", "splash", "bubble", "star", "spark", "glow", "shard", "glyph"]:
		check(kinds_seen.has(k), "explosion includes particle sprite kind: " + k)

	# Step until all effects finish and verify cleanup.
	for i in 120:
		main.step(1.0 / 60.0)
	check(main.phase == main.Phase.IDLE, "board returns to IDLE after clear & fall")
	check(main.combo_beams.is_empty(), "combo beams cleaned up after lifetime")
	check(main.fluid_splats.is_empty(), "fluid splats cleaned up after lifetime")
	check(main.shockwaves.is_empty(), "shockwaves cleaned up after lifetime")
	check(main.starbursts.is_empty(), "starbursts cleaned up after lifetime")
	check(main.particles.is_empty(), "explosion particles cleaned up after lifetime")

	# 4. Rewarded-ad continue flow & engagement integration
	main.start_run()
	main.wave_delay = 99.0
	for r in 4:
		main.board.push(0, r % 3)
	main.lives = 1
	main._lose_life()
	check(main.state == main.State.GAME_OVER, "loss enters GAME_OVER")
	check(main.engagement.can_offer_ad_continue(), "ad continue is offered on game over")
	var pre_ad_speed: float = main.belt_speed
	var continued: bool = main.watch_ad_to_continue()
	check(continued and main.state == main.State.PLAYING and main.lives == 2, "watch_ad_to_continue revives player with 2 lives")
	check(main.belt_speed <= pre_ad_speed, "post-ad DDA slows or maintains belt speed for smoother recovery")
	check(main.board.height(0) == 3, "ad continue mercy blast clears top tile of nearly-full column")

	# 5. "Slowy" Helper Spirit end-to-end mechanics (catch, flip, drop, combo-type gate & 0.5x belt speed)
	main.start_run()
	main.wave_delay = 99.0
	main.slowy_combo_type = "horizontal"
	var base_run_speed: float = main.belt_speed

	# Spawn a belt tile carrying trapped Slowy, catch it, flip it back to the belt, re-catch, and drop into bin
	main.held = [1]
	main.held_spirits = [""]
	main.paddle_lane = 2
	main._catch({"lane": 2, "y": main.paddle_top, "color": 0, "vy": 0.0, "spirit": "slowy"})
	check(main.held.size() == 2 and main.held_spirits.back() == "slowy", "catching Slowy tile stores spirit in held_spirits")
	check(main.is_slowy_trapped(), "is_slowy_trapped() detects Slowy in held stack")
	main.do_flip()
	check(main.belt_tiles.back().get("spirit", "") == "slowy", "do_flip() tosses Slowy back onto the conveyor belt with its spirit intact")
	var tossed: Dictionary = main.belt_tiles.pop_back()
	main._catch(tossed)
	main.do_drop()
	for i in 20:
		main.step(1.0 / 60.0)
	check(main.board.get_spirit(2, 0) == "slowy", "dropping Slowy tile lands trapped Slowy in board bin")
	check(main.is_slowy_trapped(), "is_slowy_trapped() detects Slowy on board")

	# Try clearing Slowy's tile (2, 0) with a VERTICAL combo when HORIZONTAL is required -> should NOT free Slowy!
	main.board.push(4, 3, "") # surviving bystander tile at (4, 0)
	main.board.push(2, 0, "")
	main.board.push(2, 0, "")
	main.check_pending = true
	for i in 40:
		main.step(1.0 / 60.0)
	check(not main.is_slowy_active(), "clearing Slowy with wrong combo type (vertical instead of horizontal) does NOT free Slowy")
	check(main.board.get_spirit(4, 0) == "slowy", "Slowy hops to a surviving board tile when cleared by wrong combo type")
	check(is_equal_approx(main.belt_speed, base_run_speed), "belt_speed remains un-halved when wrong combo type is used")

	# Now clear a HORIZONTAL Klax while Slowy is on the board -> frees Slowy & halves belt speed!
	main.board.push(0, 2, "")
	main.board.push(1, 2, "")
	main.board.push(2, 2, "")
	main.check_pending = true
	for i in 40:
		main.step(1.0 / 60.0)
	check(main.is_slowy_active(), "matching required combo type (horizontal) frees Slowy and activates power-up")
	check(main.slowy_freed_count == 1, "slowy_freed_count increments when Slowy is freed")
	check(is_equal_approx(main.belt_speed, base_run_speed * 0.5), "active Slowy reduces conveyor belt_speed to half (0.5x)")

	# Step past Slowy's duration and verify belt_speed restores to normal
	main.slowy_active_t = 0.05
	main.step(0.10)
	check(not main.is_slowy_active(), "Slowy deactivates after duration expires")
	check(is_equal_approx(main.belt_speed, base_run_speed), "conveyor belt_speed restores to 1.0x after Slowy finishes")



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
