extends Node2D
## Draws the whole game from the state held by main.gd (`g`). Pure rendering, no rules.

const S = preload("res://flax_style.gd")

var g
var _font: Font
var _fill := StyleBoxFlat.new()
var _line := StyleBoxFlat.new()
var _scroll := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_fill.anti_aliasing = true
	_line.anti_aliasing = true
	_line.draw_center = false


func _process(delta: float) -> void:
	if g != null:
		_scroll += (g.belt_speed if g.state == g.State.PLAYING else 50.0) * delta
	queue_redraw()


func _draw() -> void:
	if g == null:
		return
	_draw_belt()
	_draw_bins()
	_draw_board_tiles()
	_draw_belt_tiles()
	_draw_flights()
	_draw_paddle()
	_draw_debris()
	_draw_particles()
	if g.state != g.State.MENU:
		_draw_hud()
		_draw_buttons()
	_draw_popups()
	_draw_banner()
	if g.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, g.vp).grow(40.0), Color(S.DANGER, g.flash * 0.35))
	if g.state == g.State.MENU:
		_draw_menu()
	elif g.state == g.State.PAUSED:
		_draw_pause()
	elif g.state == g.State.GAME_OVER:
		_draw_game_over()
	_draw_sound_button()


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

func rr(rect: Rect2, color: Color, radius: float = 12.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_fill.bg_color = color
	_fill.set_corner_radius_all(int(radius))
	draw_style_box(_fill, rect)


func rr_line(rect: Rect2, color: Color, radius: float, width: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	_line.border_color = color
	_line.set_border_width_all(int(width))
	_line.set_corner_radius_all(int(radius))
	draw_style_box(_line, rect)


func ctext(text: String, cx: float, y: float, size: int, color: Color) -> void:
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, Vector2(cx - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func ltext(text: String, x: float, y: float, size: int, color: Color) -> void:
	draw_string(_font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func rtext(text: String, x: float, y: float, size: int, color: Color) -> void:
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, Vector2(x - w, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## One tile: darker "lip" underneath, flat face on top, and a faint shape glyph so the
## colors stay distinguishable without relying on hue alone.
func draw_tile(rect: Rect2, id: int, alpha: float = 1.0, glow: float = 0.0) -> void:
	var base: Color = S.tile_color(id)
	if glow > 0.0:
		base = base.lerp(Color.WHITE, glow)
	var dark: Color = base.darkened(0.3)
	base.a = alpha
	dark.a = alpha
	var lip: float = minf(6.0, rect.size.y * 0.12)
	var radius: float = minf(14.0, rect.size.y * 0.3)
	rr(rect, dark, radius)
	rr(Rect2(rect.position, Vector2(rect.size.x, rect.size.y - lip)), base, radius)
	if rect.size.y >= 40.0:
		var c := rect.position + Vector2(rect.size.x * 0.5, (rect.size.y - lip) * 0.5)
		_draw_glyph(c, id, minf(rect.size.x, rect.size.y) * 0.17, Color(1, 1, 1, 0.42 * alpha))


func _draw_glyph(c: Vector2, id: int, r: float, col: Color) -> void:
	match id % 5:
		0:
			draw_circle(c, r, col)
		1:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)]), col)
		2:
			draw_rect(Rect2(c - Vector2(r, r) * 0.9, Vector2(r, r) * 1.8), col)
		3:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 1.2), c + Vector2(r * 1.2, 0),
				c + Vector2(0, r * 1.2), c + Vector2(-r * 1.2, 0)]), col)
		4:
			draw_arc(c, r * 0.8, 0.0, TAU, 28, col, r * 0.5)


## Tile rect for a cell whose top edge is at `top` in `lane`, with the given height.
func tile_rect(lane: int, top: float, h: float) -> Rect2:
	return Rect2(g.lane_left(lane) + 5.0, top + 2.5, g.lane_w - 10.0, h - 5.0)


# ---------------------------------------------------------------------------
# Playfield
# ---------------------------------------------------------------------------

func _draw_belt() -> void:
	var top: float = g.conveyor_top - 6.0
	var bottom: float = g.paddle_top + g.paddle_h + 8.0
	rr(Rect2(g.board_left - 6.0, top, g.board_w + 12.0, bottom - top), S.PANEL, 24.0)
	var lane_h: float = bottom - 8.0 - g.conveyor_top
	for c in 5:
		if c % 2 == 0:
			draw_rect(Rect2(g.lane_left(c), g.conveyor_top, g.lane_w, lane_h), Color(1, 1, 1, 0.02))
	# Active lane guide.
	if g.state == g.State.PLAYING or g.state == g.State.PAUSED:
		draw_rect(Rect2(g.lane_left(g.paddle_lane), g.conveyor_top, g.lane_w, lane_h), Color(1, 1, 1, 0.045))
	# Scrolling dashes sell the conveyor motion.
	var spacing := 74.0
	var offset: float = fposmod(_scroll, spacing)
	var count: int = int(ceil(lane_h / spacing)) + 1
	for k in count:
		var y: float = g.conveyor_top + offset + float(k) * spacing - spacing
		if y < g.conveyor_top or y > g.conveyor_top + lane_h - 4.0:
			continue
		for c in 5:
			var cx: float = g.lane_center(c)
			draw_rect(Rect2(cx - 14.0, y, 28.0, 3.0), Color(1, 1, 1, 0.07))


