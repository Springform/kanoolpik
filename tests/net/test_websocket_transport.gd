extends GdUnitTestSuite
## WP-4.2 — the [Transport] seam over a real socket.
##
## Real WebSockets, real handshakes, on 127.0.0.1 against [FakeRelay]. What is
## on trial is the same promise WP-4.3 put on trial without sockets: the same
## command list produces the same [WorldState] on every peer. The difference is
## that this time the bytes are real, the ordering is the operating system's,
## and the frames are JSON somebody could have typed by hand.
##
## [b]Against the real relay instead:[/b]
## [codeblock]
##   cd infra/relay && npx wrangler dev &
##   KANOOLPIK_RELAY_URL=ws://localhost:8787 tools/run_tests.sh res://tests/net/
## [/codeblock]
## Every test below then runs unchanged against the Cloudflare Worker. That is
## the only thing that can catch [FakeRelay] having drifted from it, and it is
## the reason this suite is written to care about the protocol rather than about
## the fake.

const PUMP_LIMIT := 400

var _relay: FakeRelay
var _transports: Array[WebSocketTransport] = []
var _cat: Catalog
var _room: String
## Started once per test. FakeRelay.start() binds a port, so calling it twice
## fails with ERR_ALREADY_IN_USE and hands back a URL nothing is listening on.
var _url := ""
## transport instance id -> how many commands it has applied or been refused.
## The heartbeat _settle() listens to.
var _events: Dictionary = {}
var _last_activity := -1


func before_test() -> void:
	_cat = TestFixtures.catalog()
	_room = _random_room()
	_url = ""
	_events.clear()
	_last_activity = -1
	if _external_url().is_empty():
		_relay = FakeRelay.new()


func after_test() -> void:
	for transport in _transports:
		transport.close()
	_transports.clear()
	if _relay != null:
		_relay.stop()
		_relay = null


func _external_url() -> String:
	return OS.get_environment("KANOOLPIK_RELAY_URL")


## A fresh code per test, so one test's peers never wander into another's room —
## which matters most against a live wrangler, where the rooms outlive the test.
func _random_room() -> String:
	const ALPHABET := "BCDFGHJKMNPQRSTVWXYZ23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code := ""
	for i in range(6):
		code += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
	return code


func _base_url() -> String:
	if _url.is_empty():
		var external := _external_url()
		_url = external if not external.is_empty() else _relay.start()
	return _url


func _fresh_state() -> WorldState:
	var state := TestFixtures.ground_state(_cat, Progression.BASE_CAPACITY)
	for id in range(1, 7):
		if not state.has_player(id):
			state.add_player(id, Progression.BASE_CAPACITY)
	state.island_radius = 20.0
	return state


## Every peer starts from an identical world — in the real game that is
## MessGenerator run from the shared seed, which is why nobody ships item
## positions at level start.
func _join(url: String, as_host: bool) -> WebSocketTransport:
	var processor := CommandProcessor.new(_cat)
	processor.allow_debug_commands = true
	var transport := WebSocketTransport.new(url, _room, as_host, processor, _fresh_state())
	var key := transport.get_instance_id()
	_events[key] = 0
	transport.command_applied.connect(func(_c, _r): _events[key] = int(_events[key]) + 1)
	transport.command_rejected.connect(func(_c, _e): _events[key] = int(_events[key]) + 1)
	_transports.append(transport)
	return transport


## One turn of every crank in the test: the relay, then each peer.
func _turn() -> void:
	if _relay != null:
		_relay.poll()
	for transport in _transports:
		transport.poll()
	OS.delay_msec(2)


## Loopback costs microseconds; a real relay in another country costs tens of
## milliseconds each way. A fixed turn count tuned for FakeRelay would make every
## test flaky the moment KANOOLPIK_RELAY_URL points somewhere real — and a flaky
## contract test is one nobody runs, which would quietly cost us the only thing
## that can catch the fake drifting.
func _pump_scale() -> int:
	return 12 if not _external_url().is_empty() else 1


## Drain for a fixed number of turns. Only for the cases where there is nothing
## to wait FOR — checking that something did *not* happen, for instance.
func _pump(turns := 30) -> void:
	for i in range(turns * _pump_scale()):
		_turn()


## Pump until [param condition] holds, or give up. Returns whether it held, so a
## caller can assert on it with a message of its own.
func _pump_until(condition: Callable, budget_turns := PUMP_LIMIT) -> bool:
	for i in range(budget_turns * _pump_scale()):
		if condition.call():
			return true
		_turn()
	return condition.call()


