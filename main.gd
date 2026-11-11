extends Node2D
## FLAX - a minimalist, mobile-first 2.5D take on Klax.
##
## Tiles ride down a 5-lane conveyor. Move the paddle under a lane to catch them (it holds
## up to 5, last caught is dropped first). DROP a tile into the bin below, or FLIP it back
## up the conveyor. Line up 3+ of the same color across, up, or diagonally to clear them.
## Miss 3 tiles (or overfill a bin) and it's over — or watch a rewarded ad to continue!
##
## This script owns state, rules, engagement/DDA, and input. `view.gd` draws everything.

const Board = preload("res://board.gd")
const Engagement = preload("res://engagement.gd")
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
const BELT_TOP_SCALE := 0.36      # 2.5D horizon scale (36% size far away -> 100% at paddle)
const SLOWY_DURATION := 10.0      # seconds "Slowy" halves the conveyor belt speed
const SAVE_PATH := "user://flax.cfg"
const LINE_POINTS := {3: 100, 4: 300, 5: 800}

# --- run state -------------------------------------------------------------
var state: int = State.MENU
var phase: int = Phase.IDLE
var phase_t := 0.0
var check_pending := false
var clearing_cells: Array = []

var board = Board.new()
var engagement = Engagement.new()
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
var held_spirits: Array = []      # parallel to `held`: "" or "slowy"
var slowy_combo_type := "horizontal" # "horizontal", "vertical", or "diagonal"
var slowy_active_t := 0.0         # > 0 while Slowy is actively halving belt speed
var slowy_freed_count := 0

var belt_tiles: Array = []   # {lane, y, vy, toss, color}
var flights: Array = []      # {lane, color, t, from_y}
var debris: Array = []       # {pos, vel, rot, vrot, color}
var particles: Array = []    # {pos, vel, life, max, color, color_alt, size, kind, glyph, rot, vrot, gravity, drag}
var fluid_splats: Array = [] # {pos, radius, life, max, color, color_alt, rot, aspect}
var shockwaves: Array = []   # {pos, r0, r1, life, max, color, width}
var combo_beams: Array = []  # {a, b, life, max, color}
var starbursts: Array = []   # {pos, life, max, color, size, rot}
var popups: Array = []       # {text, pos, life, max, color, size}

var belt_speed := 150.0
var belt_scroll := 0.0
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
	buttons["ov_ad"] = Rect2(vp.x * 0.5 - 210.0, vp.y * 0.56 - 116.0, 420.0, 96.0)
	buttons["ov_a"] = Rect2(vp.x * 0.5 - 210.0, vp.y * 0.56, 420.0, 100.0)
	buttons["ov_b"] = Rect2(vp.x * 0.5 - 210.0, vp.y * 0.56 + 124.0, 420.0, 84.0)


func lane_left(lane: int) -> float:
	return board_left + lane_w * float(lane)


func lane_center(lane: int) -> float:
	return board_left + lane_w * (float(lane) + 0.5)


## Top y of the bin cell at (fractional) row index; row 0 is the bottom.
func cell_top(row: float) -> float:
	return bins_bottom - (row + 1.0) * cell_h


## Normalized depth (0 at horizon `conveyor_top`, 1 at paddle lip `paddle_top`).
func belt_depth(y: float) -> float:
	var span := maxf(1.0, paddle_top - conveyor_top)
	return clampf((y - conveyor_top) / span, -0.15, 1.15)


## Perspective scale factor at a given `y` along the conveyor ramp.
func belt_scale(y: float) -> float:
	return lerpf(BELT_TOP_SCALE, 1.0, clampf(belt_depth(y), 0.0, 1.0))


## Left X of `lane` (0..5, where 5 is the right edge of lane 4) at `y` on the 2.5D ramp.
func belt_lane_x(lane: float, y: float) -> float:
	var s := belt_scale(y)
	var w := board_w * s
	var left := vp.x * 0.5 - w * 0.5
	return left + (w / float(Board.COLS)) * lane


