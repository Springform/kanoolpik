extends GdUnitTestSuite
## WP-4.6 — arriving, leaving and the host walking off, over a real socket.
##
## The core suite (`tests/unit/core/test_join_leave.gd`) proves the two commands
## do the right thing to a world. This one proves the right peer issues them, at
## the right moment, and that a stranger in the room cannot issue them about
## somebody else — which is the part that needs a socket to be worth testing.
##
## Same shape as the WP-4.2 suite, and for the same reason: set
## `KANOOLPIK_RELAY_URL` and every test below runs unchanged against the
## deployed Worker instead of [FakeRelay].

const PUMP_LIMIT := 400

var _relay: FakeRelay
var _transports: Array[WebSocketTransport] = []
var _cat: Catalog
var _room: String
var _url := ""


func before_test() -> void:
	_cat = TestFixtures.catalog()
	_room = _random_room()
	_url = ""
	if _external_url().is_empty():
		_relay = FakeRelay.new()


func after_test() -> void:
	for transport in _transports:
		transport.close()
	_transports.clear()
	if _relay != null:
		_relay.stop()
		_relay = null


# --- Who knows who is in the room -------------------------------------------------

func test_a_late_arrival_learns_about_everyone_already_here() -> void:
	# The gap WP-4.4 wrote down and left open: the ids in the relay's `welcome`
	# frame were read and thrown away, so the fourth person to arrive saw an
	# empty room. They are kept now.
	var host: WebSocketTransport = await _open_room()
	var second: WebSocketTransport = await _add_guest()
	# Held in a variable so it stays connected for the duration of the test —
	# nothing else refers to it, hence the underscore.
	var _third: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 3)

	var fourth: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return fourth.known_peers().size() == 4)
	assert_array(fourth.known_peers()).override_failure_message(
		"the fourth arrival cannot see peers 2 and 3").is_equal([1, 2, 3, 4])
	assert_array(second.known_peers()).is_equal([1, 2, 3, 4])


func test_somebody_who_closes_their_tab_leaves_the_roster() -> void:
	var host: WebSocketTransport = await _open_room()
	var guest: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	guest.close()
	await _until(func() -> bool: return host.known_peers().size() == 1)
	assert_array(host.known_peers()).is_equal([1])


# --- The host is the one who decides who is playing ---------------------------------

func test_the_host_puts_an_arrival_into_the_world() -> void:
	var host: WebSocketTransport = await _open_room()
	# What GameSession does on peer_joined, done here directly: this suite is
	# about the transport, and test_lobby covers the wiring.
	var guest: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)

	host.submit_command(Commands.join(2))
	await _until(func() -> bool: return guest.state.has_player(2))
	assert_bool(host.state.has_player(2)).is_true()
	assert_int(guest.state.player_capacity(2)).is_equal(host.state.player_capacity(2))
	assert_int(guest.state_hash()).override_failure_message(
		"the guest applied the join and landed somewhere else").is_equal(host.state_hash())


func test_a_leaver_looks_the_same_on_every_peer() -> void:
	var host: WebSocketTransport = await _open_room()
	var _guest: WebSocketTransport = await _add_guest()
	var watcher: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 3)
	host.submit_command(Commands.join(2))
	host.submit_command(Commands.join(3))
	await _until(func() -> bool: return watcher.state.has_player(2) and watcher.state.has_player(3))

	host.submit_command(Commands.pick_up(2, "can_a1"))
	await _until(func() -> bool: return watcher.state.kind_of("can_a1") == WorldState.Kind.CARRIED)

	host.submit_command(Commands.leave(2, Vector3(4.0, 0.0, 4.0)))
	await _until(func() -> bool: return not watcher.state.has_player(2))
	assert_int(watcher.state.kind_of("can_a1")).is_equal(WorldState.Kind.GROUND)
	assert_int(watcher.state_hash()).is_equal(host.state_hash())


# --- A stranger in the room -----------------------------------------------------------

