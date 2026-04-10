# Main.gd
extends Node2D

@onready var paddle = $Paddle
@onready var tile_spawner = $TileSpawner
@onready var bins = $Bins
@onready var drop_button = $UI/DropButton

var score = 0
var lives = 3
var bin_contents = [[], [], [], [], []] # 2D array for the 5 bins
var pending_drop_animations = 0
const BIN_TILE_SIZE = Vector2(70, 16)
var runtime_tile_size = BIN_TILE_SIZE
const MAX_BIN_HEIGHT = 5
const DEBUG_TOOLS_ENABLED = true
var DESKTOP_DEBUG_INPUT_ENABLED = OS.has_feature("editor")
const USE_REFERENCE_BELT_BACKGROUND = true
const CANDY_COLORS = [
	Color("ff6f73"),
	Color("6ec1ff"),
	Color("ffe26f"),
	Color("7de38c"),
	Color("d58cff")
]

# Preload the Tile scene
var TileScene = preload("res://tile.tscn")
# Preload our new DroppedTile script
var DroppedTile = preload("res://dropped_tile.gd")
var RejectedTile = preload("res://rejected_tile.gd")
# Preload debug script s
var DebugTools = preload("res://debug_tools.gd")
var belt_background_texture: Texture2D
var landing_tray_texture: Texture2D


# Runs once when the scene is ready.
# Wires up timer/button signals and paints the initial HUD.
func _ready():
	if ResourceLoader.exists("res://assets/belt_background.png"):
		belt_background_texture = load("res://assets/belt_background.png")
	else:
		push_warning("Missing belt background at res://assets/belt_background.png")
	if ResourceLoader.exists("res://assets/landing tray.png"):
		landing_tray_texture = load("res://assets/landing tray.png")
	else:
		push_warning("Missing landing tray at res://assets/landing tray.png")
	tile_spawner.timeout.connect(_on_tile_spawner_timeout)
	drop_button.pressed.connect(_on_drop_button_pressed) 
	apply_candy_style()
	update_ui()
	if DEBUG_TOOLS_ENABLED and DESKTOP_DEBUG_INPUT_ENABLED:
		DebugTools.print_debug_hotkeys()

# Handles global keyboard input for gameplay and debug shortcuts.
# Uses `_input` so controls still work even when UI nodes consume events.
func _input(event):
	if event is InputEventKey and get_viewport().gui_get_focus_owner() != null:
		return
	var is_key_repeat = event is InputEventKey and event.echo
	if DESKTOP_DEBUG_INPUT_ENABLED and not is_key_repeat and event.is_action_pressed("ui_accept"):
		_on_drop_button_pressed()
		return
	
	if not DEBUG_TOOLS_ENABLED or not DESKTOP_DEBUG_INPUT_ENABLED:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		DebugTools.handle_debug_hotkey(self, event)

# Refreshes HUD labels from current gameplay state.
func update_ui():
	$UI/ScoreLabel.text = "Score: " + str(score)
	$UI/LivesLabel.text = "Lives: " + str(lives)

# Handles end-of-run reset and reloads the main scene.
func game_over():
	# reset the score and lives and reload
	score = 0
	lives = 3
	get_tree().reload_current_scene()

# In Main.gd

# Spawns one moving tile at the top-center of the conveyor polygon.
func _on_tile_spawner_timeout():
	# Get the conveyor belt node
	var conveyor = $ConveyorBelt
	
	# Get the first two points of the polygon (top-left and top-right)
	var top_left = conveyor.polygon[0]
	var top_right = conveyor.polygon[1]
	
	# Calculate the center X position between those two points
	var spawn_x = (top_left.x + top_right.x) / 2
	# Use the Y position of the top edge
	var spawn_y = top_left.y
	
	# Convert conveyor-local spawn point to world-space to remain correct
	# even if parent transforms/layouts change.
	var spawn_position = conveyor.to_global(Vector2(spawn_x, spawn_y))

	# create new tile
	var new_tile = TileScene.instantiate()
	if new_tile.has_method("set_scale_bounds_from_target_size"):
		new_tile.set_scale_bounds_from_target_size(runtime_tile_size)
	new_tile.tile_missed.connect(_on_tile_missed)
	add_child(new_tile)
	# Use world-space assignment after parenting for transform safety.
	new_tile.global_position = spawn_position