func _draw_bins() -> void:
	var rows: float = g.Board.ROWS
	rr(Rect2(g.board_left - 6.0, g.bins_top - 8.0, g.board_w + 12.0, g.cell_h * rows + 16.0), S.PANEL, 24.0)
	for c in 5:
		var col_rect := Rect2(g.lane_left(c) + 3.0, g.bins_top, g.lane_w - 6.0, g.cell_h * rows)
		var tint := 0.035
		if (g.state == g.State.PLAYING or g.state == g.State.PAUSED) and c == g.paddle_lane:
			tint = 0.08
		rr(col_rect, Color(1, 1, 1, tint), 14.0)
		# Faint slot guides show how much room is left.
		for r in range(1, int(rows)):
			var y: float = g.bins_bottom - float(r) * g.cell_h
			draw_rect(Rect2(g.lane_left(c) + 14.0, y - 1.0, g.lane_w - 28.0, 2.0), Color(1, 1, 1, 0.035))
		var h: int = g.board.height(c)
		if h >= int(rows):
			var pulse: float = 0.55 + 0.45 * sin(g.time * 9.0)
			rr_line(col_rect.grow(-1.0), Color(S.DANGER, pulse), 14.0, 3.0)
		elif h == int(rows) - 1:
			var pulse2: float = 0.5 + 0.5 * sin(g.time * 6.0)
			rr(Rect2(col_rect.position, Vector2(col_rect.size.x, g.cell_h)), Color(S.WARN, 0.05 + 0.07 * pulse2), 14.0)


func _draw_board_tiles() -> void:
	var clearing := {}
	for cell in g.clearing_cells:
		clearing[cell] = true
	var ct: float = clampf(g.phase_t / g.CLEAR_TIME, 0.0, 1.0) if g.phase == g.Phase.CLEARING else 0.0
	for c in 5:
		for r in g.board.cols[c].size():
			var id: int = g.board.cols[c][r]
			var off: float = g.board.offs[c][r]
			var top: float = g.cell_top(float(r) + off)
			var rect := tile_rect(c, top, g.cell_h)
			if clearing.has(Vector2i(c, r)):
				# Pop: swell slightly, flash white, then shrink away.
				var s: float = 1.0 + 0.18 * sin(ct * PI) - 0.9 * pow(ct, 3.0)
				var center := rect.get_center()
				rect = Rect2(center - rect.size * s * 0.5, rect.size * s)
				draw_tile(rect, id, 1.0 - ct * 0.5, minf(1.0, ct * 2.2))
			else:
				draw_tile(rect, id)


func _draw_belt_tiles() -> void:
	for t in g.belt_tiles:
		var alpha: float = clampf((t.y - (g.conveyor_top - g.cell_h * 0.5)) / (g.cell_h * 0.6), 0.0, 1.0)
		draw_tile(tile_rect(t.lane, t.y, g.cell_h), t.color, alpha)


func _draw_flights() -> void:
	for i in g.flights.size():
		var f = g.flights[i]
		var row: int = g.flight_target_row(i)
		var target: float = g.cell_top(float(row))
		var k: float = clampf(f.t, 0.0, 1.0)
		var e: float = k * k
		var top: float = lerpf(f.from_y, target, e)
		var h: float = lerpf(g.HELD_H, g.cell_h, minf(1.0, k * 2.0))
		draw_tile(tile_rect(f.lane, top, h), f.color)


func _draw_paddle() -> void:
	var w: float = g.lane_w - 10.0
	var squash: float = 0.22 * g.paddle_bump
	var ph: float = g.paddle_h * (1.0 - squash)
	var py: float = g.paddle_top + (g.paddle_h - ph)
	var px: float = g.paddle_x - w * 0.5
	# Held stack (first caught at the bottom, next to drop on top).
	for i in g.held.size():
		var top: float = g.paddle_top - float(i + 1) * g.HELD_H
		draw_tile(Rect2(px, top + 1.5, w, g.HELD_H - 2.0), g.held[i])
	rr(Rect2(px, py, w, ph), S.TEXT, ph * 0.5)
	if g.held.size() >= g.MAX_HELD:
		ctext("FULL", g.paddle_x, g.paddle_top - float(g.MAX_HELD) * g.HELD_H - 12.0, 22, S.WARN)


