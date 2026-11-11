extends Node2D
## Draws the whole game from the state held by main.gd (`g`). Pure rendering, no rules.
## Styled as a colorful, childish Paper Mario storybook craft diorama with die-cut sticker
## borders, bold cartoon ink outlines, stitched paper hills, and vibrant paint-splash combos.

const S = preload("res://flax_style.gd")

var g
var _font: Font
var _fill := StyleBoxFlat.new()
var _line := StyleBoxFlat.new()
var _scroll := 0.0

# Procedural fluid & explosion sprites generated at startup.
var _tex_droplet: ImageTexture
var _tex_splash: ImageTexture
var _tex_bubble: ImageTexture
var _tex_star: ImageTexture
var _tex_spark: ImageTexture
var _tex_glow: ImageTexture
var _tex_shard: ImageTexture


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_fill.anti_aliasing = true
	_line.anti_aliasing = true
	_line.draw_center = false
	_build_sprites()


func _process(delta: float) -> void:
	if g != null:
		_scroll += (g.belt_speed if g.state == g.State.PLAYING else 50.0) * delta
	queue_redraw()


# ---------------------------------------------------------------------------
# Procedural Fluid Paint & Paper-Star Sprite Generator
# ---------------------------------------------------------------------------

func _build_sprites() -> void:
	# 1. Glossy paint droplet sprite with cartoon ink rim (48x48)
	var sz := 48
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var mid := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var nx := (float(x) - mid) / mid
			var ny := (float(y) - mid) / mid
			var tx := nx * 0.92
			var ty := ny * (1.08 + 0.22 * nx)
			var d := sqrt(tx * tx + ty * ty)
			if d < 1.0:
				var body := clampf((1.0 - d) / 0.16, 0.0, 1.0)
				var hx := nx + 0.28
				var hy := ny + 0.28
				var spec := clampf(1.0 - sqrt(hx * hx + hy * hy) * 2.5, 0.0, 1.0)
				var r_ch := clampf(0.88 + spec * 0.45, 0.0, 1.0)
				var g_ch := clampf(0.90 + spec * 0.45, 0.0, 1.0)
				var b_ch := clampf(0.94 + spec * 0.45, 0.0, 1.0)
				img.set_pixel(x, y, Color(r_ch, g_ch, b_ch, body))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
	_tex_droplet = ImageTexture.create_from_image(img)

	# 2. Multi-lobe Color-Splash paint splat sprite (64x64)
	sz = 64
	img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	mid = float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var nx := (float(x) - mid) / mid
			var ny := (float(y) - mid) / mid
			var r := sqrt(nx * nx + ny * ny)
			var ang := atan2(ny, nx)
			var bound := 0.64 + 0.17 * sin(ang * 5.0 + 0.4) + 0.10 * cos(ang * 3.0 - 0.7) + 0.06 * sin(ang * 8.0)
			if r < bound:
				var edge := clampf((bound - r) / 0.12, 0.0, 1.0)
				var norm_r := r / maxf(0.01, bound)
				var ridge := exp(-pow((norm_r - 0.78) / 0.14, 2.0)) * 0.35
				var c_val := clampf(0.86 + ridge, 0.0, 1.0)
				img.set_pixel(x, y, Color(c_val, clampf(c_val + 0.04, 0.0, 1.0), 1.0, edge * 0.96))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
	_tex_splash = ImageTexture.create_from_image(img)

	# 3. Iridescent soap/paint bubble sprite (48x48)
	sz = 48
	img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	mid = float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var nx := (float(x) - mid) / mid
			var ny := (float(y) - mid) / mid
			var d := sqrt(nx * nx + ny * ny)
			if d < 0.96:
				var rim := exp(-pow((d - 0.78) / 0.13, 2.0))
				var fill_a := 0.22 * (1.0 - d * d)
				var sp1 := clampf(1.0 - sqrt(pow(nx + 0.36, 2.0) + pow(ny + 0.36, 2.0)) * 3.8, 0.0, 1.0)
				var sp2 := clampf(1.0 - sqrt(pow(nx - 0.32, 2.0) + pow(ny - 0.32, 2.0)) * 5.2, 0.0, 1.0) * 0.65
				var a := clampf(rim * 0.94 + fill_a + sp1 + sp2, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.95, 0.96, 1.0, a))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
	_tex_bubble = ImageTexture.create_from_image(img)

	# 4. Paper-cutout starburst sprite (64x64)
	sz = 64
	img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	mid = float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := absf(float(x) - mid) / mid
			var dy := absf(float(y) - mid) / mid
			var dist := sqrt(dx * dx + dy * dy)
			var cross := maxf(
				clampf(1.0 - dy * 4.0, 0.0, 1.0) * clampf(1.0 - dx, 0.0, 1.0),
				clampf(1.0 - dx * 4.0, 0.0, 1.0) * clampf(1.0 - dy, 0.0, 1.0)
			)
			var diag := maxf(
				clampf(1.0 - absf(dx - dy) * 4.6, 0.0, 1.0) * clampf(1.0 - dist * 1.2, 0.0, 1.0) * 0.65,
				0.0
			)
			var core := clampf(1.0 - dist * 1.7, 0.0, 1.0)
			var a := clampf(maxf(cross, diag) + core * core * 0.95, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.98, 1.0, a * a))
	_tex_star = ImageTexture.create_from_image(img)

	# 5. Elongated diamond confetti spark sprite (48x48)
	sz = 48
	img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	mid = float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := absf(float(x) - mid) / mid
			var dy := absf(float(y) - mid) / mid
			var d := dx * 1.85 + dy * 0.95
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, pow(a, 1.4)))
	_tex_spark = ImageTexture.create_from_image(img)

	# 6. Soft radial glow sprite (48x48)
	sz = 48
	img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	mid = float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := (float(x) - mid) / mid
			var dy := (float(y) - mid) / mid
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a * (3.0 - 2.0 * a)))
	_tex_glow = ImageTexture.create_from_image(img)

	# 7. Paper confetti shard sprite (32x32)
	sz = 32
	img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var u := float(x) / float(sz - 1)
			var v := float(y) / float(sz - 1)
			if u + v * 0.25 > 0.18 and u * 0.9 + v < 1.12 and u > 0.08 and v > 0.12 and u < 0.92 and v < 0.88:
				var shade := 0.96 if (v < 0.35 or u < 0.3) else 0.84
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
	_tex_shard = ImageTexture.create_from_image(img)


func _draw() -> void:
	if g == null:
		return
	_draw_space_backdrop()
	_draw_belt()
	_draw_bins()
	_draw_fluid_splats()
	_draw_board_tiles()
	_draw_belt_tiles()
	_draw_flights()
	_draw_paddle()
	_draw_combo_beams()
	_draw_shockwaves()
	_draw_starbursts()
	_draw_debris()
	_draw_particles()
	if g.state != g.State.MENU:
		_draw_hud()
		_draw_buttons()
	_draw_popups()
	_draw_banner()
	if g.flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, g.vp).grow(40.0), Color(S.DANGER, g.flash * 0.28))
	if g.state == g.State.MENU:
		_draw_menu()
	elif g.state == g.State.PAUSED:
		_draw_pause()
	elif g.state == g.State.GAME_OVER:
		_draw_game_over()
	_draw_sound_button()


# ---------------------------------------------------------------------------
# Paper Mario Cutout & Sticker Primitives
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


## Draws a layered Paper Mario die-cut sticker card: offset paper shadow, crisp white
## sticker border, bold dark cartoon ink outline, and construction-paper fill.
func paper_card(rect: Rect2, fill_col: Color, radius: float = 16.0, shadow_off: Vector2 = Vector2(0, 6), sticker_w: float = 3.5, ink_w: float = 2.5) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if shadow_off != Vector2.ZERO:
		rr(Rect2(rect.position + shadow_off, rect.size), S.SHADOW, radius + 2.0)
	if sticker_w > 0.0:
		rr(rect.grow(sticker_w + ink_w), S.STICKER, radius + sticker_w + ink_w)
	if ink_w > 0.0:
		rr(rect.grow(ink_w), S.INK, radius + ink_w)
	rr(rect, fill_col, radius)