# Function to handle when a tile is missed
# Applies penalty when a falling tile reaches the miss line.
func _on_tile_missed():
	lives -= 1
	update_ui()
	if lives <= 0:
		game_over()

# Attempts to drop the top held tile into the bin under the paddle.
# Also enforces bin overflow loss and triggers combo resolution.
func _on_drop_button_pressed():
	# Keep drops deterministic: wait until previous drop animation lands.
	# This prevents combo checks from racing against in-flight visuals.
	if pending_drop_animations > 0:
		return
	var bin_index = get_target_bin_index_from_paddle()
	if bin_index < 0:
		return
	
	var bin_node = bins.get_child(bin_index)
	# Only evaluate overflow if we actually have a tile to drop.
	var dropped_tile_color = paddle.drop_tile()
	if dropped_tile_color == null:
		return
	if bin_contents[bin_index].size() >= MAX_BIN_HEIGHT:
		spawn_rejected_falling_tile(dropped_tile_color, bin_index)
		lives -= 1
		update_ui()
		if lives <= 0:
			game_over()
		return
	
	# Add points for each tile dropped
	score += 10
	bin_contents[bin_index].append(dropped_tile_color)
	
	# --- Create and animate the dropped tile ---
	var new_dropped_tile = create_candy_stack_tile(dropped_tile_color)
	
	# Calculate where it should land in the stack
	var stack_height = bin_contents[bin_index].size()
	var target_position = get_bin_tile_target_position(bin_index, stack_height)
	
	# Set the script and tell it where to go
	new_dropped_tile.set_script(DroppedTile)
	new_dropped_tile.target_position = target_position
	new_dropped_tile.landed.connect(_on_dropped_tile_landed.bind(bin_index), CONNECT_ONE_SHOT)
	new_dropped_tile.z_as_relative = false
	new_dropped_tile.z_index = 6

	# Add to the main scene to animate
	bin_node.add_child(new_dropped_tile)
	# Start from paddle visual center; tile origin is top-left.
	new_dropped_tile.global_position = Vector2(
		get_paddle_center_x() - (runtime_tile_size.x * 0.5),
		paddle.global_position.y
	)
	pending_drop_animations += 1

func _on_dropped_tile_landed(bin_index):
	# Track outstanding drop animations; only resolve KLAXes once all
	# in-flight drops are settled so board state and visuals stay in sync.
	pending_drop_animations = max(0, pending_drop_animations - 1)
	if pending_drop_animations > 0:
		return
	# Resolve combinations only after drop animation finishes.
	# This avoids visual/state conflicts during in-flight tile movement.
	process_flax_checks(bin_index)

# Main function to trigger all Klax checks
# Resolves all possible combos iteratively until the board is stable.
# The unused parameter is kept for compatibility with older call sites.
func process_flax_checks(_bin_index):
	while true:
		if check_for_vertical_flax():
			continue
		if check_for_horizontal_flaxes():
			continue
		if check_for_diagonal_flaxes():
			continue
		break
	update_ui()

# Finds and resolves one vertical KLAX (3 same colors in one bin top).
# Returns true if a combo was removed; otherwise false.
func check_for_vertical_flax() -> bool:
	for bin_index in range(bin_contents.size()):
		var current_bin = bin_contents[bin_index]
		# Check for a vertical stack of 3 of the same color
		if current_bin.size() >= 3:
			var last_color = current_bin.back()
			if current_bin[-2] == last_color and current_bin[-3] == last_color:
				score += 100 # Bonus points for a Klax
				for _j in range(3):
					current_bin.pop_back()
				rebuild_bin_visual(bin_index)
				return true
	return false

