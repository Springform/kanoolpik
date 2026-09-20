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

enum State { TITLE, LOBBY, PLAYING, EVALUATION }

const ISLAND := preload("res://src/game/island/island.tscn")
const PLAYER := preload("res://src/game/player/player.tscn")
const HUD := preload("res://src/game/hud/hud.tscn")
const EVALUATION := preload("res://src/game/hud/evaluation/evaluation_screen.tscn")
const TITLE_SCREEN := preload("res://src/game/title/title_screen.tscn")
const PAUSE_MENU := preload("res://src/game/title/pause_menu.tscn")
const LOBBY_SCREEN := preload("res://src/game/lobby/lobby_screen.tscn")

## Passed to GameSession as "use the level's own default".
const LEVEL_DEFAULT_SEED := -1

@export var level_id := "island_01"
@export var level_seed := LEVEL_DEFAULT_SEED
## Skip the front page and drop straight into a game (handy while developing).
@export var skip_title := false

var state := State.TITLE
var island: Island
## Nodes the running scene installs that subscribe to [GameEvents] or to the
## transport, tracked so [method _tear_down] can free them — one that outlives a
## restart reacts to the next level's events. Mostly phase-3 abilities, plus the
## collectible spawner and phase 4's presence pair.
var _abilities: Array[Node] = []
var player: Player
var hud: HUD
var evaluation: EvaluationScreen
var title_screen: TitleScreen
var pause_menu: PauseMenu
var backdrop: BackdropCamera
## The test-mode admin panel, when this build has one (WP-3.10).
var test_panel: TestPanel
## Multiplayer waiting room (WP-4.4). Both are null in a single-player run —
## "Start alene" never constructs either, so no socket exists to leak.
var lobby: LobbyController
var lobby_screen: LobbyScreen
## The settings panel (WP-5.1). Built once, for the life of the game: it is
## opened from the title screen AND from the pause menu, and it survives
## [method _tear_down] because a panel that is rebuilt per screen is a panel
## whose state has to be rebuilt too.
var settings_panel: SettingsPanel
## The waking-up overlay (WP-5.4). Null when the player has turned it off, and
## null again the moment it ends — it frees itself.
var intro: WakeUp