## Draws cartoon outlined text (Paper Mario style). Dark ink text gets a crisp white
## sticker halo; light/colored text gets a bold dark cartoon ink outline + drop shadow.
func _outlined_text(text: String, pos: Vector2, size: int, color: Color) -> void:
	var a: float = color.a
	var is_dark: bool = color.get_luminance() < 0.38
	var out_col: Color = S.STICKER if is_dark else S.INK
	out_col.a = a * 0.95
	var o: float = clampf(float(size) * 0.065, 2.0, 4.5)
	if not is_dark:
		draw_string(_font, pos + Vector2(0, o + 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(S.INK, a * 0.45))
	var offsets := [
		Vector2(-o, 0), Vector2(o, 0), Vector2(0, -o), Vector2(0, o),
		Vector2(-o * 0.75, -o * 0.75), Vector2(o * 0.75, -o * 0.75),
		Vector2(-o * 0.75, o * 0.75), Vector2(o * 0.75, o * 0.75),
	]
	for d in offsets:
		draw_string(_font, pos + d, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, out_col)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func ctext(text: String, cx: float, y: float, size: int, color: Color) -> void:
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_outlined_text(text, Vector2(cx - w * 0.5, y), size, color)


func ltext(text: String, x: float, y: float, size: int, color: Color) -> void:
	_outlined_text(text, Vector2(x, y), size, color)


func rtext(text: String, x: float, y: float, size: int, color: Color) -> void:
	var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_outlined_text(text, Vector2(x - w, y), size, color)


## Draws the cute Paper Mario helper spirit "Slowy" (an aqua-mint clock/snail spirit).
## When `trapped` is true, Slowy is inside a shimmering bubble-cage; when false, Slowy cheers!
func _draw_slowy_spirit(c: Vector2, r: float, trapped: bool, alpha: float = 1.0) -> void:
	var bob: float = sin(g.time * (4.0 if trapped else 7.0)) * (r * 0.10)
	var pos := c + Vector2(0.0, bob)
	var aqua := Color("5ef2d6")
	var shell_col := Color("2eb5ff")
	var ink_col := S.INK
	var stick_col := S.STICKER
	aqua.a = alpha
	shell_col.a = alpha
	ink_col.a = alpha
	stick_col.a = alpha * 0.96

	# 1. Cute pastel-blue snail/clock shell tucked behind Slowy's back
	var sh_c := pos + Vector2(r * 0.38, r * 0.08)
	draw_circle(sh_c, r * 0.72 + 2.5, stick_col)
	draw_circle(sh_c, r * 0.72 + 1.2, ink_col)
	draw_circle(sh_c, r * 0.72, shell_col)
	draw_arc(sh_c, r * 0.38, 0.0, PI * 1.5, 16, ink_col, maxf(1.2, r * 0.14))

	# 2. Round squishy spirit body with white sticker border & dark cartoon ink outline
	draw_circle(pos, r + 3.0, stick_col)
	draw_circle(pos, r + 1.5, ink_col)
	draw_circle(pos, r, aqua)
	draw_circle(pos + Vector2(-r * 0.28, -r * 0.32), r * 0.28, Color(1, 1, 1, 0.65 * alpha))

	# 3. Expressive cartoon eyes & rosy cheeks
	var eye_dx: float = r * 0.34
	var eye_r: float = maxf(1.5, r * 0.17)
	draw_circle(pos + Vector2(-eye_dx * 1.35, r * 0.15), eye_r * 1.15, Color(1.0, 0.48, 0.58, 0.65 * alpha))
	draw_circle(pos + Vector2(eye_dx * 1.35, r * 0.15), eye_r * 1.15, Color(1.0, 0.48, 0.58, 0.65 * alpha))
	draw_circle(pos + Vector2(-eye_dx, -r * 0.06), eye_r, ink_col)
	draw_circle(pos + Vector2(eye_dx, -r * 0.06), eye_r, ink_col)
	draw_circle(pos + Vector2(-eye_dx - 0.5, -r * 0.10), eye_r * 0.42, stick_col)
	draw_circle(pos + Vector2(eye_dx - 0.5, -r * 0.10), eye_r * 0.42, stick_col)

	# 4. Trapped bubble-cage OR happy cheering hands
	if trapped:
		var bub_r: float = r * 1.28
		draw_circle(pos, bub_r, Color(0.88, 0.98, 1.0, 0.34 * alpha))
		# Cage bars across the bubble
		draw_line(pos + Vector2(-bub_r * 0.42, -bub_r * 0.88), pos + Vector2(-bub_r * 0.42, bub_r * 0.88), Color(S.INK, 0.55 * alpha), maxf(1.4, r * 0.14))
		draw_line(pos + Vector2(bub_r * 0.42, -bub_r * 0.88), pos + Vector2(bub_r * 0.42, bub_r * 0.88), Color(S.INK, 0.55 * alpha), maxf(1.4, r * 0.14))
		draw_arc(pos, bub_r, 0.0, TAU, 28, Color(S.WARN, 0.92 * alpha), maxf(1.8, r * 0.18))
		draw_arc(pos, bub_r + 1.6, 0.0, TAU, 28, Color(S.INK, 0.75 * alpha), 1.4)
	else:
		# Happy raised hands waving!
		var wave_y: float = -r * 0.35 + sin(g.time * 9.0) * (r * 0.18)
		for side in [-1.0, 1.0]:
			var hc := pos + Vector2(side * r * 1.12, wave_y)
			draw_circle(hc, r * 0.28 + 1.5, ink_col)
			draw_circle(hc, r * 0.28, aqua)


## Draws a cute Paper Mario die-cut sticker tile with white sticker trim, bold dark ink
## outline, 3D cardboard bottom lip, shape emblem, and friendly little cartoon eyes!
func draw_tile(rect: Rect2, id: int, alpha: float = 1.0, glow: float = 0.0, scale_hint: float = 1.0, spirit: String = "") -> void:
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return
	var base: Color = S.tile_color(id)
	var alt: Color = S.fluid_alt_color(id)
	if glow > 0.0:
		base = base.lerp(Color.WHITE, glow)
	var dark: Color = base.darkened(0.28)
	var rim: Color = base.lerp(alt, 0.25).lightened(0.32)
	var ink_col: Color = S.INK
	var sticker_col: Color = S.WARN if spirit == "slowy" else S.STICKER
	base.a = alpha
	dark.a = alpha
	rim.a = alpha * 0.85
	ink_col.a = alpha
	sticker_col.a = alpha * 0.96

	var s: float = clampf(scale_hint, 0.45, 1.2)
	var radius: float = minf(13.0 * s, rect.size.y * 0.30)
	var ink_w: float = maxf(1.5, 2.4 * s)
	var stick_w: float = maxf(1.2, (3.6 if spirit == "slowy" else 2.2) * s)
	var lip: float = minf(7.5 * s, rect.size.y * 0.18)

	# 1. Soft paper drop shadow
	rr(Rect2(rect.position + Vector2(0, 3.5 * s), rect.size), Color(S.SHADOW.r, S.SHADOW.g, S.SHADOW.b, S.SHADOW.a * alpha), radius + 2.0)
	# 2. White (or golden spirit) die-cut sticker rim
	rr(rect.grow(ink_w + stick_w), sticker_col, radius + ink_w + stick_w)
	# 3. Bold cartoon ink outline
	rr(rect.grow(ink_w), ink_col, radius + ink_w)
	# 4. 3D cardboard bottom lip & main bright paper face
	rr(rect, dark, radius)
	var face := Rect2(rect.position, Vector2(rect.size.x, maxf(2.0, rect.size.y - lip)))
	rr(face, base, radius)

	# 5. Glossy paper highlight bar along top edge
	if face.size.y >= 10.0 * s:
		var hl_pad: float = 6.0 * s
		rr(Rect2(face.position.x + hl_pad, face.position.y + 2.5 * s, maxf(2.0, face.size.x - hl_pad * 2.0), minf(4.5 * s, face.size.y * 0.17)), rim, 3.0 * s)

	# 6. Center shape sticker emblem (or trapped Slowy helper spirit!)
	if rect.size.y >= 22.0:
		var c: Vector2 = face.position + face.size * 0.5
		if spirit == "slowy":
			var sr: float = minf(face.size.x, face.size.y) * 0.28
			_draw_slowy_spirit(c, sr, true, alpha)
		else:
			var gr: float = minf(face.size.x, face.size.y) * 0.22
			_draw_glyph(c, id, gr + 1.8 * s, Color(S.INK.r, S.INK.g, S.INK.b, 0.32 * alpha))
			_draw_glyph(c, id, gr, Color(1, 1, 1, 0.88 * alpha))
			var eye_dx: float = minf(face.size.x * 0.30, gr * 1.95)
			var eye_r: float = maxf(1.4, 2.3 * s)
			var cheek_col := Color(1.0, 0.45, 0.55, 0.45 * alpha)
			draw_circle(c + Vector2(-eye_dx - 2.5 * s, 2.5 * s), eye_r * 1.2, cheek_col)
			draw_circle(c + Vector2(eye_dx + 2.5 * s, 2.5 * s), eye_r * 1.2, cheek_col)
			draw_circle(c + Vector2(-eye_dx, -1.0 * s), eye_r, ink_col)
			draw_circle(c + Vector2(eye_dx, -1.0 * s), eye_r, ink_col)
			draw_circle(c + Vector2(-eye_dx - 0.5 * s, -1.8 * s), eye_r * 0.4, sticker_col)
			draw_circle(c + Vector2(eye_dx - 0.5 * s, -1.8 * s), eye_r * 0.4, sticker_col)


## Returns the 4 screen-space corners [tl, tr, br, bl] of a dedicated space on the
## 2.5D Rutsche (conveyor ramp) for `lane` and logical interval `[y_log_top, y_log_bot]`.
## Both `_draw_belt()` (the empty Rutsche pockets) and `draw_belt_tile_3d()` (the tiles
## flowing down) call this exact function so every tile maps 100% into its Rutsche space!
func rutsche_space_quad(lane: int, y_log_top: float, y_log_bot: float, expand_px: float = 0.0) -> PackedVector2Array:
	var sy0_raw: float = g.belt_project_y(y_log_top)
	var sy1_raw: float = g.belt_project_y(y_log_bot)
	var s0_raw: float = g.belt_scale(sy0_raw)
	var s1_raw: float = g.belt_scale(sy1_raw)
	var pad_y0: float = (3.4 - expand_px * 0.85) * s0_raw
	var pad_y1: float = (3.4 - expand_px * 0.85) * s1_raw
	var sy0: float = clampf(sy0_raw + pad_y0, g.conveyor_top, g.paddle_top)
	var sy1: float = clampf(sy1_raw - pad_y1, g.conveyor_top, g.paddle_top)
	if sy1 - sy0 <= 2.0:
		return PackedVector2Array()
	var s0: float = g.belt_scale(sy0)
	var s1: float = g.belt_scale(sy1)
	var pad_x0: float = (4.8 - expand_px) * s0
	var pad_x1: float = (4.8 - expand_px) * s1
	return PackedVector2Array([
		Vector2(g.belt_lane_x(float(lane), sy0) + pad_x0, sy0),
		Vector2(g.belt_lane_x(float(lane + 1), sy0) - pad_x0, sy0),
		Vector2(g.belt_lane_x(float(lane + 1), sy1) - pad_x1, sy1),
		Vector2(g.belt_lane_x(float(lane), sy1) + pad_x1, sy1),
	])


## Computes the projected screen dimensions of a Rutsche space at `(lane, y_top, h)`.
## Because `belt_project_y` uses exact exponential foreshortening, the ratio of space
## width to space height is strictly constant across the entire conveyor ramp.
func belt_tile_rect(lane: int, y_top: float, h: float) -> Rect2:
	var sy0: float = g.belt_project_y(y_top)
	var sy1: float = g.belt_project_y(y_top + h)
	var s1: float = g.belt_scale(sy1)
	var tw: float = (g.lane_w - 10.0) * s1
	var th: float = sy1 - sy0
	var cx: float = g.belt_lane_center(lane, 0.5 * (sy0 + sy1))
	return Rect2(cx - tw * 0.5, sy0, tw, th)


## Draws a moving 2.5D extruded Paper Mario tile whose footprint sits 100% inside its
## dedicated space on the Rutsche, starting small far away at the horizon and growing
## to the exact paddle & drop-box size as it approaches the camera.
func draw_belt_tile_3d(lane: int, y_top: float, h: float, id: int, alpha: float = 1.0, spirit: String = "") -> void:
	if alpha <= 0.01:
		return
	var q_base: PackedVector2Array = rutsche_space_quad(lane, y_top, y_top + h, 0.0)
	if q_base.size() < 4:
		return

	var s0: float = g.belt_scale(q_base[0].y)
	var s1: float = g.belt_scale(q_base[2].y)
	var ext0: float = 7.5 * s0
	var ext1: float = 9.0 * s1

	# Base footprint corners [tl, tr, br, bl] sitting inside the Rutsche pocket
	var b_tl: Vector2 = q_base[0]
	var b_tr: Vector2 = q_base[1]
	var b_br: Vector2 = q_base[2]
	var b_bl: Vector2 = q_base[3]

	# Raised 3D top-face corners [tl, tr, br, bl]
	var t_tl := b_tl - Vector2(0.0, ext0)
	var t_tr := b_tr - Vector2(0.0, ext0)
	var t_br := b_br - Vector2(0.0, ext1)
	var t_bl := b_bl - Vector2(0.0, ext1)

	var base: Color = S.tile_color(id)
	var alt: Color = S.fluid_alt_color(id)
	var front_col: Color = base.darkened(0.30)
	var rim: Color = base.lerp(alt, 0.25).lightened(0.32)
	var ink_col: Color = S.INK
	var sticker_col: Color = S.WARN if spirit == "slowy" else S.STICKER
	base.a = alpha
	front_col.a = alpha
	rim.a = alpha * 0.88
	ink_col.a = alpha
	sticker_col.a = alpha * 0.96

	# 1. Soft shadow inside the Rutsche pocket footprint
	draw_colored_polygon(q_base, Color(0, 0, 0, 0.20 * alpha))

	# 2. Outer 3D silhouette (top face + front thickness wall) with white sticker & dark ink border
	var st0: float = (4.2 if spirit == "slowy" else 3.2) * s0
	var st1: float = (4.2 if spirit == "slowy" else 3.2) * s1
	var ik0: float = 1.8 * s0
	var ik1: float = 1.8 * s1
	draw_colored_polygon(PackedVector2Array([
		t_tl + Vector2(-st0, -st0 * 0.85),
		t_tr + Vector2(st0, -st0 * 0.85),
		b_br + Vector2(st1, st1 * 0.75),
		b_bl + Vector2(-st1, st1 * 0.75),
	]), sticker_col)
	draw_colored_polygon(PackedVector2Array([
		t_tl + Vector2(-ik0, -ik0 * 0.85),
		t_tr + Vector2(ik0, -ik0 * 0.85),
		b_br + Vector2(ik1, ik1 * 0.75),
		b_bl + Vector2(-ik1, ik1 * 0.75),
	]), ink_col)

	# 3. 3D front thickness wall facing the camera (connects raised top face down to Rutsche pocket)
	draw_colored_polygon(PackedVector2Array([t_bl, t_br, b_br, b_bl]), front_col)

	# 4. Raised 3D top face of the tile
	var q_face := PackedVector2Array([t_tl, t_tr, t_br, t_bl])
	draw_colored_polygon(q_face, base)
	draw_line(t_bl, t_br, Color(S.INK, 0.45 * alpha), maxf(1.2, 1.8 * s1))

	# 5. Glossy paper highlight strip along the top edge of the raised face
	var face_h: float = t_bl.y - t_tl.y
	if face_h >= 8.0:
		var hl_t0 := 0.10
		var hl_t1 := 0.25
		var hl_tl: Vector2 = t_tl.lerp(t_bl, hl_t0).lerp(t_tr.lerp(t_br, hl_t0), 0.06)
		var hl_tr: Vector2 = t_tr.lerp(t_br, hl_t0).lerp(t_tl.lerp(t_bl, hl_t0), 0.06)
		var hl_br: Vector2 = t_tr.lerp(t_br, hl_t1).lerp(t_tl.lerp(t_bl, hl_t1), 0.06)
		var hl_bl: Vector2 = t_tl.lerp(t_bl, hl_t1).lerp(t_tr.lerp(t_br, hl_t1), 0.06)
		draw_colored_polygon(PackedVector2Array([hl_tl, hl_tr, hl_br, hl_bl]), rim)

	# 6. Shape sticker emblem (or trapped Slowy spirit!) scaled by 2.5D depth `s_mid`
	if face_h >= 11.0:
		var c: Vector2 = (t_tl + t_tr + t_br + t_bl) * 0.25
		var s_mid: float = 0.5 * (s0 + s1)
		var face_w: float = ((t_tr.x - t_tl.x) + (t_br.x - t_bl.x)) * 0.5
		if spirit == "slowy":
			var sr: float = minf(face_w, face_h) * 0.30
			_draw_slowy_spirit(c, sr, true, alpha)
		else:
			var gr: float = minf(face_w, face_h) * 0.23
			draw_set_transform(c, 0.0, Vector2(1.0, 0.84))
			_draw_glyph(Vector2.ZERO, id, gr + 1.6 * s_mid, Color(S.INK.r, S.INK.g, S.INK.b, 0.34 * alpha))
			_draw_glyph(Vector2.ZERO, id, gr, Color(1, 1, 1, 0.90 * alpha))
			var eye_dx: float = minf(face_w * 0.28, gr * 1.95)
			var eye_r: float = maxf(1.1, 2.3 * s_mid)
			var cheek_col := Color(1.0, 0.45, 0.55, 0.45 * alpha)
			draw_circle(Vector2(-eye_dx - 2.2 * s_mid, 2.0 * s_mid), eye_r * 1.2, cheek_col)
			draw_circle(Vector2(eye_dx + 2.2 * s_mid, 2.0 * s_mid), eye_r * 1.2, cheek_col)
			draw_circle(Vector2(-eye_dx, -0.8 * s_mid), eye_r, ink_col)
			draw_circle(Vector2(eye_dx, -0.8 * s_mid), eye_r, ink_col)
			draw_circle(Vector2(-eye_dx - 0.5 * s_mid, -1.4 * s_mid), eye_r * 0.4, sticker_col)
			draw_circle(Vector2(eye_dx - 0.5 * s_mid, -1.4 * s_mid), eye_r * 0.4, sticker_col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_glyph(c: Vector2, id: int, r: float, col: Color) -> void:
	match id % 5:
		0:
			draw_circle(c, r, col)
		1:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)]), col)
		2:
			draw_rect(Rect2(c - Vector2(r, r) * 0.88, Vector2(r, r) * 1.76), col)
		3:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 1.2), c + Vector2(r * 1.2, 0),
				c + Vector2(0, r * 1.2), c + Vector2(-r * 1.2, 0)]), col)
		4:
			draw_arc(c, r * 0.78, 0.0, TAU, 28, col, r * 0.48)


