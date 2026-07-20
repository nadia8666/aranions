extends Node3D

# arachnorb controller
# my awesome philosophy:
# 	legs move one at a time, in a pattern where one moves, the opposite moves, then it cycles to the next pair
# 	the root object's position is linked to the body pos
# 	body position is dependent on the 4 feet, and never rotates
# 	individual legs rotate to face their target position, and reposition foot on their leg plane (LOCAL X & Y, Z = 0)
# 	target rotation dictates the goal rotation but the arachnorb itself never actually rotates, they are purposefully decoupled from eachother
# shoutout: https://www.superfuckingmario.com/

# misc
@export var camera: Camera3D

# body config
@export var body: Node3D
@export var body_height := 5.0
@export var body_cast: ShapeCast3D

# step config
@export var step_radius := 6.0
@export var step_height := 3.0
@export var step_length := 4.0
@export var step_length_run := 6.0
var step_timer := 0.0
const step_duration := 0.75
const step_duration_run := 0.5
var duration := step_duration
var is_stepping := false
var current_leg := 0

# foot config
@export var foot_offset := .8

# leg config
@export var leg_count: int = 4
@export var leg_template: Node3D
var legs: Array[Node3D] = []
var leg_targets: Array[Node3D] = []
var leg_offsets: Array[float] = []
var leg_fall_speeds: Array[float] = []

# movement
@export var gravity := 120.0
@export var terminal_velocity := 70.0
var target_rotation: Quaternion
var move_direction := Vector3.ZERO

# step cache
var start_leg_rot: Quaternion
var target_leg_rot: Quaternion
var start_foot_pos: Vector3
var target_foot_pos: Vector3

# network
var network_tick_timer := 0.0
const network_tick_rate := 0.033

# functions
func get_ground_pos(target: Vector3) -> Array:
	var space = get_world_3d().direct_space_state
	var ray = PhysicsRayQueryParameters3D.create(target + Vector3(0, 1, 0), target - Vector3(0, 3, 0))
	var hit = space.intersect_ray(ray)
	if hit:
		return [hit.position + Vector3(0, foot_offset, 0), true]
	return [target - Vector3(0, body_height, 0) + Vector3(0, foot_offset, 0), false]

func create_legs():
	for index in range(leg_count):
		var angle = fposmod(((TAU / leg_count) * index) + (PI / 4.0), TAU)
		var leg = leg_template.duplicate()
		leg.quaternion = Quaternion(Vector3.UP, angle)
		leg.top_level = true

		add_child(leg)
		legs.append(leg)
		leg_offsets.append(angle)
		leg_fall_speeds.append(0.0)
		
		var target = leg.find_child("LegTarget")
		target.top_level = true
		leg_targets.append(target)
		
		var outward = Quaternion(Vector3.UP, angle) * Vector3.RIGHT
		var ideal_foot = self.global_position + (outward * step_radius)
		target.global_position = get_ground_pos(ideal_foot)[0]
		
	remove_child(leg_template)

# calculates movement direction and sets target rotation accordingly
func rotate_to_input():
	if not camera:
		return
	
	var dir = Input.get_vector("move_left", "move_right", "move_down", "move_up", 0.1)
	
	if dir.length() > 0:
		move_direction = (Quaternion(Vector3.UP, atan2(-dir.x, dir.y)) * (camera.quaternion * Vector3.FORWARD).slide(Vector3.UP)).normalized().slide(Vector3.UP)
		var turn = (self.quaternion * Vector3.FORWARD).signed_angle_to(move_direction, Vector3.UP)
		target_rotation = self.quaternion * Quaternion(Vector3.UP, turn)

		if not is_stepping:
			duration = step_duration_run if Input.is_action_pressed("run") else step_duration
			is_stepping = true
	else:
		move_direction = Vector3.ZERO

