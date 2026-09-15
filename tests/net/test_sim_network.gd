extends GdUnitTestSuite
## WP-4.3 — six peers, one authority, no sockets.
##
## What is on trial here is not the harness. It is the promise the core has been
## built on since phase 0: the same command list produces the same [WorldState]
## everywhere. Two states in one process have been compared for a year. Six peers
## passing commands through an authority never have.
##
## The first test below is the one that makes the rest mean anything: it proves
## this harness can *see* a divergence. A harness that always reports agreement
## would pass every test in this file and tell us nothing.

const PEERS := 6

var cat: Catalog


func before_test() -> void:
	cat = TestFixtures.catalog()


func _net(peer_count := PEERS) -> SimNetwork:
	return SimNetwork.new(peer_count, cat, func() -> WorldState:
		var state := TestFixtures.ground_state(cat, Progression.BASE_CAPACITY)
		state.island_radius = 20.0
		return state)


## A run that touches every command the game has, issued from several peers.
##
## Deliberately never acts as peer 4: the disconnect test takes peer 4 away, and
## a run whose actor is the peer being removed tests nothing about catching up.
func _a_busy_run(net: SimNetwork) -> void:
	net.submit(2, Commands.pick_up(2, "food_bread"))
	net.flush()
	net.submit(2, Commands.place(2, "food_bread", "cooler", 0))
	net.flush()
	net.submit(3, Commands.grant_points(3, 5))
	net.flush()
	net.submit(3, Commands.unlock(3, "call_mate"))
	net.flush()
	net.submit(2, Commands.pick_up(2, "pole_1"))
	net.flush()
	net.submit(2, Commands.summon(2, "poles", Vector3(2, 0, 1)))
	net.flush()
	net.submit(5, Commands.collect(5, "trolley"))
	net.flush()
	net.submit(6, Commands.pick_up(6, "can_a1"))
	net.flush()
	net.submit(6, Commands.place(6, "can_a1", "pant_bag", 0))
	net.flush()
	net.submit(2, Commands.take_out(2, "food_bread"))
	net.flush()
	net.submit(1, Commands.tick(120))
	net.flush()


# --- The harness must be able to fail ------------------------------------------

func test_the_harness_notices_when_a_peer_is_wrong() -> void:
	# Everything else in this file is worthless if this does not hold.
	var net := _net()
	_a_busy_run(net)
	assert_bool(net.states_agree()).override_failure_message(
		"the run diverged before the check could even be tested").is_true()

	# Corrupt one peer behind the harness's back.
	net.peer(4).state.set_on_ground("can_b1", Vector3(9, 0, 9))
	assert_bool(net.states_agree()).override_failure_message(
		"a peer was made wrong on purpose and the harness still said they agree"
	).is_false()
	assert_str(net.divergence()).override_failure_message(
		"the divergence message must name the peer and the key, or it is useless"
	).contains("peer 4")
	assert_str(net.divergence()).contains("can_b1")


func test_the_divergence_message_names_the_field_not_just_the_item() -> void:
	var net := _net()
	net.peer(3).state.elapsed_ticks = 999
	assert_str(net.divergence()).contains("elapsed_ticks")
	assert_str(net.divergence()).contains("999")


# --- The promise ----------------------------------------------------------------

func test_six_peers_agree_after_a_busy_run() -> void:
	var net := _net()
	_a_busy_run(net)
	assert_str(net.divergence()).is_empty()
	# And it actually did something, rather than agreeing about an empty world.
	assert_int(net.accepted_log().size()).is_greater(8)
	assert_bool(net.authority().state.progression.has("call_mate")).is_true()


func test_latency_does_not_change_the_outcome() -> void:
	var slow := _net()
	slow.latency_ticks = 12 # 200 ms at 60 Hz
	_a_busy_run(slow)
	var fast := _net()
	_a_busy_run(fast)
	assert_str(slow.divergence()).is_empty()
	assert_dict(slow.authority().state.to_dict()).override_failure_message(
		"the same commands over a slow link produced a different world"
	).is_equal(fast.authority().state.to_dict())


func test_the_reorder_knob_actually_reorders_something() -> void:
	# Guard for the test below, and a lesson worth keeping: the first version of
	# the reordering test flushed after every command, so there was never more
	# than one message in flight per peer and the shuffle had nothing to shuffle.
	# It passed for weeks' worth of confidence it had not earned.
	var net := _net()
	net.latency_ticks = 3
	net.reorder_window = 8
	var seen: Array[String] = []
	net.peer(3).command_applied.connect(
		func(command: Dictionary, _r: Dictionary) -> void:
			seen.append(String(command.get("item_id", command.get("type", "?")))))
	# Several commands in flight at once, so one peer's queue has something to
	# scramble. These are independent items: any order is legal.
	net.submit(2, Commands.pick_up(2, "can_a1"))
	net.submit(3, Commands.pick_up(3, "can_a2"))
	net.submit(5, Commands.pick_up(5, "can_b1"))
	net.submit(6, Commands.pick_up(6, "peg_1"))
	net.flush()
	assert_int(seen.size()).override_failure_message(
		"peer 3 never received four broadcasts, so nothing could be out of order"
	).is_equal(4)
	assert_array(seen).override_failure_message(
		"the reorder window delivered in submission order — it is not reordering"
	).is_not_equal(["can_a1", "can_a2", "can_b1", "peg_1"])


