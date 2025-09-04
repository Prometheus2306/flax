extends ColorRect

var target_position = Vector2.ZERO
var speed = 1200.0

func _process(delta):
	# Move towards the target using GLOBAL coordinates
	global_position = global_position.move_toward(target_position, speed * delta)

	# When we arrive, stop processing to save performance
	if global_position.is_equal_approx(target_position):
		set_process(false)