# check for horizontal klaxes
# Finds and resolves one horizontal KLAX across 3 neighboring bins.
# Returns true if a combo was removed; otherwise false.
func check_for_horizontal_flaxes() -> bool:
	# Iterate through the three possible 3-bin windows: [0,1,2], [1,2,3], [2,3,4]
	for i in range(3):
		var bin1 = bin_contents[i]
		var bin2 = bin_contents[i+1]
		var bin3 = bin_contents[i+2]
		
		# Skip if any bin in the window is empty
		if bin1.is_empty() or bin2.is_empty() or bin3.is_empty():
			continue

		# Horizontal Klax: 3 same-colored tiles at the same height.
		# Scan all valid heights, not only the top tiles.
		var max_common_height = mini(bin1.size(), mini(bin2.size(), bin3.size()))
		for height in range(max_common_height, 0, -1):
			var idx = height - 1
			if bin1[idx] == bin2[idx] and bin2[idx] == bin3[idx]:
				score += 150
				
				bin1.remove_at(idx)
				bin2.remove_at(idx)
				bin3.remove_at(idx)
				rebuild_bin_visual(i)
				rebuild_bin_visual(i + 1)
				rebuild_bin_visual(i + 2)
				return true # Exit to start the check over from the beginning
	return false


# check for diagonal klaxes
# Finds and resolves one diagonal KLAX across 3 neighboring bins.
# Supports both rising and falling diagonals on top stack tiles.
func check_for_diagonal_flaxes() -> bool:
	# Iterate through the three possible 3-bin windows: [0,1,2], [1,2,3], [2,3,4]
	for i in range(3):
		var bin1 = bin_contents[i]
		var bin2 = bin_contents[i+1]
		var bin3 = bin_contents[i+2]
		
		# Skip if any bin in the window is empty
		if bin1.is_empty() or bin2.is_empty() or bin3.is_empty():
			continue

		var max_h = maxi(bin1.size(), maxi(bin2.size(), bin3.size()))
		for h in range(max_h, 0, -1):
			# Diagonal Klax (Up-Right): heights h, h+1, h+2
			var up_idx_1 = h - 1
			var up_idx_2 = h
			var up_idx_3 = h + 1
			if up_idx_3 < bin3.size() and up_idx_2 < bin2.size() and up_idx_1 < bin1.size():
				if bin1[up_idx_1] == bin2[up_idx_2] and bin2[up_idx_2] == bin3[up_idx_3]:
					score += 200
					bin1.remove_at(up_idx_1)
					bin2.remove_at(up_idx_2)
					bin3.remove_at(up_idx_3)
					rebuild_bin_visual(i)
					rebuild_bin_visual(i + 1)
					rebuild_bin_visual(i + 2)
					return true # Exit to start the check over from the beginning
			
			# Diagonal Klax (Down-Right): heights h+2, h+1, h
			var down_idx_1 = h + 1
			var down_idx_2 = h
			var down_idx_3 = h - 1
			if down_idx_1 < bin1.size() and down_idx_2 < bin2.size() and down_idx_3 < bin3.size():
				if bin1[down_idx_1] == bin2[down_idx_2] and bin2[down_idx_2] == bin3[down_idx_3]:
					score += 200
					bin1.remove_at(down_idx_1)
					bin2.remove_at(down_idx_2)
					bin3.remove_at(down_idx_3)
					rebuild_bin_visual(i)
					rebuild_bin_visual(i + 1)
					rebuild_bin_visual(i + 2)
					return true # Exit to start the check over from the beginning
	return false

