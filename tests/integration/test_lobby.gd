extends GdUnitTestSuite
## WP-4.4 — the lobby: a code, a room, and six people on the same island.
##
## [b]The thing that must not go wrong[/b] is at the top: two peers given the
## same room code must build byte-identical worlds before a single command is
## issued. Everything else here is about getting people into the room and
## telling them why when they cannot.
##
## The sockets are real (127.0.0.1, [FakeRelay]) and so is the HTTP
## ([FakeRoomService]). What is faked is the far end, never the client.
##
## Only the host's [LobbyController] is driven through [GameSession], because
## there is one of those per process. The other peers in a room are raw
## [WebSocketTransport]s, exactly as the WP-4.2 suite uses them.

const PUMP_LIMIT := 400
## Two codes and the islands they name. Pinned: [method RoomCode.seed_for]
## decides which world six people stand in, so a change to it is a change to
## everybody's game and has to be a decision, not a refactor.
const PINNED_SEEDS := {"BCDFGH": 73308507, "ZZZ999": 1232693026}

var _relay: FakeRelay
var _rooms: FakeRoomService
var _lobby: LobbyController
var _extra: Array[WebSocketTransport] = []
var _cat: Catalog
var _failures: Array[String] = []
var _closures: Array[String] = []
var _opened: Array = []
var _rosters: Array = []
var _started := 0


func before_test() -> void:
	_cat = TestFixtures.catalog()
	_relay = FakeRelay.new()
	_rooms = FakeRoomService.new()
	_failures.clear()
	_closures.clear()
	_opened.clear()
	_rosters.clear()
	_started = 0
	GameSession.autosave_enabled = false
	OS.set_environment(RelayEndpoint.ENV_WS, _relay.start())
	OS.set_environment(RelayEndpoint.ENV_HTTP, _rooms.start())


func after_test() -> void:
	if _lobby != null:
		_lobby.leave()
		_lobby = null
	for transport in _extra:
		transport.close()
	_extra.clear()
	_relay.stop()
	_rooms.stop()
	OS.set_environment(RelayEndpoint.ENV_WS, "")
	OS.set_environment(RelayEndpoint.ENV_HTTP, "")
	GameSession.stop_level()
	GameSession.autosave_enabled = true


# --- The thing that must not go wrong -------------------------------------------------

func test_two_peers_given_the_same_code_build_identical_worlds() -> void:
	# No network in this test on purpose. This is the promise the lobby is
	# built on: the code is the seed, so nothing about the level has to travel.
	GameSession.start_level("island_01", RoomCode.seed_for("BCDFGH"))
	var first: Dictionary = GameSession.state.to_dict()
	GameSession.start_level("island_01", RoomCode.seed_for("bcd-fgh"))
	var second: Dictionary = GameSession.state.to_dict()
	assert_str(JSON.stringify(second)).is_equal(JSON.stringify(first))


func test_a_different_code_is_a_different_island() -> void:
	GameSession.start_level("island_01", RoomCode.seed_for("BCDFGH"))
	var first: Dictionary = GameSession.state.to_dict()
	GameSession.start_level("island_01", RoomCode.seed_for("ZZZ999"))
	assert_str(JSON.stringify(GameSession.state.to_dict())).is_not_equal(JSON.stringify(first))


func test_the_seed_a_code_names_never_moves() -> void:
	for code: String in PINNED_SEEDS:
		assert_int(RoomCode.seed_for(code)).is_equal(int(PINNED_SEEDS[code]))


func test_the_seed_is_positive_for_every_code_shape() -> void:
	# A negative seed would be read as "use the level default" by
	# GameSession.start_level, silently putting a whole room on the wrong island.
	for i in 200:
		assert_int(RoomCode.seed_for(_random_room())).is_greater_equal(0)


# --- Codes -----------------------------------------------------------------------------

func test_the_alphabet_matches_the_protocol_document() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/NETWORKING.md")
	assert_bool(doc.contains(RoomCode.ALPHABET)).override_failure_message(
		"docs/NETWORKING.md no longer states the alphabet RoomCode uses").is_true()