## Center X of `lane` at `y` on the 2.5D conveyor ramp.
func belt_lane_center(lane: int, y: float) -> float:
	return belt_lane_x(float(lane) + 0.5, y)


## Width of a single lane at `y` on the 2.5D conveyor ramp.
func belt_lane_w(y: float) -> float:
	return (board_w * belt_scale(y)) / float(Board.COLS)


## Logical belt step for one Rutsche space so that under `belt_project_y`, a space at the
## horizon (`s = BELT_TOP_SCALE`) has screen height `BELT_TOP_SCALE * cell_h` and grows
## to `1.0 * cell_h` right at the paddle (matching the drop boxes 1-to-1).
func belt_slot_h() -> float:
	var s0 := BELT_TOP_SCALE
	var span := maxf(1.0, paddle_top - conveyor_top)
	var f_prev := 1.0 - (cell_h / span)
	var s_prev := s0 + (1.0 - s0) * f_prev
	var u_step := log(s_prev) / log(s0)
	return u_step * span


## Projects a logical belt Y coordinate (`conveyor_top`..`paddle_top`) onto the 2.5D
## perspective ramp using exact exponential foreshortening so that `sy1 - sy0` is
## strictly proportional to `belt_scale(sy)` at every depth along the Rutsche!
func belt_project_y(y_logical: float) -> float:
	var span := maxf(1.0, paddle_top - conveyor_top)
	var u := (y_logical - conveyor_top) / span
	var s0 := BELT_TOP_SCALE
	var f := (pow(s0, 1.0 - u) - s0) / (1.0 - s0)
	return conveyor_top + f * span


## Snaps a logical belt Y coordinate to the nearest scrolling Rutsche space boundary.
func snap_to_belt_slot(y_logical: float, lane: int = -1) -> float:
	var sh := belt_slot_h()
	var phase_off := fposmod(belt_scroll, sh)
	var k := roundf((y_logical - conveyor_top - phase_off) / sh)
	var snapped := conveyor_top + phase_off + k * sh
	if lane >= 0:
		for other in belt_tiles:
			if not other.get("toss", false) and int(other.lane) == lane and absf(float(other.y) - snapped) < sh * 0.45:
				snapped -= sh
	return snapped


func _wave_progress_ratio() -> float:
	return clampf(float(wave_progress) / float(maxi(1, wave_goal)), 0.0, 1.0)


func _board_fill_ratio() -> float:
	return clampf(float(board.total_tiles()) / float(Board.COLS * Board.ROWS), 0.0, 1.0)


func is_slowy_active() -> bool:
	return slowy_active_t > 0.0


## Returns true if a trapped "Slowy" helper spirit is currently anywhere in play
## (riding the Rutsche, held on the paddle, in flight, or sitting in a bin).
func is_slowy_trapped() -> bool:
	if board.find_spirit("slowy") != Vector2i(-1, -1):
		return true
	for t in belt_tiles:
		if t.get("spirit", "") == "slowy":
			return true
	for sp in held_spirits:
		if sp == "slowy":
			return true
	for f in flights:
		if f.get("spirit", "") == "slowy":
			return true
	return false


func _sync_held_spirits() -> void:
	while held_spirits.size() < held.size():
		held_spirits.append("")
	while held_spirits.size() > held.size():
		held_spirits.pop_back()


func _sync_belt_speed() -> void:
	belt_speed = engagement.get_belt_speed(wave, is_slowy_active())
	spawn_interval = engagement.get_spawn_interval(wave, is_slowy_active())


