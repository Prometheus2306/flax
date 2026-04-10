extends Node2D

var target_position = Vector2.ZERO
var duration = 0.2
var elapsed = 0.0
var start_position = Vector2.ZERO
var initialized = false

# Animates a dropped stack tile toward its bin target position.
# Disables processing after arrival to reduce per-frame overhead.
func _process(delta):
	if not initialized:
		start_position = global_position
		initialized = true
	
	elapsed += delta
	var t = clamp(elapsed / duration, 0.0, 1.0)
	
	# Ease-out with a small arc and settle bounce to fake depth.
	var eased = 1.0 - pow(1.0 - t, 3.0)
	var pos = start_position.lerp(target_position, eased)
	var arc_height = 26.0 * sin(t * PI)
	pos.y -= arc_height
	if t > 0.85:
		pos.y += sin((t - 0.85) * 30.0) * 2.0
	global_position = pos
	
	if t >= 1.0:
		global_position = target_position
		set_process(false)