# Removes only generated stack-tile visuals from a bin node.
# This keeps authored bin children (Area2D/ColorRect) intact.
func clear_bin_visual(bin_node):
	for child in bin_node.get_children():
		if child.has_meta("is_stack_tile") and child.get_meta("is_stack_tile"):
			# Use deferred deletion because this can run during signal emission.
			child.queue_free()

# Rebuilds one bin's stacked tile visuals from `bin_contents`.
# Used after combo removals to keep visuals and logic synchronized.
func rebuild_bin_visual(bin_index):
	var bin_node = bins.get_child(bin_index)
	clear_bin_visual(bin_node)
	for stack_index in range(bin_contents[bin_index].size()):
		var tile_color = bin_contents[bin_index][stack_index]
		var tile = create_candy_stack_tile(tile_color)
		bin_node.add_child(tile)
		tile.global_position = get_bin_tile_target_position(bin_index, stack_index + 1)

# Converts a bin index + stack height into world-space tile position.
# Height is 1-based: 1 is bottom tile, increasing upward.
func get_bin_tile_target_position(bin_index, stack_height) -> Vector2:
	var bin_node = bins.get_child(bin_index)
	var bin_visual = bin_node.get_node("ColorRect")
	var bin_scale = bin_node.global_scale
	# Convert bin and tile dimensions into the same (scaled) world-space
	# units so placement remains correct after layout scaling changes.
	var scaled_bin_size = Vector2(
		bin_visual.size.x * bin_scale.x,
		bin_visual.size.y * bin_scale.y
	)
	var scaled_tile_size = Vector2(
		runtime_tile_size.x * bin_node.global_scale.x,
		runtime_tile_size.y * bin_node.global_scale.y
	)
	var target_x = bin_visual.global_position.x + (scaled_bin_size.x - scaled_tile_size.x) / 2.0
	var target_y = bin_visual.global_position.y + scaled_bin_size.y - (stack_height * scaled_tile_size.y)
	return Vector2(target_x, target_y)

# Finds which bin is currently "under" the paddle by horizontal position.
# This avoids brittle Area2D layer/mask overlap dependencies.
func get_target_bin_index_from_paddle() -> int:
	var paddle_center_x = get_paddle_center_x()
	for i in range(bins.get_child_count()):
		var bin_node = bins.get_child(i)
		var bin_visual = bin_node.get_node("ColorRect")
		var left = bin_visual.global_position.x
		var right = left + (bin_visual.size.x * bin_node.global_scale.x)
		# Pick the bin whose visible x-range contains the paddle center.
		if paddle_center_x >= left and paddle_center_x <= right:
			return i
	return -1

# Returns paddle center x in world-space for robust bin targeting/drop alignment.
func get_paddle_center_x() -> float:
	if paddle.has_node("PaddleSprite"):
		var paddle_visual = paddle.get_node("PaddleSprite") as Sprite2D
		# Sprite2D is centered by default, so global_position is already center.
		if paddle_visual:
			return paddle_visual.global_position.x
	if paddle.has_node("ColorRect"):
		var paddle_visual = paddle.get_node("ColorRect") as ColorRect
		if paddle_visual:
			# `ColorRect` (Control) has no `global_scale`; use parent node scale.
			return paddle_visual.global_position.x + (paddle_visual.size.x * paddle.global_scale.x * 0.5)
	return paddle.global_position.x

# Spawns a dropped tile that keeps falling when a bin is full.
# This tile is intentionally not connected to miss-life logic because
# the life penalty is applied immediately by the bin rejection.
func spawn_rejected_falling_tile(tile_color, bin_index):
	# Build a transient brick visual and attach rejection physics behavior.
	var rejected_tile = create_candy_stack_tile(tile_color)
	rejected_tile.set_script(RejectedTile)
	rejected_tile.global_position = paddle.global_position
	rejected_tile.z_as_relative = false
	rejected_tile.z_index = 6
	
	# Push rejected tiles away from the bin center for a clear "bounce off" cue.
	var bin_node = bins.get_child(bin_index)
	var bin_visual = bin_node.get_node("ColorRect")
	var bin_center_x = bin_visual.global_position.x + (bin_visual.size.x * bin_node.global_scale.x * 0.5)
	var push_dir = sign(rejected_tile.global_position.x - bin_center_x)
	if push_dir == 0:
		push_dir = 1 if (bin_index % 2 == 0) else -1
	
	rejected_tile.launch_velocity = Vector2(340.0 * push_dir, -180.0)
	add_child(rejected_tile)

