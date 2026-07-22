extends Control

@export var color_picker: ColorPicker
@export var head: MouseDetectorArea2D
@export var legs: Array[MouseDetectorArea2D]
@export var paint_sound: AudioStreamPlayer
@export var button: Button
@export var ui: Control

func _ready():
	button.pressed.connect(toggle_ui)

func toggle_ui():
	ui.visible = not ui.visible

func get_root() -> Node3D:
	var peer_id = multiplayer.get_unique_id()
	if NetworkManager.players_container and NetworkManager.players_container.has_node(str(peer_id)):
		return NetworkManager.players_container.get_node(str(peer_id))
	return null

func paint_leg(leg: MouseDetectorArea2D, index: int):
	var root = get_root()
	if root:
		root.rpc_id(1, "request_leg_color", index, color_picker.color)
		leg.sprite.modulate = color_picker.color
	
	get_tree().root.set_input_as_handled()
	paint_sound.play()

func paint_body():
	var root = get_root()
	if root:
		root.rpc_id(1, "request_body_color", color_picker.color)
		head.sprite.modulate = color_picker.color
	
	get_tree().root.set_input_as_handled()
	paint_sound.play()

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		for leg in legs:
			if leg.is_hovered:
				paint_leg(leg, int(leg.name.substr(3)))
				return
				
		if head.is_hovered:
			paint_body()
