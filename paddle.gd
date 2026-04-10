# Paddle.gd
extends CharacterBody2D

const SPEED = 400
var held_tiles = []
const MAX_TILES = 5
var DESKTOP_DEBUG_INPUT_ENABLED = OS.has_feature("editor")

# Add this line to get a reference to the container
@onready var held_tiles_container = $VBoxContainer
@onready var paddle_visual = $PaddleSprite

# We'll use a variable to track movement direction
var move_direction = 0

# Ensures the paddle body stays opaque and consistently styled.
func _ready():
	apply_paddle_visual_style()

# Handles touch input and converts screen taps into paddle direction.
# Left half moves left, right half moves right, release stops movement.
func _unhandled_input(event):
	if event is InputEventScreenTouch:
		if event.is_pressed():
			if event.position.x < get_viewport_rect().size.x / 2:
				move_direction = -1
			else:
				move_direction = 1
		else:
			move_direction = 0

# Applies horizontal velocity each physics tick and resolves movement.
func _physics_process(_delta):
	var active_direction = move_direction
	# Allow keyboard/controller movement only for local desktop debugging.
	if DESKTOP_DEBUG_INPUT_ENABLED:
		var axis = Input.get_axis("ui_left", "ui_right")
		if axis != 0.0:
			active_direction = axis
	
	velocity.x = active_direction * SPEED
	move_and_slide()
	
	# Keep paddle inside the visible play area.
	var viewport_width = get_viewport_rect().size.x
	var half_width = 37.0
	global_position.x = clamp(global_position.x, half_width, viewport_width - half_width)

# This function is called by the Area2D's signal
# Triggered when the paddle catch zone overlaps another Area2D.
# Only tile-group objects are accepted as catchable pieces.
func _on_area_2d_area_entered(area):
	# Check if the object that entered is a tile
	if area.is_in_group("tiles"):
		catch_tile(area)

# Adds a tile color to the held LIFO stack if capacity allows.
# The live falling tile is removed after being caught.
func catch_tile(tile):
	if held_tiles.size() < MAX_TILES:
		# We store the tile's color, not the tile itself
		held_tiles.append(tile.current_color)
		tile.queue_free() # The tile is caught, so we remove it from the screen
		update_held_tiles_display()

# Removes and returns the most recently caught tile color.
# Returns null when no tiles are available to drop.
func drop_tile():
	if held_tiles.size() > 0:
		# When dropping, we just need the color
		var tile_color = held_tiles.pop_back()
		update_held_tiles_display()
		return tile_color # Return the color to the Main script
	return null


# Rebuilds the paddle-held tile visuals from current stack contents.
# Display order is top-of-stack first so it matches drop behavior.
func update_held_tiles_display():
	# First, clear all the old visual tiles
	for child in held_tiles_container.get_children():
		child.queue_free()

	# Create horizontal LIFO tile stack on paddle 
	for i in range(held_tiles.size() - 1, -1, -1):
		var tile_color = held_tiles[i]
		var visual_tile = ColorRect.new()
		visual_tile.custom_minimum_size = Vector2(70, 16) # Small toy bricks
		visual_tile.color = tile_color
		var top_bevel = ColorRect.new()
		top_bevel.color = tile_color.lightened(0.3)
		top_bevel.custom_minimum_size = Vector2(66, 3)
		top_bevel.position = Vector2(2, 1)
		visual_tile.add_child(top_bevel)
		var bottom_shadow = ColorRect.new()
		bottom_shadow.color = tile_color.darkened(0.45)
		bottom_shadow.custom_minimum_size = Vector2(68, 3)
		bottom_shadow.position = Vector2(1, 13)
		visual_tile.add_child(bottom_shadow)
		for stud_idx in range(2):
			var stud = ColorRect.new()
			stud.color = tile_color.lightened(0.4)
			stud.custom_minimum_size = Vector2(12, 3)
			stud.position = Vector2(14 + stud_idx * 30, 4)
			visual_tile.add_child(stud)
		
		held_tiles_container.add_child(visual_tile)

func apply_paddle_visual_style():
	# Re-apply base visual state every frame to prevent accidental
	# transparency/modulate side effects from other scene updates.
	paddle_visual.visible = true
	paddle_visual.modulate = Color(1, 1, 1, 1)
	paddle_visual.self_modulate = Color(1, 1, 1, 1)
