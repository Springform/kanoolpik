extends GdUnitTestSuite
## WP-4.5 — the other five people, and what they cost.
##
## Two halves, deliberately. [Presence] is pure and is tested as arithmetic: no
## socket, no scene, no waiting. The rest needs a real transport, because the
## interesting claims are about who is allowed to move whom and how many frames
## went out — neither of which a stub could be wrong about.
##
## Same harness as `tests/net/`: set `KANOOLPIK_RELAY_URL` and the socket half
## runs unchanged against the deployed Worker.

const PUMP_LIMIT := 400
## A metre is far past MOVED_EPSILON and far short of TELEPORT_DISTANCE.
const A_STEP := Vector3(1.0, 0.0, 0.0)

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


# --- The wire shape ----------------------------------------------------------------

func test_a_transform_survives_the_round_trip() -> void:
	var there := Vector3(4.25, 1.5, -9.0)
	var decoded := Presence.from_wire(Presence.to_wire(there, 1.25))
	assert_vector(decoded["position"] as Vector3).is_equal_approx(there, Vector3.ONE * Presence.STEP)
	assert_float(decoded["yaw"]).is_equal_approx(1.25, Presence.STEP)


func test_a_frame_that_is_not_a_transform_is_no_news() -> void:
	# A malformed presence is one avatar not moving for one tick, not an error:
	# the far end of this is the open internet, and the only safe answer to a
	# frame we do not understand is to ignore it. Same discipline as CommandCodec.
	for junk: Variant in [null, 7, "t", {}, {"t": "over there"}, {"t": [1.0, 2.0]},
			{"t": [1.0, 2.0, 3.0, 4.0, 5.0]}, {"t": [1.0, "2", 3.0, 4.0]}]:
		assert_dict(Presence.from_wire(junk)).override_failure_message(
			"%s was accepted as a transform" % [junk]).is_empty()


func test_a_position_that_is_not_a_number_is_refused() -> void:
	# NaN is the nasty one: it decodes as a float, teleports an avatar nowhere,
	# and then every later comparison against it is false — so it stays there.
	assert_dict(Presence.from_wire({"t": [NAN, 0.0, 0.0, 0.0]})).is_empty()
	assert_dict(Presence.from_wire({"t": [0.0, INF, 0.0, 0.0]})).is_empty()


func test_standing_still_is_not_a_change() -> void:
	var here := Vector3(3.0, 1.0, 3.0)
	var last := {"position": here, "yaw": 0.5}
	assert_bool(Presence.differs(here, 0.5, last)).override_failure_message(
		"a player who has not moved would send a frame").is_false()
	# Below the rounding: this would serialise to the identical frame.
	assert_bool(Presence.differs(here + Vector3(0.001, 0, 0), 0.5, last)).is_false()
	assert_bool(Presence.differs(here + A_STEP, 0.5, last)).is_true()
	assert_bool(Presence.differs(here, 1.5, last)).override_failure_message(
		"turning on the spot is movement — it is what people aim with").is_true()


func test_the_first_frame_always_sends() -> void:
	assert_bool(Presence.differs(Vector3.ZERO, 0.0, {})).is_true()


func test_turning_the_long_way_round_is_still_a_small_turn() -> void:
	# Just either side of the wrap. A naive subtraction makes this 6.2 radians
	# and reports a spin every frame somebody faces north.
	var last := {"position": Vector3.ZERO, "yaw": PI - 0.005}
	assert_bool(Presence.differs(Vector3.ZERO, -PI + 0.005, last)).is_false()


# --- What it costs -----------------------------------------------------------------

func test_a_room_where_nobody_moves_sends_nothing() -> void:
	# The acceptance criterion, as a number. Six people standing still reading
	# labels is the most common state this game is in, and it must be free.
	var host: WebSocketTransport = await _open_room()
	var guest: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	var before := host.presence_sent + guest.presence_sent

	for i in 30:
		host.send_presence({})
		guest.send_presence({})
		_turn()

	assert_int(host.presence_sent + guest.presence_sent).override_failure_message(
		"thirty ticks of nobody moving put %d frames on the wire"
		% [host.presence_sent + guest.presence_sent - before]).is_equal(before)