## Tile rect for a bin cell whose top edge is at `top` in `lane`, with the given height.
func tile_rect(lane: int, top: float, h: float) -> Rect2:
	return Rect2(g.lane_left(lane) + 5.0, top + 2.5, g.lane_w - 10.0, h - 5.0)


# ---------------------------------------------------------------------------
# Paper Mario Storybook Diorama Backdrop & 2.5D Craft Playfield
# ---------------------------------------------------------------------------

func _draw_space_backdrop() -> void:
	var w: float = g.vp.x
	var h: float = g.vp.y

	# 1. Warm cream craft-paper base + pastel sky-blue paper top sheet
	draw_rect(Rect2(-40.0, -40.0, w + 80.0, h + 80.0), S.BG)
	var sky_h: float = g.paddle_top + 20.0
	draw_rect(Rect2(-40.0, -40.0, w + 80.0, sky_h + 40.0), S.SKY_TOP)

	# 2. Gentle sunlit paper rays fanning from behind the stage horizon
	var sun_c := Vector2(w * 0.5, g.conveyor_top + 20.0)
	for i in 7:
		var ang: float = -PI + float(i) * (PI / 6.0) + sin(g.time * 0.3) * 0.04
		var a1: float = ang - 0.11
		var a2: float = ang + 0.11
		var ray_r: float = w * 0.95
		draw_colored_polygon(PackedVector2Array([
			sun_c,
			sun_c + Vector2(cos(a1), sin(a1)) * ray_r,
			sun_c + Vector2(cos(a2), sin(a2)) * ray_r,
		]), Color(1.0, 0.98, 0.88, 0.28))

	# 3. Layered Paper Mario rolling green hills with sticker borders & sewing stitches
	_draw_paper_hill(g.paddle_top - 95.0, 38.0, 0.0, S.HILL_BACK, 1.0)
	_draw_paper_hill(g.paddle_top - 28.0, 28.0, 2.1, S.HILL_FRONT, -1.0)

	# 4. Hanging puffy paper clouds on strings in the left & right stage margins
	_draw_hanging_cloud(Vector2(w * 0.13, 250.0 + sin(g.time * 1.7) * 8.0), 0.88)
	_draw_hanging_cloud(Vector2(w * 0.87, 305.0 + cos(g.time * 1.5 + 1.0) * 9.0), 0.94)
	_draw_hanging_cloud(Vector2(w * 0.11, 490.0 + sin(g.time * 1.3 + 2.4) * 7.0), 0.76)

	# 5. Festive Paper-Cutout Bunting / Stage Pennants along the top of the screen
	_draw_stage_bunting()

	# 6. Floating colorful paper stars & paint bubbles in the margins
	var mote_tex: Texture2D = _tex_star if _tex_star != null else _tex_bubble
	if mote_tex != null:
		var cx: float = w * 0.5
		for m in 8:
			var seed_f := float(m) * 1.73
			var side := -1.0 if m % 2 == 0 else 1.0
			var my: float = fposmod(seed_f * 137.0 - g.time * (14.0 + float(m % 3) * 4.0), g.paddle_top - 120.0) + 90.0
			var mx: float = cx + side * (g.board_w * 0.36 + fposmod(seed_f * 83.0, g.board_w * 0.12))
			var mcol: Color = S.tile_color(m % 5)
			mcol.a = 0.55 + 0.25 * sin(g.time * 2.5 + seed_f)
			var msz := 16.0 + float(m % 3) * 5.0
			draw_texture_rect(mote_tex, Rect2(mx - msz * 0.5, my - msz * 0.5, msz, msz), false, mcol)


