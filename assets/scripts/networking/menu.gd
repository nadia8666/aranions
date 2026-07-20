extends Control

func _ready() -> void:
	$Singleplayer.pressed.connect(_on_singleplayer_pressed)
	$MultiHost.pressed.connect(_on_host_pressed)
	$MultiJoin.pressed.connect(_on_join_pressed)

func _on_singleplayer_pressed() -> void:
	NetworkManager.start_singleplayer(get_username(""))

func get_username(default_user = "Player") -> String:
	var username = $Username.text
	return default_user if username.is_empty() else username

func _on_host_pressed() -> void:
	NetworkManager.create_host(get_username())

func _on_join_pressed() -> void:
	var ip = $MultiJoinIP.text
	NetworkManager.join_server("127.0.0.1" if ip == "" else ip, get_username())
	
