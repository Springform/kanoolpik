class_name WebSocketTransport
extends Transport
## The [Transport] seam over a real socket (WP-4.2, ADR 0011).
##
## Gameplay does not change a line: scenes still call
## [method Transport.submit_command] and listen for [signal command_applied].
## What changes underneath is who decides. In single player [LocalTransport]
## applies immediately; here the host's [CommandProcessor] is the only judge and
## everybody else obeys.
##
## [b]How a command travels.[/b] Exactly as [SimNetwork] proved it (WP-4.3):
## [codeblock]
##   client.submit_command(cmd)  →  relay  →  host validates against ITS state
##                                         →  accepted: broadcast the COMMAND
##                                         →  refused:  only the sender is told
## [/codeblock]
##
## The host broadcasts the [b]command[/b], not the resulting events. Applying
## events on a client would need a second piece of code that knows the rules,
## and two implementations of one rule set is how desyncs are born. So every
## peer runs the same processor over the same state and the host only ever
## decides [i]whether[/i] and [i]in what order[/i].
##
## [b]Three rules that are not negotiable[/b], each with a test that fails when
## it is broken:
##
## 1. [b]A client never applies its own command first.[/b] It sends and waits.
##    Local prediction is a rollback problem and this game is about walking to
##    a bin.
## 2. [b]The host stamps the sender's peer id over [code]player_id[/code].[/b]
##    A frame is whatever the other end chose to type; a client claiming to be
##    peer 1 decodes perfectly (see [CommandCodec]) and must still act as
##    itself. This is the only place that stamp happens.
## 3. [b]Every broadcast carries the host's state hash.[/b] A peer that lands on
##    a different number has diverged, and says so at that command rather than
##    letting the difference compound into a rumour about last Friday.
##
## [b]Usage[/b]
## [codeblock]
##   var t := WebSocketTransport.new("wss://relay.example.dev", "BCDFGH", true, processor, state)
##   GameSession.start_level("island_01", seed, t)
## [/codeblock]

## Connected and issued a peer id by the relay. Until this, commands queue.
## [signal Transport.peer_joined], [signal Transport.peer_left] and
## [signal Transport.disconnected] are declared on the seam, not here: WP-4.6
## made [GameSession] a listener too, and a signal that exists only on one
## implementation forces every listener to ask which one it has.
signal joined(peer_id: int, is_host: bool)
## Our state stopped matching the host's at this command. Not recoverable by
## carrying on — WP-4.6 will ask for a snapshot; for now it is loud.
signal diverged(command: Dictionary, expected_hash: int, actual_hash: int)

## Envelope kinds inside the relay's opaque `d`. Single letters because this is
## the field that travels twenty times a second (see the billing note in
## `docs/NETWORKING.md`), not because anybody enjoys reading them.
const K_COMMAND := "c" ## client → host: please apply this
const K_APPLY := "a" ## host → peers: apply this, and here is my hash
const K_REJECT := "r" ## host → one peer: no, and why
const K_SNAPSHOT := "s" ## host → one peer: here is the whole world

const R_HOST_GONE := "host_left"
const R_ROOM_FULL := "room_full"
const R_SOCKET_CLOSED := "connection_lost"
const E_NOT_CONNECTED := "not_connected"

## Cloudflare refuses a frame over 1 MiB, so matching it here means a snapshot
## that would be dropped in production is dropped in the test too, rather than
## working locally and failing on the lake.
const MAX_FRAME := 1048576

var state: WorldState
var processor: CommandProcessor

var _socket := WebSocketPeer.new()
var _url: String
var _peer_id := 0
var _is_host: bool
var _joined := false
var _closed := false
## Everyone the relay says is in the room, us included.
##
## The ids in `welcome` used to be read and thrown away, so a client arriving
## fourth never learned about peers two and three and WP-4.4 had to draw a
## roster it knew was incomplete. Kept here instead — it is the relay's fact,
## not the game's, and this is the only place that hears it.
var _known_peers: Array[int] = []
## Commands submitted before the relay answered `welcome`. Sent in order once it
## does; dropping them instead would lose the first thing an eager player does.
var _outbox: Array[Dictionary] = []


func _init(base_url: String, room_code: String, as_host: bool,
		p_processor: CommandProcessor, p_state: WorldState) -> void:
	_is_host = as_host
	processor = p_processor
	state = p_state
	_url = "%s/room/%s" % [base_url.rstrip("/"), room_code.to_upper()]
	_socket.inbound_buffer_size = MAX_FRAME
	_socket.outbound_buffer_size = MAX_FRAME
	var err := _socket.connect_to_url(_url)
	if err != OK:
		_die("%s (%d)" % [R_SOCKET_CLOSED, err])