func _draw_paper_hill(base_y: float, amp: float, phase: float, col: Color, dir: float) -> void:
	var w: float = g.vp.x
	var bot: float = g.vp.y + 40.0
	var steps := 28
	var pts_shadow := PackedVector2Array()
	var pts_sticker := PackedVector2Array()
	var pts_ink := PackedVector2Array()
	var pts_fill := PackedVector2Array()
	for i in range(steps + 1):
		var u := float(i) / float(steps)
		var x: float = lerpf(-30.0, w + 30.0, u)
		var y: float = base_y + sin(u * PI * 2.2 * dir + phase) * amp + cos(u * PI * 1.1) * (amp * 0.4)
		pts_shadow.append(Vector2(x, y - 9.0))
		pts_sticker.append(Vector2(x, y - 6.0))
		pts_ink.append(Vector2(x, y - 2.8))
		pts_fill.append(Vector2(x, y))
	pts_shadow.append(Vector2(w + 30.0, bot))
	pts_shadow.append(Vector2(-30.0, bot))
	pts_sticker.append(Vector2(w + 30.0, bot))
	pts_sticker.append(Vector2(-30.0, bot))
	pts_ink.append(Vector2(w + 30.0, bot))
	pts_ink.append(Vector2(-30.0, bot))
	pts_fill.append(Vector2(w + 30.0, bot))
	pts_fill.append(Vector2(-30.0, bot))

	draw_colored_polygon(pts_shadow, Color(0, 0, 0, 0.08))
	draw_colored_polygon(pts_sticker, S.STICKER)
	draw_colored_polygon(pts_ink, S.INK)
	draw_colored_polygon(pts_fill, col)

	# Dashed sewing-stitch line along the paper hill crest
	for i in range(0, steps, 2):
		var p0: Vector2 = pts_fill[i] + Vector2(0, 10.0)
		var p1: Vector2 = pts_fill[i + 1] + Vector2(0, 10.0)
		draw_line(p0, p1, Color(1, 1, 1, 0.55), 2.2)


func _draw_hanging_cloud(c: Vector2, sc: float) -> void:
	# Hanging craft string from top of stage
	draw_line(Vector2(c.x, -20.0), c + Vector2(0, -18.0 * sc), Color(S.INK, 0.35), 2.0)
	var puffs := [
		Vector2(0, 0),
		Vector2(-24.0 * sc, 5.0 * sc),
		Vector2(24.0 * sc, 5.0 * sc),
		Vector2(-12.0 * sc, -11.0 * sc),
		Vector2(12.0 * sc, -10.0 * sc),
	]
	var radii := [22.0 * sc, 16.0 * sc, 16.0 * sc, 17.0 * sc, 16.0 * sc]
	# Drop shadow
	for i in puffs.size():
		draw_circle(c + puffs[i] + Vector2(0, 5.0 * sc), radii[i] + 3.0, S.SHADOW)
	# Dark cartoon ink outline
	for i in puffs.size():
		draw_circle(c + puffs[i], radii[i] + 2.8, S.INK)
	# Cream-white paper fill
	for i in puffs.size():
		draw_circle(c + puffs[i], radii[i], S.STICKER)
	# Cute Paper Mario cloud eyes & rosy cheeks
	draw_circle(c + Vector2(-9.0 * sc, 4.0 * sc), 3.2 * sc, Color(1.0, 0.55, 0.65, 0.55))
	draw_circle(c + Vector2(9.0 * sc, 4.0 * sc), 3.2 * sc, Color(1.0, 0.55, 0.65, 0.55))
	draw_line(c + Vector2(-5.5 * sc, -3.5 * sc), c + Vector2(-5.5 * sc, 2.5 * sc), S.INK, 2.4 * sc)
	draw_line(c + Vector2(5.5 * sc, -3.5 * sc), c + Vector2(5.5 * sc, 2.5 * sc), S.INK, 2.4 * sc)


func _draw_stage_bunting() -> void:
	var count := 12
	var flag_w: float = g.vp.x / float(count)
	for i in count:
		var x0: float = float(i) * flag_w
		var x1: float = x0 + flag_w
		var xm: float = (x0 + x1) * 0.5
		var sway: float = sin(g.time * 2.2 + float(i) * 0.6) * 2.5
		var tip := Vector2(xm + sway, 28.0)
		var col: Color = S.tile_color(i % 5)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0 - 2.0, -4.0), Vector2(x1 + 2.0, -4.0), tip + Vector2(0, 5.0)
		]), S.STICKER)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0, -4.0), Vector2(x1, -4.0), tip + Vector2(0, 2.5)
		]), S.INK)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0 + 2.0, -4.0), Vector2(x1 - 2.0, -4.0), tip
		]), col)


