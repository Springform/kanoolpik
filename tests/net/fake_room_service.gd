class_name FakeRoomService
extends RefCounted
## `GET /new`, in-process, for tests (WP-4.4).
##
## [FakeRelay] is a WebSocket server and cannot also answer HTTP on the same
## socket: [method WebSocketPeer.accept_stream] performs the handshake itself,
## so there is no way to read the request line first and then decide. Rather
## than teach the relay fake a second protocol it would then be free to get
## wrong, the one HTTP endpoint the game uses gets its own fake on its own port.
##
## Deliberately stupid, for the same reason [FakeRelay] is: it answers what
## `docs/NETWORKING.md` says `/new` answers, and nothing else. The real
## endpoint is exercised by `net-live.yml` against the deployed Worker.
##
## Lives under [code]tests/[/code] and therefore cannot ship.

## What the next `GET /new` will hand back. Tests set these to make the relay
## behave badly on purpose.
var code := "BCDFGH"
var status := 200
## When set, sent verbatim instead of a well-formed JSON body.
var body_override := ""
## Requests seen, so a test can prove the client did not retry behind its back.
var requests := 0

var _server := TCPServer.new()
var _open: Array[StreamPeerTCP] = []
var _buffers: Array[String] = []


## Returns the base URL for [constant RelayEndpoint.ENV_HTTP]. Port 0 means
## "any free port", so two suites never fight over one.
func start() -> String:
	var err := _server.listen(0, "127.0.0.1")
	assert(err == OK, "FakeRoomService could not listen: %d" % err)
	return "http://127.0.0.1:%d" % _server.get_local_port()


func stop() -> void:
	for conn in _open:
		conn.disconnect_from_host()
	_open.clear()
	_buffers.clear()
	_server.stop()


## One turn of the crank. Tests call this in a loop, as they do for [FakeRelay].
func poll() -> void:
	while _server.is_connection_available():
		_open.append(_server.take_connection())
		_buffers.append("")

	var keep_conns: Array[StreamPeerTCP] = []
	var keep_bufs: Array[String] = []
	for i in _open.size():
		var conn := _open[i]
		conn.poll()
		if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var buffer := _buffers[i]
		var available := conn.get_available_bytes()
		if available > 0:
			buffer += conn.get_utf8_string(available)
		# A request can arrive in pieces even on loopback; wait for the blank
		# line that ends the headers rather than assuming one packet.
		if not buffer.contains("\r\n\r\n"):
			keep_conns.append(conn)
			keep_bufs.append(buffer)
			continue
		_answer(conn, buffer)
	_open = keep_conns
	_buffers = keep_bufs


func _answer(conn: StreamPeerTCP, request: String) -> void:
	requests += 1
	var first_line := request.get_slice("\r\n", 0)
	if not first_line.begins_with("GET " + RoomService.ENDPOINT):
		_write(conn, 404, "{}")
		return
	if not body_override.is_empty():
		_write(conn, status, body_override)
		return
	_write(conn, status, JSON.stringify({"code": code, "max_peers": FakeRelay.MAX_PEERS}))


func _write(conn: StreamPeerTCP, code_out: int, body: String) -> void:
	var bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\n" % [code_out, "OK" if code_out == 200 else "ERR"]
	head += "Content-Type: application/json\r\n"
	# The game is served from a different origin than the relay, so this header
	# is load-bearing in production. Stated here too, so a test cannot pass on a
	# response the browser would refuse.
	head += "Access-Control-Allow-Origin: *\r\n"
	head += "Content-Length: %d\r\n" % bytes.size()
	head += "Connection: close\r\n\r\n"
	conn.put_data(head.to_utf8_buffer())
	conn.put_data(bytes)
	conn.disconnect_from_host()
