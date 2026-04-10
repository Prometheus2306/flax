extends Node2D

# Velocity/physics tuning for bin-rejection animation.
var launch_velocity = Vector2.ZERO
var gravity = 1500.0
var angular_velocity = 4.2
var damping = 0.995
var has_bounced = false

func _process(delta):
	# Integrate simple arcade-like motion.
	launch_velocity.y += gravity * delta
	position += launch_velocity * delta
	rotation += angular_velocity * delta
	launch_velocity *= damping
	
	# One visible ricochet before falling away.
	if not has_bounced and position.y >= 960.0:
		has_bounced = true
		position.y = 960.0
		launch_velocity.y = -abs(launch_velocity.y) * 0.38
		launch_velocity.x *= 1.25
	
	if position.y > 1360.0 or position.x < -120.0 or position.x > 840.0:
		queue_free()
