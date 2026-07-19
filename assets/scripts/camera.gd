extends Camera3D

@export var phantom_camera: PhantomCamera3D
@export var look_sensitivity: float = 0.005

func _input(event):
	if event.is_action_pressed("right_click"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_released("right_click"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_pressed("right_click") and event is InputEventMouseMotion:
		var current_orbit = phantom_camera.get_third_person_rotation()
		current_orbit.y -= event.relative.x * look_sensitivity
		current_orbit.x -= event.relative.y * look_sensitivity
		
		current_orbit.x = clamp(current_orbit.x, deg_to_rad(-85), deg_to_rad(85))
		phantom_camera.set_third_person_rotation(current_orbit)
