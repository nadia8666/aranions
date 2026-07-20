extends Node

signal player_spawned(peer_id: int, player_node: Node)
signal player_despawned(peer_id: int)

const PORT = 7070
const DEFAULT_IP = "127.0.0.1"

var player_scene: PackedScene = preload("res://assets/scenes/arachnorb_player.tscn")
var main_scene_path: String = "res://assets/scenes/main.tscn"
var players_container: Node = null

var pending_peers: Array[int] = []

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func start_singleplayer() -> void:
	get_tree().change_scene_to_file(main_scene_path)

func create_host() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	if error != OK:
		print("[ERROR] failed to host: %s" % [error])
		return
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(main_scene_path)

func join_server(ip: String) -> void:
	var target_ip = ip if not ip.is_empty() else DEFAULT_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, PORT)
	if error != OK:
		print("[ERROR] failed to connect: %s" % [error])
		return
	multiplayer.multiplayer_peer = peer

func _on_connected_to_server() -> void:
	get_tree().change_scene_to_file(main_scene_path)

func _on_connection_failed() -> void:
	print("[ERROR] failed to connect!")
	multiplayer.multiplayer_peer = null

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		pending_peers.append(id)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		pending_peers.erase(id)
		if players_container:
			var player = players_container.get_node_or_null(str(id))
			if player:
				player.queue_free()
				player_despawned.emit(id)

func setup_game_scene(container: Node) -> void:
	players_container = container
	rpc_id(1, "server_notify_client_ready")

@rpc("any_peer", "call_local", "reliable")
func server_notify_client_ready() -> void:
	if not multiplayer.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	
	if sender_id == 1:
		add_player(1)
		return
		
	if sender_id in pending_peers:
		pending_peers.erase(sender_id)
		add_player(sender_id)

func add_player(id: int) -> void:
	if not players_container:
		return
	if players_container.has_node(str(id)):
		return
		
	var player = player_scene.instantiate()
	player.name = str(id) 
	players_container.add_child(player)
	player_spawned.emit(id, player)