func _draw_belt() -> void:
	var y_top: float = g.conveyor_top
	var y_bot: float = g.paddle_top
	var lip_h := 14.0

	var tl := Vector2(g.belt_lane_x(0.0, y_top), y_top)
	var tr := Vector2(g.belt_lane_x(5.0, y_top), y_top)
	var br := Vector2(g.belt_lane_x(5.0, y_bot), y_bot)
	var bl := Vector2(g.belt_lane_x(0.0, y_bot), y_bot)

	var rail_top := 9.0
	var rail_bot := 24.0
	var rail_drop := 15.0

	# 0. Distant 3D wooden dispenser arch / hood at the far horizon of the Rutsche
	var hood_rect := Rect2(tl.x - rail_top - 4.0, y_top - 16.0, (tr.x - tl.x) + (rail_top + 4.0) * 2.0, 20.0)
	paper_card(hood_rect, S.WOOD_DARK, 8.0, Vector2(0, 3), 2.5, 2.0)

	# 1. Outer paper drop shadow + white sticker halo + dark cartoon ink border around the whole ramp
	var outer_tl := tl + Vector2(-rail_top, 0)
	var outer_tr := tr + Vector2(rail_top, 0)
	var outer_br := br + Vector2(rail_bot, lip_h)
	var outer_bl := bl + Vector2(-rail_bot, lip_h)

	draw_colored_polygon(PackedVector2Array([
		outer_tl + Vector2(0, 10), outer_tr + Vector2(0, 10),
		outer_br + Vector2(6, 10), outer_bl + Vector2(-6, 10),
	]), S.SHADOW)
	draw_colored_polygon(PackedVector2Array([
		outer_tl + Vector2(-6, -6), outer_tr + Vector2(6, -6),
		outer_br + Vector2(7, 6), outer_bl + Vector2(-7, 6),
	]), S.STICKER)
	draw_colored_polygon(PackedVector2Array([
		outer_tl + Vector2(-3, -3), outer_tr + Vector2(3, -3),
		outer_br + Vector2(3.5, 3), outer_bl + Vector2(-3.5, 3),
	]), S.INK)

	# 2. Toy-wood side rails (left and right)
	draw_colored_polygon(PackedVector2Array([
		tl + Vector2(-rail_top, 0), tl, bl, bl + Vector2(-rail_bot, 0),
	]), S.WOOD_RAIL)
	draw_colored_polygon(PackedVector2Array([
		tl + Vector2(-rail_top, 0), bl + Vector2(-rail_bot, 0),
		bl + Vector2(-rail_bot, rail_drop), tl + Vector2(-rail_top, rail_drop * 0.6),
	]), S.WOOD_DARK)

	draw_colored_polygon(PackedVector2Array([
		tr, tr + Vector2(rail_top, 0), br + Vector2(rail_bot, 0), br,
	]), S.WOOD_RAIL)
	draw_colored_polygon(PackedVector2Array([
		tr + Vector2(rail_top, 0), tr + Vector2(rail_top, rail_drop * 0.6),
		br + Vector2(rail_bot, rail_drop), br + Vector2(rail_bot, 0),
	]), S.WOOD_DARK)

	# Cute cartoon rivets along the wooden side rails
	for r_i in 5:
		var ru: float = (float(r_i) + 0.5) / 5.0
		var ry: float = lerpf(y_top, y_bot, pow(ru, 1.35))
		var r_sc: float = g.belt_scale(ry)
		var lx_riv: float = g.belt_lane_x(0.0, ry) - lerpf(rail_top, rail_bot, ru) * 0.5
		var rx_riv: float = g.belt_lane_x(5.0, ry) + lerpf(rail_top, rail_bot, ru) * 0.5
		draw_circle(Vector2(lx_riv, ry), 3.6 * r_sc, S.INK)
		draw_circle(Vector2(lx_riv, ry), 2.2 * r_sc, S.STICKER)
		draw_circle(Vector2(rx_riv, ry), 3.6 * r_sc, S.INK)
		draw_circle(Vector2(rx_riv, ry), 2.2 * r_sc, S.STICKER)

	# 3. Main kraft-cardboard conveyor surface (with cool mint frost tint when Slowy is active!)
	var belt_surface_col: Color = S.PANEL.lerp(Color(0.62, 0.96, 0.90), 0.30) if g.is_slowy_active() else S.PANEL
	draw_colored_polygon(PackedVector2Array([tl, tr, br, bl]), belt_surface_col)

	# 4. Alternating paper lane bands & active lane highlight
	for c in 5:
		var l_top := Vector2(g.belt_lane_x(float(c), y_top), y_top)
		var r_top := Vector2(g.belt_lane_x(float(c + 1), y_top), y_top)
		var r_bot := Vector2(g.belt_lane_x(float(c + 1), y_bot), y_bot)
		var l_bot := Vector2(g.belt_lane_x(float(c), y_bot), y_bot)
		if c % 2 == 1:
			draw_colored_polygon(PackedVector2Array([l_top, r_top, r_bot, l_bot]), Color(S.PANEL_DARK, 0.35))
		if (g.state == g.State.PLAYING or g.state == g.State.PAUSED) and c == g.paddle_lane:
			draw_colored_polygon(PackedVector2Array([l_top, r_top, r_bot, l_bot]), Color(S.STICKER, 0.38))

	# 5. Dedicated scrolling Rutsche spaces (recessed 3D pockets) + horizontal slat lines!
	# Driven by `g.belt_scroll` and `g.belt_slot_h()` so spaces start small far away
	# (`s = 0.36`) and grow progressively larger to reach the exact paddle & drop-box
	# size (`s = 1.0`) at the bottom of the Rutsche!
	var sh: float = g.belt_slot_h()
	var phase_off: float = fposmod(g.belt_scroll, sh)
	var row_count: int = int(ceil((y_bot - y_top) / sh)) + 2
	for k in range(-1, row_count):
		var y_log0: float = y_top + phase_off + float(k) * sh
		var y_log1: float = y_log0 + sh
		for c in 5:
			var space_q: PackedVector2Array = rutsche_space_quad(c, y_log0, y_log1, 0.0)
			if space_q.size() == 4:
				var s_mid: float = g.belt_scale(0.5 * (space_q[0].y + space_q[2].y))
				var active_lane: bool = (g.state == g.State.PLAYING or g.state == g.State.PAUSED) and c == g.paddle_lane
				var pocket_col: Color = Color(S.PANEL_LIGHT, 0.58) if active_lane else Color(S.PANEL_DARK, lerpf(0.38, 0.62, s_mid))
				draw_colored_polygon(space_q, pocket_col)
				# 3D recessed inner top shadow & bottom highlight inside each Rutsche space
				draw_line(space_q[0], space_q[1], Color(S.INK, 0.26 * s_mid), maxf(1.0, 2.2 * s_mid))
				draw_line(space_q[3], space_q[2], Color(S.STICKER, 0.55 * s_mid), maxf(1.0, 1.8 * s_mid))
				draw_polyline(PackedVector2Array([space_q[0], space_q[1], space_q[2], space_q[3], space_q[0]]), Color(S.INK, 0.22), maxf(1.0, 1.5 * s_mid))
		if y_log0 > y_top + 2.0 and y_log0 < y_bot - 2.0:
			var sy: float = g.belt_project_y(y_log0)
			var depth_t: float = g.belt_depth(sy)
			var lx: float = g.belt_lane_x(0.0, sy) + 2.0
			var rx: float = g.belt_lane_x(5.0, sy) - 2.0
			draw_line(Vector2(lx, sy), Vector2(rx, sy), Color(S.WOOD_DARK, lerpf(0.24, 0.56, depth_t)), lerpf(1.2, 2.8, depth_t))

	# 6. Atmospheric depth shading near the distant horizon of the Rutsche
	var haze_y: float = lerpf(y_top, y_bot, 0.22)
	draw_colored_polygon(PackedVector2Array([
		tl, tr,
		Vector2(g.belt_lane_x(5.0, haze_y), haze_y),
		Vector2(g.belt_lane_x(0.0, haze_y), haze_y),
	]), Color(S.WOOD_DARK, 0.14))

	# 6. Converging lane divider lines with cartoon ink edge
	draw_line(tl, bl, S.INK, 2.4)
	draw_line(tr, br, S.INK, 2.4)
	for c in range(1, 5):
		var p0 := Vector2(g.belt_lane_x(float(c), y_top), y_top)
		var p1 := Vector2(g.belt_lane_x(float(c), y_bot), y_bot)
		draw_line(p0, p1, Color(S.INK, 0.34), 2.0)

	# 7. Front 3D wooden lip at bottom of conveyor ramp
	draw_colored_polygon(PackedVector2Array([
		bl + Vector2(-rail_bot, 0),
		br + Vector2(rail_bot, 0),
		br + Vector2(rail_bot, lip_h),
		bl + Vector2(-rail_bot, lip_h),
	]), S.WOOD_DARK)
	draw_line(bl + Vector2(-rail_bot, 0), br + Vector2(rail_bot, 0), S.INK, 2.6)