func test_codes_are_case_insensitive_and_survive_being_read_aloud() -> void:
	assert_bool(RoomCode.is_valid("bcdfgh")).is_true()
	assert_bool(RoomCode.is_valid("BCD-FGH")).is_true()
	assert_bool(RoomCode.is_valid(" bcd fgh ")).is_true()
	assert_str(RoomCode.normalize("bcd-fgh")).is_equal("BCDFGH")
	assert_str(RoomCode.spaced("bcdfgh")).is_equal("BCD-FGH")


func test_a_code_outside_the_alphabet_is_not_a_code() -> void:
	assert_bool(RoomCode.is_valid("AEIOUY")).is_false() # vowels
	assert_bool(RoomCode.is_valid("BCDFG0")).is_false() # zero
	assert_bool(RoomCode.is_valid("BCDFG1")).is_false() # one
	assert_bool(RoomCode.is_valid("BCDFG")).is_false() # too short
	assert_bool(RoomCode.is_valid("BCDFGHJ")).is_false() # too long
	assert_bool(RoomCode.is_valid("")).is_false()


func test_a_bad_code_fails_before_a_socket_is_opened() -> void:
	_new_lobby()
	_lobby.join("NOPE")
	assert_array(_failures).contains([LobbyController.E_BAD_CODE])
	assert_object(_lobby.transport).override_failure_message(
		"a code we already know is wrong must not cost a connection").is_null()


# --- The relay host is stated once ------------------------------------------------------

func test_the_net_live_workflow_can_still_read_the_relay_host() -> void:
	# net-live.yml greps RelayEndpoint for the address instead of carrying a
	# repository variable, because the same host in two places is how the
	# compatibility_date bug happened. If this fails, the workflow is reading
	# nothing and will run against whatever it defaults to.
	var source := FileAccess.get_file_as_string(RelayEndpoint.SOURCE_PATH)
	var re := RegEx.new()
	# (?m) is what makes "^" mean "start of a line" rather than "start of the
	# file". grep is line-based and needs no such flag, which is the one
	# difference between the two readers of this pattern.
	assert_int(re.compile("(?m)" + RelayEndpoint.HOST_PATTERN)).is_equal(OK)
	var found := re.search(source)
	assert_object(found).override_failure_message(
		"net-live.yml's pattern no longer matches relay_endpoint.gd").is_not_null()
	assert_str(found.get_string(1)).is_equal(RelayEndpoint.HOST)


func test_the_http_base_follows_the_socket_override() -> void:
	# One override must not leave the other pointing at the deployed Worker, or
	# a unit test would mint live room codes on somebody's Cloudflare account.
	OS.set_environment(RelayEndpoint.ENV_HTTP, "")
	OS.set_environment(RelayEndpoint.ENV_WS, "wss://example.test")
	assert_str(RelayEndpoint.http_base()).is_equal("https://example.test")
	OS.set_environment(RelayEndpoint.ENV_WS, "ws://127.0.0.1:9999")
	assert_str(RelayEndpoint.http_base()).is_equal("http://127.0.0.1:9999")


func test_a_shipped_build_can_only_reach_the_baked_in_host() -> void:
	OS.set_environment(RelayEndpoint.ENV_WS, "")
	OS.set_environment(RelayEndpoint.ENV_HTTP, "")
	assert_bool(RelayEndpoint.is_default()).is_true()
	assert_str(RelayEndpoint.ws_base()).is_equal("wss://" + RelayEndpoint.HOST)
	assert_str(RelayEndpoint.http_base()).is_equal("https://" + RelayEndpoint.HOST)


# --- Asking for a room ------------------------------------------------------------------

func test_hosting_mints_a_code_and_opens_the_room() -> void:
	_rooms.code = "BCDFGH"
	_new_lobby()
	_lobby.host_new_room()
	await _until(func() -> bool: return not _opened.is_empty())
	assert_array(_opened).is_equal([["BCDFGH", true]])
	assert_bool(_lobby.is_host).is_true()
	assert_int(_rooms.requests).override_failure_message(
		"one button press is one request — no retry behind the player's back").is_equal(1)


func test_a_relay_that_answers_rubbish_is_a_reason_not_a_crash() -> void:
	_rooms.body_override = "<html>not json at all</html>"
	_new_lobby()
	_lobby.host_new_room()
	await _until(func() -> bool: return not _failures.is_empty())
	assert_array(_failures).contains([RoomService.E_RELAY])