# rotates and steps the current focused leg
func step_legs(delta: float):
	if is_stepping:
		var leg = legs[current_leg]
		var offset = leg_offsets[current_leg]
		var foot = leg_targets[current_leg]

		# calculate targets
		if step_timer == 0.0:
			start_leg_rot = leg.quaternion
			start_foot_pos = foot.global_position

			var ideal_rot = (target_rotation * Quaternion(Vector3.UP, offset)).normalized()
			var angle_diff = start_leg_rot.angle_to(ideal_rot)
			var max_angle = PI / 4.0
			
			if angle_diff > max_angle:
				target_leg_rot = start_leg_rot.slerp(ideal_rot, max_angle / angle_diff)
			else:
				target_leg_rot = ideal_rot

			var outward_dir = target_leg_rot * Vector3.RIGHT
			var walk_dir = target_rotation * Vector3.FORWARD
			var ideal_foot = body.global_position + (outward_dir * step_radius)
			
			if move_direction.length_squared() > 0.0:
				ideal_foot += walk_dir * (step_length_run if Input.is_action_pressed("run") else step_length)
				
			target_foot_pos = get_ground_pos(ideal_foot)[0]


		step_timer += delta
		var alpha = clamp(step_timer / duration, 0.0, 1.0)

		leg.quaternion = start_leg_rot.slerp(target_leg_rot, alpha)

		var current_foot_pos = start_foot_pos.lerp(target_foot_pos, alpha)
		current_foot_pos.y += sin(alpha * PI) * step_height
		foot.global_position = current_foot_pos
			
		# advance cycle
		if step_timer >= duration:
			duration = step_duration_run if Input.is_action_pressed("run") else step_duration
			is_stepping = false
			step_timer = 0.0
			
			var half_count = leg_count / 2
			if current_leg < half_count:
				current_leg += half_count
			else:
				current_leg = (current_leg - half_count + 1) % half_count

	var ball_grounded = body_cast.is_colliding()
	var index = 0
	for target in leg_targets:
		if !is_stepping or index != current_leg:
			var ground_data = get_ground_pos(target.global_position)
			var hit_pos: Vector3 = ground_data[0]
			var is_hit: bool = ground_data[1]
			
			if ball_grounded or (is_hit and target.global_position.y < hit_pos.y):
				if is_hit:
					target.global_position.y = hit_pos.y
				leg_fall_speeds[index] = 0.0
			else:
				leg_fall_speeds[index] = min(leg_fall_speeds[index] + (gravity * delta), terminal_velocity)
			target.global_position.y -= leg_fall_speeds[index] * delta
		index += 1

	if leg_targets[0].global_position.y <= 0:
		for target in leg_targets:
			target.global_position = Vector3(0, 300, 0)


# centers the body between all 4 feet
func position_body():
	var average_pos = Vector3.ZERO
	
	for foot in leg_targets:
		average_pos += foot.global_position
	
	average_pos /= leg_count
	average_pos += Vector3(0, body_height, 0)

	self.global_position = average_pos
	body.global_position = average_pos
	
	for i in range(legs.size()):
		var leg = legs[i]
		var foot = leg_targets[i]
		
		leg.global_position = average_pos
		var dir_to_foot = (foot.global_position - average_pos)
		dir_to_foot.y = 0
		
		if dir_to_foot.length_squared() > 0.001:
			var target_basis = Basis.looking_at(dir_to_foot.normalized(), Vector3.UP)
			target_basis = target_basis.rotated(Vector3.UP, PI / 2.0)
			
			leg.quaternion = target_basis.get_rotation_quaternion()

# springs the first joint of the leg to look good on flat ground
func update_leg_pose(leg_index: int):
	var leg = legs[leg_index]
	var foot = leg_targets[leg_index]
	var skeleton: Skeleton3D = leg.get_node("LegArmature/Skeleton3D")
	var index = skeleton.find_bone("Leg1")
	
	var dist = leg.global_position.distance_to(foot.global_position)
	var factor = clamp(((dist / (step_radius * 1.85)) - .6) * 2, 0, 1)
	skeleton.set_bone_pose_rotation(index, Quaternion(0, .7, lerp(.3, .7, factor), 0))

# replicates leg positions
func _send_leg_positions() -> void:
	var positions := PackedVector3Array()
	positions.resize(leg_targets.size())
	
	for index in range(leg_targets.size()):
		positions[index] = leg_targets[index].global_position
		
	rpc_id(0, "sync_leg_targets", positions)

# update leg targets
@rpc("any_peer", "call_remote", "unreliable")
func sync_leg_targets(positions: PackedVector3Array) -> void:
	if is_multiplayer_authority():
		return
		
	var max_index: int = min(positions.size(), leg_targets.size())
	for index in range(max_index):
		leg_targets[index].global_position = positions[index]

# lifecycle events
func _ready() -> void:
	var peer = str(name).to_int()
	if peer != 0:
		set_multiplayer_authority(peer)
	
	if is_multiplayer_authority():
		if not camera:
			camera = get_viewport().get_camera_3d()
		if camera:
			camera.current = true
	
	self.global_position = Vector3(0, 222.865, 0)
	
	body.top_level = true
	target_rotation = self.quaternion
	if leg_count % 2 != 0:
		push_error("[FATAL]: arachnorb player with invalid leg count of %s" % [leg_count])
		return
	
	create_legs()

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		rotate_to_input()
		step_legs(delta)
		
		# handle network ticks
		network_tick_timer += delta
		if network_tick_timer >= network_tick_rate:
			network_tick_timer = 0.0
			_send_leg_positions()
	
	for index in range(leg_count):
		update_leg_pose(index)
	
	position_body()