## Wait until the party has stopped moving: nobody has applied or been refused
## anything for several turns running, and every client agrees with the host.
##
## The obvious version of this — "pump until the clients match the host" — is a
## test that cannot fail. Right after a submit the clients DO match the host:
## nothing has been applied anywhere yet, so the condition is true immediately
## and the assertion runs before the command has left the building. It passed on
## loopback by accident, because a handful of drain turns happened to be enough.
## Quiescence is the property actually wanted, so quiescence is what is measured.
func _settle(quiet_turns := 8) -> void:
	var quiet := 0
	var settled := _pump_until(func() -> bool:
		var snapshot := _activity()
		if snapshot == _last_activity:
			quiet += 1
		else:
			quiet = 0
			_last_activity = snapshot
		if quiet < quiet_turns:
			return false
		var truth := _transports[0].state_hash()
		for transport in _transports:
			if transport.is_joined() and transport.state_hash() != truth:
				return false
		return true)
	# Deliberately not asserted: several tests settle at a state the peers do
	# NOT share (a refusal, a divergence) and make their own assertion about it.
	# This only guarantees we waited as long as there was anything to wait for.
	if not settled:
		_pump(4)


## Total commands applied and refused across every peer. Changes on any activity
## anywhere, which is the point: it is a heartbeat, not a measurement.
func _activity() -> int:
	var total := 0
	for key in _events:
		total += int(_events[key])
	return total


func _await_joined(transports: Array) -> void:
	var joined := _pump_until(func() -> bool:
		for transport in transports:
			if not (transport as WebSocketTransport).is_joined():
				return false
		return true)
	assert_bool(joined).override_failure_message("peers never finished joining").is_true()


func _party(client_count: int) -> Array[WebSocketTransport]:
	var url := _base_url()
	var out: Array[WebSocketTransport] = [_join(url, true)]
	_await_joined([out[0]])
	for i in range(client_count):
		var client := _join(url, false)
		_await_joined([client])
		out.append(client)
	_settle()
	return out


## WorldState exposes one location dictionary rather than an accessor per field;
## these two keep the assertions readable.
func _carrier(transport: WebSocketTransport, item_id: String) -> int:
	return int(transport.state.location(item_id).get("player_id", -1))


func _position(transport: WebSocketTransport, item_id: String) -> Vector3:
	return transport.state.location(item_id).get("position", Vector3.ZERO)


# --- The harness can see a failure ---------------------------------------------

## First, because it makes every other test in this file mean something. If two
## peers always compared equal, everything below would pass while proving
## nothing — the exact trap WP-4.3 fell into twice.
func test_two_peers_that_actually_differ_are_reported_as_different() -> void:
	var party := _party(1)
	party[1].state.set_on_ground("can_a1", Vector3(9, 0, 9))
	assert_int(party[0].state_hash()).is_not_equal(party[1].state_hash())


func test_the_relay_gives_the_first_arrival_peer_one_and_numbers_the_rest() -> void:
	var party := _party(2)
	assert_int(party[0].peer_id()).is_equal(1)
	assert_bool(party[0].is_authority()).is_true()
	assert_int(party[1].peer_id()).is_equal(2)
	assert_bool(party[1].is_authority()).is_false()
	assert_int(party[2].peer_id()).is_equal(3)


# --- The promise ---------------------------------------------------------------

func test_a_mixed_run_leaves_host_and_clients_identical() -> void:
	var party := _party(2)
	var host := party[0]
	var a := party[1]
	var b := party[2]

	a.submit_command(Commands.pick_up(a.peer_id(), "can_a1"))
	_settle()
	a.submit_command(Commands.place(a.peer_id(), "can_a1", "pant_bag", 0))
	_settle()
	b.submit_command(Commands.pick_up(b.peer_id(), "food_bread"))
	_settle()
	b.submit_command(Commands.drop(b.peer_id(), "food_bread", Vector3(2.5, 0.125, -3.75)))
	_settle()
	host.submit_command(Commands.grant_points(host.peer_id(), 5))
	_settle()
	host.submit_command(Commands.unlock(host.peer_id(), "call_mate"))
	_settle()

	assert_dict(a.state.to_dict()).override_failure_message(
		"client 2 drifted from the host").is_equal(host.state.to_dict())
	assert_dict(b.state.to_dict()).override_failure_message(
		"client 3 drifted from the host").is_equal(host.state.to_dict())


