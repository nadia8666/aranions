extends Control

func _ready() -> void:
	$Singleplayer.pressed.connect(_on_singleplayer_pressed)
	$MultiHost.pressed.connect(_on_host_pressed)
	$MultiJoin.pressed.connect(_on_join_pressed)

func _on_singleplayer_pressed() -> void:
	NetworkManager.start_singleplayer()

func _on_host_pressed() -> void:
	NetworkManager.create_host()

func _on_join_pressed() -> void:
	var ip = $MultiJoinIP.text
	NetworkManager.join_server("127.0.0.1" if ip == "" else ip)
	
