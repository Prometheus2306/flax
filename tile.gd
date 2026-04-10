# Tile.gd
extends Area2D
class_name Tile
var colors = [
	Color("ff6f73"),
	Color("6ec1ff"),
	Color("ffe26f"),
	Color("7de38c"),
	Color("d58cff")
]
var current_color: Color
var has_forced_color = false
var forced_color = Color.WHITE
var shadow_rect: ColorRect

# Signal to notify when a tile is missed
signal tile_missed

# --- 2.5D Perspective Variables ---
const TOP_Y = 150.0
const BOTTOM_Y = 950.0
var start_scale = 0.2
var end_scale = 1.0
var speed = 200.0

# Sets conveyor tile perspective scale so bottom-size matches target bounds.
func set_scale_bounds_from_target_size(target_size: Vector2):
	var height_scale = max(0.01, target_size.y / 10.0)
	var width_scale = max(0.01, target_size.x / 70.0)
	end_scale = min(height_scale, width_scale)
	start_scale = end_scale * 0.2

# Initializes a new falling tile with random color and base scale.
# Also registers this node in the catchable `tiles` group.
func _ready():
	
		# Add the tile to the "tiles" group
	add_to_group("tiles")
	
	# Use forced color when supplied (e.g. rejected bin drops), otherwise random.
	if has_forced_color:
		current_color = forced_color
	else:
		current_color = colors[randi() % colors.size()]
	$ColorRect.visible = false
	
	var w = 70.0
	var h = 10.0
	var d = 4.0
	var slant = 8.0
	
	var top_face = Polygon2D.new()
	top_face.polygon = PackedVector2Array([
		Vector2(0, d),
		Vector2(w, d),
		Vector2(w - slant, 0),
		Vector2(slant, 0)
	])
	top_face.color = current_color.lightened(0.18)
	add_child(top_face)
	
	var front_face = Polygon2D.new()
	front_face.polygon = PackedVector2Array([
		Vector2(0, d),
		Vector2(w, d),
		Vector2(w, h),
		Vector2(0, h)
	])
	front_face.color = current_color
	add_child(front_face)
	
	var right_face = Polygon2D.new()
	right_face.polygon = PackedVector2Array([
		Vector2(w, d),
		Vector2(w - slant, 0),
		Vector2(w - slant, h - d),
		Vector2(w, h)
	])
	right_face.color = current_color.darkened(0.35)
	add_child(right_face)
	
	for stud_idx in range(2):
		var stud = Polygon2D.new()
		var sx = 18 + stud_idx * 26
		stud.polygon = PackedVector2Array([
			Vector2(sx, d - 1),
			Vector2(sx + 12, d - 1),
			Vector2(sx + 10, d - 3),
			Vector2(sx + 2, d - 3)
		])
		stud.color = current_color.lightened(0.35)
		add_child(stud)
	
	shadow_rect = ColorRect.new()
	shadow_rect.color = Color(0, 0, 0, 0.18)
	shadow_rect.size = Vector2(48, 4)
	shadow_rect.position = Vector2(11, 12)
	add_child(shadow_rect)
	
	# Set the initial scale
	scale = Vector2(start_scale, start_scale)

# Advances tile movement and perspective scaling each frame.
# Emits `tile_missed` once the tile passes the miss threshold.
func _process(delta):
	# Move the tile down the screen
	position.y += speed * delta

	# Calculate how far down the screen the tile is (a value from 0.0 to 1.0)
	var progress = (position.y - TOP_Y) / (BOTTOM_Y - TOP_Y)
	progress = clamp(progress, 0.0, 1.0) # Ensure it stays between 0 and 1

	# Linearly interpolate the scale based on the progress
	# This makes the tile get bigger as it moves down
	var new_scale = lerp(start_scale, end_scale, progress)
	scale = Vector2(new_scale, new_scale)
	
	# Grow and darken shadow as tile "approaches" the camera.
	if shadow_rect:
		shadow_rect.scale.x = lerp(0.5, 1.2, progress)
		shadow_rect.modulate.a = lerp(0.08, 0.26, progress)
		shadow_rect.position.y = lerp(11.0, 14.0, progress)
	
	# UPDATED: Emit a signal when the tile is missed
	if position.y > BOTTOM_Y + 20: # A little past the paddle's line
		emit_signal("tile_missed")
		queue_free()
