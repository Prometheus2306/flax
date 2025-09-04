# Main.gd
extends Node2D

@onready var paddle = $Paddle
@onready var tile_spawner = $TileSpawner
@onready var bins = $Bins
@onready var drop_button = $UI/DropButton

var score = 0
var lives = 3
var bin_contents = [[], [], [], [], []] # 2D array for the 5 bins

# Preload the Tile scene
var TileScene = preload("res://tile.tscn")
# Preload our new DroppedTile script
var DroppedTile = preload("res://dropped_tile.gd")


func _ready():
	tile_spawner.timeout.connect(_on_tile_spawner_timeout)
	drop_button.pressed.connect(_on_drop_button_pressed) 
	update_ui()

func update_ui():
	$UI/ScoreLabel.text = "Score: " + str(score)
	$UI/LivesLabel.text = "Lives: " + str(lives)

func game_over():
	# reset the score and lives and reload
	score = 0
	lives = 3
	get_tree().reload_current_scene()

# In Main.gd

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
func _on_tile_missed():
	lives -= 1
	update_ui()
	if lives <= 0:
		game_over()

func _on_drop_button_pressed():
	print("Button pressed")
	var paddle_area = paddle.get_node("Area2D")
	for i in range(bins.get_child_count()):
		var bin_node = bins.get_child(i)
		if paddle_area.overlaps_area(bin_node):
			
			# Ask the paddle to drop a tile and get its color
			var dropped_tile_color = paddle.drop_tile()
			if dropped_tile_color != null:
				# Add points for each tile dropped
				score+=10
				bin_contents[i].append(dropped_tile_color)
				
				# --- Create and animate the dropped tile ---
				var new_dropped_tile = ColorRect.new()
				new_dropped_tile.color = dropped_tile_color
				new_dropped_tile.size = Vector2(70, 10) # Or whatever size you prefer
				new_dropped_tile.name = "Bin{}_Tile{}".format(i, bin_contents[i].size())
				
				# Start the tile at the paddle's position
				new_dropped_tile.global_position = paddle.global_position
				
				# Calculate where it should land in the stack
				var stack_height = bin_contents[i].size()
				var bin_visual = bin_node.get_node("ColorRect")
				var target_x = bin_visual.global_position.x
				var target_y = bin_visual.global_position.y + bin_visual.size.y - (stack_height * new_dropped_tile.size)
				
				# Set the script and tell it where to go
				new_dropped_tile.set_script(DroppedTile)
				new_dropped_tile.get_script().target_position = Vector2(target_x, target_y)

				# Add to the main scene to animate
				bin_node.add_child(new_dropped_tile)
				
				# check for flaxes
				process_flax_checks(i)
				break

# Main function to trigger all Klax checks
func process_flax_checks(bin_index):
	# Check for vertical Klaxes in the bin that was just changed
	check_for_vertical_flax(bin_index)
	# Check for patterns across all bins, as a new tile could complete one
	check_for_horizontal_flaxes()
	check_for_diagonal_flaxes()
	update_ui()

func check_for_vertical_flax(bin_index):
	var current_bin = bin_contents[bin_index]
	# Check for a vertical stack of 3 of the same color
	if current_bin.size() >= 3:
		var last_color = current_bin.back()
		if current_bin[-2] == last_color and current_bin[-3] == last_color:
			score += 100 # Bonus points for a Klax
			
			var original_size = current_bin.size()
			# Remove the 3 visual tiles by finding them by name
			for j in range(3):
				var tile_num = original_size - j
				var tile_node = get_node_or_null("Bin{}_Tile{}".format(bin_index, tile_num))
				if tile_node:
					tile_node.queue_free()
			
			current_bin.resize(original_size - 3)
			process_flax_checks(bin_index)

# check for horizontal klaxes
func check_for_horizontal_flaxes():
	# Iterate through the three possible 3-bin windows: [0,1,2], [1,2,3], [2,3,4]
	for i in range(3):
		var bin1 = bin_contents[i]
		var bin2 = bin_contents[i+1]
		var bin3 = bin_contents[i+2]
		
		# Skip if any bin in the window is empty
		if bin1.is_empty() or bin2.is_empty() or bin3.is_empty():
			continue

		# Horizontal Klax: 3 same-colored tiles at the same height
		if bin1.size() == bin2.size() and bin2.size() == bin3.size():
			if bin1.back() == bin2.back() and bin2.back() == bin3.back():
				score += 150
				var stack_height = bin1.size()
				
				# Find and remove the 3 visual tiles by name
				var tile1 = get_node_or_null("Bin{}_Tile{}".format(i, stack_height))
				var tile2 = get_node_or_null("Bin{}_Tile{}".format(i+1, stack_height))
				var tile3 = get_node_or_null("Bin{}_Tile{}".format(i+2, stack_height))
				if tile1: tile1.queue_free()
				if tile2: tile2.queue_free()
				if tile3: tile3.queue_free()
				
				bin1.pop_back()
				bin2.pop_back()
				bin3.pop_back()
				
				# A Klax was made, re-run all affected bins for chain reactions
				process_flax_checks(i)
				process_flax_checks(i+1)
				process_flax_checks(i+2)
				return # Exit to start the check over from the beginning


# check for diagonal klaxes
func check_for_diagonal_flaxes():
	# Iterate through the three possible 3-bin windows: [0,1,2], [1,2,3], [2,3,4]
	for i in range(3):
		var bin1 = bin_contents[i]
		var bin2 = bin_contents[i+1]
		var bin3 = bin_contents[i+2]
		
		# Skip if any bin in the window is empty
		if bin1.is_empty() or bin2.is_empty() or bin3.is_empty():
			continue

		var color1 = bin1.back()
		var color2 = bin2.back()
		var color3 = bin3.back()
		
		# Check if the top tiles of the three bins have the same color
		if color1 == color2 and color2 == color3:
			var size1 = bin1.size()
			var size2 = bin2.size()
			var size3 = bin3.size()
			var flax_found = false
			
			# Diagonal Klax (Up-Right): Heights are sequential (e.g., 2, 3, 4)
			if size1 + 1 == size2 and size2 + 1 == size3:
				score += 200
				flax_found = true
			# Diagonal Klax (Down-Right): Heights are sequential (e.g., 4, 3, 2)
			elif size1 - 1 == size2 and size2 - 1 == size3:
				score += 200
				flax_found = true
				
				if flax_found:
					# Find and remove the 3 visual tiles by name
					var tile1 = get_node_or_null("Bin{}_Tile{}".format(i, size1))
					var tile2 = get_node_or_null("Bin{}_Tile{}".format(i+1, size2))
					var tile3 = get_node_or_null("Bin{}_Tile{}".format(i+2, size3))
					if tile1: tile1.queue_free()
					if tile2: tile2.queue_free()
					if tile3: tile3.queue_free()
					bin1.pop_back()
					bin2.pop_back()
					bin3.pop_back()
					
					# A Klax was made, re-run all affected bins for chain reactions
					process_flax_checks(i)
					process_flax_checks(i+1)
					process_flax_checks(i+2)
					
				return # Exit to start the check over from the beginning
