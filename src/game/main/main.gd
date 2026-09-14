class_name Main
extends Node
## Entry scene and the flow between the game's three screens (WP-1.6).
##
##   TITLE      island drifting behind the front page, no player, no clock
##   PLAYING    island + player + HUD + pause menu; the session runs
##   EVALUATION the level is finished and the score is up
##
## Main is also the only place that builds a level, so restarting is "throw the
## nodes away and build again" — no stale node reacting to the next level's
## events. Everything it owns is listed in [method _tear_down].

enum State { TITLE, PLAYING, EVALUATION }

const ISLAND := preload("res://src/game/island/island.tscn")
const PLAYER := preload("res://src/game/player/player.tscn")
const HUD := preload("res://src/game/hud/hud.tscn")
const EVALUATION := preload("res://src/game/hud/evaluation/evaluation_screen.tscn")
const TITLE_SCREEN := preload("res://src/game/title/title_screen.tscn")
const PAUSE_MENU := preload("res://src/game/title/pause_menu.tscn")

## Passed to GameSession as "use the level's own default".
const LEVEL_DEFAULT_SEED := -1

@export var level_id := "island_01"
@export var level_seed := LEVEL_DEFAULT_SEED
## Skip the front page and drop straight into a game (handy while developing).
@export var skip_title := false

var state := State.TITLE
var island: Island
## Phase-3 ability nodes for the running scene, tracked so [method _tear_down]
## can free them — they subscribe to GameEvents and must not outlive a restart.
var _abilities: Array[Node] = []
var player: Player
var hud: HUD
var evaluation: EvaluationScreen
var title_screen: TitleScreen
var pause_menu: PauseMenu
var backdrop: BackdropCamera
## The test-mode admin panel, when this build has one (WP-3.10).
var test_panel: TestPanel


func _ready() -> void:
	if skip_title:
		start_game(level_seed)
	else:
		to_title()


# --- Screens ----------------------------------------------------------------------

## Front page: the island is built as a backdrop only — the session is stopped
## right away, so no clock runs and no command can be submitted.
func to_title() -> void:
	_tear_down()
	state = State.TITLE
	GameSession.start_level(level_id, LEVEL_DEFAULT_SEED)
	GameSession.stop_level()
	island = ISLAND.instantiate()
	add_child(island)
	backdrop = BackdropCamera.new()
	add_child(backdrop)
	title_screen = TITLE_SCREEN.instantiate()
	add_child(title_screen)
	# Deferred: start_game frees the title screen, which would otherwise still be
	# locked emitting this very signal.
	title_screen.start_requested.connect(start_game, CONNECT_DEFERRED)
	title_screen.continue_requested.connect(continue_game, CONNECT_DEFERRED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Build (or rebuild) a playable level. [param seed] < 0 uses the level default.
func start_game(seed: int = LEVEL_DEFAULT_SEED) -> void:
	_tear_down()
	state = State.PLAYING
	GameSession.start_level(level_id, seed)
	_build_playing_scene()


## The nodes a playable level needs, whether it was generated or loaded.
func _build_playing_scene() -> void:
	island = ISLAND.instantiate()
	add_child(island)
	player = PLAYER.instantiate()
	player.player_id = GameSession.local_player_id()
	# Spawn points in the level data are flat (Y is presentation, not world
	# state), so lift them onto the terrain — otherwise the player can start
	# inside or under a hill and fall straight through into the lake.
	player.position = spawn_point(0)
	player.spawn_position = player.position
	add_child(player)
	hud = HUD.instantiate()
	add_child(hud)
	pause_menu = PAUSE_MENU.instantiate()
	add_child(pause_menu)
	pause_menu.restart_requested.connect(restart_same_island, CONNECT_DEFERRED)
	pause_menu.title_requested.connect(to_title, CONNECT_DEFERRED)
	evaluation = EVALUATION.instantiate()
	add_child(evaluation)
	_install_abilities()
	if TestMode.is_enabled():
		test_panel = TestPanel.new()
		test_panel.name = "TestPanel"
		add_child(test_panel)
	GameEvents.island_clean.connect(_on_island_clean)


## Phase-3 abilities. Each one checks [Progression] itself and does nothing until
## the party has bought it, so they are installed unconditionally and the skill
## menu is the only thing that decides whether they fire.
##
## They live on [Main] rather than on the player: [method _tear_down] frees this
## subtree between runs, which is what stops a restart from leaving two sets of
## highlights behind.
func _install_abilities() -> void:
	_abilities.append(InsightAbility.install(self))
	var call_mate := CallMateAbility.new()
	call_mate.name = "CallMateAbility"
	# The HUD now maps every summon error itself (WP-3.1 extended
	# [method HUD.error_key]), so the ability's own fallback toast would be the
	# second one the player sees. This is the switch WP-3.4 left for exactly
	# this moment.
	call_mate.own_rejection_toasts = false
	add_child(call_mate)
	_abilities.append(call_mate)


## Resume the autosave. Falls back to a fresh game when the slot turns out to be
## unusable, so the button can never leave the player stuck on the title.
func continue_game(slot: String = SaveGame.DEFAULT_SLOT) -> bool:
	_tear_down()
	if not GameSession.load_save(slot):
		start_game(LEVEL_DEFAULT_SEED)
		return false
	state = State.PLAYING
	_build_playing_scene()
	return true


## Play the same mess again.
func restart_same_island() -> void:
	start_game(current_seed())


## Roll a new mess on the same island.
func restart_new_mess() -> void:
	start_game(randi() % 1000000)


## A level spawn point placed on the actual ground, with room to stand.
func spawn_point(index: int) -> Vector3:
	var spawn := GameSession.player_spawn(index)
	if island != null:
		spawn.y = island.height_at(spawn.x, spawn.z) + 1.0
	return spawn


func current_seed() -> int:
	return GameSession.state.rng_seed if GameSession.state != null else level_seed


func is_paused() -> bool:
	return pause_menu != null and pause_menu.is_open()


func _on_island_clean() -> void:
	state = State.EVALUATION
	if pause_menu != null:
		pause_menu.can_open = false # the score is up; Esc has nothing to pause


## Free the level's nodes immediately rather than deferring: a queued node is
## still connected to GameEvents and would react to the next level's events.
func _tear_down() -> void:
	if GameEvents.island_clean.is_connected(_on_island_clean):
		GameEvents.island_clean.disconnect(_on_island_clean)
	GameSession.stop_level()
	get_tree().paused = false
	# Abilities first: they hold connections to GameEvents, and one that outlives
	# a restart animates the next shout twice.
	for node: Node in _abilities + [test_panel, evaluation, pause_menu, hud, player, title_screen, backdrop, island]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()
	_abilities.clear()
	island = null
	player = null
	test_panel = null
	hud = null
	evaluation = null
	title_screen = null
	pause_menu = null
	backdrop = null