func test_a_client_cannot_remove_another_player() -> void:
	# The room code is the only access control (docs/NETWORKING.md), so anyone
	# who hears it is in. The stamp is what stops them being a problem: the host
	# overwrites player_id with the SENDER's peer id, so this frame can only
	# remove the sender.
	var host: WebSocketTransport = await _open_room()
	var attacker: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	host.submit_command(Commands.join(2))
	await _until(func() -> bool: return host.state.has_player(2))

	attacker.submit_command(Commands.leave(1, Vector3.ZERO))
	# The stamp turns this into "peer 2 leaves", which IS allowed — so the
	# observable effect of the attack landing is the attacker removing itself.
	# Waiting for that beats pumping a fixed number of turns: 40 turns is 80 ms,
	# a round trip on loopback and nothing at all against Cloudflare, and a test
	# that asserts "the bad thing did not happen" proves nothing until the frame
	# has had its chance. `net-live` said so the first time it ran this.
	await _until(func() -> bool: return not host.state.has_player(2))
	assert_bool(host.state.has_player(1)).override_failure_message(
		"a client talked the host into removing the host").is_true()


func test_a_client_cannot_add_a_player_of_its_choosing() -> void:
	# Same shape, same reason: wait for proof the frame was judged, then check
	# the verdict. The stamp turns `join(5)` into `join(2)`, peer 2 is already a
	# player, so the host refuses it and tells the sender — and that refusal is
	# the signal this waits on.
	var host: WebSocketTransport = await _open_room()
	var attacker: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	host.submit_command(Commands.join(2))
	await _until(func() -> bool: return host.state.has_player(2))

	var refusals: Array[String] = []
	attacker.command_rejected.connect(
		func(_c: Dictionary, error: String) -> void: refusals.append(error))
	attacker.submit_command(Commands.join(5))
	await _until(func() -> bool: return not refusals.is_empty())
	assert_str(refusals[0]).override_failure_message(
		"the forged join was not refused for the reason the stamp implies"
	).is_equal(CommandProcessor.E_ALREADY_JOINED)
	assert_bool(host.state.has_player(5)).override_failure_message(
		"a client invented a player").is_false()


func test_a_client_cannot_give_itself_bigger_pockets() -> void:
	# `join` has no capacity field at all, so there is nothing to smuggle — but
	# a frame carrying one must not produce a command carrying one either. That
	# is CommandCodec's whitelist, checked here because this is where somebody
	# would try it.
	var forged := {"type": Commands.JOIN, "player_id": 2, "capacity": 99}
	var decoded := CommandCodec.from_wire(CommandCodec.to_wire(forged))
	assert_bool(decoded["ok"]).is_true()
	assert_bool(decoded["command"].has("capacity")).override_failure_message(
		"the codec let an unknown field through").is_false()


# --- The host walking off ---------------------------------------------------------

func test_the_host_leaving_tells_everyone_rather_than_freezing_them() -> void:
	var host: WebSocketTransport = await _open_room()
	var guest: WebSocketTransport = await _add_guest()
	var reasons: Array[String] = []
	guest.disconnected.connect(func(reason: String) -> void: reasons.append(reason))

	host.close()
	await _until(func() -> bool: return not reasons.is_empty())
	assert_str(reasons[0]).is_equal(WebSocketTransport.R_HOST_GONE)
	assert_str(LobbyController.reason_key(reasons[0])).override_failure_message(
		"there is no sentence to show for the commonest way a round ends"
	).is_equal("ui.lobby.error.host_left")


