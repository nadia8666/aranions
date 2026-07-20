extends Node

signal player_spawned(peer_id: int, player_node: Node)
signal player_despawned(peer_id: int)

const PORT = 7070
const DEFAULT_IP = "127.0.0.1"
var usernames: Dictionary[int, String] = {}
var local_username = "Player"

var player_scene: PackedScene = preload("res://assets/scenes/arachnorb_player.tscn")
var main_scene_path: String = "res://assets/scenes/main.tscn"
var players_container: Node = null

var pending_peers: Array[int] = []

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func start_singleplayer(user) -> void:
	local_username = user
	get_tree().change_scene_to_file(main_scene_path)

func create_host(username: String) -> void:
	local_username = "Player" if username == "" else username
	usernames[1] = local_username
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	if error != OK:
		print("[ERROR] failed to host: %s" % [error])
		return
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(main_scene_path)

func join_server(ip: String, username) -> void:
	local_username = "Player" if username == "" else username
	
	var target_ip = DEFAULT_IP
	var target_port = PORT
	
	if ":" in ip:
		var parts = ip.split(":")
		target_ip = parts[0]
		target_port = int(parts[1])
		print("SET TO TARGET PORT %s" % [target_port])
	else:
		target_ip = ip
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_ip, target_port)
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
		usernames.erase(id)
		rpc("sync_usernames", usernames)
		if players_container:
			var player = players_container.get_node_or_null(str(id))
			if player:
				player.queue_free()
				player_despawned.emit(id)

func setup_game_scene(container: Node, spawner: MultiplayerSpawner) -> void:
	players_container = container
	
	if not multiplayer.is_server() and not spawner.spawned.is_connected(_on_player_spawned_via_spawner):
		spawner.spawned.connect(_on_player_spawned_via_spawner)
	
	rpc_id(1, "server_notify_client_ready", local_username)

@rpc("any_peer", "call_local", "reliable")
func server_notify_client_ready(username: String) -> void:
	if not multiplayer.is_server():
		return
		
	var sender_id = multiplayer.get_remote_sender_id()
	usernames[sender_id] = username
	rpc("sync_usernames", usernames)
	
	if sender_id == 1:
		add_player(1)
		return
		
	if sender_id in pending_peers:
		pending_peers.erase(sender_id)
		add_player(sender_id)

@rpc("authority", "call_local", "reliable")
func sync_usernames(dict: Dictionary[int, String]):
	for key in dict:
		usernames[key] = dict[key]
		
	if players_container:
		for id in usernames:
			var p_node = players_container.get_node_or_null(str(id))
			if p_node:
				p_node.set_username(usernames[id])

func add_player(id: int) -> void:
	if not players_container:
		return
	if players_container.has_node(str(id)):
		return
		
	var player = player_scene.instantiate()
	player.name = str(id) 
	players_container.add_child(player)
	
	var display_name = usernames.get(id, "i forgot to put a username, laugh at me!")
	player.set_username(display_name)
	player_spawned.emit(id, player)

func _on_player_spawned_via_spawner(node: Node):
	var peer_id = int(str(node.name))
	
	if not usernames.has(peer_id):
		await get_tree().create_timer(1).timeout
		
	var display_name = usernames.get(peer_id, "i forgot to put a username, laugh at me!")
	if node.has_method("set_username"):
		node.set_username(display_name)