func _draw_debris() -> void:
	for d in g.debris:
		draw_set_transform(d.pos, d.rot, Vector2.ONE)
		var w: float = g.lane_w - 10.0
		draw_tile(Rect2(-w * 0.5, -g.cell_h * 0.5, w, g.cell_h), d.color, 0.9)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_particles() -> void:
	for p in g.particles:
		var a: float = clampf(p.life / p.max, 0.0, 1.0)
		var s: float = p.size * a
		var col: Color = p.color
		col.a = a
		draw_rect(Rect2(p.pos - Vector2(s, s) * 0.5, Vector2(s, s)), col)


func _draw_popups() -> void:
	for p in g.popups:
		var a: float = clampf(p.life / 0.4, 0.0, 1.0)
		var pop: float = clampf((p.max - p.life) / 0.12, 0.0, 1.0)
		var col: Color = p.color
		col.a = a
		var size: int = int(float(p.size) * (0.7 + 0.3 * pop))
		# Soft shadow keeps text readable over tiles.
		ctext(p.text, p.pos.x + 2.0, p.pos.y + 2.0, size, Color(0, 0, 0, a * 0.5))
		ctext(p.text, p.pos.x, p.pos.y, size, col)


func _draw_banner() -> void:
	if g.banner_t <= 0.0 or g.state != g.State.PLAYING:
		return
	var a: float = clampf(g.banner_t / 0.5, 0.0, 1.0)
	var enter: float = clampf((1.7 - g.banner_t) / 0.25, 0.0, 1.0)
	var y: float = g.vp.y * 0.38 - (1.0 - enter) * 24.0
	ctext(g.banner_text, g.vp.x * 0.5, y, 84, Color(S.TEXT, a * enter))
	var sub := "clear %d tiles" % g.wave_goal
	ctext(sub, g.vp.x * 0.5, y + 48.0, 28, Color(S.DIM, a * enter))


# ---------------------------------------------------------------------------
# HUD and buttons
# ---------------------------------------------------------------------------

func _draw_hud() -> void:
	var cx: float = g.vp.x * 0.5
	ctext("SCORE", cx, 42.0, 20, S.DIM)
	ctext(str(g.score), cx, 104.0, 66, S.TEXT)

	var left: float = g.board_left
	var right: float = g.board_left + g.board_w
	ltext("WAVE %d" % g.wave, left, 154.0, 26, S.TEXT)
	ctext("%d / %d" % [mini(g.wave_progress, g.wave_goal), g.wave_goal], cx, 154.0, 22, S.DIM)
	# Lives.
	var slots: int = maxi(g.START_LIVES, g.lives)
	for i in slots:
		var c := Vector2(right - 12.0 - float(slots - 1 - i) * 28.0, 145.0)
		if i < g.lives:
			draw_circle(c, 10.0, S.DANGER)
		else:
			draw_arc(c, 9.0, 0.0, TAU, 24, Color(S.DIM, 0.6), 2.0)
	# Wave progress bar.
	var bar := Rect2(left, 168.0, g.board_w, 8.0)
	rr(bar, S.LINE, 4.0)
	var frac: float = clampf(float(g.wave_progress) / float(g.wave_goal), 0.0, 1.0)
	rr(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), S.GOOD, 4.0)

	# Pause glyph.
	var pr: Rect2 = g.buttons["pause"]
	var pc := pr.get_center()
	rr(Rect2(pc.x - 13.0, pc.y - 15.0, 8.0, 30.0), S.DIM, 3.0)
	rr(Rect2(pc.x + 5.0, pc.y - 15.0, 8.0, 30.0), S.DIM, 3.0)


func _draw_sound_button() -> void:
	var sr: Rect2 = g.buttons["sound"]
	var c := sr.get_center()
	var col: Color = S.DIM if g.sound_on else Color(S.DIM, 0.45)
	# Minimal speaker icon.
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-16, -6), c + Vector2(-8, -6), c + Vector2(2, -15),
		c + Vector2(2, 15), c + Vector2(-8, 6), c + Vector2(-16, 6)]), col)
	if g.sound_on:
		draw_arc(c + Vector2(2, 0), 9.0, -0.9, 0.9, 12, col, 3.0)
		draw_arc(c + Vector2(2, 0), 16.0, -0.9, 0.9, 12, col, 3.0)
	else:
		draw_line(c + Vector2(8, -8), c + Vector2(20, 8), S.DANGER, 3.0)
		draw_line(c + Vector2(20, -8), c + Vector2(8, 8), S.DANGER, 3.0)