## Frees the "Slowy" helper spirit, halving conveyor belt speed for SLOWY_DURATION seconds!
func activate_slowy(origin_pos: Vector2 = Vector2.ZERO) -> void:
	slowy_active_t = SLOWY_DURATION
	slowy_freed_count += 1
	engagement.on_slowy_freed(wave, lives)
	_sync_belt_speed()
	sfx.play("slowy")
	var fx_pos := origin_pos if origin_pos != Vector2.ZERO else Vector2(vp.x * 0.5, bins_top)
	_explode_tile(fx_pos, S.GOOD, 1.25, 1)
	_add_popup("SLOWY FREED! 1/2 SPEED!", Vector2(vp.x * 0.5, conveyor_top + 96.0), S.GOOD, 42)


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
			p.vel.y += float(p.get("gravity", 900.0)) * dt
			p.vel *= exp(-float(p.get("drag", 1.2)) * dt)
			p.pos += p.vel * dt
			p.rot = float(p.get("rot", 0.0)) + float(p.get("vrot", 0.0)) * dt
		i -= 1

	i = fluid_splats.size() - 1
	while i >= 0:
		var fs = fluid_splats[i]
		fs.life -= dt
		if fs.life <= 0.0:
			fluid_splats.remove_at(i)
		i -= 1

	i = shockwaves.size() - 1
	while i >= 0:
		var sw = shockwaves[i]
		sw.life -= dt
		if sw.life <= 0.0:
			shockwaves.remove_at(i)
		i -= 1

	i = combo_beams.size() - 1
	while i >= 0:
		var cb = combo_beams[i]
		cb.life -= dt
		if cb.life <= 0.0:
			combo_beams.remove_at(i)
		i -= 1

	i = starbursts.size() - 1
	while i >= 0:
		var sb = starbursts[i]
		sb.life -= dt
		if sb.life <= 0.0:
			starbursts.remove_at(i)
		else:
			sb.rot += 2.6 * dt
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
	if slowy_active_t > 0.0:
		slowy_active_t = maxf(0.0, slowy_active_t - dt)
		if slowy_active_t <= 0.0:
			_sync_belt_speed()
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
# Conveyor & Engagement-Assisted Spawning
# ---------------------------------------------------------------------------

func _pick_color() -> int:
	var n: int = mini(3 + int(floor((wave - 1) / 2.0)), 5)
	var help_prob: float = engagement.get_helpful_color_probability(
		wave, lives, _wave_progress_ratio(), _board_fill_ratio()
	)
	if randf() < help_prob:
		var pool: Array = []
		for c in Board.COLS:
			var h: int = board.height(c)
			if h > 0 and board.cols[c][h - 1] < n:
				var top_c: int = board.cols[c][h - 1]
				pool.append(top_c)
				# Extra weight if column already has 2 stacked or is near overflow!
				if (h >= 2 and board.cols[c][h - 2] == top_c) or h >= Board.ROWS - 1:
					pool.append(top_c)
					pool.append(top_c)
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
	var sh := belt_slot_h()
	var phase_off := fposmod(belt_scroll, sh)
	var spawn_y := snap_to_belt_slot(conveyor_top + phase_off - sh, lane)
	var busy := is_slowy_trapped() or is_slowy_active()
	var slowy_prob: float = engagement.get_slowy_spawn_probability(wave, lives, _board_fill_ratio(), busy)
	var spirit := ""
	if randf() < slowy_prob:
		spirit = "slowy"
		slowy_combo_type = engagement.pick_slowy_combo_type(wave, lives, _board_fill_ratio())
		engagement.on_tile_spawned(true)
	else:
		engagement.on_tile_spawned(false)
	belt_tiles.append({
		"lane": lane,
		"y": spawn_y,
		"vy": belt_speed,
		"toss": false,
		"snapped": true,
		"color": _pick_color(),
		"spirit": spirit,
	})


func _update_belt(dt: float) -> void:
	var sh := belt_slot_h()
	belt_scroll += belt_speed * dt
	var i := belt_tiles.size() - 1
	while i >= 0:
		var t = belt_tiles[i]
		if t.toss:
			t.vy += TOSS_DECEL * dt
			if t.vy >= belt_speed:
				t.vy = belt_speed
				t.toss = false
				t.y = snap_to_belt_slot(t.y, int(t.lane))
				t["snapped"] = true
			t.y += t.vy * dt
		else:
			if not t.get("snapped", false) and t.y + sh < paddle_top:
				t.y = snap_to_belt_slot(t.y, int(t.lane))
				t["snapped"] = true
			t.vy = belt_speed
			t.y += belt_speed * dt
		if t.vy > 0.0:
			var threshold := paddle_top
			if t.lane == paddle_lane:
				threshold -= float(held.size()) * HELD_H
			if t.y + sh >= threshold:
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
	_sync_held_spirits()
	held.append(t.color)
	var sp: String = t.get("spirit", "")
	held_spirits.append(sp)
	paddle_bump = 1.0
	sfx.play("catch", 0.85 + 0.08 * float(held.size()))
	_burst(Vector2(lane_center(t.lane), paddle_top - float(held.size()) * HELD_H), S.tile_color(t.color), 7, 180.0, t.color)


