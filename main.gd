extends Node2D
## FLAX - a minimalist, mobile-first take on Klax.
##
## Tiles ride down a 5-lane conveyor. Move the paddle under a lane to catch them (it holds
## up to 5, last caught is dropped first). DROP a tile into the bin below, or FLIP it back
## up the conveyor. Line up 3+ of the same color across, up, or diagonally to clear them.
## Miss 3 tiles (or overfill a bin) and it's over.
##
## This script owns state, rules and input. `view.gd` draws everything from this state.

const Board = preload("res://board.gd")
const Sfx = preload("res://sfx.gd")
const View = preload("res://view.gd")
const S = preload("res://flax_style.gd")

enum State { MENU, PLAYING, PAUSED, GAME_OVER }
enum Phase { IDLE, CLEARING, FALLING }

const MAX_HELD := 5
const START_LIVES := 3
const MAX_LIVES := 5
const HELD_H := 24.0              # height of a tile squashed on the paddle
const CLEAR_TIME := 0.32
const FLIGHT_TIME := 0.13
const TOSS_SPEED := -900.0        # initial upward speed of a flipped tile
const TOSS_DECEL := 1500.0
const SAVE_PATH := "user://flax.cfg"
const LINE_POINTS := {3: 100, 4: 300, 5: 800}

# --- run state -------------------------------------------------------------
var state: int = State.MENU
var phase: int = Phase.IDLE
var phase_t := 0.0
var check_pending := false
var clearing_cells: Array = []

var board = Board.new()
var score := 0
var best := 0
var new_best := false
var wave := 1
var wave_progress := 0
var wave_goal := 12
var lives := START_LIVES
var chain := 0

var paddle_lane := 2
var paddle_x := 0.0
var paddle_bump := 0.0
var held: Array = []

var belt_tiles: Array = []   # {lane, y, vy, toss, color}
var flights: Array = []      # {lane, color, t, from_y}
var debris: Array = []       # {pos, vel, rot, vrot, color}
var particles: Array = []    # {pos, vel, life, max, color, size}
var popups: Array = []       # {text, pos, life, max, color, size}

var belt_speed := 150.0
var spawn_interval := 1.7
var spawn_timer := 0.0
var wave_delay := 0.0
var last_spawn_lane := -1
var banner_text := ""
var banner_t := 0.0
var shake := 0.0
var flash := 0.0
var time := 0.0
var game_over_t := 0.0
var sound_on := true
var save_enabled := true   # tests turn this off so they never touch the real save
var button_flash := {"flip": 0.0, "drop": 0.0}
var touches := {}

# --- layout (recomputed whenever the window changes) -------------------------
var vp := Vector2(720, 1280)
var board_left := 24.0
var board_w := 672.0
var lane_w := 134.4
var cell_h := 67.0
var conveyor_top := 194.0
var paddle_top := 700.0
var paddle_h := 26.0
var bins_top := 760.0
var bins_bottom := 1095.0
var buttons := {}

var view
var sfx


func _ready() -> void:
	RenderingServer.set_default_clear_color(S.BG)
	randomize()
	sfx = Sfx.new()
	add_child(sfx)
	view = View.new()
	view.g = self
	add_child(view)
	_load_save()
	get_tree().root.size_changed.connect(_compute_layout)
	_compute_layout()
	paddle_x = lane_center(paddle_lane)


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------

func _compute_layout() -> void:
	vp = get_viewport_rect().size
	board_w = minf(vp.x - 40.0, 760.0)
	board_left = (vp.x - board_w) * 0.5
	lane_w = board_w / float(Board.COLS)
	cell_h = clampf(lane_w * 0.5, 44.0, 72.0)

	var button_h := 112.0
	var buttons_top := vp.y - 28.0 - button_h
	bins_bottom = buttons_top - 24.0
	bins_top = bins_bottom - cell_h * float(Board.ROWS)
	paddle_top = bins_top - 30.0 - paddle_h
	conveyor_top = 194.0

	var half := (board_w - 16.0) * 0.5
	buttons["flip"] = Rect2(board_left, buttons_top, half, button_h)
	buttons["drop"] = Rect2(board_left + half + 16.0, buttons_top, half, button_h)
	buttons["pause"] = Rect2(board_left - 8.0, 14.0, 84.0, 84.0)
	buttons["sound"] = Rect2(board_left + board_w - 76.0, 14.0, 84.0, 84.0)
	buttons["ov_a"] = Rect2(vp.x * 0.5 - 210.0, vp.y * 0.56, 420.0, 100.0)
	buttons["ov_b"] = Rect2(vp.x * 0.5 - 210.0, vp.y * 0.56 + 124.0, 420.0, 84.0)


