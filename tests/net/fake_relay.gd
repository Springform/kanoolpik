class_name FakeRelay
extends RefCounted
## The relay's protocol, in-process, for tests (WP-4.2).
##
## It speaks exactly what `docs/NETWORKING.md` specifies and lives under
## [code]tests/[/code] so it can never ship: the export preset excludes the
## directory. Real sockets on 127.0.0.1, real WebSocket handshakes, no
## Cloudflare account and no internet — which is what lets the transport suite
## run in CI.
##
## [b]This is a test double of a thing that exists, which is the dangerous
## kind.[/b] The house rule says a test against a fake tells you the fake works.
## Two defences, and neither is optional:
##
## 1. [b]It is deliberately stupid.[/b] It does what the document says and
##    nothing more — no convenience the Worker lacks, no tolerance the Worker
##    lacks. Every line it does not have is a line that cannot drift.
## 2. [b]The same suite runs against the real relay.[/b] Set
##    [code]KANOOLPIK_RELAY_URL[/code] and [WebSocketTransport]'s tests skip this
##    class and connect there instead:
##    [codeblock]
##      npx wrangler dev &
##      KANOOLPIK_RELAY_URL=ws://localhost:8787 tools/run_tests.sh res://tests/net/
##    [/codeblock]
##    That is the only thing that can catch this file lying. Run it when you
##    touch either side of the protocol.
##
## Not a Node: tests drive [method poll] themselves, so a run is deterministic
## rather than depending on when the scene tree felt like processing.

const MAX_PEERS := 6
const HOST_ID := 1

## Emitted for anything the relay refused. Tests assert on it so a protocol
## mistake surfaces as a failure rather than as a message that silently vanished.
signal refused(peer_id: int, code: String)

var _server := TCPServer.new()
var _port := 0
## peer_id -> WebSocketPeer
var _peers: Dictionary = {}
## Sockets that have connected but not yet finished the handshake.
var _pending: Array[WebSocketPeer] = []



## Returns the base URL to hand [WebSocketTransport]. Port 0 means "any free
## port", so two suites never fight over one.
func start() -> String:
	var err := _server.listen(0, "127.0.0.1")
	assert(err == OK, "FakeRelay could not listen: %d" % err)
	_port = _server.get_local_port()
	return "ws://127.0.0.1:%d" % _port


func stop() -> void:
	for peer in _peers.values():
		(peer as WebSocketPeer).close()
	_peers.clear()
	_pending.clear()
	_server.stop()


func peer_ids() -> Array[int]:
	var out: Array[int] = []
	for id in _peers.keys():
		out.append(int(id))
	out.sort()
	return out


## One turn of the crank: accept, handshake, route. Tests call this in a loop.
func poll() -> void:
	while _server.is_connection_available():
		if _peers.size() + _pending.size() >= MAX_PEERS:
			# The Worker answers 409 before upgrading. A TCP server cannot send
			# an HTTP status without speaking HTTP, so the fake does the closest
			# honest thing: refuses the connection outright. A test that cares
			# about the *reason* belongs in the relay suite, where there is a
			# real HTTP response to assert on.
			_server.take_connection().disconnect_from_host()
			continue
		var socket := WebSocketPeer.new()
		if socket.accept_stream(_server.take_connection()) == OK:
			_pending.append(socket)

	var still_pending: Array[WebSocketPeer] = []
	for socket in _pending:
		socket.poll()
		match socket.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_admit(socket)
			WebSocketPeer.STATE_CONNECTING:
				still_pending.append(socket)
			_:
				pass # died during the handshake; nobody ever knew about it
	_pending = still_pending

	for id in peer_ids():
		# The host departing empties the room mid-loop, so this list can name
		# peers that are already gone by the time we reach them.
		if not _peers.has(id):
			continue
		var socket: WebSocketPeer = _peers[id]
		socket.poll()
		if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
			_depart(id)
			continue
		while socket.get_available_packet_count() > 0:
			_route(id, socket.get_packet().get_string_from_utf8())




# --- Internals -----------------------------------------------------------------

func _admit(socket: WebSocketPeer) -> void:
	var peer_id := _next_free_id()
	var existing := peer_ids()
	_peers[peer_id] = socket
	_send(peer_id, {"t": "welcome", "id": peer_id, "host": peer_id == HOST_ID, "peers": existing})
	for other in existing:
		_send(other, {"t": "join", "id": peer_id})


## Lowest free id, so a rejoining sixth player does not become peer 9.
func _next_free_id() -> int:
	for id in range(HOST_ID, HOST_ID + MAX_PEERS):
		if not _peers.has(id):
			return id
	return HOST_ID + MAX_PEERS


func _depart(peer_id: int) -> void:
	var was_host := peer_id == HOST_ID
	_peers.erase(peer_id)
	if was_host:
		# ADR 0002: no authority, no session. Everyone is told and the room empties.
		#
		# [b]Sent and closed in the same breath, exactly as the Worker does it[/b]
		# (`infra/relay/src/room.js`). An earlier version of this fake deferred
		# the close by a turn so the farewell was always read — which made the
		# test pass and made the fake stop resembling production, which is the
		# one thing it must never do. The close code is what carries the reason
		# now; the frame is a fast path that may or may not win.
		for other in peer_ids():
			var socket: WebSocketPeer = _peers[other]
			_send(other, {"t": "hostgone"})
			socket.close(WebSocketTransport.CLOSE_HOST_LEFT, "host left")
		_peers.clear()
		return

	for other in peer_ids():
		_send(other, {"t": "leave", "id": peer_id})


## Clients may only reach the host. The host may reach one client or all of
## them. There is no client-to-client path — the thing that stops a peer
## impersonating the authority by talking straight to its neighbours.
func _route(from_id: int, raw: String) -> void:
	var json := JSON.new()
	if json.parse(raw) != OK:
		_refuse(from_id, "bad_json", "frame was not JSON")
		return
	var message: Variant = json.data
	if not message is Dictionary or String((message as Dictionary).get("t", "")) != "m":
		_refuse(from_id, "bad_type", "expected {t:'m'}")
		return
	var frame: Dictionary = message

	if from_id != HOST_ID:
		if not _peers.has(HOST_ID):
			_refuse(from_id, "no_host", "the host has gone")
			return
		# `to` from a client is ignored on purpose, not rejected — the Worker
		# does the same. It still reaches only the host.
		_send(HOST_ID, {"t": "m", "from": from_id, "d": frame.get("d")})
		return

	var to := int(frame.get("to", 0))
	if to == 0:
		for other in peer_ids():
			if other != HOST_ID:
				_send(other, {"t": "m", "from": HOST_ID, "d": frame.get("d")})
		return
	if not _peers.has(to):
		_refuse(from_id, "no_such_peer", "peer %d is not here" % to)
		return
	_send(to, {"t": "m", "from": HOST_ID, "d": frame.get("d")})


func _refuse(peer_id: int, code: String, msg: String) -> void:
	# A bad frame is the sender's problem, not the room's: nobody else hears it.
	_send(peer_id, {"t": "err", "code": code, "msg": msg})
	refused.emit(peer_id, code)


func _send(peer_id: int, payload: Dictionary) -> void:
	var socket: WebSocketPeer = _peers.get(peer_id)
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	socket.send_text(JSON.stringify(payload))
