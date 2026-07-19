extends Node3D

@export var leg_target: Node3D
@export var skeleton: Skeleton3D
var foot: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	foot = skeleton.find_bone("Foot")
	
	pass # Replace with function body.

func reset_foot():
	var parent_bone = skeleton.get_bone_parent(foot)
	var parent_global_pose = skeleton.get_bone_global_pose(parent_bone)
	var target = Quaternion(Vector3.RIGHT, PI)
	var local_rotation = parent_global_pose.basis.get_rotation_quaternion().inverse() * target
	skeleton.set_bone_pose_rotation(foot, local_rotation)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	reset_foot()
	pass

func _physics_process(delta: float) -> void:
	
	pass