func lane_left(lane: int) -> float:
	return board_left + lane_w * float(lane)


func lane_center(lane: int) -> float:
	return board_left + lane_w * (float(lane) + 0.5)


## Top y of the bin cell at (fractional) row index; row 0 is the bottom.
func cell_top(row: float) -> float:
	return bins_bottom - (row + 1.0) * cell_h


# ---------------------------------------------------------------------------
# Frame loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	step(delta)


## Advances the whole game by `delta` seconds. Public so headless tests can drive it.
func step(delta: float) -> void:
	time += delta
	_update_effects(delta)
	paddle_x = lerpf(paddle_x, lane_center(paddle_lane), 1.0 - exp(-30.0 * delta))
	paddle_bump = maxf(0.0, paddle_bump - 5.0 * delta)
	for key in button_flash.keys():
		button_flash[key] = maxf(0.0, button_flash[key] - 4.0 * delta)
	if banner_t > 0.0:
		banner_t -= delta
	if state == State.PLAYING:
		_update_game(delta)
	elif state == State.GAME_OVER:
		game_over_t += delta


func _update_effects(dt: float) -> void:
	shake *= exp(-9.0 * dt)
	flash = maxf(0.0, flash - 2.2 * dt)
	if view != null:
		view.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake

	var i := particles.size() - 1
	while i >= 0:
		var p = particles[i]
		p.life -= dt
		if p.life <= 0.0:
			particles.remove_at(i)
		else:
			p.vel.y += 900.0 * dt
			p.pos += p.vel * dt
		i -= 1

	i = popups.size() - 1
	while i >= 0:
		var p = popups[i]
		p.life -= dt
		if p.life <= 0.0:
			popups.remove_at(i)
		else:
			p.pos.y -= 55.0 * dt
		i -= 1

	i = debris.size() - 1
	while i >= 0:
		var d = debris[i]
		d.vel.y += 2400.0 * dt
		d.pos += d.vel * dt
		d.rot += d.vrot * dt
		if d.pos.y > vp.y + 200.0:
			debris.remove_at(i)
		i -= 1

	# Board tiles that just fell ease back to their slot.
	var moving := false
	for c in Board.COLS:
		var o: Array = board.offs[c]
		for r in o.size():
			if o[r] > 0.0:
				o[r] = maxf(0.0, o[r] - (7.0 + 9.0 * o[r]) * dt)
				if o[r] > 0.0:
					moving = true
	if phase == Phase.FALLING and not moving:
		phase = Phase.IDLE
		check_pending = true


func _update_game(dt: float) -> void:
	if wave_delay > 0.0:
		wave_delay -= dt
	else:
		spawn_timer -= dt
		if spawn_timer <= 0.0:
			_spawn_tile()
			spawn_timer = spawn_interval
	_update_belt(dt)
	if state != State.PLAYING:
		return
	_update_flights(dt)
	_update_resolution(dt)


# ---------------------------------------------------------------------------
# Conveyor
# ---------------------------------------------------------------------------

func _pick_color() -> int:
	var n: int = mini(3 + int(floor((wave - 1) / 2.0)), 5)
	# Gently favor colors you can actually use, so streaks feel achievable.
	if randf() < 0.35:
		var pool: Array = []
		for c in Board.COLS:
			var h: int = board.height(c)
			if h > 0 and board.cols[c][h - 1] < n:
				pool.append(board.cols[c][h - 1])
		for id in held:
			if id < n:
				pool.append(id)
		if not pool.is_empty():
			return pool.pick_random()
	return randi() % n


func _spawn_tile() -> void:
	var lane := randi() % Board.COLS
	if lane == last_spawn_lane and randf() < 0.5:
		lane = (lane + 1 + randi() % (Board.COLS - 1)) % Board.COLS
	last_spawn_lane = lane
	belt_tiles.append({
		"lane": lane,
		"y": conveyor_top - cell_h * 0.5,
		"vy": belt_speed,
		"toss": false,
		"color": _pick_color(),
	})


func _update_belt(dt: float) -> void:
	var i := belt_tiles.size() - 1
	while i >= 0:
		var t = belt_tiles[i]
		if t.toss:
			t.vy += TOSS_DECEL * dt
			if t.vy >= belt_speed:
				t.vy = belt_speed
				t.toss = false
		else:
			t.vy = belt_speed
		t.y += t.vy * dt
		if t.vy > 0.0:
			var threshold := paddle_top
			if t.lane == paddle_lane:
				threshold -= float(held.size()) * HELD_H
			if t.y + cell_h >= threshold:
				belt_tiles.remove_at(i)
				if t.lane == paddle_lane and held.size() < MAX_HELD:
					_catch(t)
				else:
					# Fell off the end, or the paddle is full and the tile bounced away.
					_miss(t, t.lane == paddle_lane)
					if state != State.PLAYING:
						return
		i -= 1