# Applies a bright "candy" visual treatment to HUD and playfield.
func apply_candy_style():
	if USE_REFERENCE_BELT_BACKGROUND:
		apply_reference_belt_background()
		apply_reference_layout()
	else:
		build_perspective_backdrop()
		build_conveyor_plane_visual()
	# Keep unused screen regions pure black behind all art.
	RenderingServer.set_default_clear_color(Color.BLACK)
	$ConveyorBelt.color = Color(0, 0, 0, 0)
	
	var score_label = $UI/ScoreLabel
	var lives_label = $UI/LivesLabel
	score_label.add_theme_color_override("font_color", Color("f4f7ff"))
	lives_label.add_theme_color_override("font_color", Color("f4f7ff"))
	score_label.add_theme_color_override("font_outline_color", Color("060b1f"))
	lives_label.add_theme_color_override("font_outline_color", Color("060b1f"))
	score_label.add_theme_constant_override("outline_size", 7)
	lives_label.add_theme_constant_override("outline_size", 7)
	score_label.add_theme_font_size_override("font_size", 40)
	lives_label.add_theme_font_size_override("font_size", 40)
	score_label.position = Vector2(178, 318)
	lives_label.position = Vector2(178, 360)
	
	var button_visual = $UI/DropButton/ColorRect
	# Remove the temporary red-square look; keep TouchScreenButton interaction.
	button_visual.visible = false
	
	for i in range(bins.get_child_count()):
		var bin_visual = bins.get_child(i).get_node_or_null("ColorRect")
		if bin_visual == null:
			continue
		if USE_REFERENCE_BELT_BACKGROUND:
			# Keep collision/placement rect but let tray PNG provide visuals.
			bin_visual.color = color_with_alpha("254278", 0.08)
		else:
			# Bins are neutral machine slots; color should come from tiles only.
			bin_visual.color = color_with_alpha("cdd4e8", 0.16)
	if not USE_REFERENCE_BELT_BACKGROUND:
		build_bin_slot_planes()

func apply_reference_belt_background():
	var old = get_node_or_null("ReferenceBackground")
	if old:
		old.queue_free()
	if belt_background_texture == null:
		return
	
	var bg = Sprite2D.new()
	bg.name = "ReferenceBackground"
	bg.texture = belt_background_texture
	bg.centered = false
	bg.position = Vector2.ZERO
	bg.z_as_relative = false
	# Force reference background fully behind gameplay/UI layers.
	bg.z_index = -1000
	add_child(bg)
	move_child(bg, 0)
	
	# Use the full reference image (no cropping).
	bg.region_enabled = false
	
	# Fit full image to width while keeping aspect ratio.
	var tex_size = belt_background_texture.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		var scale_ratio = 700.0 / tex_size.x
		bg.scale = Vector2.ONE * scale_ratio
		var draw_size = tex_size * scale_ratio
		bg.position = Vector2((720.0 - draw_size.x) * 0.5, 0.0)