func _draw_bins() -> void:
	var rows: float = g.Board.ROWS
	var b_left: float = g.board_left
	var b_top: float = g.bins_top
	var b_w: float = g.board_w
	var c_h: float = g.cell_h
	var well_rect := Rect2(b_left - 8.0, b_top - 14.0, b_w + 16.0, c_h * rows + 22.0)

	# Cardboard collector box with white sticker border & bold dark cartoon ink outline
	paper_card(well_rect, S.PANEL, 24.0, Vector2(0, 8), 4.0, 3.0)

	var chute_h := 13.0
	for c in 5:
		var x0: float = g.lane_left(c) + 4.0
		var w: float = g.lane_w - 8.0
		var inset := 6.0
		var active: bool = (g.state == g.State.PLAYING or g.state == g.State.PAUSED) and c == g.paddle_lane
		var chute_col: Color = S.WARN.lightened(0.25) if active else S.WOOD_DARK
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0, g.bins_top - chute_h),
			Vector2(x0 + w, g.bins_top - chute_h),
			Vector2(x0 + w - inset, g.bins_top),
			Vector2(x0 + inset, g.bins_top),
		]), chute_col)

		var col_rect := Rect2(x0, g.bins_top, w, g.cell_h * rows)
		var slot_col: Color = S.PANEL_LIGHT if active else S.PANEL_DARK.lightened(0.12)
		rr(col_rect, slot_col, 14.0)
		rr_line(col_rect, Color(S.INK, 0.35 if active else 0.18), 14.0, 2.0)

		# Stitched slot guides inside each bin column
		for r in range(1, int(rows)):
			var y: float = g.bins_bottom - float(r) * g.cell_h
			draw_line(Vector2(x0 + 10.0, y), Vector2(x0 + w - 10.0, y), Color(S.INK, 0.14), 2.0)

		var h: int = g.board.height(c)
		if h >= int(rows):
			var pulse: float = 0.55 + 0.45 * sin(g.time * 9.0)
			rr_line(col_rect.grow(-1.0), Color(S.DANGER, pulse), 14.0, 3.5)
		elif h == int(rows) - 1:
			var pulse2: float = 0.5 + 0.5 * sin(g.time * 6.0)
			rr(Rect2(col_rect.position, Vector2(col_rect.size.x, g.cell_h)), Color(S.WARN, 0.18 + 0.14 * pulse2), 14.0)


func _draw_board_tiles() -> void:
	var clearing := {}
	for cell in g.clearing_cells:
		clearing[cell] = true
	var ct: float = clampf(g.phase_t / g.CLEAR_TIME, 0.0, 1.0) if g.phase == g.Phase.CLEARING else 0.0
	for c in 5:
		for r in g.board.cols[c].size():
			var id: int = g.board.cols[c][r]
			var off: float = g.board.offs[c][r]
			var sp: String = g.board.get_spirit(c, r)
			var top: float = g.cell_top(float(r) + off)
			var rect := tile_rect(c, top, g.cell_h)
			if clearing.has(Vector2i(c, r)):
				var s: float = 1.0 + 0.26 * sin(ct * PI) - 0.92 * pow(ct, 2.6)
				var center := rect.get_center()
				rect = Rect2(center - rect.size * s * 0.5, rect.size * s)
				draw_tile(rect, id, 1.0 - ct * 0.6, minf(1.0, 0.35 + ct * 2.2), 1.0, sp)
			else:
				draw_tile(rect, id, 1.0, 0.0, 1.0, sp)


func _draw_belt_tiles() -> void:
	var sorted: Array = g.belt_tiles.duplicate()
	sorted.sort_custom(func(a, b): return a.y < b.y)
	var sh: float = g.belt_slot_h()
	for t in sorted:
		var alpha: float = clampf((t.y - (g.conveyor_top - sh * 0.55)) / (sh * 0.5), 0.0, 1.0)
		var sp: String = String(t.get("spirit", ""))
		draw_belt_tile_3d(t.lane, t.y, sh, t.color, alpha, sp)


func _draw_flights() -> void:
	for i in g.flights.size():
		var f = g.flights[i]
		var row: int = g.flight_target_row(i)
		var target: float = g.cell_top(float(row))
		var k: float = clampf(f.t, 0.0, 1.0)
		var e: float = k * k
		var top: float = lerpf(f.from_y, target, e)
		var h: float = lerpf(g.HELD_H, g.cell_h, minf(1.0, k * 2.0))
		var sp: String = String(f.get("spirit", ""))
		draw_tile(tile_rect(f.lane, top, h), f.color, 1.0, 0.0, 1.0, sp)


func _draw_paddle() -> void:
	var w: float = g.lane_w - 6.0
	var squash: float = 0.22 * g.paddle_bump
	var ph: float = g.paddle_h * (1.0 - squash)
	var py: float = g.paddle_top + (g.paddle_h - ph)
	var px: float = g.paddle_x - w * 0.5
	var pad_rect := Rect2(px, py, w, ph)

	# Paper-craft catcher tray with white sticker rim & cartoon ink outline
	paper_card(pad_rect, S.PANEL_LIGHT, ph * 0.45, Vector2(0, 5), 3.0, 2.5)
	rr(Rect2(px + 3.0, py + ph - 6.0, w - 6.0, 5.0), S.WOOD_RAIL, 3.0)
	# Cute little eyes on the catcher paddle
	draw_circle(Vector2(g.paddle_x - 10.0, py + ph * 0.48), 2.5, S.INK)
	draw_circle(Vector2(g.paddle_x + 10.0, py + ph * 0.48), 2.5, S.INK)

	# Held stack rendered as stacked Paper Mario sticker slabs
	var stack_w: float = w - 6.0
	for i in g.held.size():
		var slab_bot: float = py - float(i) * g.HELD_H
		var slab_top: float = slab_bot - g.HELD_H + 1.5
		var sx: float = g.paddle_x - stack_w * 0.5
		var s_rect := Rect2(sx, slab_top, stack_w, g.HELD_H - 2.0)
		var base: Color = S.tile_color(g.held[i])
		var dark: Color = base.darkened(0.26)
		rr(s_rect.grow(3.5), S.STICKER, 8.0)
		rr(s_rect.grow(1.8), S.INK, 7.0)
		rr(s_rect, dark, 6.0)
		rr(Rect2(sx, slab_top, stack_w, g.HELD_H - 5.5), base, 6.0)
		if i < g.held_spirits.size() and String(g.held_spirits[i]) == "slowy":
			_draw_slowy_spirit(s_rect.get_center(), 8.5, true, 1.0)

	if g.held.size() >= g.MAX_HELD:
		ctext("FULL!", g.paddle_x, py - float(g.MAX_HELD) * g.HELD_H - 18.0, 24, S.WARN)


# ---------------------------------------------------------------------------
# Color-Splash Paint Splats, Beams, Shockwaves & Confetti Sprites
# ---------------------------------------------------------------------------