func _catch(t) -> void:
	held.append(t.color)
	paddle_bump = 1.0
	sfx.play("catch", 0.85 + 0.08 * float(held.size()))
	_burst(Vector2(lane_center(t.lane), paddle_top - float(held.size()) * HELD_H), S.tile_color(t.color), 6, 170.0)


func _miss(t, bounce: bool) -> void:
	var pos := Vector2(lane_center(t.lane), t.y + cell_h * 0.5)
	var vel := Vector2(0.0, 140.0)
	if bounce:
		vel = Vector2(240.0 * (1.0 if randf() < 0.5 else -1.0), -460.0)
	_spawn_debris(pos, vel, t.color)
	_add_popup("MISS", Vector2(pos.x, paddle_top - 70.0), S.DANGER, 40)
	_lose_life()


func _spawn_debris(pos: Vector2, vel: Vector2, color: int) -> void:
	debris.append({
		"pos": pos,
		"vel": vel,
		"rot": 0.0,
		"vrot": randf_range(-5.0, 5.0),
		"color": color,
	})


func _lose_life() -> void:
	lives -= 1
	flash = 0.55
	shake = maxf(shake, 14.0)
	sfx.play("miss")
	Input.vibrate_handheld(70)
	if lives <= 0:
		_end_game()


# ---------------------------------------------------------------------------
# Player actions
# ---------------------------------------------------------------------------

func set_lane(lane: int) -> void:
	lane = clampi(lane, 0, Board.COLS - 1)
	if lane != paddle_lane:
		paddle_lane = lane
		sfx.play("tick", 1.0 + 0.05 * float(lane))


func move_lane(dir: int) -> void:
	set_lane(paddle_lane + dir)


func set_lane_from_x(x: float) -> void:
	set_lane(int(floorf((x - board_left) / lane_w)))


## Throws the top held tile into the bin below the paddle.
func do_drop() -> void:
	if state != State.PLAYING or held.is_empty():
		return
	var color: int = held.pop_back()
	var lane := paddle_lane
	var top := paddle_top - float(held.size() + 1) * HELD_H
	if _effective_height(lane) >= Board.ROWS:
		# Bin is full: the tile bounces off and costs a life.
		_spawn_debris(Vector2(lane_center(lane), top + HELD_H * 0.5),
				Vector2(260.0 * (1.0 if randf() < 0.5 else -1.0), -420.0), color)
		_add_popup("BIN FULL", Vector2(lane_center(lane), top - 30.0), S.DANGER, 36)
		_lose_life()
		return
	flights.append({"lane": lane, "color": color, "t": 0.0, "from_y": top})
	sfx.play("flip", 0.7)


## Tosses the top held tile back up the conveyor.
func do_flip() -> void:
	if state != State.PLAYING or held.is_empty():
		return
	var color: int = held.pop_back()
	var top := paddle_top - float(held.size() + 1) * HELD_H
	belt_tiles.append({
		"lane": paddle_lane,
		"y": top + HELD_H - cell_h,
		"vy": TOSS_SPEED,
		"toss": true,
		"color": color,
	})
	sfx.play("flip", 1.3)


## Bin height as the player perceives it: tiles being cleared don't count, tiles in
## flight do.
func _effective_height(lane: int) -> int:
	var h: int = board.height(lane)
	for cell in clearing_cells:
		if cell.x == lane:
			h -= 1
	for f in flights:
		if f.lane == lane:
			h += 1
	return h


## Row a flight will land on (counts earlier flights into the same column).
func flight_target_row(index: int) -> int:
	var lane: int = flights[index].lane
	var row: int = board.height(lane)
	for j in index:
		if flights[j].lane == lane:
			row += 1
	return row


func _update_flights(dt: float) -> void:
	var i := 0
	while i < flights.size():
		var f = flights[i]
		f.t += dt / FLIGHT_TIME
		if f.t >= 1.0:
			var lane: int = f.lane
			var row: int = board.height(lane)
			board.push(lane, f.color)
			flights.remove_at(i)
			check_pending = true
			score += 5
			paddle_bump = 0.0
			shake = maxf(shake, 3.0)
			sfx.play("drop", 0.9 + 0.05 * float(row))
			_burst(Vector2(lane_center(lane), cell_top(float(row)) + cell_h), S.tile_color(f.color), 5, 120.0)
		else:
			i += 1