# Applies a readability-focused layout tuned for the reference belt image.
func apply_reference_layout():
	# Hide procedural conveyor because the reference image already contains one.
	$ConveyorBelt.visible = false
	# Reposition/scale core gameplay nodes to fit the composition in the image.
	bins.scale = Vector2(0.58, 0.58)
	bins.position = Vector2(170, 448)
	normalize_bin_visuals_and_tile_size()
	paddle.scale = Vector2(0.78, 0.78)
	paddle.position = Vector2(307, 940)
	$UI/ScoreLabel.position = Vector2(30, 44)
	$UI/LivesLabel.position = Vector2(494, 44)
	$UI/DropButton.position = Vector2(628, 1136)
	# Any scale/position change can shift stack placement, so normalize and
	# rebuild all bin visuals immediately after layout updates.
	for i in range(bin_contents.size()):
		rebuild_bin_visual(i)

# Keeps every bin visually identical and derives tile size from
# bin height and `MAX_BIN_HEIGHT` so stacks stay proportional.
func normalize_bin_visuals_and_tile_size():
	var uniform_bin_size = Vector2(104, 178)
	var uniform_y = 976.0
	var uniform_start_x = 56.0
	var uniform_spacing = 118.0
	
	for i in range(bins.get_child_count()):
		var bin_node = bins.get_child(i)
		# Normalize per-bin transforms first; some scene bins have different
		# authored offsets which otherwise create uneven apparent heights.
		bin_node.position = Vector2.ZERO
		bin_node.scale = Vector2.ONE
		var bin_visual = bin_node.get_node("ColorRect")
		bin_visual.position = Vector2(uniform_start_x + (i * uniform_spacing), uniform_y)
		bin_visual.size = uniform_bin_size
	
	# One single tray image should visually cover all 5 bins as one landing area.
	var tray_x = uniform_start_x
	var tray_y = uniform_y
	var tray_width = ((bins.get_child_count() - 1) * uniform_spacing) + uniform_bin_size.x
	var tray_size = Vector2(tray_width, uniform_bin_size.y)
	apply_landing_tray_visual_single(Vector2(tray_x, tray_y), tray_size)
	
	# Final landed tile height is exactly one bin slot:
	# bin_height divided by max tiles that fit in one bin.
	var per_tile_height = uniform_bin_size.y / float(MAX_BIN_HEIGHT)
	var per_tile_width = floor(uniform_bin_size.x * 0.72)
	runtime_tile_size = Vector2(per_tile_width, per_tile_height)

# Adds/updates one sprite-based tray visual spanning all bins.
func apply_landing_tray_visual_single(top_left: Vector2, target_size: Vector2):
	# Remove accidental legacy tray attached under `Bins`.
	var legacy = bins.get_node_or_null("LandingTraySprite")
	if legacy:
		legacy.queue_free()
	
	# Keep the tray outside the bin container so bin child loops remain gameplay-only.
	var sprite = get_node_or_null("LandingTraySprite")
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "LandingTraySprite"
		sprite.centered = false
		sprite.z_as_relative = false
		sprite.z_index = 3
		add_child(sprite)
	if landing_tray_texture == null:
		return
	sprite.texture = landing_tray_texture
	sprite.position = top_left
	var tex_size = landing_tray_texture.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		sprite.scale = Vector2(target_size.x / tex_size.x, target_size.y / tex_size.y)