func test_out_of_order_delivery_breaks_the_world_which_is_why_ordering_is_required() -> void:
	# This is a finding, not a wish. Transport's contract says commands must be
	# applied "in the same order on every peer", and here is the proof that the
	# requirement is real rather than defensive: a pick-up and the place that
	# depends on it, delivered the wrong way round, leave that peer behind.
	#
	# It is also the reason the transport must be an ORDERED one. WebSocket is
	# ordered per connection and gives this away for free (ADR 0011); an
	# unreliable WebRTC data channel would not, and would have needed a
	# resequencing layer nobody had budgeted for.
	var net := _net()
	net.latency_ticks = 3
	net.reorder_window = 8
	net.submit(2, Commands.pick_up(2, "can_a1"))
	net.submit(2, Commands.place(2, "can_a1", "pant_bag", 0))
	net.flush()
	assert_bool(net.states_agree()).override_failure_message(
		"dependent commands arrived out of order and every peer still agreed — "
		+ "either the shuffle is not shuffling or this test has stopped meaning anything"
	).is_false()


func test_even_unrelated_pick_ups_are_order_sensitive() -> void:
	# A finding, written down as a test so it cannot be forgotten.
	#
	# The expectation going in was that six people picking up six DIFFERENT
	# things must not care what order they are applied in. They do care, and the
	# reason is [member WorldState._carry_counter]: it is global, and it stamps a
	# `carry_seq` on every item as it is picked up, so the same set of unrelated
	# pick-ups in a different order produces different numbers and therefore a
	# different snapshot. Reproduced in isolation: two players, two items, two
	# orders, `carry_seq` 1 vs 2.
	#
	# Functionally it changes nothing a player can see — the counter only orders
	# a single player's own hands — but it means **no two commands commute**, and
	# so the transport must deliver in order. WebSocket does, per connection, for
	# free (ADR 0011). An unreliable channel would have needed a resequencing
	# layer that nobody had budgeted for.
	#
	# Making the counter per-player would make unrelated pick-ups commute. That
	# is a core change on a replicated field and is KA's call, not this WP's.
	var shuffled := _net()
	shuffled.latency_ticks = 3
	shuffled.reorder_window = 8
	var unrelated := [
		Commands.pick_up(2, "can_a1"), Commands.pick_up(3, "can_a2"),
		Commands.pick_up(4, "can_b1"), Commands.pick_up(5, "peg_1"),
		Commands.pick_up(6, "peg_2"), Commands.pick_up(2, "food_bread"),
	]
	for command in unrelated:
		shuffled.submit(int(command["player_id"]), command)
	shuffled.flush()
	assert_bool(shuffled.states_agree()).override_failure_message(
		"unrelated pick-ups now commute — if that is deliberate, delete this test "
		+ "and the note in STATUS about the global carry counter"
	).is_false()

	# Every item still ended up in the right hands; it is only the bookkeeping
	# that differs. That is what makes this a latent trap rather than a live bug.
	var host := shuffled.authority().state
	assert_int(host.location("can_a1")["player_id"]).is_equal(2)
	assert_int(host.location("peg_1")["player_id"]).is_equal(5)


func test_a_rejected_command_changes_nothing_anywhere() -> void:
	var net := _net()
	# Peer 5 has no points, so this cannot be bought.
	var before := net.authority().state.to_dict()
	net.submit(5, Commands.unlock(5, "auto_place"))
	net.flush()
	assert_dict(net.authority().state.to_dict()).override_failure_message(
		"a refused command still moved the authority").is_equal(before)
	assert_str(net.divergence()).is_empty()
	assert_bool(net.authority().state.progression.has("auto_place")).is_false()


func test_the_sender_hears_about_a_rejection_and_nobody_else_does() -> void:
	var net := _net()
	var heard: Array[String] = []
	for id in net.peer_ids():
		net.peer(id).command_rejected.connect(
			func(_cmd: Dictionary, error: String, who := id) -> void:
				heard.append("%d:%s" % [who, error]))
	net.submit(5, Commands.unlock(5, "auto_place"))
	net.flush()
	assert_array(heard).override_failure_message(
		"exactly one peer — the one who asked — should have been told"
	).contains_exactly(["5:" + CommandProcessor.E_NOT_ENOUGH_POINTS])


