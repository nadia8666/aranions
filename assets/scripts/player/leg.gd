class_name ArachnorbFoot extends SkeletonModifier3D

func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if not skeleton:
		return
		
	var bone_idx: int = skeleton.find_bone("Foot")
	if bone_idx == -1:
		return
		
	var parent_idx: int = skeleton.get_bone_parent(bone_idx)
	if parent_idx == -1:
		return
		
	# 1. Grab the current global pose of the parent chain
	var parent_global_pose: Transform3D = skeleton.get_bone_global_pose(parent_idx)
	
	# 2. Define your desired target orientation in global space. 
	# Since Y- points UP along the bone length, flip it 180 degrees (PI) around X.
	var target_global_rot := Quaternion(Vector3.RIGHT, PI)
	
	# 3. Completely strip out the parent's current frame rotation by multiplying by its inverse.
	# This converts your absolute target rotation into the correct local space.
	var final_local_rot: Quaternion = parent_global_pose.basis.get_rotation_quaternion().inverse() * target_global_rot
	
	# 4. Enforce the rotation directly
	skeleton.set_bone_pose_rotation(bone_idx, final_local_rot.normalized())