# Builds retro perspective grid + machine deck to push the 2.5D vibe.
func build_perspective_backdrop():
	var old = get_node_or_null("PerspectiveBackdrop")
	if old:
		old.queue_free()
	
	var backdrop = Node2D.new()
	backdrop.name = "PerspectiveBackdrop"
	add_child(backdrop)
	move_child(backdrop, 0)
	
	var horizon_y = 260.0
	var floor_bottom = 1240.0
	var top_left = Vector2(230, horizon_y)
	var top_right = Vector2(490, horizon_y)
	var bottom_left = Vector2(20, floor_bottom)
	var bottom_right = Vector2(700, floor_bottom)
	
	var plane = Polygon2D.new()
	plane.polygon = PackedVector2Array([top_left, top_right, bottom_right, bottom_left])
	plane.color = color_with_alpha("101e3c", 0.75)
	backdrop.add_child(plane)
	
	# Horizontal grid lines constrained to trapezoid edges.
	for i in range(15):
		var t = float(i) / 14.0
		var y = lerp(horizon_y, floor_bottom, t * t)
		var left_x = lerp(top_left.x, bottom_left.x, t)
		var right_x = lerp(top_right.x, bottom_right.x, t)
		var line = Line2D.new()
		line.width = lerp(1.0, 2.8, t)
		line.default_color = color_with_alpha("3bd3ff", 0.24 + t * 0.4)
		line.add_point(Vector2(left_x, y))
		line.add_point(Vector2(right_x, y))
		backdrop.add_child(line)
	
	# Vertical perspective lines from bottom edge to top edge.
	for i in range(12):
		var t = float(i) / 11.0
		var x_bottom = lerp(bottom_left.x, bottom_right.x, t)
		var x_top = lerp(top_left.x, top_right.x, t)
		var line = Line2D.new()
		line.width = 1.5
		line.default_color = color_with_alpha("52ffd8", 0.3)
		line.add_point(Vector2(x_bottom, floor_bottom))
		line.add_point(Vector2(x_top, horizon_y))
		backdrop.add_child(line)
	
	# Machine/front deck panel near bins.
	var deck = ColorRect.new()
	deck.color = color_with_alpha("192956", 0.9)
	deck.position = Vector2(70, 1080)
	deck.size = Vector2(580, 140)
	backdrop.add_child(deck)
	
	var deck_highlight = ColorRect.new()
	deck_highlight.color = color_with_alpha("6ec1ff", 0.25)
	deck_highlight.position = Vector2(8, 8)
	deck_highlight.size = Vector2(564, 8)
	deck.add_child(deck_highlight)

# Builds a dedicated pseudo-3D conveyor with rails and slats.
# This replaces the flat polygon look with a KLAX-style machine plane.
func build_conveyor_plane_visual():
	var conveyor = $ConveyorBelt
	var existing = conveyor.get_node_or_null("ConveyorVisual")
	if existing:
		existing.queue_free()
	
	var visual = Node2D.new()
	visual.name = "ConveyorVisual"
	conveyor.add_child(visual)
	
	var poly = conveyor.polygon
	var tl = poly[0]
	var tr = poly[1]
	var br = poly[2]
	var bl = poly[3]
	
	# Main top face.
	var top_face = Polygon2D.new()
	top_face.polygon = PackedVector2Array([tl, tr, br, bl])
	top_face.color = Color("2c2d63")
	visual.add_child(top_face)
	
	# Side rails.
	var left_rail = Polygon2D.new()
	left_rail.polygon = PackedVector2Array([
		tl + Vector2(-10, 2),
		tl + Vector2(8, 2),
		bl + Vector2(8, -6),
		bl + Vector2(-14, -2)
	])
	left_rail.color = Color("7fa2ff")
	visual.add_child(left_rail)
	
	var right_rail = Polygon2D.new()
	right_rail.polygon = PackedVector2Array([
		tr + Vector2(-8, 2),
		tr + Vector2(10, 2),
		br + Vector2(14, -2),
		br + Vector2(-8, -6)
	])
	right_rail.color = Color("7fa2ff")
	visual.add_child(right_rail)
	
	# Conveyor slats in perspective.
	for i in range(24):
		var t0 = float(i) / 24.0
		var t1 = float(i + 1) / 24.0
		var y_curve0 = t0 * t0
		var y_curve1 = t1 * t1
		
		var l0 = tl.lerp(bl, y_curve0)
		var r0 = tr.lerp(br, y_curve0)
		var l1 = tl.lerp(bl, y_curve1)
		var r1 = tr.lerp(br, y_curve1)
		
		var slat = Polygon2D.new()
		slat.polygon = PackedVector2Array([l0, r0, r1, l1])
		# Alternate cool steel and magenta strips like the cover art.
		if i % 3 == 0:
			slat.color = Color("7b4c8f")
		else:
			slat.color = Color("4d6cae")
		visual.add_child(slat)
	
	# Front machine lip to ground the belt.
	var front_lip = Polygon2D.new()
	front_lip.polygon = PackedVector2Array([
		bl + Vector2(-8, 6),
		br + Vector2(8, 6),
		br + Vector2(18, 34),
		bl + Vector2(-18, 34)
	])
	front_lip.color = Color("232c57")
	visual.add_child(front_lip)

