extends GdUnitTestSuite
## WP-4.6 — `join` and `leave` as commands, in the pure core.
##
## Being in the room is not being in the world. These two commands are what
## turns a peer into a player and back, and they are commands rather than direct
## calls for the reason everything else is: a peer that changes its own state is
## a peer whose hash stops matching, one command later, with nothing able to say
## why.

var cat: Catalog
var proc: CommandProcessor
var state: WorldState


func before_test() -> void:
	cat = TestFixtures.catalog()
	proc = CommandProcessor.new(cat)
	state = TestFixtures.ground_state(cat, Progression.BASE_CAPACITY)
	state.island_radius = 20.0


# --- Joining -------------------------------------------------------------------

func test_a_peer_becomes_a_player_with_the_party_capacity() -> void:
	assert_bool(state.has_player(4)).is_false()
	var result := proc.apply(state, Commands.join(4))
	assert_bool(result["ok"]).is_true()
	assert_bool(state.has_player(4)).is_true()
	assert_int(state.player_capacity(4)).is_equal(state.progression.capacity())
	assert_str(result["events"][0]["type"]).is_equal("player_joined")


func test_capacity_is_the_partys_not_the_commands() -> void:
	# The command has no capacity field at all, so there is nothing to forge.
	# A newcomer to a party that has bought Rolige hænder gets the big pockets;
	# a newcomer cannot ask for them.
	state.progression.points = 10
	assert_bool(state.progression.unlock("steady_hands")).is_true()
	proc.apply(state, Commands.join(4))
	assert_int(state.player_capacity(4)).is_equal(state.progression.capacity())
	assert_int(state.player_capacity(4)).is_greater(Progression.BASE_CAPACITY)


func test_joining_twice_is_refused_rather_than_resetting_a_player() -> void:
	proc.apply(state, Commands.join(4))
	var again := proc.apply(state, Commands.join(4))
	assert_bool(again["ok"]).is_false()
	assert_str(again["error"]).is_equal(CommandProcessor.E_ALREADY_JOINED)


func test_a_command_nobody_stamped_cannot_add_a_player() -> void:
	# -1 is what an unstamped command carries and 0 is what a transport reports
	# before the relay has welcomed it. Neither is a peer.
	for bogus in [-1, 0]:
		var result := proc.apply(state, Commands.join(bogus))
		assert_bool(result["ok"]).override_failure_message(
			"player_id %d was accepted as a peer" % bogus).is_false()


# --- Leaving -------------------------------------------------------------------

func test_a_leaver_drops_their_armful_where_they_stood() -> void:
	var here := Vector3(6.0, 0.0, -3.0)
	proc.apply(state, Commands.join(4))
	var carried := _fill_hands(4)
	assert_int(carried.size()).is_greater(0)

	var result := proc.apply(state, Commands.leave(4, here))
	assert_bool(result["ok"]).is_true()
	assert_bool(state.has_player(4)).is_false()
	for item_id in carried:
		assert_int(state.kind_of(item_id)).is_equal(WorldState.Kind.GROUND)
		var where: Vector3 = state.location(item_id)["position"]
		assert_float(where.distance_to(here)).override_failure_message(
			"%s landed %.1f m from where the player stood" % [item_id, where.distance_to(here)]
		).is_less_equal(CommandProcessor.DROP_RING_RADIUS + 0.001)


func test_the_armful_is_not_one_unclickable_pile() -> void:
	proc.apply(state, Commands.join(4))
	var carried := _fill_hands(4)
	if carried.size() < 2:
		return
	proc.apply(state, Commands.leave(4, Vector3(6.0, 0.0, -3.0)))
	var first: Vector3 = state.location(carried[0])["position"]
	var second: Vector3 = state.location(carried[1])["position"]
	assert_bool(first.is_equal_approx(second)).override_failure_message(
		"two of the leaver's items are at the same coordinate").is_false()


func test_every_dropped_item_is_announced() -> void:
	# The presentation layer already knows how to animate an item_dropped, so a
	# friend's wifi dying looks like them putting things down.
	proc.apply(state, Commands.join(4))
	var carried := _fill_hands(4)
	var result := proc.apply(state, Commands.leave(4, Vector3(2.0, 0.0, 2.0)))
	var dropped: Array[String] = []
	for event: Dictionary in result["events"]:
		if event["type"] == "item_dropped":
			dropped.append(String(event["item_id"]))
	dropped.sort()
	carried.sort()
	assert_array(dropped).is_equal(carried)
	assert_str(result["events"][result["events"].size() - 1]["type"]).is_equal("player_left")


func test_a_leaver_never_drops_anything_in_the_lake() -> void:
	proc.apply(state, Commands.join(4))
	_fill_hands(4)
	# Standing on the very edge: half the ring would be over water.
	proc.apply(state, Commands.leave(4, Vector3(state.island_radius, 0.0, 0.0)))
	for item_id in state.items_of_kind(WorldState.Kind.GROUND):
		var p: Vector3 = state.location(item_id)["position"]
		assert_float(Vector2(p.x, p.z).length()).override_failure_message(
			"%s is in the water" % item_id).is_less_equal(state.island_radius + 0.001)


func test_leaving_a_world_you_are_not_in_is_refused() -> void:
	var result := proc.apply(state, Commands.leave(9, Vector3.ZERO))
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).is_equal(CommandProcessor.E_UNKNOWN_PLAYER)


func test_the_party_keeps_its_points_when_somebody_leaves() -> void:
	# Progression is party-wide and lives in the replicated state (ADR 0010).
	# Losing it because the person who packed the cooler went home would be a
	# punishment for their wifi.
	state.progression.points = 5
	proc.apply(state, Commands.join(4))
	proc.apply(state, Commands.leave(4, Vector3.ZERO))
	assert_int(state.progression.points).is_equal(5)


# --- Determinism ----------------------------------------------------------------

func test_two_peers_applying_the_same_leave_land_in_the_same_place() -> void:
	# Every peer computes the ring from the command, so no coordinate travels
	# and none is rounded differently anywhere.
	proc.apply(state, Commands.join(4))
	_fill_hands(4)
	# A second peer with a byte-identical world, as a client's snapshot is.
	var other := WorldState.from_dict(state.to_dict())
	var other_proc := CommandProcessor.new(cat)
	proc.apply(state, Commands.leave(4, Vector3(3.0, 0.0, 1.0)))
	other_proc.apply(other, Commands.leave(4, Vector3(3.0, 0.0, 1.0)))
	assert_str(JSON.stringify(other.to_dict())).is_equal(JSON.stringify(state.to_dict()))


# --- Helpers ---------------------------------------------------------------------

## Put as much in the player's hands as they can hold. Returns the item ids.
func _fill_hands(pid: int) -> Array[String]:
	for item_id in state.items_of_kind(WorldState.Kind.GROUND):
		proc.apply(state, Commands.pick_up(pid, item_id))
	return state.carried_by(pid)
