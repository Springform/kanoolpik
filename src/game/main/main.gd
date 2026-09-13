class_name Main
extends Node
## Entry scene and the one place that builds (and rebuilds) a running level.
##
## Keeps the level's moving parts as children it owns, so restarting is just
## "throw them away and build again" — no stale nodes reacting to the new
## level's events. Phase 1.6 turns this into a TITLE → PLAYING → EVALUATION
## state machine; today it goes straight to PLAYING.

const ISLAND := preload("res://src/game/island/island.tscn")
const PLAYER := preload("res://src/game/player/player.tscn")
const HUD := preload("res://src/game/hud/hud.tscn")
const EVALUATION := preload("res://src/game/hud/evaluation/evaluation_screen.tscn")

## Passed to GameSession as "use the level's own default".
const LEVEL_DEFAULT_SEED := -1

@export var level_id := "island_01"
@export var level_seed := LEVEL_DEFAULT_SEED

var island: Island
var player: Player
var hud: HUD
var evaluation: EvaluationScreen


func _ready() -> void:
	start_game(level_seed)


## Build (or rebuild) the level. [param seed] < 0 uses the level default.
func start_game(seed: int = LEVEL_DEFAULT_SEED) -> void:
	_tear_down()
	GameSession.start_level(level_id, seed)
	island = ISLAND.instantiate()
	add_child(island)
	player = PLAYER.instantiate()
	player.player_id = GameSession.local_player_id()
	player.position = GameSession.player_spawn(0)
	player.spawn_position = player.position
	add_child(player)
	hud = HUD.instantiate()
	add_child(hud)
	evaluation = EVALUATION.instantiate()
	add_child(evaluation)


## Play the same mess again.
func restart_same_island() -> void:
	start_game(current_seed())


## Roll a new mess on the same island.
func restart_new_mess() -> void:
	start_game(randi() % 1000000)


func current_seed() -> int:
	return GameSession.state.rng_seed if GameSession.state != null else level_seed


## Free the level's nodes immediately rather than deferring: a queued node is
## still connected to GameEvents and would react to the next level's events.
func _tear_down() -> void:
	GameSession.stop_level()
	for node: Node in [evaluation, hud, player, island]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()
	island = null
	player = null
	hud = null
	evaluation = null
