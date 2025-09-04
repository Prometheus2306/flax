# Paddle.gd
extends CharacterBody2D

const SPEED = 400
var held_tiles = []
const MAX_TILES = 5

# Add this line to get a reference to the container
@onready var held_tiles_container = $VBoxContainer

# We'll use a variable to track movement direction
var move_direction = 0

func _unhandled_input(event):
	if event is InputEventScreenTouch:
		if event.is_pressed():
			if event.position.x < get_viewport_rect().size.x / 2:
				move_direction = -1
			else:
				move_direction = 1
		else:
			move_direction = 0

func _physics_process(_delta):
	velocity.x = move_direction * SPEED
	move_and_slide()

# This function is called by the Area2D's signal
func _on_area_2d_area_entered(area):
	# Check if the object that entered is a tile
	if area.is_in_group("tiles"):
		catch_tile(area)

func catch_tile(tile):
	if held_tiles.size() < MAX_TILES:
		# We store the tile's color, not the tile itself
		held_tiles.append(tile.current_color)
		tile.queue_free() # The tile is caught, so we remove it from the screen
		update_held_tiles_display()

func drop_tile():
	if held_tiles.size() > 0:
		# When dropping, we just need the color
		var tile_color = held_tiles.pop_back()
		update_held_tiles_display()
		return tile_color # Return the color to the Main script
	return null


func update_held_tiles_display():
	# First, clear all the old visual tiles
	for child in held_tiles_container.get_children():
		child.queue_free()

	# Create horizontal LIFO tile stack on paddle 
	for i in range(held_tiles.size() - 1, -1, -1):
		var tile_color = held_tiles[i]
		var visual_tile = ColorRect.new()
		visual_tile.custom_minimum_size = Vector2(70, 10) # Small squares
		visual_tile.color = tile_color
		
		held_tiles_container.add_child(visual_tile)
