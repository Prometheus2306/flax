# Tile.gd
extends Area2D
class_name Tile
var colors = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color.PURPLE]
var current_color: Color

# Signal to notify when a tile is missed
signal tile_missed

# --- 2.5D Perspective Variables ---
const TOP_Y = 150.0
const BOTTOM_Y = 950.0
const START_SCALE = 0.2
const END_SCALE = 1.0
var speed = 200.0

func _ready():
	
		# Add the tile to the "tiles" group
	add_to_group("tiles")
	
	# Randomly assign a color
	current_color = colors[randi() % colors.size()]
	$ColorRect.color = current_color
	
	# Set the initial scale
	scale = Vector2(START_SCALE, START_SCALE)

func _process(delta):
	# Move the tile down the screen
	position.y += speed * delta

	# Calculate how far down the screen the tile is (a value from 0.0 to 1.0)
	var progress = (position.y - TOP_Y) / (BOTTOM_Y - TOP_Y)
	progress = clamp(progress, 0.0, 1.0) # Ensure it stays between 0 and 1

	# Linearly interpolate the scale based on the progress
	# This makes the tile get bigger as it moves down
	var new_scale = lerp(START_SCALE, END_SCALE, progress)
	scale = Vector2(new_scale, new_scale)
	
	# UPDATED: Emit a signal when the tile is missed
	if position.y > BOTTOM_Y + 20: # A little past the paddle's line
		emit_signal("tile_missed")
		queue_free()
