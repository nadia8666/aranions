extends Node3D

@onready var phantom_camera: Node3D = $Camera/PhantomCamera3D
@onready var system_camera: Camera3D = $Camera/Camera3D
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner

func _ready() -> void:
	NetworkManager.player_spawned.connect(_on_player_spawned)
	
	if multiplayer_spawner:
		multiplayer_spawner.spawned.connect(_on_network_player_spawned)
		
	NetworkManager.setup_game_scene($Players, multiplayer_spawner)

func _on_player_spawned(peer_id: int, player_node: Node) -> void:
	_configure_player_camera(player_node)

func _on_network_player_spawned(player_node: Node) -> void:
	_configure_player_camera(player_node)

func _configure_player_camera(player_node: Node) -> void:
	if player_node.is_multiplayer_authority():
		if "camera" in player_node:
			player_node.camera = system_camera
			
		if phantom_camera and phantom_camera.has_method("set_follow_target"):
			phantom_camera.set_follow_target(player_node)