func _miss(t, bounce: bool) -> void:
	if t.get("spirit", "") == "slowy":
		engagement.slowy_trapped_in_play = false
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
	engagement.on_life_lost(wave, lives, _wave_progress_ratio(), _board_fill_ratio())
	# Apply dynamic intra-wave relief so the player has a better chance of surviving the wave.
	_sync_belt_speed()
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
	_sync_held_spirits()
	var color: int = held.pop_back()
	var sp: String = held_spirits.pop_back()
	var lane := paddle_lane
	var top := paddle_top - float(held.size() + 1) * HELD_H
	if _effective_height(lane) >= Board.ROWS:
		# Bin is full: the tile bounces off and costs a life.
		if sp == "slowy":
			engagement.slowy_trapped_in_play = false
		_spawn_debris(Vector2(lane_center(lane), top + HELD_H * 0.5),
				Vector2(260.0 * (1.0 if randf() < 0.5 else -1.0), -420.0), color)
		_add_popup("BIN FULL", Vector2(lane_center(lane), top - 30.0), S.DANGER, 36)
		_lose_life()
		return
	flights.append({"lane": lane, "color": color, "spirit": sp, "t": 0.0, "from_y": top})
	sfx.play("flip", 0.7)


## Tosses the top held tile back up the conveyor.
func do_flip() -> void:
	if state != State.PLAYING or held.is_empty():
		return
	_sync_held_spirits()
	var color: int = held.pop_back()
	var sp: String = held_spirits.pop_back()
	var top := paddle_top - float(held.size() + 1) * HELD_H
	belt_tiles.append({
		"lane": paddle_lane,
		"y": top + HELD_H - belt_slot_h(),
		"vy": TOSS_SPEED,
		"toss": true,
		"color": color,
		"spirit": sp,
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
			board.push(lane, f.color, f.get("spirit", ""))
			flights.remove_at(i)
			check_pending = true
			score += 5
			paddle_bump = 0.0
			shake = maxf(shake, 3.0)
			sfx.play("drop", 0.9 + 0.05 * float(row))
			_burst(Vector2(lane_center(lane), cell_top(float(row)) + cell_h), S.tile_color(f.color), 6, 135.0, f.color)
			engagement.update_kpi(wave, lives, _wave_progress_ratio(), _board_fill_ratio(), score, best)
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
	var matched_slowy_combo := false
	for ln in lines:
		var base: int = LINE_POINTS.get(ln.length, 800)
		if ln.diagonal:
			base *= 2
			diagonal = true
		if ln.get("kind", "") == slowy_combo_type:
			matched_slowy_combo = true
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
	engagement.on_combo_cleared(chain)

	# Check if trapped "Slowy" helper spirit is freed by this Klax combo!
	var slowy_cell: Vector2i = board.find_spirit("slowy")
	if slowy_cell != Vector2i(-1, -1):
		var slowy_pos := Vector2(lane_center(slowy_cell.x), cell_top(float(slowy_cell.y)) + cell_h * 0.5)
		if matched_slowy_combo:
			board.set_spirit(slowy_cell.x, slowy_cell.y, "")
			activate_slowy(slowy_pos)
		elif cells.has(slowy_cell):
			# Slowy's tile was cleared, but NOT with the required Klax combo type!
			# Transfer Slowy to a surviving tile on the board (if any) and remind the player.
			board.set_spirit(slowy_cell.x, slowy_cell.y, "")
			var moved := false
			for c_idx in Board.COLS:
				for r_idx in board.cols[c_idx].size():
					var cand := Vector2i(c_idx, r_idx)
					if not cells.has(cand):
						board.set_spirit(c_idx, r_idx, "slowy")
						moved = true
						break
				if moved:
					break
			if not moved:
				engagement.slowy_trapped_in_play = false
			_add_popup("NEED %s KLAX!" % slowy_combo_type.to_upper(), slowy_pos + Vector2(0, -36), S.WARN, 34)

	engagement.update_kpi(wave, lives, _wave_progress_ratio(), _board_fill_ratio(), score, best)

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
		var cid: int = board.get_cell(cell.x, cell.y)
		_explode_tile(pos, S.tile_color(cid), 1.0 + 0.22 * float(mini(chain, 4)), cid)
	center /= float(clearing_cells.size())

	# Spawn glowing energy beams along each matched line and a central shockwave.
	for ln in lines:
		if ln.cells.size() >= 2:
			var c0: Vector2i = ln.cells[0]
			var c1: Vector2i = ln.cells[ln.cells.size() - 1]
			var p0 := Vector2(lane_center(c0.x), cell_top(float(c0.y)) + cell_h * 0.5)
			var p1 := Vector2(lane_center(c1.x), cell_top(float(c1.y)) + cell_h * 0.5)
			combo_beams.append({
				"a": p0,
				"b": p1,
				"life": 0.42,
				"max": 0.42,
				"color": S.tile_color(ln.color),
			})
	shockwaves.append({
		"pos": center,
		"r0": 18.0,
		"r1": 185.0 + 36.0 * float(mini(lines.size() + chain, 5)),
		"life": 0.48,
		"max": 0.48,
		"color": S.WARN if chain >= 2 else S.STICKER,
		"width": 9.0,
	})
	starbursts.append({
		"pos": center,
		"life": 0.38,
		"max": 0.38,
		"color": S.WARN if chain >= 2 else Color.WHITE,
		"size": 120.0 + 22.0 * float(mini(chain, 4)),
		"rot": randf() * TAU,
	})

	center.y = maxf(center.y, conveyor_top + 120.0)
	_add_popup(label, center + Vector2(0, -20), S.STICKER, 46)
	_add_popup("+%d" % total, center + Vector2(0, 34), S.WARN, 40)
	if chain >= 2:
		_add_popup("CHAIN x%d" % chain, center + Vector2(0, 86), S.GOOD, 36)
	sfx.play("clear", 0.96 + 0.05 * float(mini(chain - 1, 5)))
	sfx.play("boom", 0.95 + 0.04 * float(mini(chain - 1, 5)))
	shake = maxf(shake, 6.0 + 3.0 * float(mini(chain, 5)))
	Input.vibrate_handheld(45)


func _complete_wave() -> void:
	var bonus := 250 * wave + maxi(0, Board.COLS * Board.ROWS - board.total_tiles()) * 10
	score += bonus
	var mid := Vector2(vp.x * 0.5, vp.y * 0.34)
	_add_popup("WAVE CLEAR  +%d" % bonus, mid, S.GOOD, 44)
	for i in 3:
		var cid := (wave + i) % 5
		var fx_pos := Vector2(board_left + board_w * (0.2 + 0.3 * float(i)), bins_top - 40.0)
		_explode_tile(fx_pos, S.tile_color(cid), 0.95, cid)
	wave += 1
	if (wave - 1) % 3 == 0 and lives < MAX_LIVES:
		lives += 1
		_add_popup("+1 LIFE", mid + Vector2(0, 56), S.DANGER, 40)
	# Increase difficulty after every completed wave via the engagement controller.
	engagement.on_wave_completed(wave, lives, MAX_LIVES)
	sfx.play("wave")
	_setup_wave()


func _setup_wave() -> void:
	wave_progress = 0
	wave_goal = 12 + 3 * (wave - 1)
	_sync_belt_speed()
	wave_delay = 1.4
	spawn_timer = 0.0
	banner_text = "WAVE %d" % wave
	banner_t = 1.7
	engagement.update_kpi(wave, lives, _wave_progress_ratio(), _board_fill_ratio(), score, best)


# ---------------------------------------------------------------------------
# Fluid & Multi-Sprite Effects
# ---------------------------------------------------------------------------

func _burst(pos: Vector2, color: Color, count: int, speed: float, glyph_id: int = 0) -> void:
	var kinds := ["droplet", "splash", "bubble", "spark", "star", "glow"]
	var alt_col: Color = S.fluid_alt_color(glyph_id)
	for i in count:
		var ang := randf() * TAU
		var spd := randf_range(0.35, 1.0) * speed
		var life := randf_range(0.35, 0.68)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd + Vector2(0, -75),
			"life": life,
			"max": life,
			"color": color.lightened(randf_range(0.0, 0.22)),
			"color_alt": alt_col,
			"size": randf_range(12.0, 22.0),
			"kind": kinds[i % kinds.size()],
			"glyph": glyph_id,
			"rot": randf() * TAU,
			"vrot": randf_range(-7.0, 7.0),
			"gravity": 720.0,
			"drag": 1.5,
		})