func _draw_buttons() -> void:
	var specs := {
		"flip": ["FLIP", "swipe up"],
		"drop": ["DROP", "tap your lane"],
	}
	for key in specs:
		var r: Rect2 = g.buttons[key]
		var lit: float = g.button_flash[key]
		var fill: Color = S.PANEL_LIGHT.lerp(Color(0.38, 0.43, 0.62), lit)
		if key == "drop" and not g.held.is_empty():
			# Preview the color you're about to drop.
			rr(r, fill, 28.0)
			var tc: Color = S.tile_color(g.held.back())
			rr(Rect2(r.position.x + 18.0, r.position.y + 18.0, 10.0, r.size.y - 36.0), tc, 5.0)
		else:
			rr(r, fill, 28.0)
		ctext(specs[key][0], r.get_center().x, r.get_center().y + 4.0, 38, S.TEXT)
		ctext(specs[key][1], r.get_center().x, r.get_center().y + 36.0, 18, S.DIM)


# ---------------------------------------------------------------------------
# Overlays
# ---------------------------------------------------------------------------

func _button(rect: Rect2, label: String, primary: bool) -> void:
	if primary:
		rr(rect, S.TEXT, rect.size.y * 0.5)
		ctext(label, rect.get_center().x, rect.get_center().y + 13.0, 38, S.BG)
	else:
		rr(rect, S.PANEL_LIGHT, rect.size.y * 0.5)
		ctext(label, rect.get_center().x, rect.get_center().y + 11.0, 30, S.TEXT)


func _dim() -> void:
	draw_rect(Rect2(Vector2.ZERO, g.vp).grow(40.0), Color(S.BG, 0.82))


func _draw_menu() -> void:
	_dim()
	_dim()
	var cx: float = g.vp.x * 0.5
	# Title: each letter in its own tile color.
	var letters := "FLAX"
	var size := 168
	var total := 0.0
	var widths: Array = []
	for ch in letters:
		var w: float = _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 18.0
		widths.append(w)
		total += w
	var x: float = cx - total * 0.5
	var base_y: float = g.vp.y * 0.30
	for i in letters.length():
		var bob: float = sin(g.time * 2.4 + float(i) * 0.9) * 8.0
		var col: Color = S.tile_color(i)
		ltext(letters[i], x, base_y + bob, size, col)
		x += widths[i]
	ctext("catch  ·  stack  ·  match", cx, base_y + 56.0, 28, S.DIM)

	if g.best > 0:
		ctext("BEST  %d" % g.best, cx, g.vp.y * 0.46, 34, S.TEXT)

	var pulse: float = 1.0 + 0.03 * sin(g.time * 4.0)
	var a: Rect2 = g.buttons["ov_a"]
	var grown := Rect2(a.get_center() - a.size * pulse * 0.5, a.size * pulse)
	_button(grown, "TAP TO PLAY", true)

	var hy: float = g.vp.y * 0.56 + 260.0
	ctext("Catch tiles on the paddle and drop them in the bins.", cx, hy, 24, S.DIM)
	ctext("Line up 3 of a color: across, up, or diagonal.", cx, hy + 36.0, 24, S.DIM)
	ctext("Drag to move  ·  tap your lane to drop  ·  swipe up to flip", cx, hy + 84.0, 22, Color(S.DIM, 0.8))
	ctext("Keys: arrows / A D move, space drops, up flips", cx, hy + 116.0, 20, Color(S.DIM, 0.6))


func _draw_pause() -> void:
	_dim()
	var cx: float = g.vp.x * 0.5
	ctext("PAUSED", cx, g.vp.y * 0.38, 96, S.TEXT)
	_button(g.buttons["ov_a"], "RESUME", true)
	_button(g.buttons["ov_b"], "QUIT", false)


func _draw_game_over() -> void:
	_dim()
	var cx: float = g.vp.x * 0.5
	ctext("GAME OVER", cx, g.vp.y * 0.26, 88, S.TEXT)
	ctext("SCORE", cx, g.vp.y * 0.34, 22, S.DIM)
	ctext(str(g.score), cx, g.vp.y * 0.34 + 84.0, 96, S.TEXT)
	if g.new_best:
		var pulse: float = 0.75 + 0.25 * sin(g.time * 7.0)
		ctext("NEW BEST!", cx, g.vp.y * 0.34 + 140.0, 38, Color(S.WARN, pulse))
	else:
		ctext("BEST  %d" % g.best, cx, g.vp.y * 0.34 + 140.0, 32, S.DIM)
	ctext("reached wave %d" % g.wave, cx, g.vp.y * 0.34 + 184.0, 26, S.DIM)
	var ready: bool = g.game_over_t >= 0.7
	if ready:
		_button(g.buttons["ov_a"], "PLAY AGAIN", true)
		_button(g.buttons["ov_b"], "MENU", false)
