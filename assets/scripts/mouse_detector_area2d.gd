class_name MouseDetectorArea2D extends Area2D

@export var is_hovered := false
@export var sprite: Sprite2D # optional!

func _mouse_enter():
	is_hovered = true

func _mouse_exit():
	is_hovered = false