func test_the_reason_survives_the_farewell_being_lost() -> void:
	# What actually protects the sentence the player reads.
	#
	# [b]Godot drops buffered packets when a WebSocket reaches STATE_CLOSED[/b] —
	# measured, not assumed: the socket goes from OPEN with one packet straight
	# to CLOSED with none, in one poll. So the `hostgone` frame can be lost, and
	# against the deployed relay it was: `net-live` was red here while every
	# loopback run was green.
	#
	# The close code cannot be lost, because it is the close. This test throws
	# the frame away on purpose and checks the answer is still right.
	if _relay == null:
		return # needs a relay this test can crank by hand
	var host: WebSocketTransport = await _open_room()
	var guest: WebSocketTransport = await _add_guest()
	var reasons: Array[String] = []
	guest.disconnected.connect(func(reason: String) -> void: reasons.append(reason))

	host.close()
	_relay.poll()
	OS.delay_msec(2)
	# Drain the socket behind the transport's back, so whatever the relay said
	# in a message is gone by the time the transport looks.
	guest._socket.poll()
	while guest._socket.get_available_packet_count() > 0:
		guest._socket.get_packet()
	guest.poll()

	assert_array(reasons).override_failure_message(
		"the guest never noticed the room had ended").is_not_empty()
	assert_str(reasons[0]).override_failure_message(
		"with the frame gone, only the close code could answer — and it did not"
	).is_equal(WebSocketTransport.R_HOST_GONE)


func test_a_dropped_socket_is_not_the_host_leaving() -> void:
	# Both end the round, and they say different things. Telling somebody the
	# host left when their own wifi died sends them to ask an innocent friend
	# what they did.
	assert_str(LobbyController.reason_key(WebSocketTransport.R_SOCKET_CLOSED)).is_equal(
		LobbyController.E_LOST)
	assert_str(LobbyController.reason_key(WebSocketTransport.R_HOST_GONE)).is_not_equal(
		LobbyController.E_LOST)


# --- Helpers -----------------------------------------------------------------------

func _external_url() -> String:
	return OS.get_environment("KANOOLPIK_RELAY_URL")


func _base_url() -> String:
	if _url.is_empty():
		var external := _external_url()
		_url = external if not external.is_empty() else _relay.start()
	return _url


func _fresh_state() -> WorldState:
	var state := TestFixtures.ground_state(_cat, Progression.BASE_CAPACITY)
	state.island_radius = 20.0
	return state


## The room's host: the first socket in.
##
## [b]Nobody else may connect until this one has been welcomed.[/b] "The first
## socket in a room is the host" is the relay's rule, so two sockets opened back
## to back are racing to decide who the authority is. On loopback the host
## always won, which is why every test here passed locally and `net-live` logged
## "asked to be host=true but the relay made us host=false" — across the
## Atlantic the guest's handshake can finish first.
##
## The game never has this problem: the host mints a code and reads it aloud, so
## there is a person in the loop between the two connections. The tests have to
## put that ordering back by hand.
func _open_room() -> WebSocketTransport:
	var host := _join(true)
	await _until(func() -> bool: return host.is_joined())
	return host


## Somebody else, admitted only once the room has a host. Sequential, so the
## peer ids come out 1, 2, 3, … in the order the tests ask for them.
func _add_guest() -> WebSocketTransport:
	var guest := _join(false)
	await _until(func() -> bool: return guest.is_joined())
	return guest


## Every peer starts from an identical world — in the real game that is
## MessGenerator run from the seed the room code names (WP-4.4).
func _join(as_host: bool) -> WebSocketTransport:
	var processor := CommandProcessor.new(_cat)
	var transport := WebSocketTransport.new(_base_url(), _room, as_host, processor, _fresh_state())
	_transports.append(transport)
	return transport


func _turn() -> void:
	if _relay != null:
		_relay.poll()
	for transport in _transports:
		transport.poll()
	OS.delay_msec(2)


## Waits on a condition rather than a turn count, so the suite survives being
## pointed at a relay in another country (`net-live`).
func _until(condition: Callable) -> void:
	var limit := PUMP_LIMIT * (12 if not _external_url().is_empty() else 1)
	for i in limit:
		if condition.call():
			return
		_turn()
	assert_bool(condition.call()).override_failure_message(
		"condition never became true within %d turns" % limit).is_true()


func _random_room() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code := ""
	for i in RoomCode.LENGTH:
		code += RoomCode.ALPHABET[rng.randi_range(0, RoomCode.ALPHABET.length() - 1)]
	return code