# --- Losing and regaining a peer ------------------------------------------------

func test_a_disconnected_peer_is_left_behind_and_a_snapshot_catches_it_up() -> void:
	var net := _net()
	net.submit(2, Commands.pick_up(2, "food_bread"))
	net.flush()

	net.disconnect_peer(4)
	_a_busy_run(net) # the world moves on without peer 4
	assert_str(net.divergence()).override_failure_message(
		"the connected peers should still agree while one is away").is_empty()

	var away := net.peer(4).state.to_dict()
	assert_dict(away).override_failure_message(
		"peer 4 was disconnected but somehow kept up"
	).is_not_equal(net.authority().state.to_dict())

	net.reconnect_peer(4)
	assert_str(net.divergence()).override_failure_message(
		"the snapshot did not bring the returning peer all the way back").is_empty()
	# The snapshot carries the party's progress, not just where things lie —
	# which is the whole reason ADR 0010 moved progression inside the state.
	var back := net.peer(4).state.progression
	assert_bool(back.has("call_mate")).is_true()
	assert_bool(back.can_summon("poles")).is_false()
	assert_bool(back.has_found("trolley")).is_true()
	assert_int(back.available_points()).is_equal(
		net.authority().state.progression.available_points())


func test_a_disconnected_peer_cannot_submit() -> void:
	var net := _net()
	net.disconnect_peer(3)
	var errors: Array[String] = []
	net.peer(3).command_rejected.connect(
		func(_cmd: Dictionary, error: String) -> void: errors.append(error))
	net.submit(3, Commands.pick_up(3, "can_a1"))
	net.flush()
	assert_array(errors).contains_exactly([SimNetwork.E_DISCONNECTED])
	assert_int(net.authority().state.kind_of("can_a1")).is_equal(WorldState.Kind.GROUND)


func test_a_dropped_message_does_not_silently_desync() -> void:
	# If a broadcast is lost, the peer that missed it is behind — and the harness
	# must be able to say so. Silently "agreeing" here would mean the check is
	# not looking at anything.
	var net := _net()
	net.submit(2, Commands.pick_up(2, "can_a1"))
	net.flush()
	net.submit(2, Commands.place(2, "can_a1", "pant_bag", 0))
	# One tick delivers the request to the authority, which queues the broadcasts;
	# they go out on the next one. Dropping before the flush therefore eats a
	# broadcast rather than the request — drop the request and nothing happens at
	# all, which is agreement, not a desync.
	net.deliver(1)
	net.drop_next(1)
	net.flush()
	assert_bool(net.states_agree()).override_failure_message(
		"a message was dropped and every peer still claimed to agree").is_false()


# --- Two people reaching for the same thing -------------------------------------

func test_two_peers_grabbing_the_same_item_resolve_the_same_way_everywhere() -> void:
	var net := _net()
	net.submit(2, Commands.pick_up(2, "can_a1"))
	net.submit(3, Commands.pick_up(3, "can_a1"))
	net.flush()
	assert_str(net.divergence()).override_failure_message(
		"the two peers disagreed about who got the can").is_empty()
	# Exactly one of them is holding it, and it is the same one on every peer.
	var holder: int = net.authority().state.location("can_a1")["player_id"]
	assert_int(holder).is_in([2, 3])
	for id in net.peer_ids():
		assert_int(int(net.peer(id).state.location("can_a1")["player_id"])).override_failure_message(
			"peer %d thinks somebody else is holding the can" % id).is_equal(holder)
	assert_int(net.accepted_log().size()).override_failure_message(
		"both pick-ups were accepted — the second should have been refused"
	).is_equal(1)


func test_the_authority_decides_order_not_the_sender() -> void:
	# Peer 6 asks first but its message is slow; peer 2 asks later over a fast
	# link. Whatever the authority accepts first is what every peer sees.
	var net := _net()
	net.latency_ticks = 6
	net.submit(6, Commands.pick_up(6, "peg_1"))
	net.deliver(2)
	net.submit(2, Commands.pick_up(2, "peg_1"))
	net.flush()
	assert_str(net.divergence()).is_empty()
	assert_int(net.accepted_log().size()).is_equal(1)


# --- The clock ------------------------------------------------------------------

func test_only_the_authority_moves_the_clock() -> void:
	var net := _net()
	net.peer(3).tick(0.016) # a client trying to advance time
	net.flush()
	assert_int(net.authority().state.elapsed_ticks).override_failure_message(
		"a client moved the simulation clock").is_equal(0)
	net.authority().tick(0.016)
	net.flush()
	assert_int(net.authority().state.elapsed_ticks).is_equal(1)
	assert_str(net.divergence()).is_empty()