## Rule 1. A client that applied its own command first would be one command
## ahead of the host between sending and hearing back — briefly, invisibly, and
## permanently once a command is refused.
func test_a_client_does_not_apply_its_own_command_before_the_host_says_so() -> void:
	var party := _party(1)
	var client := party[1]
	var before := client.state_hash()
	client.submit_command(Commands.pick_up(client.peer_id(), "can_a1"))
	# No pumping: the frame has not even left yet.
	assert_int(client.state_hash()).override_failure_message(
		"the client changed its own world before the host had seen the command").is_equal(before)
	_settle()
	assert_int(client.state_hash()).is_not_equal(before)


## Rule 2, and the reason [CommandCodec] refuses to enforce it: a decoded frame
## is only as honest as whoever sent it. Peer 2 claims to be peer 1 here; the
## can must end up in peer 2's hands.
func test_a_client_cannot_act_as_another_player() -> void:
	var party := _party(1)
	var host := party[0]
	var liar := party[1]

	var forged := Commands.pick_up(1, "can_a1") # "I am the host"
	liar.submit_command(forged)
	_settle()

	assert_int(_carrier(host, "can_a1")).override_failure_message(
		"a client picked something up as another player").is_equal(liar.peer_id())


## Rule 3. The hash travels with the command precisely so that a peer which has
## already drifted finds out at the next command instead of at the end of the
## game.
func test_a_diverged_client_is_told_at_the_next_command() -> void:
	var party := _party(1)
	var host := party[0]
	var client := party[1]
	# Reach in and break it, which is the one thing gameplay can never do.
	client.state.set_on_ground("can_b1", Vector3(5, 0, 5))

	var divergences: Array = []
	client.diverged.connect(func(_c, _e, _a): divergences.append(true))
	host.submit_command(Commands.pick_up(host.peer_id(), "can_a1"))
	_pump_until(func() -> bool: return not divergences.is_empty())

	assert_int(divergences.size()).override_failure_message(
		"a client applied a command onto a state that no longer matched and said nothing").is_greater(0)


func test_a_rejected_command_reaches_the_sender_and_changes_nothing_anywhere() -> void:
	var party := _party(1)
	var host := party[0]
	var client := party[1]
	var before := host.state.to_dict()

	var rejections: Array = []
	client.command_rejected.connect(func(_cmd, error): rejections.append(error))
	client.submit_command(Commands.pick_up(client.peer_id(), "no_such_item"))
	_pump_until(func() -> bool: return not rejections.is_empty())

	assert_array(rejections).override_failure_message(
		"the client was never told its command was refused").is_not_empty()
	assert_str(rejections[0]).is_equal(CommandProcessor.E_UNKNOWN_ITEM)
	assert_dict(host.state.to_dict()).is_equal(before)
	assert_dict(client.state.to_dict()).is_equal(before)


func test_commands_are_applied_in_the_order_they_were_sent() -> void:
	# WP-4.3's first finding: a pick-up and the place that depends on it,
	# applied the wrong way round, desync that peer permanently. A WebSocket is
	# ordered per connection, so this should be free — this test is what says so.
	var party := _party(1)
	var host := party[0]
	var client := party[1]

	for i in range(12):
		client.submit_command(Commands.pick_up(client.peer_id(), "can_a1"))
		client.submit_command(Commands.drop(client.peer_id(), "can_a1", Vector3(i, 0, 0)))
	_settle()

	assert_dict(client.state.to_dict()).is_equal(host.state.to_dict())
	assert_vector(_position(host, "can_a1")).is_equal(Vector3(11, 0, 0))


# --- Joining late --------------------------------------------------------------

func test_a_late_joiner_receives_the_world_including_progression() -> void:
	var party := _party(1)
	var host := party[0]
	var early := party[1]

	early.submit_command(Commands.pick_up(early.peer_id(), "can_a1"))
	_settle()
	early.submit_command(Commands.place(early.peer_id(), "can_a1", "pant_bag", 0))
	_settle()
	host.submit_command(Commands.grant_points(host.peer_id(), 7))
	_settle()
	host.submit_command(Commands.unlock(host.peer_id(), "call_mate"))
	_settle()

	var late := _join(_base_url(), false)
	_await_joined([late])
	_settle()

	assert_dict(late.state.to_dict()).override_failure_message(
		"the late joiner did not arrive in the party's world").is_equal(host.state.to_dict())
	# Spelled out, because "the dicts match" would also pass if progression were
	# missing from both: ADR 0010 put it inside the state for exactly this.
	assert_bool(late.state.progression.has("call_mate")).is_true()


