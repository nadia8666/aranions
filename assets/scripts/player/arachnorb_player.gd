extends Node3D

# arachnorb character controller
# move like a beady long legs :D
# legs move in an x sort of pattern, move one leg, move the opposite, then rotate to the next pair and repeat. 

# camera
@export var camera: Camera3D

# legs
@export var leg_count: int = 4
@export var leg_template: Node3D
var legs: Array[Node3D] = []

# stepping
var step_timer = 0.0
var step_duration: float = 2.0
var is_stepping: bool = false
var current_leg_index: int = 0

# movement
var target_rotation: Quaternion

# code
func _ready() -> void:
	target_rotation = self.quaternion
	
	if leg_count % 2 != 0:
		push_error("[FATAL]: arachnorb player with invalid leg count of %s" % [leg_count])
		return

	# generate legs
	for index in range(leg_count):
		var leg = leg_template.duplicate()
		add_child(leg)

		var angle = fposmod(((TAU / leg_count) * index) + (PI / 4.0), TAU)
		leg.quaternion = Quaternion(Vector3.UP, angle)
		legs.append(leg)
		
	remove_child(leg_template)


func _process(delta: float) -> void:
	var dir = Input.get_vector("move_left", "move_right", "move_down", "move_up", 0.1)

	# footstep
	if is_stepping:
		step_timer += delta
		
		# reset cycle
		if step_timer >= step_duration:
			is_stepping = false
			step_timer = 0.0
			
			current_leg_index = (current_leg_index + (leg_count / 2)) % leg_count
			if current_leg_index % (leg_count / 2) == 0:
				current_leg_index = (current_leg_index + 1) % leg_count

	# angle target
	if dir.length() > 0:
		is_stepping = true
	else:
		return
		
	var cam_look = Vector3.UP.slide(camera.quaternion * Vector3.FORWARD)
	var cam_move = (Quaternion(Vector3.UP, atan2(-dir.x, -dir.y)) * cam_look).normalized()
	var move = Vector3.UP.slide(cam_move)
	var turn = (self.quaternion * Vector3.FORWARD).signed_angle_to(move, Vector3.UP)
	
	target_rotation = turn * Quaternion(Vector3.UP, turn)
