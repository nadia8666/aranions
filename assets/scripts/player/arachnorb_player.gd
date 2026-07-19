extends Node3D

# arachnorb controller
# my awesome philosiphy:
#	legs move one at a time, in a pattern where one moves, the opposite moves, then it cycles to the next pair
#	the root object's position is linked to the body pos
#	body position is dependent on the 4 feet, and never rotates
#	invidiaul legs rotate to face their target position, and reposition foot on their leg plane (LOCAL X & Y, Z = 0)
#	target rotation dictates the goal rotation but the arachnorb itself never actually rotates, they are purposefully decoupled from eachother

# variables
@export var camera: Camera3D
@export var leg_count: int = 4
@export var leg_template: Node3D
@export var body: Node3D
@export var body_height := 5.0

var legs: Array[Node3D] = []
var leg_targets: Array[Node3D] = []
var leg_offsets: Array[float] = []

var step_timer := 0.0
var step_duration := 1
var is_stepping := false
var current_leg := 0

var target_rotation: Quaternion

# functions
func create_legs():
	for index in range(leg_count):
		var angle = fposmod(((TAU / leg_count) * index) + (PI / 4.0), TAU)
		var leg = leg_template.duplicate()
		leg.quaternion = Quaternion(Vector3.UP, angle)
		leg.top_level = true

		add_child(leg)
		legs.append(leg)
		leg_offsets.append(angle)
		leg_targets.append(leg.find_child("LegTarget"))
		
	remove_child(leg_template)

# calculates movement direction and sets target rotation accordingly
func rotate_to_input():
	var dir = Input.get_vector("move_left", "move_right", "move_down", "move_up", 0.1)
	
	if dir.length() > 0:
		var move = (Quaternion(Vector3.UP, atan2(dir.x, -dir.y)) * (camera.quaternion * Vector3.FORWARD).slide(Vector3.UP)).normalized().slide(Vector3.UP)
		var turn = (self.quaternion * Vector3.FORWARD).signed_angle_to(move, Vector3.UP)
		target_rotation = self.quaternion * Quaternion(Vector3.UP, turn)

		if not is_stepping:
			is_stepping = true

# rotates and steps the current focused leg
func step_legs(delta: float):
	# move leg
	if is_stepping:
		step_timer += delta

		var leg = legs[current_leg]
		var offset = leg_offsets[current_leg]
		var foot = leg_targets[current_leg]

		var target_rot = (target_rotation * Quaternion(Vector3.UP, offset)).normalized()
		leg.quaternion = leg.quaternion.slerp(target_rot, delta * 5)
		# TODO: step and reposition foot
		
	# reset legs
	if step_timer >= step_duration:
		is_stepping = false
		step_timer = 0.0
		
		var half_count = leg_count / 2
		if current_leg < half_count:
			current_leg += half_count
		else:
			current_leg = (current_leg - half_count + 1) % half_count

# centers the body between all 4 feet
func position_body():
	var average_pos = Vector3.ZERO

	var feet_positions: Array[Vector3] = []
	for foot in leg_targets:
		average_pos += foot.global_position;
		feet_positions.append(foot.global_position)
	
	average_pos /= leg_count
	average_pos += Vector3(0, body_height, 0)

	body.global_position = average_pos

	for leg in legs:
		leg.global_position = average_pos
	
	var index = 0
	for foot in leg_targets:
		foot.global_position = feet_positions[index]
		index += 1

# lifecycle events
func _ready() -> void:
	body.top_level = true
	target_rotation = self.quaternion
	if leg_count % 2 != 0:
		push_error("[FATAL]: arachnorb player with invalid leg count of %s" % [leg_count])
		return

	create_legs()

func _process(delta: float) -> void:
	rotate_to_input()
	step_legs(delta)
	position_body()