func test_the_host_merges_the_room_into_one_frame() -> void:
	# Five uplinks and ONE fan-out, not five forwards. This is the difference
	# between six incoming messages a tick and eleven, and ADR 0011's "~9 hours
	# a day at 10 Hz" is costed at six. See WebSocketTransport.send_presence.
	var host: WebSocketTransport = await _open_room()
	var second: WebSocketTransport = await _add_guest()
	var third: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 3)

	second.send_presence(Presence.to_wire(Vector3(1, 0, 0), 0.0))
	third.send_presence(Presence.to_wire(Vector3(2, 0, 0), 0.0))
	await _until(func() -> bool: return host._presence_pending.size() == 2)

	var before := host.presence_sent
	host.send_presence(Presence.to_wire(Vector3(3, 0, 0), 0.0))
	assert_int(host.presence_sent - before).override_failure_message(
		"the host sent %d frames to report three people" % [host.presence_sent - before]
	).is_equal(1)


func test_a_host_standing_still_still_forwards_everybody_else() -> void:
	# The reason send_presence is called with {} rather than not called at all.
	# A host reading a label while five people walk around must not stop the
	# room seeing each other.
	var host: WebSocketTransport = await _open_room()
	var guest: WebSocketTransport = await _add_guest()
	var third: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 3)
	var seen: Array[int] = []
	third.presence_received.connect(func(peer_id: int, _p: Dictionary) -> void: seen.append(peer_id))

	guest.send_presence(Presence.to_wire(A_STEP, 0.0))
	await _until(func() -> bool: return not host._presence_pending.is_empty())
	host.send_presence({})
	await _until(func() -> bool: return not seen.is_empty())

	assert_array(seen).override_failure_message(
		"peer 3 never heard about peer 2 because the host was standing still").contains([2])


# --- Who is allowed to move whom ---------------------------------------------------

func test_a_client_cannot_move_somebody_elses_avatar() -> void:
	# The same stamp as rule 2 of the command path, for the same reason: a frame
	# is whatever the other end chose to type. Peer 3 claims to be peer 2.
	var host: WebSocketTransport = await _open_room()
	var _second: WebSocketTransport = await _add_guest()
	var third: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 3)
	var moved: Array[int] = []
	host.presence_received.connect(func(peer_id: int, _p: Dictionary) -> void: moved.append(peer_id))

	# Hand-built rather than through send_presence, which would stamp it
	# correctly — the point is a peer that does not use our client.
	third._put({"k": WebSocketTransport.K_PRESENCE,
		"p": {"2": Presence.to_wire(Vector3(9, 0, 9), 0.0)}})
	await _until(func() -> bool: return not moved.is_empty())

	assert_array(moved).override_failure_message(
		"a frame claiming to be peer 2 was believed").not_contains([2])
	assert_array(moved).contains([3])
	# And what the host is about to tell the room. Believing the claim only on
	# the way out would move peer 2's avatar on everybody's screen but the
	# host's, which is worse than believing it everywhere.
	assert_array(host._presence_pending.keys()).override_failure_message(
		"the host is about to forward peer 3's frame as peer 2's").not_contains(["2"])
	assert_array(host._presence_pending.keys()).contains(["3"])


func test_presence_never_touches_the_world() -> void:
	# The whole reason transforms are not commands. If a transform could change
	# the state, twenty a second of them would decide the hash, and the hash is
	# what tells six people they still agree about the island.
	var host: WebSocketTransport = await _open_room()
	var guest: WebSocketTransport = await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	var before := host.state_hash()

	for i in 10:
		guest.send_presence(Presence.to_wire(Vector3(float(i), 0, 0), float(i)))
		_turn()
	await _until(func() -> bool: return not host._presence_pending.is_empty())

	assert_int(host.state_hash()).override_failure_message(
		"ten transforms changed the world's hash").is_equal(before)


# --- Avatars -----------------------------------------------------------------------