func test_a_late_joiner_keeps_up_with_what_happens_after_it_arrives() -> void:
	var party := _party(1)
	var host := party[0]
	var late := _join(_base_url(), false)
	_await_joined([late])
	_settle()

	host.submit_command(Commands.pick_up(host.peer_id(), "peg_1"))
	_settle()
	assert_dict(late.state.to_dict()).is_equal(host.state.to_dict())


# --- When it goes wrong --------------------------------------------------------

func test_the_host_leaving_is_reported_rather_than_swallowed() -> void:
	var party := _party(1)
	var client := party[1]
	var reasons: Array = []
	client.disconnected.connect(func(reason): reasons.append(reason))

	party[0].close()
	_pump_until(func() -> bool: return not reasons.is_empty())

	assert_array(reasons).override_failure_message(
		"the client never noticed the host had gone").is_not_empty()


func test_a_command_submitted_after_the_socket_died_is_refused_not_crashed() -> void:
	var party := _party(1)
	var client := party[1]
	client.close()
	var rejections: Array = []
	client.command_rejected.connect(func(_cmd, error): rejections.append(error))
	client.submit_command(Commands.pick_up(client.peer_id(), "can_a1"))
	assert_array(rejections).contains([WebSocketTransport.E_NOT_CONNECTED])


## The relay never parses `d`, so the host is the first thing to look at these
## bytes. A hostile frame must cost the sender its command and cost the room
## nothing.
func test_a_hostile_frame_is_refused_without_disturbing_the_room() -> void:
	var party := _party(2)
	var host := party[0]
	var innocent := party[2]
	var before := host.state.to_dict()

	# Straight down the socket, bypassing submit_command — which is exactly what
	# somebody with the room code and a browser console would do.
	var liar := party[1]
	liar._send({"k": WebSocketTransport.K_COMMAND, "c": {
		"type": "drop", "player_id": 1, "item_id": "can_a1", "position": [1e999, 0, 0],
	}})
	_pump(40)

	assert_dict(host.state.to_dict()).override_failure_message(
		"a crafted frame changed the host's world").is_equal(before)
	assert_dict(innocent.state.to_dict()).is_equal(before)
	# And the room still works afterwards.
	innocent.submit_command(Commands.pick_up(innocent.peer_id(), "can_a1"))
	_settle()
	assert_int(_carrier(host, "can_a1")).is_equal(innocent.peer_id())


## Commands submitted before `welcome` arrives are queued, not dropped. A player
## who mashes a key during the handshake should not silently lose the action.
func test_a_command_submitted_before_joining_is_sent_once_joined() -> void:
	var url := _base_url()
	var host := _join(url, true)
	_await_joined([host])
	var client := _join(url, false)
	client.submit_command(Commands.pick_up(0, "can_a1")) # peer id not known yet
	_await_joined([client])
	_settle()

	assert_int(_carrier(host, "can_a1")).override_failure_message(
		"a command submitted during the handshake was lost").is_equal(client.peer_id())


## The host is subject to the same wire rules as everybody else, and that is not
## pedantry: a command the host can apply but cannot transmit is a silent
## divergence. The host would move the can, every client would refuse the
## broadcast as out of bounds, and nobody would be told — the host's own frames
## are the one path where a hash mismatch is never checked, because the host has
## nothing to compare itself against.
##
## So the host runs its own commands through the codec before applying them, and
## refuses what it could not have sent. Found by mutation: removing that step
## left all fourteen tests above green.
func test_the_host_refuses_its_own_command_when_it_could_not_be_transmitted() -> void:
	var party := _party(1)
	var host := party[0]
	var client := party[1]
	host.submit_command(Commands.pick_up(host.peer_id(), "can_a1"))
	_settle()

	var rejections: Array = []
	host.command_rejected.connect(func(_cmd, error): rejections.append(error))
	# Far outside CommandCodec.MAX_COORD, so no client could decode it.
	host.submit_command(Commands.drop(host.peer_id(), "can_a1", Vector3(50000, 0, 0)))
	_pump_until(func() -> bool: return not rejections.is_empty())

	assert_array(rejections).override_failure_message(
		"the host applied a command no client could have received").is_not_empty()
	assert_dict(client.state.to_dict()).override_failure_message(
		"the host moved an item the clients never heard about").is_equal(host.state.to_dict())