func _ready() -> void:
	# Before any screen exists: the locale decides what the title screen says,
	# and the bus volumes decide how loud it opens. WP-5.1.
	Settings.apply_all()
	settings_panel = SettingsPanel.install(self)
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
	title_screen.settings_requested.connect(open_settings)
	title_screen.host_requested.connect(to_lobby.bind(""), CONNECT_DEFERRED)
	title_screen.join_requested.connect(to_lobby, CONNECT_DEFERRED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The multiplayer waiting room (WP-4.4). An empty [param room] means "host a
## new one"; anything else is a code somebody read aloud.
##
## The screen goes up before the relay has answered, so a slow Worker looks like
## a room that has not filled yet rather than a button that did nothing.
func to_lobby(room: String) -> void:
	_tear_down()
	state = State.LOBBY
	# The island keeps drifting behind the lobby exactly as it does behind the
	# title: the backdrop is presentation, and the lobby's own world is built by
	# LobbyController the moment a code exists.
	island = ISLAND.instantiate()
	add_child(island)
	backdrop = BackdropCamera.new()
	add_child(backdrop)
	lobby_screen = LOBBY_SCREEN.instantiate()
	add_child(lobby_screen)
	lobby_screen.show_status("ui.lobby.connecting")
	lobby_screen.back_pressed.connect(to_title, CONNECT_DEFERRED)
	lobby = LobbyController.new()
	lobby.name = "LobbyController"
	lobby.level_id = level_id
	add_child(lobby)
	lobby.room_opened.connect(_on_room_opened)
	lobby.peers_changed.connect(_on_peers_changed)
	lobby.failed.connect(_on_lobby_failed)
	lobby.closed.connect(_on_lobby_failed)
	lobby.game_started.connect(start_multiplayer, CONNECT_DEFERRED)
	lobby_screen.start_pressed.connect(lobby.start_game)
	if room.is_empty():
		lobby.host_new_room()
	else:
		lobby.join(room)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_room_opened(room: String, is_host: bool) -> void:
	lobby_screen.show_room(room, is_host, lobby.transport.peer_id())
	lobby_screen.show_status("")


func _on_peers_changed(peers: Array) -> void:
	lobby_screen.set_peers(peers)


func _on_lobby_failed(reason_key: String) -> void:
	lobby_screen.show_status(reason_key)


## Build (or rebuild) a playable level. [param seed] < 0 uses the level default.
func start_game(seed: int = LEVEL_DEFAULT_SEED) -> void:
	_tear_down()
	state = State.PLAYING
	GameSession.start_level(level_id, seed)
	_build_playing_scene()


## Leave the lobby for the island (WP-4.4).
##
## [LobbyController] has already called [method GameSession.start_level] with
## the live transport, so this must [b]not[/b] start a level of its own: doing
## so would build a [LocalTransport] over a fresh world and drop the socket on
## the floor, and the symptom would be a multiplayer game in which nobody else
## exists. The scene is torn down without stopping the session for the same
## reason.
func start_multiplayer() -> void:
	_tear_down(false)
	state = State.PLAYING
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
	# Not deferred: opening settings frees nothing, and the pause menu stays up
	# underneath with the tree still paused.
	pause_menu.settings_requested.connect(open_settings)
	pause_menu.restart_requested.connect(restart_same_island, CONNECT_DEFERRED)
	pause_menu.title_requested.connect(to_title, CONNECT_DEFERRED)
	evaluation = EVALUATION.instantiate()
	add_child(evaluation)
	# WP-4.6: the host walking off ends the round for everyone. Without this the
	# island simply stops — no clock, no other players, nothing said — which
	# reads as the game having crashed.
	if GameSession.transport != null:
		GameSession.transport.disconnected.connect(_on_connection_lost, CONNECT_DEFERRED)
	_install_abilities()
	# WP-4.5. Installed unconditionally: in single player the seam's
	# send_presence does nothing and presence_received never fires, so this is
	# one node doing nothing rather than a branch that can be wrong.
	_abilities.append(PresenceSender.install(self, player))
	_abilities.append(RemotePlayers.install(self, island))
	if TestMode.is_enabled():
		test_panel = TestPanel.new()
		test_panel.name = "TestPanel"
		add_child(test_panel)
	GameEvents.island_clean.connect(_on_island_clean)
	# WP-5.4, and the only line this work package adds outside src/game/fx/.
	# It goes last, after everything a round needs exists, because the intro is
	# drawn over a world that is already running and must never be the thing
	# that starts one. Returns null when the player has switched it off.
	intro = WakeUp.install(self)


## Show the settings panel over whatever is on screen. It never pauses or
## unpauses anything itself — opened from the pause menu the tree is already
## paused and must stay that way; opened from the title there is nothing
## running to pause.
func open_settings() -> void:
	if settings_panel != null:
		settings_panel.open()


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
	_abilities.append(MapSenseAbility.install(self))
	_abilities.append(AutoPlaceAbility.install(self))
	# Not an ability, but the same lifetime problem: it listens to GameEvents and
	# must not outlive a restart.
	_abilities.append(CollectibleSpawner.install(self))


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


## The socket died mid-round. There is no authority any more (ADR 0002), so
## there is no round; say which of the two it was and go back to the title
## rather than leaving people on a world nobody owns.
func _on_connection_lost(reason: String) -> void:
	if state != State.PLAYING:
		return
	var key := LobbyController.reason_key(reason)
	# Read before the tear-down: `to_title` stops the session, and the transport
	# that knows which room we were in goes with it.
	#
	# Only when it was OUR connection that died. If the host left there is no
	# room to go back to — the relay would make us the first socket in a new one
	# and we would be hosting an empty island under a code nobody is coming to.
	# (WP-4.4 catches that and refuses it, but offering it is still a lie.)
	var room := ""
	if reason != WebSocketTransport.R_HOST_GONE and GameSession.transport != null:
		room = GameSession.transport.room_code()
	to_title()
	if title_screen == null:
		return
	title_screen.show_notice("ui.title.rejoin" if not room.is_empty() else key)
	title_screen.prefill_room(room)


func _on_island_clean() -> void:
	state = State.EVALUATION
	if pause_menu != null:
		pause_menu.can_open = false # the score is up; Esc has nothing to pause


## Free the level's nodes immediately rather than deferring: a queued node is
## still connected to GameEvents and would react to the next level's events.
## [param stop_session] false keeps the running level alive while its nodes are
## replaced — the one caller is [method start_multiplayer], where the session
## already owns a live socket that stopping would silence.
func _tear_down(stop_session: bool = true) -> void:
	if GameEvents.island_clean.is_connected(_on_island_clean):
		GameEvents.island_clean.disconnect(_on_island_clean)
	if stop_session:
		# Ending the session means ending the room with it. Leaving the socket
		# to be closed whenever the transport happens to be collected would keep
		# a departed player in everyone else's list for as long as that took.
		if is_instance_valid(lobby):
			lobby.leave()
		GameSession.stop_level()
	get_tree().paused = false
	# Abilities first: they hold connections to GameEvents, and one that outlives
	# a restart animates the next shout twice.
	for node: Node in _abilities + [intro, test_panel, evaluation, pause_menu, hud, player,
			title_screen, lobby_screen, lobby, backdrop, island]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()
	_abilities.clear()
	intro = null
	island = null
	player = null
	test_panel = null
	hud = null
	evaluation = null
	title_screen = null
	pause_menu = null
	backdrop = null
	lobby = null
	lobby_screen = null