# ---------------------------------------------------------------------------
# Matching / clearing
# ---------------------------------------------------------------------------

func _update_resolution(dt: float) -> void:
	match phase:
		Phase.IDLE:
			if check_pending:
				check_pending = false
				var lines: Array = board.find_lines()
				if lines.is_empty():
					chain = 0
				else:
					_begin_clear(lines)
		Phase.CLEARING:
			phase_t += dt
			if phase_t >= CLEAR_TIME:
				board.remove_cells(clearing_cells)
				clearing_cells = []
				phase = Phase.FALLING
				phase_t = 0.0
				if wave_progress >= wave_goal:
					_complete_wave()
		Phase.FALLING:
			pass


func _begin_clear(lines: Array) -> void:
	var cells := {}
	var points := 0
	var diagonal := false
	var longest := 0
	for ln in lines:
		var base: int = LINE_POINTS.get(ln.length, 800)
		if ln.diagonal:
			base *= 2
			diagonal = true
		points += base
		longest = maxi(longest, ln.length)
		for cell in ln.cells:
			cells[cell] = true
	clearing_cells = cells.keys()
	chain += 1
	var total := points * chain
	score += total
	wave_progress += clearing_cells.size()
	phase = Phase.CLEARING
	phase_t = 0.0

	var label := "KLAX!"
	if lines.size() >= 3:
		label = "MEGA KLAX!"
	elif lines.size() == 2:
		label = "DOUBLE KLAX!"
	elif longest >= 5:
		label = "FIVE-WAY KLAX!"
	elif longest == 4:
		label = "SUPER KLAX!"
	elif diagonal:
		label = "DIAGONAL KLAX!"

	var center := Vector2.ZERO
	for cell in clearing_cells:
		var pos := Vector2(lane_center(cell.x), cell_top(float(cell.y)) + cell_h * 0.5)
		center += pos
		_burst(pos, S.tile_color(board.get_cell(cell.x, cell.y)), 9, 330.0)
	center /= float(clearing_cells.size())
	center.y = maxf(center.y, conveyor_top + 120.0)
	_add_popup(label, center + Vector2(0, -20), S.TEXT, 46)
	_add_popup("+%d" % total, center + Vector2(0, 34), S.WARN, 40)
	if chain >= 2:
		_add_popup("CHAIN x%d" % chain, center + Vector2(0, 86), S.GOOD, 36)
	sfx.play("clear", 1.0 + 0.1 * float(mini(chain - 1, 6)))
	shake = maxf(shake, 6.0 + 3.0 * float(mini(chain, 5)))
	Input.vibrate_handheld(35)


func _complete_wave() -> void:
	var bonus := 250 * wave + maxi(0, Board.COLS * Board.ROWS - board.total_tiles()) * 10
	score += bonus
	var mid := Vector2(vp.x * 0.5, vp.y * 0.34)
	_add_popup("WAVE CLEAR  +%d" % bonus, mid, S.GOOD, 44)
	wave += 1
	if (wave - 1) % 3 == 0 and lives < MAX_LIVES:
		lives += 1
		_add_popup("+1 LIFE", mid + Vector2(0, 56), S.DANGER, 40)
	sfx.play("wave")
	_setup_wave()


func _setup_wave() -> void:
	wave_progress = 0
	wave_goal = 12 + 3 * (wave - 1)
	belt_speed = minf(150.0 + 18.0 * float(wave - 1), 400.0)
	spawn_interval = maxf(1.7 - 0.09 * float(wave - 1), 0.6)
	wave_delay = 1.4
	spawn_timer = 0.0
	banner_text = "WAVE %d" % wave
	banner_t = 1.7


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------

func _burst(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		var ang := randf() * TAU
		var spd := randf_range(0.3, 1.0) * speed
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd + Vector2(0, -80),
			"life": randf_range(0.35, 0.7),
			"max": 0.7,
			"color": color,
			"size": randf_range(5.0, 11.0),
		})


func _add_popup(text: String, pos: Vector2, color: Color, size: int) -> void:
	popups.append({"text": text, "pos": pos, "life": 1.1, "max": 1.1, "color": color, "size": size})


# ---------------------------------------------------------------------------
# Game flow
# ---------------------------------------------------------------------------

func start_run() -> void:
	board.reset()
	score = 0
	wave = 1
	lives = START_LIVES
	chain = 0
	new_best = false
	held = []
	belt_tiles = []
	flights = []
	debris = []
	particles = []
	popups = []
	clearing_cells = []
	phase = Phase.IDLE
	phase_t = 0.0
	check_pending = false
	paddle_lane = 2
	touches.clear()
	_setup_wave()
	state = State.PLAYING
	sfx.play("ui")