func test_somebody_appears_when_they_first_move_not_when_they_join() -> void:
	# An avatar built on `join` stands at the origin until the first transform
	# arrives, and then slides across the island to where its owner actually is.
	GameSession.start_level("island_01", 99)
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	var remote := RemotePlayers.install(self, world)

	assert_array(remote.visible_peers()).is_empty()
	remote._on_presence(4, Presence.to_wire(Vector3(2, 1, 3), 0.0))
	await get_tree().process_frame

	assert_array(remote.visible_peers()).is_equal([4])
	var avatar := remote.avatar_for(4)
	assert_vector(avatar.position).override_failure_message(
		"the avatar was placed at the origin and has to walk to its owner"
	).is_equal_approx(Vector3(2, 1, 3), Vector3.ONE * 0.01)

	remote.free()
	GameSession.stop_level()


func test_an_avatar_stands_where_its_owner_stands() -> void:
	# The position on the wire is [Player]'s node origin, and that node's
	# collision capsule is CENTRED on it — so an avatar built standing on the
	# origin floats a metre off the grass. It did, for one screenshot.
	#
	# The invariant, rather than the number: the avatar's body occupies the same
	# space the local player's capsule would at the same position.
	var player: Player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = false
	add_child(player)
	await get_tree().process_frame
	var shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D

	assert_float(RemoteAvatar.BODY_HEIGHT).override_failure_message(
		"a remote player is not the size of a player").is_equal_approx(shape.height, 0.01)
	assert_float(RemoteAvatar.BODY_RADIUS).is_equal_approx(shape.radius, 0.01)

	var avatar := RemoteAvatar.new(3)
	add_child(avatar)
	await get_tree().process_frame
	avatar.place_at(Presence.from_wire(Presence.to_wire(Vector3(0, 5, 0), 0.0)))
	var body := avatar.get_child(0) as MeshInstance3D
	assert_vector(body.position).override_failure_message(
		"the body is offset from the origin, so the avatar does not stand where its owner does"
	).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.01)
	avatar.free()


func test_we_are_never_our_own_avatar() -> void:
	# The host's fan-out carries the whole room, our own row included. An avatar
	# standing inside the local camera is a grey wall.
	GameSession.start_level("island_01", 99)
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	var remote := RemotePlayers.install(self, world)

	remote._on_presence(GameSession.local_player_id(), Presence.to_wire(Vector3.ZERO, 0.0))
	await get_tree().process_frame

	assert_array(remote.visible_peers()).is_empty()
	remote.free()
	GameSession.stop_level()


func test_somebody_leaving_takes_their_avatar_and_their_subscription() -> void:
	# The wave-1 lesson: an avatar listens to GameEvents, so a departure that
	# only hides it leaves a node reacting to the next level's events. Freed,
	# not queued — a queued node is still connected.
	GameSession.start_level("island_01", 99)
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	var remote := RemotePlayers.install(self, world)
	remote._on_presence(5, Presence.to_wire(Vector3(1, 0, 1), 0.0))
	await get_tree().process_frame
	var before := GameEvents.core_event.get_connections().size()
	var avatar := remote.avatar_for(5)

	remote.remove_peer(5)

	# Before any frame passes, on purpose. `queue_free` would leave this true
	# until the end of the frame, and in that window the avatar is still
	# subscribed and still answering events about a player who has gone.
	assert_bool(is_instance_valid(avatar)).override_failure_message(
		"the avatar was queued rather than freed").is_false()
	await get_tree().process_frame

	assert_array(remote.visible_peers()).is_empty()
	assert_int(GameEvents.core_event.get_connections().size()).override_failure_message(
		"the avatar is gone but something of it is still listening").is_equal(before - 1)

	remote.free()
	GameSession.stop_level()


func test_an_avatar_shows_what_its_owner_is_carrying() -> void:
	# Not sent, looked up: pick_up is a command, so every peer applied it and
	# already knows. Paying for this twenty times a second would be paying for a
	# fact we have.
	GameSession.start_level("island_01", 99)
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	var remote := RemotePlayers.install(self, world)
	remote._on_presence(2, Presence.to_wire(Vector3(1, 0, 1), 0.0))
	await get_tree().process_frame

	GameSession.submit(Commands.join(2))
	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	GameSession.submit(Commands.pick_up(2, item_id))
	await get_tree().process_frame

	assert_array(remote.avatar_for(2).carried()).contains([item_id])
	assert_int(remote.avatar_for(2).get_node("Armful").get_child_count()
		).override_failure_message("the armful is not drawn").is_equal(1)

	# Drawn is not the same as visible. The first version drew it perfectly,
	# inside the capsule — see the test below.
	remote.free()
	GameSession.stop_level()