# Adds pseudo-3D slot planes so bins read like embedded machine channels.
func build_bin_slot_planes():
	for i in range(bins.get_child_count()):
		var bin_node = bins.get_child(i)
		var existing_plane = bin_node.get_node_or_null("SlotPlane")
		if existing_plane:
			existing_plane.queue_free()
		
		var bin_visual = bin_node.get_node("ColorRect")
		var top = Vector2(bin_visual.position.x + 8, bin_visual.position.y + 6)
		var width = bin_visual.size.x - 16
		var depth = 14
		
		var slot = Node2D.new()
		slot.name = "SlotPlane"
		bin_node.add_child(slot)
		
		var top_face = Polygon2D.new()
		top_face.polygon = PackedVector2Array([
			top,
			top + Vector2(width, 0),
			top + Vector2(width - 8, depth),
			top + Vector2(8, depth)
		])
		top_face.color = Color("c2cbe2")
		slot.add_child(top_face)
		
		var front_face = Polygon2D.new()
		front_face.polygon = PackedVector2Array([
			top + Vector2(8, depth),
			top + Vector2(width - 8, depth),
			top + Vector2(width - 8, depth + 8),
			top + Vector2(8, depth + 8)
		])
		front_face.color = Color("7a839b")
		slot.add_child(front_face)

# Builds one glossy stack tile visual used in bins.
func create_candy_stack_tile(tile_color) -> Node2D:
	# Stack tiles are pseudo-3D polygon bricks so visuals match the scene style.
	var tile = Node2D.new()
	tile.set_meta("is_stack_tile", true)
	
	var w = runtime_tile_size.x
	var h = runtime_tile_size.y
	var d = 6.0
	var slant = 8.0
	
	# Top plane (trapezoid).
	var top_face = Polygon2D.new()
	top_face.polygon = PackedVector2Array([
		Vector2(0, d),
		Vector2(w, d),
		Vector2(w - slant, 0),
		Vector2(slant, 0)
	])
	top_face.color = tile_color.lightened(0.18)
	tile.add_child(top_face)
	
	# Front face.
	var front_face = Polygon2D.new()
	front_face.polygon = PackedVector2Array([
		Vector2(0, d),
		Vector2(w, d),
		Vector2(w, h),
		Vector2(0, h)
	])
	front_face.color = tile_color
	tile.add_child(front_face)
	
	# Right side face for depth.
	var right_face = Polygon2D.new()
	right_face.polygon = PackedVector2Array([
		Vector2(w, d),
		Vector2(w - slant, 0),
		Vector2(w - slant, h - d),
		Vector2(w, h)
	])
	right_face.color = tile_color.darkened(0.35)
	tile.add_child(right_face)
	
	# Brick studs on top plane.
	for stud_idx in range(2):
		var stud = Polygon2D.new()
		var sx = 18 + stud_idx * 26
		stud.polygon = PackedVector2Array([
			Vector2(sx, d - 1),
			Vector2(sx + 12, d - 1),
			Vector2(sx + 10, d - 4),
			Vector2(sx + 2, d - 4)
		])
		stud.color = tile_color.lightened(0.35)
		tile.add_child(stud)
	return tile

func color_with_alpha(hex_color: String, alpha: float) -> Color:
	# Small helper for readable color definitions with explicit alpha values.
	var c = Color(hex_color)
	c.a = alpha
	return c
