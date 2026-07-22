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
@export var username: String
@export var username_container: Label3D
var turn_direction := 0.0

# cursor
@export var target_cursor: Node3D
@export var current_cursor: Node3D

# body config
@export var body: Node3D
@export var body_height := 3.0
@export var body_cast: ShapeCast3D
@export var body_mesh: MeshInstance3D

# step config
@export var step_radius := 6.0
@export var step_height := 3.0
@export var step_length := 5.0
@export var step_length_run := 8.0
var step_timer := 0.0
var step_duration := 0.65
var step_duration_run := 0.3
var duration := step_duration
var is_stepping := false
var current_leg := 0
var step_cast_distance = 4

# foot config
@export var foot_offset := 0.8
@export var foot_margin := 0.5

# leg config
@export var leg_count: int = 4
@export var leg_template: Node3D
var legs: Array[Node3D] = []
var leg_targets: Array[Node3D] = []
var leg_offsets: Array[float] = []
var leg_fall_speeds: Array[float] = []
@export var max_stretch := 18.0 # controls the maximum distance the legs can be from the body and the body can be from the legs
@export var leg_out_min := 0.3 # how far out the arachnorbian legs are for the first joint at minimum slope
@export var leg_out_max := 0.7 # how far out the arachnorbian legs are for the first joint at maximum slope

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
var network_tick_rate := 0.033

# functions

# raycasts towards the ground to calculate foot height
func get_ground_pos(target: Vector3, cast_down_dist: float = step_cast_distance + 2.0) -> Array:
	var ray = PhysicsRayQueryParameters3D.create(target + Vector3(0, step_cast_distance, 0), target - Vector3(0, cast_down_dist, 0))
	var hit = get_world_3d().direct_space_state.intersect_ray(ray)
	if hit:
		return [hit.position + Vector3(0, foot_offset, 0), true]
	return [target - Vector3(0, body_height, 0) + Vector3(0, foot_offset, 0), false]

# modifies the foot's target position to prevent walking into walls
func check_leg_collide(origin: Vector3, target: Vector3) -> Array:
	# horizontal
	var space = get_world_3d().direct_space_state
	var elevated_origin = origin + Vector3(0, step_cast_distance, 0)
	var elevated_target = target + Vector3(0, step_cast_distance, 0)
	var ray = PhysicsRayQueryParameters3D.create(elevated_origin, elevated_target)
	var hit = space.intersect_ray(ray)
	
	if hit:
		# vertical
		var flat_normal = hit.normal.slide(Vector3.UP).normalized()
		var adjusted_pos = hit.position
		if flat_normal.length_squared() > foot_margin:
			adjusted_pos += flat_normal * foot_margin
			
		var down_ray = PhysicsRayQueryParameters3D.create(adjusted_pos, adjusted_pos - Vector3(0, step_cast_distance + 2, 0))
		var down_hit = space.intersect_ray(down_ray)
		if down_hit:
			return [true, down_hit.position + Vector3(0, foot_offset, 0)]
		return [true, adjusted_pos - Vector3(0, step_cast_distance, 0)]
		
	return [false, target]

# sets up legs
func create_legs():
	for index in range(leg_count):
		var angle = fposmod(((TAU / leg_count) * index) + (PI / 4.0), TAU)
		var leg = leg_template.duplicate()
		leg.quaternion = Quaternion(Vector3.UP, angle)
		leg.top_level = true
		leg.name = "Leg %s" % [index]
		leg.find_child("Index").text = str(index)

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
		
		var unique = leg.mesh.get_active_material(0).duplicate()
		leg.mesh.material_override = unique
		
	remove_child(leg_template)

# calculates movement direction and sets target rotation accordingly
func rotate_to_input():
	if not camera:
		return
	
	var dir = Input.get_vector("move_left", "move_right", "move_down", "move_up", 0.1)
	
	if dir.length() > 0 and not Input.is_action_pressed("center_home"):
		move_direction = (Quaternion(Vector3.UP, atan2(-dir.x, dir.y)) * (camera.quaternion * Vector3.FORWARD).slide(Vector3.UP)).normalized().slide(Vector3.UP)
		var turn = (self.quaternion * Vector3.FORWARD).signed_angle_to(move_direction, Vector3.UP)
		target_rotation = self.quaternion * Quaternion(Vector3.UP, turn)
	else:
		move_direction = Vector3.ZERO
		
	turn_direction = 0.0
	if Input.is_action_pressed("turn_left"): turn_direction += 1.0
	if Input.is_action_pressed("turn_right"): turn_direction -= 1.0