func local_player_id() -> int:
	# Before `welcome` we do not know. 0 is not a valid peer id, so a caller
	# that builds a command too early gets one the host will refuse rather than
	# one that silently acts as somebody else.
	return _peer_id


func is_authority() -> bool:
	return _is_host


func is_joined() -> bool:
	return _joined


func peer_id() -> int:
	return _peer_id


func known_peers() -> Array[int]:
	return _known_peers.duplicate()


## Fire-and-forget, as the seam promises. On the host this applies immediately
## (it is the authority); on a client it goes to the host and comes back.
func submit_command(command: Dictionary) -> void:
	if _closed:
		command_rejected.emit(command, E_NOT_CONNECTED)
		return
	if not _joined:
		_outbox.append(command)
		return
	if _is_host:
		_host_decides(_peer_id, command)
		return
	_send({"k": K_COMMAND, "c": CommandCodec.to_wire(command)})


## Called once per fixed step. Two jobs: pump the socket, and — on the host
## only — advance the clock. A client ticking its own state would drift from the
## first frame, so the tick is broadcast like any other command.
func tick(_delta: float) -> void:
	poll()
	if _is_host and _joined:
		_host_decides(_peer_id, Commands.tick(1))


## Drain the socket. Separate from [method tick] so a lobby can pump the
## connection before a level (and therefore a clock) exists.
func poll() -> void:
	if _closed:
		return
	_socket.poll()
	# Drain before deciding anything, whatever the ready state (WP-4.6).
	#
	# [b]This is a guard with no test, and that is not an oversight.[/b] It was
	# added believing it fixed the host-left message; it does not. Godot discards
	# buffered packets when a socket reaches STATE_CLOSED, and it goes there
	# from STATE_OPEN in a single poll — so by the time the close is visible the
	# farewell is already gone, and no ordering here can recover it. What
	# actually protects that message is the relay sending and closing on
	# separate turns; `test_the_farewell_goes_out_before_the_socket_goes_down`
	# is what pins it.
	#
	# The reordering stays because reacting to a close while unread bytes are
	# sitting there is wrong regardless, and STATE_CLOSING is reachable on paths
	# this game does not exercise today. It is one line of caution, labelled
	# rather than dressed up as a fix.
	while _socket.get_available_packet_count() > 0:
		_receive(_socket.get_packet().get_string_from_utf8())
		if _closed:
			# `hostgone` has already ended us, with the better reason.
			return
	match _socket.get_ready_state():
		WebSocketPeer.STATE_CLOSED, WebSocketPeer.STATE_CLOSING:
			# A close nobody explained. Our end of the wire, as far as we can
			# tell from here.
			_die(R_SOCKET_CLOSED)
		_:
			pass


func close() -> void:
	_closed = true
	_joined = false
	_socket.close()


# --- Receiving -----------------------------------------------------------------

func _receive(text: String) -> void:
	var json := JSON.new()
	# Quietly: an engine error from a hostile frame would fail the whole test
	# run, which is a denial of service with extra steps. Same reasoning as
	# CommandCodec.decode().
	if json.parse(text) != OK or not json.data is Dictionary:
		push_warning("relay sent something that was not a frame")
		return
	var frame: Dictionary = json.data
	match String(frame.get("t", "")):
		"welcome":
			_welcome(frame)
		"join":
			var id := int(frame.get("id", 0))
			_remember(id)
			peer_joined.emit(id)
			if _is_host:
				# A late joiner gets WorldState.to_dict() and nothing else — the
				# same snapshot a save writes, which is why ADR 0010 put
				# progression inside the state. They arrive with the party's
				# points and abilities, not just item positions.
				_send({"k": K_SNAPSHOT, "s": state.to_dict()}, id)
		"leave":
			var gone := int(frame.get("id", 0))
			_known_peers.erase(gone)
			peer_left.emit(gone)
		"hostgone":
			_die(R_HOST_GONE)
		"err":
			push_warning("relay refused a frame: %s" % frame.get("code", "?"))
		"m":
			_payload(int(frame.get("from", 0)), frame.get("d"))