func test_a_code_the_relay_did_not_mint_is_refused() -> void:
	# The response decides which island six people stand on. It is the first
	# thing read from across the internet and it is validated like one.
	_rooms.body_override = JSON.stringify({"code": "AEIOUY"})
	_new_lobby()
	_lobby.host_new_room()
	await _until(func() -> bool: return not _failures.is_empty())
	assert_array(_failures).contains([RoomService.E_RELAY])


# --- The room ----------------------------------------------------------------------------

func test_the_roster_grows_and_shrinks_as_friends_come_and_go() -> void:
	var room := await _hosted_room()
	var guest := _guest(room)
	await _until(func() -> bool: return _lobby.peers.size() == 2)
	assert_array(_lobby.peers).is_equal([1, 2])

	guest.close()
	await _until(func() -> bool: return _lobby.peers.size() == 1)
	assert_array(_lobby.peers).override_failure_message(
		"somebody who closed their tab is still in the list").is_equal([1])
	assert_bool(_rosters.size() >= 3).is_true()


func test_joining_a_code_nobody_is_hosting_says_so() -> void:
	# The failure that looks exactly like success: the relay makes the first
	# socket in a room the host, so a typo would quietly open an empty room and
	# leave somebody waiting in it forever.
	_new_lobby()
	_lobby.join(_random_room())
	await _until(func() -> bool: return not _failures.is_empty())
	assert_array(_failures).contains([LobbyController.E_NO_SUCH_ROOM])
	assert_bool(_started == 0).is_true()


# --- Handing the room to the game ---------------------------------------------------------

func test_starting_hands_the_live_socket_to_the_session() -> void:
	await _hosted_room()
	_lobby.start_game()
	assert_int(_started).is_equal(1)
	assert_object(GameSession.transport).is_same(_lobby.transport)
	assert_bool(GameSession.is_running()).is_true()


func test_the_session_and_the_transport_share_one_world() -> void:
	# The wiring test. start_level builds a fresh WorldState from the same seed:
	# identical in content, a different object. Two objects for one world is a
	# desync no hash can catch, because each peer stays consistent with itself.
	await _hosted_room()
	_lobby.start_game()
	assert_object(GameSession.transport.state).override_failure_message(
		"the transport is applying commands to a world the game cannot see"
	).is_same(GameSession.state)
	assert_object(GameSession.transport.processor).is_same(GameSession.processor)


func test_the_island_survives_being_handed_over() -> void:
	# Regenerating must not produce a different world from the one a guest was
	# already given a snapshot of.
	var room := await _hosted_room()
	var before: String = JSON.stringify(_lobby.transport.state.to_dict())
	_lobby.start_game()
	assert_str(JSON.stringify(GameSession.state.to_dict())).is_equal(before)
	assert_str(room).is_not_empty()


func test_the_clock_does_not_run_while_people_are_still_arriving() -> void:
	await _hosted_room()
	var ticks: int = _lobby.transport.state.elapsed_ticks
	await _pump(30)
	assert_int(_lobby.transport.state.elapsed_ticks).override_failure_message(
		"the lobby is ticking the world before anybody has set off").is_equal(ticks)


# --- What the screen says ------------------------------------------------------------------

func test_a_refused_join_does_not_claim_you_are_in() -> void:
	# Found by looking at it, not by a test: the client heading was
	# unconditional, so "Du er med" sat directly above "Ingen runde med den
	# kode". Every assertion about both strings passed.
	var screen: LobbyScreen = auto_free(load("res://src/game/lobby/lobby_screen.tscn").instantiate())
	add_child(screen)
	screen.show_status(LobbyController.E_NO_SUCH_ROOM)
	assert_str(screen.heading.text).is_equal(tr("ui.lobby.joining_heading"))
	assert_str(screen.heading.text).is_not_equal(tr("ui.lobby.client_heading"))
	assert_int(screen.roster.get_child_count()).override_failure_message(
		"a refused join is drawing a roster for a room it is not in").is_equal(0)


func test_only_the_host_is_offered_the_button_that_starts_the_game() -> void:
	var screen: LobbyScreen = auto_free(load("res://src/game/lobby/lobby_screen.tscn").instantiate())
	add_child(screen)
	screen.show_room("BCDFGH", false, 4)
	assert_bool(screen.start_button.visible).is_false()
	assert_bool(screen.copy_button.visible).is_false()
	screen.show_room("BCDFGH", true, 1)
	assert_bool(screen.start_button.visible).is_true()
	assert_str(screen.code_label.text).override_failure_message(
		"the code is grouped for reading aloud").is_equal("BCD-FGH")