# rotates and steps the current focused leg
func step_legs(delta: float):
	var force_home = Input.is_action_pressed("center_home")
	var has_input = move_direction.length_squared() > 0 or turn_direction != 0.0 or force_home
	
	if not is_stepping and has_input:
		if move_direction.length_squared() == 0 and turn_direction == 0.0:
			var ideal_rot = (target_rotation * Quaternion(Vector3.UP, leg_offsets[current_leg])).normalized()
			var ideal_foot = body.global_position + (ideal_rot * Vector3.RIGHT * step_radius)
			ideal_foot.y = leg_targets[current_leg].global_position.y
			
			if leg_targets[current_leg].global_position.distance_to(ideal_foot) < 0.5:
				var half_count = leg_count / 2
				if current_leg < half_count:
					current_leg += half_count
				else:
					current_leg = (current_leg - half_count + 1) % half_count
				return
				
		is_stepping = true
		duration = step_duration_run if Input.is_action_pressed("run") else step_duration
		
	if is_stepping:
		var leg = legs[current_leg]
		var offset = leg_offsets[current_leg]
		var foot = leg_targets[current_leg]

		# calculate foot targets
		if step_timer == 0.0:
			if turn_direction != 0.0 and move_direction.length_squared() == 0.0:
				var turn_increment = (PI / 4.0) / leg_count
				target_rotation = (target_rotation * Quaternion(Vector3.UP, turn_direction * turn_increment)).normalized()

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
			ideal_foot.y = start_foot_pos.y - foot_offset
			
			if move_direction.length_squared() > 0.0:
				ideal_foot += walk_dir * (step_length_run if Input.is_action_pressed("run") else step_length)
			
			var temp_target = get_ground_pos(ideal_foot)[0]
			var collision_info = check_leg_collide(start_foot_pos, temp_target)
			target_foot_pos = collision_info[1]

		# animate foot
		step_timer += delta
		var alpha = clamp(step_timer / duration, 0.0, 1.0)

		leg.quaternion = start_leg_rot.slerp(target_leg_rot, alpha)

		var current_foot_pos = start_foot_pos.lerp(target_foot_pos, alpha)
		current_foot_pos.y += sin(alpha * PI) * step_height
		foot.global_position = current_foot_pos

		# advance cycle 
		if step_timer >= duration:
			duration = step_duration_run if Input.is_action_pressed("run") else step_duration
			step_timer = 0.0
			
			var half_count = leg_count / 2
			if current_leg < half_count:
				current_leg += half_count
			else:
				current_leg = (current_leg - half_count + 1) % half_count
			is_stepping = false

	# foot gravity, ball detection is kind of a bandaid but it works well enough.
	var ball_grounded = body_cast.is_colliding()
	for index in range(leg_count):
		if !is_stepping or index != current_leg:
			var target = leg_targets[index]
			var fall_dist = (leg_fall_speeds[index] * delta) + step_cast_distance + 2.0
			var ground_data = get_ground_pos(target.global_position, fall_dist)
			var hit_pos: Vector3 = ground_data[0]
			var is_hit: bool = ground_data[1]
			
			if ball_grounded or (is_hit and target.global_position.y < hit_pos.y + 0.05):
				if is_hit:
					if abs(target.global_position.y - hit_pos.y) > 0.05:
						target.global_position.y = lerp(target.global_position.y, hit_pos.y, 25.0 * delta)
					else:
						target.global_position.y = hit_pos.y
				leg_fall_speeds[index] = 0.0
			else:
				leg_fall_speeds[index] = min(leg_fall_speeds[index] + (gravity * delta), terminal_velocity)
				target.global_position.y -= leg_fall_speeds[index] * delta

				var outward_dir = (target_rotation * Quaternion(Vector3.UP, leg_offsets[index])).normalized() * Vector3.RIGHT
				var home_pos = body.global_position + (outward_dir * step_radius) - Vector3(0, body_height - foot_offset, 0)
				target.global_position = target.global_position.lerp(home_pos, 3 * delta)

	# reset if too low
	if leg_targets[0].global_position.y <= 0:
		var index = 0
		for target in leg_targets:
			var outward_dir = (target_rotation * Quaternion(Vector3.UP, leg_offsets[index])).normalized() * Vector3.RIGHT
			var home_pos = Vector3(0, 300, 0) + (outward_dir * step_radius) - Vector3(0, body_height - foot_offset, 0)
			target.global_position = home_pos
			index += 1


# centers the body between all 4 feet
func position_body():
	var average_pos = Vector3.ZERO
	
	for foot in leg_targets:
		average_pos += foot.global_position
	
	average_pos /= leg_count
	average_pos += Vector3(0, body_height, 0)

	# clamp body
	for iter in range(2):
		for foot in leg_targets:
			var dist = average_pos.distance_to(foot.global_position)
			if dist > max_stretch:
				var dir = (average_pos - foot.global_position).normalized()
				average_pos = foot.global_position + dir * max_stretch

	self.global_position = average_pos
	body.global_position = average_pos
	
	# rotate legs: prevent; Drifts (We dont like Islands !)
	for i in range(legs.size()):
		var leg = legs[i]
		var foot = leg_targets[i]
		
		# clamp feet
		var foot_dist = foot.global_position.distance_to(average_pos)
		if foot_dist > max_stretch:
			var dir = (foot.global_position - average_pos).normalized()
			foot.global_position = average_pos + dir * max_stretch
		
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
	skeleton.set_bone_pose_rotation(index, Quaternion(0, .7, lerp(leg_out_min, leg_out_max, factor), 0))

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