func _draw_fluid_splats() -> void:
	if _tex_splash == null:
		return
	for fs in g.fluid_splats:
		var t: float = clampf(fs.life / fs.max, 0.0, 1.0)
		var grow: float = 1.0 - pow(t, 3.0) * 0.45
		var r: float = float(fs.radius) * grow
		var col: Color = fs.color.lerp(fs.color_alt, 1.0 - t)
		col.a = t * 0.85
		var aspect: float = float(fs.get("aspect", 1.0))
		draw_set_transform(fs.pos, float(fs.rot), Vector2(aspect, 1.0 / aspect))
		# White sticker halo behind paint splat so it pops like a Paper Mario Color Splash decal
		var sticker_r: float = r * 1.08
		draw_texture_rect(_tex_splash, Rect2(-Vector2(sticker_r, sticker_r), Vector2(sticker_r * 2.0, sticker_r * 2.0)), false, Color(1, 1, 1, t * 0.7))
		draw_texture_rect(_tex_splash, Rect2(-Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_combo_beams() -> void:
	for cb in g.combo_beams:
		var t: float = clampf(cb.life / cb.max, 0.0, 1.0)
		var col: Color = cb.color
		col.a = t * 0.85
		draw_line(cb.a, cb.b, Color(S.INK, t * 0.7), 34.0 * t, true)
		draw_line(cb.a, cb.b, col, 26.0 * t, true)
		draw_line(cb.a, cb.b, Color(S.STICKER, t * 0.96), 10.0 * t, true)


func _draw_shockwaves() -> void:
	for sw in g.shockwaves:
		var progress: float = 1.0 - clampf(sw.life / sw.max, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - progress, 2.4)
		var radius: float = lerpf(sw.r0, sw.r1, eased)
		var alpha: float = pow(1.0 - progress, 1.35)
		var col: Color = sw.color
		col.a = alpha * 0.90
		var w: float = maxf(2.0, sw.width * (1.0 - progress * 0.68))
		draw_arc(sw.pos, radius, 0.0, TAU, 48, Color(S.INK, alpha * 0.55), w + 4.0, true)
		draw_arc(sw.pos, radius, 0.0, TAU, 48, col, w, true)


func _draw_starbursts() -> void:
	if _tex_star == null:
		return
	for sb in g.starbursts:
		var t: float = clampf(sb.life / sb.max, 0.0, 1.0)
		var scale_f: float = sin((1.0 - t) * PI) * 1.15 + t * 0.35
		var sz: float = sb.size * scale_f
		var col: Color = sb.color
		col.a = t
		draw_set_transform(sb.pos, sb.rot, Vector2.ONE)
		var out_sz: float = sz * 1.12
		draw_texture_rect(_tex_star, Rect2(-Vector2(out_sz, out_sz) * 0.5, Vector2(out_sz, out_sz)), false, Color(S.INK, t * 0.65))
		draw_texture_rect(_tex_star, Rect2(-Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_debris() -> void:
	for d in g.debris:
		draw_set_transform(d.pos, d.rot, Vector2.ONE)
		var w: float = g.lane_w - 10.0
		draw_tile(Rect2(-w * 0.5, -g.cell_h * 0.5, w, g.cell_h), d.color, 0.92)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_particles() -> void:
	for p in g.particles:
		var a: float = clampf(p.life / p.max, 0.0, 1.0)
		var s: float = p.size * (0.42 + 0.68 * a)
		var alt: Color = p.get("color_alt", p.color)
		var col: Color = p.color.lerp(alt, (1.0 - a) * 0.72)
		col.a = a
		var kind: String = p.get("kind", "spark")
		var rot: float = float(p.get("rot", 0.0))
		if kind == "glyph":
			draw_set_transform(p.pos, rot, Vector2.ONE)
			_draw_glyph(Vector2.ZERO, int(p.get("glyph", 0)), s * 0.48 + 1.8, Color(S.INK, a * 0.75))
			_draw_glyph(Vector2.ZERO, int(p.get("glyph", 0)), s * 0.45, col)
			continue
		var tex: Texture2D = _tex_spark
		var scale_vec := Vector2.ONE
		if kind == "droplet":
			tex = _tex_droplet
			var vel: Vector2 = p.get("vel", Vector2.ZERO)
			var spd: float = vel.length()
			if spd > 15.0:
				rot = vel.angle()
				var stretch := clampf(1.0 + spd / 420.0, 1.0, 2.0)
				scale_vec = Vector2(stretch, 1.0 / sqrt(stretch))
		elif kind == "splash":
			tex = _tex_splash
		elif kind == "bubble":
			tex = _tex_bubble
		elif kind == "star":
			tex = _tex_star
		elif kind == "glow":
			tex = _tex_glow
		elif kind == "shard":
			tex = _tex_shard
		elif kind == "spark":
			var vel2: Vector2 = p.get("vel", Vector2.ZERO)
			if vel2.length() > 15.0:
				rot = vel2.angle()
		if tex != null:
			draw_set_transform(p.pos, rot, scale_vec)
			if kind != "glow":
				var rim_s: float = s * 1.16
				draw_texture_rect(tex, Rect2(-Vector2(rim_s, rim_s) * 0.5, Vector2(rim_s, rim_s)), false, Color(S.INK, a * 0.55))
			draw_texture_rect(tex, Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, col)
		else:
			draw_rect(Rect2(p.pos - Vector2(s, s) * 0.5, Vector2(s, s)), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_popups() -> void:
	for p in g.popups:
		var a: float = clampf(p.life / 0.4, 0.0, 1.0)
		var pop: float = clampf((p.max - p.life) / 0.12, 0.0, 1.0)
		var col: Color = p.color
		col.a = a
		var size: int = int(float(p.size) * (0.7 + 0.3 * pop))
		ctext(p.text, p.pos.x, p.pos.y, size, col)


func _draw_banner() -> void:
	if g.banner_t <= 0.0 or g.state != g.State.PLAYING:
		return
	var a: float = clampf(g.banner_t / 0.5, 0.0, 1.0)
	var enter: float = clampf((1.7 - g.banner_t) / 0.25, 0.0, 1.0)
	var y: float = g.vp.y * 0.38 - (1.0 - enter) * 24.0
	var cx: float = g.vp.x * 0.5
	var ribbon := Rect2(cx - 210.0, y - 68.0, 420.0, 134.0)
	if a * enter > 0.65:
		paper_card(ribbon, S.PANEL_LIGHT, 26.0, Vector2(0, 8), 4.0, 3.0)
	ctext(g.banner_text, cx, y + 4.0, 74, Color(S.WARN, a * enter))
	var sub := "Clear %d tiles!" % g.wave_goal
	ctext(sub, cx, y + 48.0, 26, Color(S.TEXT, a * enter))


# ---------------------------------------------------------------------------
# Paper Mario HUD, Sticker Hearts & Buttons
# ---------------------------------------------------------------------------

func _draw_heart(c: Vector2, r: float, filled: bool) -> void:
	var col: Color = S.DANGER if filled else S.PANEL_DARK
	# Sticker & ink backing
	for pass_i in 3:
		var rad: float = r + (3.2 if pass_i == 0 else (1.6 if pass_i == 1 else 0.0))
		var pcol: Color = S.STICKER if pass_i == 0 else (S.INK if pass_i == 1 else col)
		draw_circle(c + Vector2(-r * 0.45, -r * 0.25), rad * 0.58, pcol)
		draw_circle(c + Vector2(r * 0.45, -r * 0.25), rad * 0.58, pcol)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-rad * 0.98, -r * 0.05),
			c + Vector2(rad * 0.98, -r * 0.05),
			c + Vector2(0, rad * 1.05),
		]), pcol)
	if filled:
		draw_circle(c + Vector2(-r * 0.48, -r * 0.35), r * 0.20, Color(1, 1, 1, 0.75))


func _draw_hud() -> void:
	var cx: float = g.vp.x * 0.5
	var badge := Rect2(cx - 125.0, 20.0, 250.0, 96.0)
	paper_card(badge, S.PANEL_LIGHT, 24.0, Vector2(0, 5), 3.0, 2.5)
	ctext("SCORE", cx, 46.0, 19, S.DIM)
	ctext(str(g.score), cx, 102.0, 58, S.TEXT)

	var left: float = g.board_left
	var right: float = g.board_left + g.board_w
	ltext("WAVE %d" % g.wave, left, 154.0, 26, S.TEXT)
	ctext("%d / %d" % [mini(g.wave_progress, g.wave_goal), g.wave_goal], cx, 154.0, 22, S.DIM)

	# Sticker Heart Lives
	var slots: int = maxi(g.START_LIVES, g.lives)
	for i in slots:
		var hc := Vector2(right - 14.0 - float(slots - 1 - i) * 32.0, 145.0)
		_draw_heart(hc, 11.5, i < g.lives)

	# Stitched Wave Progress Bar
	var bar := Rect2(left, 168.0, g.board_w, 12.0)
	rr(bar.grow(3.5), S.STICKER, 8.0)
	rr(bar.grow(1.8), S.INK, 7.0)
	rr(bar, S.PANEL_DARK, 6.0)
	var frac: float = clampf(float(g.wave_progress) / float(g.wave_goal), 0.0, 1.0)
	if frac > 0.0:
		rr(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), S.GOOD, 6.0)

	# Pause sticker button
	var pr: Rect2 = g.buttons["pause"]
	var pc := pr.get_center()
	var pbox := Rect2(pc - Vector2(26, 26), Vector2(52, 52))
	paper_card(pbox, S.PANEL_LIGHT, 16.0, Vector2(0, 4), 2.5, 2.2)
	rr(Rect2(pc.x - 10.0, pc.y - 12.0, 7.0, 24.0), S.INK, 3.0)
	rr(Rect2(pc.x + 3.0, pc.y - 12.0, 7.0, 24.0), S.INK, 3.0)

	_draw_slowy_hud()


func _draw_slowy_hud() -> void:
	var trapped: bool = g.is_slowy_trapped()
	var active: bool = g.is_slowy_active()
	if not trapped and not active:
		return

	var card := Rect2(g.vp.x - 194.0, 188.0, 180.0, 108.0)
	var pulse: float = 0.5 + 0.5 * sin(g.time * 6.5)
	var bg_col: Color = S.PANEL_LIGHT.lerp(Color(0.75, 0.99, 0.93), 0.45 if active else (0.18 + 0.15 * pulse))
	paper_card(card, bg_col, 20.0, Vector2(0, 5), 3.2, 2.5)

	var cx: float = card.get_center().x
	if active:
		ctext("SLOWY FREE!", cx, card.position.y + 23.0, 17, S.INK)
		_draw_slowy_spirit(card.position + Vector2(36.0, 56.0), 18.0, false, 1.0)
		ctext("1/2 SPEED", card.position.x + 118.0, card.position.y + 52.0, 19, Color(0.08, 0.52, 0.44))
		var secs: float = maxf(0.0, g.slowy_active_t)
		ctext("%.1fs" % secs, card.position.x + 118.0, card.position.y + 73.0, 16, S.DIM)
		var t_bar := Rect2(card.position.x + 16.0, card.position.y + 86.0, card.size.x - 32.0, 10.0)
		rr(t_bar.grow(2.0), S.INK, 6.0)
		rr(t_bar, S.PANEL_DARK, 5.0)
		var tf: float = clampf(g.slowy_active_t / g.SLOWY_DURATION, 0.0, 1.0)
		if tf > 0.0:
			rr(Rect2(t_bar.position, Vector2(t_bar.size.x * tf, t_bar.size.y)), Color(0.22, 0.90, 0.76), 5.0)
	else:
		var combo_kind: String = String(g.slowy_combo_type)
		ctext("FREE SLOWY!", cx, card.position.y + 22.0, 17, S.DANGER.lerp(S.INK, 0.35))
		_draw_slowy_spirit(card.position + Vector2(35.0, 54.0), 16.5, true, 1.0)

		# Draw visual 3-tile Klax combo diagram (horizontal, vertical, or diagonal)
		var diag_c := card.position + Vector2(118.0, 52.0)
		var offsets: Array[Vector2] = []
		var label_str := "HORIZONTAL KLAX"
		var badge_col := Color(0.18, 0.72, 0.96)
		if combo_kind == "vertical":
			offsets = [Vector2(0, -16), Vector2(0, 0), Vector2(0, 16)]
			label_str = "VERTICAL KLAX"
			badge_col = Color(0.32, 0.84, 0.42)
		elif combo_kind == "diagonal":
			offsets = [Vector2(-18, 13), Vector2(0, 0), Vector2(18, -13)]
			label_str = "DIAGONAL KLAX"
			badge_col = Color(0.98, 0.56, 0.18)
		else:
			offsets = [Vector2(-20, 0), Vector2(0, 0), Vector2(20, 0)]
			label_str = "HORIZONTAL KLAX"
			badge_col = Color(0.18, 0.72, 0.96)

		draw_line(diag_c + offsets[0], diag_c + offsets[2], S.INK, 6.0)
		draw_line(diag_c + offsets[0], diag_c + offsets[2], S.WARN, 3.0)
		for idx in offsets.size():
			var pt: Vector2 = diag_c + offsets[idx]
			var b_sz := Vector2(14.0, 11.0)
			var br := Rect2(pt - b_sz * 0.5, b_sz)
			rr(br.grow(2.2), S.STICKER, 4.0)
			rr(br.grow(1.2), S.INK, 3.5)
			rr(br, badge_col.lightened(0.15 * pulse), 3.0)

		# Highlighted pill label at bottom of sticker card
		var pill := Rect2(card.position.x + 10.0, card.position.y + 78.0, card.size.x - 20.0, 22.0)
		rr(pill.grow(1.8), S.INK, 9.0)
		rr(pill, badge_col, 8.0)
		ctext(label_str, cx, pill.position.y + 16.0, 14, S.STICKER)


