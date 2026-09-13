extends Node
## Entry scene. Starts the session, then instantiates island, local player and
## HUD. Kept deliberately tiny so feature work never has to touch it.

const ISLAND := preload("res://src/game/island/island.tscn")
const PLAYER := preload("res://src/game/player/player.tscn")
const HUD := preload("res://src/game/hud/hud.tscn")

@export var level_id := "island_01"
@export var level_seed := -1 ## -1 = level default


func _ready() -> void:
	GameSession.start_level(level_id, level_seed)
	add_child(ISLAND.instantiate())
	var player: Player = PLAYER.instantiate()
	player.player_id = GameSession.local_player_id()
	player.position = GameSession.player_spawn(0)
	player.spawn_position = player.position
	add_child(player)
	add_child(HUD.instantiate())