# TODO: probably change these to authority instead?
@rpc("any_peer", "call_local", "reliable")
func request_leg_color(leg_index: int, color: Color):
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != get_multiplayer_authority():
		return
		
	if leg_index < 0 or leg_index >= legs.size():
		return
		
	rpc("sync_leg_color", leg_index, color)

@rpc("any_peer", "call_local", "reliable")
func request_body_color(color: Color):
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != get_multiplayer_authority():
		return
		
	rpc("sync_body_color", color)

@rpc("any_peer", "call_local", "reliable")
func sync_leg_color(leg_index: int, color: Color):
	if leg_index >= 0 and leg_index < legs.size():
		var leg = legs[leg_index]
		if leg and leg.mesh:
			var mat = leg.mesh.get_active_material(0)
			if mat is BaseMaterial3D:
				mat.albedo_color = color

@rpc("any_peer", "call_local", "reliable")
func sync_body_color(color: Color):
	if body_mesh:
		var mat = body_mesh.get_active_material(0)
		if mat is BaseMaterial3D:
			mat.albedo_color = color

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

# sets username and fills out its ui
func set_username(user: String):
	username = user
	username_container.text = user

# gets the "physical" forward vector of the arachnorb
func get_pseudo_forward() -> Vector3:
	var front_center = Vector3.ZERO
	var back_center = Vector3.ZERO
	var half_count = leg_count / 2
	var front_legs = 0
	var back_legs = 0
	
	for i in range(leg_count):
		var local_angle = fposmod(leg_offsets[i], TAU)
		
		if local_angle < PI / 2.0 or local_angle > 3.0 * PI / 2.0:
			front_center += leg_targets[i].global_position
			front_legs += 1
		else:
			back_center += leg_targets[i].global_position
			back_legs += 1
	
	if front_legs > 0 and back_legs > 0:
		front_center /= front_legs
		back_center /= back_legs
		var dir = front_center - back_center
		dir.y = 0.0
		
		if dir.length_squared() > .001:
			return dir.normalized()
	
	return Vector3.FORWARD

func cursor_cast(center) -> Array:
	var ray = PhysicsRayQueryParameters3D.create(center + Vector3(0, 15, 0), center - Vector3(0, 20, 0))
	var hit = get_world_3d().direct_space_state.intersect_ray(ray)
	return [(hit.position + hit.normal / 4) if hit else (center - Vector3(0, 2.963, 0)), hit]

# rotates both the current and target cursors
func update_cursors(delta: float):
	var center = self.global_position
	
	target_cursor.rotation.x = 0
	target_cursor.rotation.z = 0
	target_cursor.quaternion = target_cursor.quaternion.slerp(target_rotation, 15 * delta)
	var target_res = cursor_cast(center + target_cursor.quaternion * Vector3.FORWARD * 13)
	var target_pos = target_res[0]
	var hit_target = target_res[1]
	if hit_target:
		var diff = Quaternion(target_rotation * Vector3.UP, hit_target.normal)
		target_cursor.quaternion = diff * target_cursor.quaternion
	target_cursor.global_position = target_pos
	
	current_cursor.rotation.x = 0
	current_cursor.rotation.z = 0
	var current_rotation = Basis.looking_at(get_pseudo_forward()).get_rotation_quaternion() * Quaternion(Vector3.UP, PI / 2)
	current_cursor.quaternion = current_cursor.quaternion.slerp(current_rotation, 3 * delta)
	var current_res = cursor_cast(center + current_cursor.quaternion * Vector3.FORWARD * 10)
	var current_pos = current_res[0]
	var hit_current = current_res[1]
	if hit_current:
		var diff = Quaternion(current_rotation * Vector3.UP, hit_current.normal)
		current_cursor.quaternion = diff * current_cursor.quaternion
	current_cursor.global_position = current_pos
	

func _physics_process(delta: float):
	if is_multiplayer_authority():
		rotate_to_input()
		step_legs(delta)
		update_cursors(delta)
		
		# handle network ticks
		network_tick_timer += delta
		if network_tick_timer >= network_tick_rate:
			network_tick_timer = 0.0
			_send_leg_positions()
	
	for index in range(leg_count):
		update_leg_pose(index)
	
	position_body()