func _draw_sound_button() -> void:
	var sr: Rect2 = g.buttons["sound"]
	var c := sr.get_center()
	var sbox := Rect2(c - Vector2(26, 26), Vector2(52, 52))
	paper_card(sbox, S.PANEL_LIGHT, 16.0, Vector2(0, 4), 2.5, 2.2)
	var col: Color = S.INK if g.sound_on else S.DIM
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-14, -5), c + Vector2(-7, -5), c + Vector2(2, -13),
		c + Vector2(2, 13), c + Vector2(-7, 5), c + Vector2(-14, 5)]), col)
	if g.sound_on:
		draw_arc(c + Vector2(2, 0), 8.0, -0.85, 0.85, 12, col, 2.8)
		draw_arc(c + Vector2(2, 0), 14.0, -0.85, 0.85, 12, col, 2.8)
	else:
		draw_line(c + Vector2(6, -7), c + Vector2(17, 7), S.DANGER, 3.2)
		draw_line(c + Vector2(17, -7), c + Vector2(6, 7), S.DANGER, 3.2)


func _draw_buttons() -> void:
	var specs := {
		"flip": ["FLIP", "swipe up"],
		"drop": ["DROP", "tap your lane"],
	}
	for key in specs:
		var r: Rect2 = g.buttons[key]
		var lit: float = g.button_flash[key]
		var fill: Color = S.PANEL_LIGHT.lerp(S.WARN.lightened(0.35), lit)
		paper_card(r, fill, 26.0, Vector2(0, 6), 3.5, 2.8)
		if key == "drop" and not g.held.is_empty():
			var tc: Color = S.tile_color(g.held.back())
			var badge := Rect2(r.position.x + 16.0, r.position.y + 18.0, 14.0, r.size.y - 36.0)
			rr(badge.grow(2.0), S.INK, 8.0)
			rr(badge, tc, 6.0)
		ctext(specs[key][0], r.get_center().x, r.get_center().y + 4.0, 38, S.TEXT)
		ctext(specs[key][1], r.get_center().x, r.get_center().y + 36.0, 18, S.DIM)


# ---------------------------------------------------------------------------
# Paper Mario Sticker Overlays (Menu, Pause, Game Over)
# ---------------------------------------------------------------------------

func _button(rect: Rect2, label: String, primary: bool) -> void:
	var fill: Color = S.WARN if primary else S.PANEL_LIGHT
	paper_card(rect, fill, rect.size.y * 0.48, Vector2(0, 7), 4.0, 3.0)
	ctext(label, rect.get_center().x, rect.get_center().y + 13.0, 36 if primary else 30, S.STICKER if primary else S.TEXT)


func _dim() -> void:
	draw_rect(Rect2(Vector2.ZERO, g.vp).grow(40.0), Color(0.18, 0.13, 0.24, 0.58))


func _draw_menu() -> void:
	_dim()
	var cx: float = g.vp.x * 0.5
	var letters := "FLAX"
	var card_w := 124.0
	var card_h := 148.0
	var gap := 14.0
	var total_w: float = float(letters.length()) * card_w + float(letters.length() - 1) * gap
	var start_x: float = cx - total_w * 0.5
	var base_y: float = g.vp.y * 0.22

	# Bouncing Paper Mario letter cutout cards!
	for i in letters.length():
		var bob: float = sin(g.time * 2.6 + float(i) * 0.85) * 9.0
		var tilt: float = sin(g.time * 1.8 + float(i) * 1.4) * 0.065
		var card_c := Vector2(start_x + float(i) * (card_w + gap) + card_w * 0.5, base_y + bob)
		draw_set_transform(card_c, tilt, Vector2.ONE)
		var crect := Rect2(-Vector2(card_w, card_h) * 0.5, Vector2(card_w, card_h))
		paper_card(crect, S.tile_color(i), 24.0, Vector2(0, 8), 4.5, 3.2)
		ctext(letters[i], 0.0, 38.0, 112, S.STICKER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	ctext("catch  ·  stack  ·  match", cx, base_y + 118.0, 28, S.STICKER)

	if g.best > 0:
		var best_card := Rect2(cx - 140.0, g.vp.y * 0.42, 280.0, 56.0)
		paper_card(best_card, S.PANEL_LIGHT, 20.0, Vector2(0, 5), 3.0, 2.4)
		ctext("BEST  %d" % g.best, cx, best_card.get_center().y + 11.0, 30, S.TEXT)

	var pulse: float = 1.0 + 0.03 * sin(g.time * 4.0)
	var a: Rect2 = g.buttons["ov_a"]
	var grown := Rect2(a.get_center() - a.size * pulse * 0.5, a.size * pulse)
	_button(grown, "TAP TO PLAY!", true)

	var info_card := Rect2(cx - 295.0, g.vp.y * 0.72, 590.0, 175.0)
	paper_card(info_card, S.PANEL_LIGHT, 24.0, Vector2(0, 7), 3.5, 2.6)
	var hy: float = info_card.position.y + 42.0
	ctext("Catch sticker tiles & drop them in the bins!", cx, hy, 23, S.TEXT)
	ctext("Line up 3 of a color: across, up, or diagonal.", cx, hy + 36.0, 23, S.TEXT)
	ctext("Drag to move  ·  tap lane to drop  ·  swipe up to flip", cx, hy + 80.0, 20, S.DIM)
	ctext("Keys: arrows / A D move, space drops, up flips", cx, hy + 112.0, 18, S.DIM)


func _draw_pause() -> void:
	_dim()
	var cx: float = g.vp.x * 0.5
	var pcard := Rect2(cx - 220.0, g.vp.y * 0.28, 440.0, 120.0)
	paper_card(pcard, S.PANEL_LIGHT, 28.0, Vector2(0, 8), 4.0, 3.0)
	ctext("PAUSED", cx, pcard.get_center().y + 28.0, 80, S.WARN)
	_button(g.buttons["ov_a"], "RESUME", true)
	_button(g.buttons["ov_b"], "QUIT", false)


func _draw_game_over() -> void:
	_dim()
	var cx: float = g.vp.x * 0.5
	var card := Rect2(cx - 250.0, g.vp.y * 0.125, 500.0, 360.0)
	paper_card(card, S.PANEL_LIGHT, 30.0, Vector2(0, 10), 4.5, 3.2)

	ctext("GAME OVER", cx, g.vp.y * 0.21, 72, S.DANGER)
	ctext("SCORE", cx, g.vp.y * 0.265, 22, S.DIM)
	ctext(str(g.score), cx, g.vp.y * 0.265 + 74.0, 86, S.TEXT)
	if g.new_best:
		var pulse: float = 0.75 + 0.25 * sin(g.time * 7.0)
		ctext("NEW BEST!", cx, g.vp.y * 0.265 + 124.0, 34, Color(S.WARN, pulse))
	else:
		ctext("BEST  %d" % g.best, cx, g.vp.y * 0.265 + 124.0, 28, S.DIM)
	var kpi_pct: int = int(round(g.engagement.kpi_ad_watch_probability * 100.0))
	ctext("Wave %d  ·  Continue KPI %d%%" % [g.wave, kpi_pct], cx, g.vp.y * 0.265 + 162.0, 22, S.DIM)

	var ready: bool = g.game_over_t >= 0.7
	if ready:
		if g.engagement.can_offer_ad_continue():
			var ad_rect: Rect2 = g.buttons["ov_ad"]
			paper_card(ad_rect, S.GOOD, ad_rect.size.y * 0.48, Vector2(0, 7), 4.0, 3.0)
			ctext("WATCH AD  +2 LIVES", ad_rect.get_center().x, ad_rect.get_center().y + 12.0, 34, S.STICKER)
		_button(g.buttons["ov_a"], "PLAY AGAIN", true)
		_button(g.buttons["ov_b"], "MENU", false)