func test_every_lobby_string_has_a_translation() -> void:
	# A missing row shows the key itself on screen, in 64 px if it is unlucky.
	const KEYS := [
		"ui.title.host", "ui.title.join", "ui.title.room_hint",
		"ui.lobby.host_heading", "ui.lobby.client_heading", "ui.lobby.joining_heading",
		"ui.lobby.copy", "ui.lobby.copied", "ui.lobby.connecting", "ui.lobby.start",
		"ui.lobby.leave", "ui.lobby.waiting_for_host", "ui.lobby.player_n",
		"ui.lobby.seats_left", "ui.lobby.error.bad_code", "ui.lobby.error.no_such_room",
		"ui.lobby.error.network", "ui.lobby.error.relay", "ui.lobby.error.busy",
		"ui.lobby.error.full", "ui.lobby.error.host_left", "ui.lobby.error.lost",
	]
	for locale in ["da", "en"]:
		TranslationServer.set_locale(locale)
		for key: String in KEYS:
			assert_str(tr(key)).override_failure_message(
				"%s has no %s translation" % [key, locale]).is_not_equal(key)
	TranslationServer.set_locale("da")


# --- Single player is untouched ------------------------------------------------------------

func test_single_player_goes_nowhere_near_a_socket() -> void:
	var main: Main = auto_free(load("res://src/game/main/main.tscn").instantiate())
	add_child(main)
	main.title_screen.start_requested.emit(Main.LEVEL_DEFAULT_SEED)
	await await_millis(50)
	assert_int(main.state).is_equal(Main.State.PLAYING)
	assert_object(main.lobby).is_null()
	assert_object(main.lobby_screen).is_null()
	assert_bool(GameSession.transport is LocalTransport).override_failure_message(
		"single player built a network transport").is_true()


# --- Helpers ---------------------------------------------------------------------------------

func _new_lobby() -> void:
	_lobby = auto_free(LobbyController.new())
	_lobby.level_id = "island_01"
	add_child(_lobby)
	_lobby.room_opened.connect(func(c: String, h: bool) -> void: _opened.append([c, h]))
	_lobby.peers_changed.connect(func(p: Array) -> void: _rosters.append(p.duplicate()))
	_lobby.failed.connect(func(r: String) -> void: _failures.append(r))
	_lobby.closed.connect(func(r: String) -> void: _closures.append(r))
	_lobby.game_started.connect(func() -> void: _started += 1)


## A lobby that is hosting an open room. Returns the code.
func _hosted_room() -> String:
	_rooms.code = _random_room()
	_new_lobby()
	_lobby.host_new_room()
	await _until(func() -> bool: return not _opened.is_empty())
	return _lobby.code


## Another peer in the room, as a raw transport — there is one [GameSession] per
## process, so a second [LobbyController] would fight this one for it.
func _guest(room: String) -> WebSocketTransport:
	var processor := CommandProcessor.new(_cat)
	var transport := WebSocketTransport.new(
		RelayEndpoint.ws_base(), room, false, processor, TestFixtures.ground_state(_cat, 3))
	_extra.append(transport)
	return transport


## One turn of every crank: the fakes, the guests, and the frame that lets
## LobbyController._process pump its own socket.
func _turn() -> void:
	_relay.poll()
	_rooms.poll()
	for transport in _extra:
		transport.poll()
	await get_tree().process_frame


func _pump(turns: int) -> void:
	for i in turns:
		await _turn()


## Waits on a condition rather than a turn count, so the suite survives being
## pointed at a relay in another country (`net-live`).
func _until(condition: Callable) -> void:
	for i in PUMP_LIMIT:
		if condition.call():
			return
		await _turn()
	assert_bool(condition.call()).override_failure_message(
		"condition never became true within %d turns" % PUMP_LIMIT).is_true()


func _random_room() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code := ""
	for i in RoomCode.LENGTH:
		code += RoomCode.ALPHABET[rng.randi_range(0, RoomCode.ALPHABET.length() - 1)]
	return code