func _end_game() -> void:
	state = State.GAME_OVER
	game_over_t = 0.0
	touches.clear()
	if score > best:
		best = score
		new_best = true
		_save()
	sfx.play("over")


func pause_game() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		touches.clear()
		sfx.play("ui", 0.8)


func resume_game() -> void:
	if state == State.PAUSED:
		state = State.PLAYING
		touches.clear()
		sfx.play("ui")


func to_menu() -> void:
	state = State.MENU
	touches.clear()
	sfx.play("ui", 0.8)


func toggle_sound() -> void:
	sound_on = not sound_on
	sfx.enabled = sound_on
	sfx.play("ui")
	_save()


func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best = int(cf.get_value("game", "best", 0))
		sound_on = bool(cf.get_value("game", "sound", true))
	sfx.enabled = sound_on


func _save() -> void:
	if not save_enabled:
		return
	var cf := ConfigFile.new()
	cf.set_value("game", "best", best)
	cf.set_value("game", "sound", sound_on)
	cf.save(SAVE_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		pause_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		match state:
			State.PLAYING:
				pause_game()
			State.PAUSED:
				resume_game()
			State.GAME_OVER:
				to_menu()
			State.MENU:
				get_tree().quit()


# ---------------------------------------------------------------------------
# Input: touch (and mouse, emulated as touch) + keyboard
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_move(event.index, event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event.keycode)


func _touch_down(index: int, pos: Vector2) -> void:
	if buttons["sound"].has_point(pos):
		toggle_sound()
		return
	match state:
		State.MENU:
			start_run()
		State.PAUSED:
			if buttons["ov_b"].has_point(pos):
				to_menu()
			else:
				resume_game()
		State.GAME_OVER:
			if game_over_t < 0.7:
				return
			if buttons["ov_b"].has_point(pos):
				to_menu()
			else:
				start_run()
		State.PLAYING:
			if buttons["pause"].has_point(pos):
				pause_game()
			elif buttons["flip"].has_point(pos):
				button_flash["flip"] = 1.0
				touches[index] = {"kind": "button"}
				do_flip()
			elif buttons["drop"].has_point(pos):
				button_flash["drop"] = 1.0
				touches[index] = {"kind": "button"}
				do_drop()
			else:
				# Tap another lane to move there, tap your own lane to drop,
				# drag to slide the paddle, swipe up to flip.
				touches[index] = {
					"kind": "play",
					"start": pos,
					"ms": Time.get_ticks_msec(),
					"lane": paddle_lane,
					"moved": false,
					"flipped": false,
				}
				set_lane_from_x(pos.x)


func _touch_move(index: int, pos: Vector2) -> void:
	if state != State.PLAYING or not touches.has(index):
		return
	var t = touches[index]
	if t.kind != "play":
		return
	set_lane_from_x(pos.x)
	if pos.distance_to(t.start) > 28.0:
		t.moved = true
	var age := float(Time.get_ticks_msec() - t.ms) / 1000.0
	if not t.flipped and t.start.y - pos.y > 110.0 and absf(pos.x - t.start.x) < 90.0 and age < 0.6:
		t.flipped = true
		do_flip()


func _touch_up(index: int) -> void:
	if not touches.has(index):
		return
	var t = touches[index]
	touches.erase(index)
	if state != State.PLAYING or t.kind != "play":
		return
	var age := float(Time.get_ticks_msec() - t.ms) / 1000.0
	if not t.moved and not t.flipped and age < 0.3 and t.lane == paddle_lane:
		do_drop()


func _key(code: int) -> void:
	match state:
		State.MENU:
			if code == KEY_SPACE or code == KEY_ENTER or code == KEY_KP_ENTER:
				start_run()
		State.PAUSED:
			if code == KEY_ESCAPE or code == KEY_P or code == KEY_SPACE:
				resume_game()
			elif code == KEY_Q:
				to_menu()
		State.GAME_OVER:
			if game_over_t < 0.7:
				return
			if code == KEY_SPACE or code == KEY_ENTER or code == KEY_KP_ENTER:
				start_run()
			elif code == KEY_ESCAPE:
				to_menu()
		State.PLAYING:
			match code:
				KEY_LEFT, KEY_A:
					move_lane(-1)
				KEY_RIGHT, KEY_D:
					move_lane(1)
				KEY_SPACE, KEY_DOWN, KEY_S:
					button_flash["drop"] = 1.0
					do_drop()
				KEY_UP, KEY_W:
					button_flash["flip"] = 1.0
					do_flip()
				KEY_ESCAPE, KEY_P:
					pause_game()