func test_the_first_block_of_an_armful_is_outside_the_body() -> void:
	# A playtest found the armful invisible until somebody held more than three
	# things: the blocks stacked straight up the node origin, and the capsule is
	# CENTRED on that origin, so the stack only cleared the shoulder at the
	# third block. The count is what people read, and one item reads as none.
	#
	# The rule is geometric, so it is checked as geometry rather than by
	# counting children — a block that exists and cannot be seen is exactly what
	# shipped last time.
	for i in 8:
		assert_bool(RemoteAvatar.block_is_outside_body(i)).override_failure_message(
			"block %d sits %.2f m from the body axis; the capsule is %.2f m"
			% [i, Vector2(RemoteAvatar.block_position(i).x, RemoteAvatar.block_position(i).z).length(),
				RemoteAvatar.BODY_RADIUS]
		).is_true()


func test_an_armful_is_a_bundle_and_not_a_mast() -> void:
	# Capacity is by item size, so eight small things is a legal armful. In one
	# column that is a 1.4 m tower through the name tag; the columns are what
	# keep it under the tag whoever is carrying what.
	var top := RemoteAvatar.block_position(7).y + RemoteAvatar.CARRY_BLOCK * 0.5
	assert_float(top).override_failure_message(
		"a full armful reaches %.2f m, and the name tag is at %.2f m"
		% [top, RemoteAvatar.TAG_HEIGHT]
	).is_less(RemoteAvatar.TAG_HEIGHT)


# --- The rate ----------------------------------------------------------------------

func test_the_sender_holds_its_tongue_while_the_player_stands_still() -> void:
	GameSession.start_level("island_01", 99)
	var player: Player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = false # no input, no mouse capture, no camera fight
	add_child(player)
	await get_tree().process_frame
	player.global_position = Vector3(2, 1, 2)
	var sender := PresenceSender.install(self, player)
	# Driven by hand: _process would fire its own ticks between the assertions
	# and the numbers below would be about the frame rate.
	sender.set_process(false)

	var counting := CountingTransport.new()
	var was := GameSession.transport
	GameSession.transport = counting
	sender.send_now()
	sender.send_now()
	sender.send_now()
	assert_int(counting.with_something).override_failure_message(
		"a player who has not moved reported %d times" % counting.with_something).is_equal(1)
	assert_int(counting.calls).override_failure_message(
		"the host's forwarding tick stopped when the local player stopped walking"
	).is_equal(3)

	player.global_position += A_STEP
	sender.send_now()
	assert_int(counting.with_something).is_equal(2)

	GameSession.transport = was
	sender.free()
	GameSession.stop_level()


## Counts what the sender decided, without a socket to decide it for us.
class CountingTransport extends Transport:
	var calls := 0
	var with_something := 0

	func send_presence(presence: Dictionary) -> void:
		calls += 1
		if not presence.is_empty():
			with_something += 1


func test_the_rate_is_a_number_somebody_chose() -> void:
	# ADR 0011 costs the free plan at 20 Hz and at 10. A rate above the sum the
	# ADR quotes is a bill, not a setting, so the test is here to make changing
	# it a decision rather than a typo.
	assert_float(PresenceSender.RATE_HZ).is_less_equal(20.0)
	assert_float(PresenceSender.RATE_HZ).is_greater(0.0)


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


## The host first, alone, then guests one at a time — the relay decides who is
## host by arrival, and two sockets opened back to back race for it. See the
## note in `tests/net/test_join_leave.gd`.
func _open_room() -> WebSocketTransport:
	var host := _join(true)
	await _until(func() -> bool: return host.is_joined())
	return host


func _add_guest() -> WebSocketTransport:
	var guest := _join(false)
	await _until(func() -> bool: return guest.is_joined())
	return guest


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