func _welcome(frame: Dictionary) -> void:
	_peer_id = int(frame.get("id", 0))
	var relay_says_host := bool(frame.get("host", false))
	if relay_says_host != _is_host:
		# The relay decides who is host: whoever got there first. Two people
		# both pressing "host" is a lobby bug, and silently believing our own
		# flag would give the room two authorities and no way to tell.
		push_error("asked to be host=%s but the relay made us host=%s" % [_is_host, relay_says_host])
		_is_host = relay_says_host
	_joined = true
	# Everyone already here, plus us. Emitted as joins after `joined` so a
	# listener that only knows how to add a row does not need a second code
	# path for "the ones who were here before me".
	_known_peers.clear()
	_remember(_peer_id)
	var already: Array = frame.get("peers", [])
	joined.emit(_peer_id, _is_host)
	for other in already:
		var id := int(other)
		if id != _peer_id:
			_remember(id)
			peer_joined.emit(id)
	var queued := _outbox.duplicate()
	_outbox.clear()
	for command in queued:
		submit_command(command)


func _payload(from: int, raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var d: Dictionary = raw
	match String(d.get("k", "")):
		K_COMMAND:
			if _is_host:
				_from_client(from, d.get("c"))
		K_APPLY:
			if not _is_host:
				_apply_broadcast(d)
		K_REJECT:
			if not _is_host:
				var decoded := CommandCodec.from_wire(d.get("c"))
				command_rejected.emit(decoded["command"], String(d.get("e", "")))
		K_SNAPSHOT:
			if not _is_host:
				state = WorldState.from_dict(d.get("s", {}))
				state_replaced.emit(state)


## A client asked for something. The host is the only judge.
func _from_client(from: int, wire: Variant) -> void:
	var decoded := CommandCodec.from_wire(wire)
	if not decoded["ok"]:
		# Refused before it ever reaches the processor. Told to the sender only:
		# a malformed frame is one peer's problem, not the room's.
		_send({"k": K_REJECT, "c": wire, "e": String(decoded["error"])}, from)
		return
	var command: Dictionary = decoded["command"]
	# Rule 2. The single line that stops a client acting as somebody else.
	command["player_id"] = from
	_host_decides(from, command)


## Apply, then tell everyone — or tell the one peer it was refused. The only
## place in multiplayer where a command is judged.
func _host_decides(from: int, command: Dictionary) -> void:
	# Through the codec before applying, so the host's own floats are the ones
	# the clients will see. Vector3 is 32-bit and JSON carries that exactly, so
	# today this changes nothing — it is here so it still changes nothing on the
	# day somebody builds with double precision and the two stop agreeing.
	var canonical := CommandCodec.from_wire(CommandCodec.to_wire(command))
	if not canonical["ok"]:
		command_rejected.emit(command, String(canonical["error"]))
		return
	var final: Dictionary = canonical["command"]
	var result := processor.apply(state, final)
	if not result["ok"]:
		if from == _peer_id:
			command_rejected.emit(final, String(result["error"]))
		else:
			_send({"k": K_REJECT, "c": CommandCodec.to_wire(final), "e": String(result["error"])}, from)
		return
	command_applied.emit(final, result)
	_send({"k": K_APPLY, "c": CommandCodec.to_wire(final), "h": state_hash()})


func _apply_broadcast(d: Dictionary) -> void:
	var decoded := CommandCodec.from_wire(d.get("c"))
	if not decoded["ok"]:
		push_error("the host broadcast something we cannot decode: %s" % decoded["error"])
		return
	var command: Dictionary = decoded["command"]
	var result := processor.apply(state, command)
	if not result["ok"]:
		# The host accepted it and we did not: the two states had already
		# drifted. Loud, not silent.
		command_rejected.emit(command, String(result["error"]))
		diverged.emit(command, int(d.get("h", 0)), state_hash())
		return
	command_applied.emit(command, result)
	var expected := int(d.get("h", 0))
	var actual := state_hash()
	if expected != actual:
		# Rule 3. We applied it and landed somewhere else. Carrying on from here
		# only makes the difference bigger.
		diverged.emit(command, expected, actual)


func _remember(id: int) -> void:
	if id > 0 and not _known_peers.has(id):
		_known_peers.append(id)
		_known_peers.sort()


# --- Plumbing ------------------------------------------------------------------

## Reuses [SimNetwork]'s fingerprint so the simulated harness and the real
## transport cannot disagree about what "the same state" means.
func state_hash() -> int:
	return SimNetwork.hash_state(state)


func _send(payload: Dictionary, to: int = 0) -> void:
	if _closed or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var frame := {"t": "m", "d": payload}
	if to != 0:
		frame["to"] = to
	var text := JSON.stringify(frame)
	if text.length() > MAX_FRAME:
		# Better a named failure than a socket the relay closes underneath us.
		push_error("frame of %d bytes exceeds the relay's limit" % text.length())
		return
	_socket.send_text(text)


func _die(reason: String) -> void:
	if _closed:
		return
	_closed = true
	_joined = false
	_socket.close()
	disconnected.emit(reason)
