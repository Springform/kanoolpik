extends GdUnitTestSuite
## Reconnect, which turned out not to need a number.
##
## The open question at the end of WP-4.6 was: how long does a dropped player
## keep their seat? Remove them at once and a ten-second tunnel costs somebody
## their armful; hold the seat and a room of six fills with ghosts.
##
## [b]KA's answer was to ask a different question.[/b] Joining a round that is
## already running works, and nothing personal is lost when you go — progression
## lives in the replicated [WorldState], so you come back with the party's points
## and abilities. So there is no seat to hold: drop them straight away and let
## them walk back in.
##
## That left exactly two things worth fixing, and neither of them is a number:
## where the armful lands, and how you find the room again.

const NEAR := 2.0

var _main: Main


func before_test() -> void:
	GameSession.start_level("island_01", 4242)


func after_test() -> void:
	if is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_main = null
	GameSession.stop_level()


# --- Where the armful lands ----------------------------------------------------------

func test_a_dropped_players_armful_falls_where_they_were_standing() -> void:
	var pid := 2
	GameSession.submit(Commands.join(pid))
	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	GameSession.submit(Commands.pick_up(pid, item_id))
	assert_int(GameSession.state.kind_of(item_id)).is_equal(WorldState.Kind.CARRIED)

	# What RemotePlayers does on every transform it decodes. The y is a body
	# centre, as it is on the wire.
	var stood_at := Vector3(6.0, GameSession.ground_y() + 0.9, -4.0)
	GameSession.remember_peer_position(pid, stood_at)
	GameSession._on_peer_left(pid)

	assert_bool(GameSession.state.has_player(pid)).is_false()
	var where: Vector3 = GameSession.state.location(item_id)["position"]
	assert_float(Vector2(where.x, where.z).distance_to(Vector2(stood_at.x, stood_at.z))
		).override_failure_message(
		"the armful landed at %s, %.1f m from where they were standing"
		% [where, Vector2(where.x, where.z).distance_to(Vector2(stood_at.x, stood_at.z))]
	).is_less(NEAR)


func test_the_armful_lands_flat_whatever_height_it_was_told() -> void:
	# The transform handed over is a body centre, about 0.9 m up, and it is
	# passed along unflattened on purpose: WorldState.clamp_to_island already
	# drops every position to ground_y, and saying it twice is how two places
	# start to differ. So what this pins is that guarantee, along the whole path
	# a leaver's armful actually takes — a clamp that kept the y it was given
	# would leave six items hanging in the air where somebody logged off.
	var pid := 2
	GameSession.submit(Commands.join(pid))
	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	GameSession.submit(Commands.pick_up(pid, item_id))
	GameSession.remember_peer_position(pid, Vector3(3.0, 99.0, 3.0))
	GameSession._on_peer_left(pid)

	var where: Vector3 = GameSession.state.location(item_id)["position"]
	assert_float(where.y).override_failure_message(
		"a body centre was stored as a world position").is_equal_approx(
		GameSession.ground_y(), 0.01)


func test_somebody_who_never_moved_still_drops_their_armful() -> void:
	# No transform ever arrived, so there is nothing remembered. The spawn point
	# is the fallback: wrong, but wrong somewhere a person walks past.
	var pid := 2
	GameSession.submit(Commands.join(pid))
	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	GameSession.submit(Commands.pick_up(pid, item_id))
	GameSession._on_peer_left(pid)

	assert_int(GameSession.state.kind_of(item_id)).override_failure_message(
		"the item went with them").is_equal(WorldState.Kind.GROUND)


func test_a_position_does_not_outlive_its_round() -> void:
	GameSession.remember_peer_position(3, Vector3(5, 0, 5))
	GameSession.stop_level()
	GameSession.start_level("island_01", 4242)
	GameSession.submit(Commands.join(3))
	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	GameSession.submit(Commands.pick_up(3, item_id))
	GameSession._on_peer_left(3)

	var where: Vector3 = GameSession.state.location(item_id)["position"]
	var spawn := GameSession.player_spawn(0)
	assert_float(Vector2(where.x, where.z).distance_to(Vector2(spawn.x, spawn.z))
		).override_failure_message(
		"a position from the previous round decided where this one's items fell"
	).is_less(NEAR)


# --- How you find the room again ------------------------------------------------------

func test_the_code_is_waiting_in_the_field() -> void:
	var title: TitleScreen = auto_free(load("res://src/game/title/title_screen.tscn").instantiate())
	add_child(title)
	await get_tree().process_frame

	title.prefill_room("bcd-fgh")
	assert_str(title.room_input.text).override_failure_message(
		"the code was not normalised on the way in").is_equal("BCDFGH")


func test_an_empty_code_leaves_the_field_alone() -> void:
	var title: TitleScreen = auto_free(load("res://src/game/title/title_screen.tscn").instantiate())
	add_child(title)
	await get_tree().process_frame
	# Six characters: the field has max_length 7, and a longer string would be
	# truncated by the LineEdit rather than by anything under test.
	title.room_input.text = "XYZ234"

	title.prefill_room("")
	assert_str(title.room_input.text).is_equal("XYZ234")


func test_a_dropped_connection_offers_the_way_back() -> void:
	await _playing_in_room("BCDFGH")
	_main._on_connection_lost(WebSocketTransport.R_SOCKET_CLOSED)
	await get_tree().process_frame

	assert_str(_main.title_screen.room_input.text).override_failure_message(
		"the player was sent back to the title with nothing to type").is_equal("BCDFGH")
	assert_str(_main.title_screen.notice_label.text).is_equal(tr("ui.title.rejoin"))


func test_the_host_leaving_offers_nothing_to_go_back_to() -> void:
	# There is no room any more. The relay would make us the first socket in a
	# new one, and we would be hosting an empty island under a code nobody is
	# coming to — WP-4.4 catches that and refuses it, but offering it is a lie.
	await _playing_in_room("BCDFGH")
	_main._on_connection_lost(WebSocketTransport.R_HOST_GONE)
	await get_tree().process_frame

	assert_str(_main.title_screen.room_input.text).override_failure_message(
		"the player is being invited back into a room that ended").is_empty()
	assert_str(_main.title_screen.notice_label.text).is_equal(
		tr(LobbyController.reason_key(WebSocketTransport.R_HOST_GONE)))


# --- Helpers -----------------------------------------------------------------------

## A running level whose transport believes it is in [param code].
func _playing_in_room(code: String) -> void:
	_main = load("res://src/game/main/main.tscn").instantiate()
	_main.skip_title = true
	add_child(_main)
	await get_tree().process_frame
	GameSession.transport = InARoom.new(code)


## Enough of a transport to be in a room. The routing rule under test is about
## what [Main] asks the transport before tearing it down, not about a socket.
class InARoom extends Transport:
	var _code: String

	func _init(code: String) -> void:
		_code = code

	func room_code() -> String:
		return _code

	func submit_command(_command: Dictionary) -> void:
		pass
