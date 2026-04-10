# Main.gd
extends Node2D

@onready var paddle = $Paddle
@onready var tile_spawner = $TileSpawner
@onready var bins = $Bins
@onready var drop_button = $UI/DropButton

var score = 0
var lives = 3
var bin_contents = [[], [], [], [], []] # 2D array for the 5 bins
const BIN_TILE_SIZE = Vector2(70, 16)
const MAX_BIN_HEIGHT = 5
const DEBUG_TOOLS_ENABLED = true
var DESKTOP_DEBUG_INPUT_ENABLED = OS.has_feature("editor")
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


# Runs once when the scene is ready.
# Wires up timer/button signals and paints the initial HUD.
func _ready():
	tile_spawner.timeout.connect(_on_tile_spawner_timeout)
	drop_button.pressed.connect(_on_drop_button_pressed) 
	apply_candy_style()
	update_ui()
	if DEBUG_TOOLS_ENABLED and DESKTOP_DEBUG_INPUT_ENABLED:
		DebugTools.print_debug_hotkeys()

# Handles global keyboard input for gameplay and debug shortcuts.
# Uses `_input` so controls still work even when UI nodes consume events.
func _input(event):
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
	
	# Combine the conveyor's position with our calculated spawn point
	var spawn_position = conveyor.position + Vector2(spawn_x, spawn_y)

	# create new tile
	var new_tile = TileScene.instantiate()
	new_tile.tile_missed.connect(_on_tile_missed)
	# Use our new calculated position
	new_tile.position = spawn_position
	add_child(new_tile)

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
	
	# Start the tile at the paddle's position
	new_dropped_tile.global_position = paddle.global_position
	
	# Calculate where it should land in the stack
	var stack_height = bin_contents[bin_index].size()
	var target_position = get_bin_tile_target_position(bin_index, stack_height)
	
	# Set the script and tell it where to go
	new_dropped_tile.set_script(DroppedTile)
	new_dropped_tile.target_position = target_position

	# Add to the main scene to animate
	bin_node.add_child(new_dropped_tile)
	
	# check for flaxes
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
			child.queue_free()

# Rebuilds one bin's stacked tile visuals from `bin_contents`.
# Used after combo removals to keep visuals and logic synchronized.
func rebuild_bin_visual(bin_index):
	var bin_node = bins.get_child(bin_index)
	clear_bin_visual(bin_node)
	for stack_index in range(bin_contents[bin_index].size()):
		var tile_color = bin_contents[bin_index][stack_index]
		var tile = create_candy_stack_tile(tile_color)
		tile.global_position = get_bin_tile_target_position(bin_index, stack_index + 1)
		bin_node.add_child(tile)

# Converts a bin index + stack height into world-space tile position.
# Height is 1-based: 1 is bottom tile, increasing upward.
func get_bin_tile_target_position(bin_index, stack_height) -> Vector2:
	var bin_node = bins.get_child(bin_index)
	var bin_visual = bin_node.get_node("ColorRect")
	var target_x = bin_visual.global_position.x + (bin_visual.size.x - BIN_TILE_SIZE.x) / 2.0
	var target_y = bin_visual.global_position.y + bin_visual.size.y - (stack_height * BIN_TILE_SIZE.y)
	return Vector2(target_x, target_y)

# Finds which bin is currently "under" the paddle by horizontal position.
# This avoids brittle Area2D layer/mask overlap dependencies.
func get_target_bin_index_from_paddle() -> int:
	var paddle_center_x = paddle.global_position.x + 60.0
	for i in range(bins.get_child_count()):
		var bin_visual = bins.get_child(i).get_node("ColorRect")
		var left = bin_visual.global_position.x
		var right = left + bin_visual.size.x
		if paddle_center_x >= left and paddle_center_x <= right:
			return i
	return -1

# Spawns a dropped tile that keeps falling when a bin is full.
# This tile is intentionally not connected to miss-life logic because
# the life penalty is applied immediately by the bin rejection.
func spawn_rejected_falling_tile(tile_color, bin_index):
	var rejected_tile = create_candy_stack_tile(tile_color)
	rejected_tile.set_script(RejectedTile)
	rejected_tile.global_position = paddle.global_position
	
	var bin_visual = bins.get_child(bin_index).get_node("ColorRect")
	var bin_center_x = bin_visual.global_position.x + bin_visual.size.x * 0.5
	var push_dir = sign(rejected_tile.global_position.x - bin_center_x)
	if push_dir == 0:
		push_dir = 1
	
	rejected_tile.launch_velocity = Vector2(340.0 * push_dir, -180.0)
	add_child(rejected_tile)

# Applies a bright "candy" visual treatment to HUD and playfield.
func apply_candy_style():
	build_perspective_backdrop()
	build_conveyor_plane_visual()
	RenderingServer.set_default_clear_color(Color("0a0f1f"))
	$ConveyorBelt.color = Color(0, 0, 0, 0)
	
	var score_label = $UI/ScoreLabel
	var lives_label = $UI/LivesLabel
	score_label.add_theme_color_override("font_color", Color("f4f7ff"))
	lives_label.add_theme_color_override("font_color", Color("f4f7ff"))
	score_label.add_theme_color_override("font_outline_color", Color("101a42"))
	lives_label.add_theme_color_override("font_outline_color", Color("101a42"))
	score_label.add_theme_constant_override("outline_size", 5)
	lives_label.add_theme_constant_override("outline_size", 5)
	score_label.add_theme_font_size_override("font_size", 40)
	lives_label.add_theme_font_size_override("font_size", 40)
	score_label.position = Vector2(178, 318)
	lives_label.position = Vector2(178, 360)
	
	var button_visual = $UI/DropButton/ColorRect
	button_visual.color = Color("f04770")
	button_visual.size = Vector2(90, 90)
	button_visual.position = Vector2(-45, -45)
	
	for i in range(bins.get_child_count()):
		var bin_visual = bins.get_child(i).get_node("ColorRect")
		# Bins are neutral machine slots; color should come from tiles only.
		bin_visual.color = color_with_alpha("cdd4e8", 0.16)
	build_bin_slot_planes()

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
	var tile = Node2D.new()
	tile.set_meta("is_stack_tile", true)
	
	var w = BIN_TILE_SIZE.x
	var h = BIN_TILE_SIZE.y
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
	var c = Color(hex_color)
	c.a = alpha
	return c