## Full fluid + chromatic sprite explosion when a tile is cleared in a Flax combination.
func _explode_tile(pos: Vector2, color: Color, power: float = 1.0, glyph_id: int = 0) -> void:
	var alt_col: Color = S.fluid_alt_color(glyph_id)
	# Organic liquid splash puddle behind the exploding tile.
	fluid_splats.append({
		"pos": pos,
		"radius": 68.0 * power,
		"life": 0.52,
		"max": 0.52,
		"color": color,
		"color_alt": alt_col,
		"rot": randf() * TAU,
		"aspect": randf_range(0.85, 1.18),
	})
	# Local shockwave ring.
	shockwaves.append({
		"pos": pos,
		"r0": 10.0,
		"r1": 112.0 * power,
		"life": 0.38,
		"max": 0.38,
		"color": color.lerp(alt_col, 0.45).lightened(0.28),
		"width": 7.5,
	})
	# Core starburst flash sprite.
	starbursts.append({
		"pos": pos,
		"life": 0.34,
		"max": 0.34,
		"color": color.lightened(0.45),
		"size": 106.0 * power,
		"rot": randf() * TAU,
	})
	# Fluid droplets, liquid splashes, chromatic bubbles, starbursts, sparks, glows, shards & glyphs.
	var total_p := int(28.0 * power)
	for i in total_p:
		var ang := (float(i) / float(total_p)) * TAU + randf_range(-0.22, 0.22)
		var kind := "droplet"
		var spd := randf_range(170.0, 540.0) * power
		var sz := randf_range(16.0, 30.0)
		var grav := 780.0
		var drag := 1.8
		var pcol := color
		var life := randf_range(0.44, 0.90)
		var r := i % 8
		if r == 0:
			kind = "droplet"
			spd = randf_range(180.0, 520.0) * power
			sz = randf_range(20.0, 36.0)
			grav = 860.0
			drag = 1.4
			pcol = color.lightened(0.12)
		elif r == 1:
			kind = "splash"
			spd = randf_range(110.0, 360.0) * power
			sz = randf_range(26.0, 44.0)
			grav = 480.0
			drag = 2.4
			pcol = color.lerp(alt_col, 0.35)
		elif r == 2:
			kind = "bubble"
			spd = randf_range(90.0, 310.0) * power
			sz = randf_range(18.0, 34.0)
			grav = -180.0
			drag = 2.2
			pcol = alt_col.lightened(0.22)
		elif r == 3:
			kind = "star"
			spd = randf_range(150.0, 450.0) * power
			sz = randf_range(22.0, 36.0)
			pcol = color.lightened(0.42)
		elif r == 4:
			kind = "shard"
			spd = randf_range(190.0, 480.0) * power
			sz = randf_range(16.0, 28.0)
			grav = 1280.0
			drag = 0.6
			pcol = color.lightened(randf_range(-0.08, 0.22))
		elif r == 5:
			kind = "glow"
			spd = randf_range(65.0, 250.0) * power
			sz = randf_range(34.0, 56.0)
			grav = -110.0
			drag = 2.8
			pcol = color.lerp(alt_col, 0.5).lightened(0.25)
		elif r == 6:
			kind = "glyph"
			spd = randf_range(140.0, 380.0) * power
			sz = randf_range(14.0, 22.0)
			grav = 680.0
			drag = 1.4
			pcol = Color.WHITE.lerp(color, 0.35)
		else:
			kind = "spark"
			pcol = color.lerp(Color.WHITE, randf_range(0.25, 0.7))
		particles.append({
			"pos": pos + Vector2(randf_range(-12.0, 12.0), randf_range(-9.0, 9.0)),
			"vel": Vector2(cos(ang), sin(ang)) * spd + Vector2(0, -120.0),
			"life": life,
			"max": life,
			"color": pcol,
			"color_alt": alt_col,
			"size": sz,
			"kind": kind,
			"glyph": glyph_id,
			"rot": randf() * TAU,
			"vrot": randf_range(-11.0, 11.0),
			"gravity": grav,
			"drag": drag,
		})


func _add_popup(text: String, pos: Vector2, color: Color, size: int) -> void:
	popups.append({"text": text, "pos": pos, "life": 1.1, "max": 1.1, "color": color, "size": size})


# ---------------------------------------------------------------------------
# Game flow & Rewarded-Ad Continue
# ---------------------------------------------------------------------------

func start_run() -> void:
	board.reset()
	score = 0
	wave = 1
	lives = START_LIVES
	chain = 0
	new_best = false
	held = []
	held_spirits = []
	slowy_active_t = 0.0
	slowy_freed_count = 0
	slowy_combo_type = "horizontal"
	belt_tiles = []
	flights = []
	debris = []
	particles = []
	fluid_splats = []
	shockwaves = []
	combo_beams = []
	starbursts = []
	popups = []
	clearing_cells = []
	phase = Phase.IDLE
	phase_t = 0.0
	check_pending = false
	paddle_lane = 2
	touches.clear()
	engagement.reset_for_new_run()
	_setup_wave()
	state = State.PLAYING
	sfx.play("ui")


## Simulates watching a rewarded ad to continue the current wave with +2 lives,
## softer DDA speed/cadence, and a board-clearing mercy blast on full columns.
func watch_ad_to_continue() -> bool:
	if state != State.GAME_OVER or not engagement.can_offer_ad_continue():
		return false
	lives = 2
	engagement.on_ad_watched(wave, lives, _wave_progress_ratio())
	_sync_belt_speed()
	belt_tiles.clear()
	flights.clear()
	wave_delay = 1.1
	spawn_timer = 0.0

	# Mercy blast: pop the top tile of any column with >= 4 tiles so the player has breathing room.
	var rescued: Array = []
	for c in Board.COLS:
		var h: int = board.height(c)
		if h >= Board.ROWS - 1:
			var r := h - 1
			var cid: int = board.get_cell(c, r)
			var pos := Vector2(lane_center(c), cell_top(float(r)) + cell_h * 0.5)
			_explode_tile(pos, S.tile_color(cid), 0.9, cid)
			rescued.append(Vector2i(c, r))
	if not rescued.is_empty():
		board.remove_cells(rescued)
		check_pending = true

	_add_popup("AD CONTINUE  +2 LIVES!", Vector2(vp.x * 0.5, vp.y * 0.36), S.GOOD, 42)
	state = State.PLAYING
	touches.clear()
	sfx.play("wave")
	return true


func _end_game() -> void:
	state = State.GAME_OVER
	game_over_t = 0.0
	touches.clear()
	engagement.on_wave_failed(wave, _wave_progress_ratio(), _board_fill_ratio(), score, best)
	if engagement.can_offer_ad_continue():
		engagement.ad_offers_shown += 1
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
			if engagement.can_offer_ad_continue() and buttons["ov_ad"].has_point(pos):
				watch_ad_to_continue()
			elif buttons["ov_b"].has_point(pos):
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
			if code == KEY_C and engagement.can_offer_ad_continue():
				watch_ad_to_continue()
			elif code == KEY_SPACE or code == KEY_ENTER or code == KEY_KP_ENTER:
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
