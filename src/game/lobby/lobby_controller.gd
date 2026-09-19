class_name LobbyController
extends Node
## The lobby without a face (WP-4.4): room codes in, a live socket and a peer
## list out. [LobbyScreen] draws it; the tests drive this class directly.
##
## [b]Three things happen here and nowhere else.[/b]
##
## 1. [b]The island is decided by the code.[/b] [method RoomCode.seed_for] turns
##    the six characters into the seed, and every peer runs [MessGenerator]
##    locally. Nothing about the level layout is sent, and — more usefully — a
##    client that arrives before the host has pressed anything is already
##    standing on the right island.
## 2. [b]The world is built before the socket is opened.[/b] [WebSocketTransport]
##    wants a processor and a state at construction, and the host answers a join
##    with [code]state.to_dict()[/code] — so a host whose world did not exist yet
##    would hand the first arrival a null.
## 3. [b]One state object, not two.[/b] See [method adopt_into_session].
##
## The lobby polls the socket itself rather than letting [GameSession] tick it:
## a tick advances the clock, and the clock has no business running while
## people are still reading a code aloud. [method WebSocketTransport.poll] was
## split out in WP-4.2 for exactly this.

## Connected, and the relay has issued a peer id.
signal room_opened(code: String, is_host: bool)
## The roster changed. Host-side this is everybody; see the note on [member peers].
signal peers_changed(peers: Array)
## We never got in. [param reason_key] is a translation key.
signal failed(reason_key: String)
## We were in and now we are not.
signal closed(reason_key: String)
## Leave the lobby and build the playing scene.
signal game_started()

const DEFAULT_LEVEL := "island_01"

const E_BAD_CODE := "ui.lobby.error.bad_code"
const E_NO_SUCH_ROOM := "ui.lobby.error.no_such_room"
const E_LOST := "ui.lobby.error.lost"

var transport: WebSocketTransport
var service: RoomService
var code := ""
var is_host := false
var level_id := DEFAULT_LEVEL

## Everyone we know is in the room, us included, lowest first.
##
## [b]On the host this is the whole room; on a client it is not.[/b] The relay's
## `welcome` frame carries the ids already present, and [WebSocketTransport]
## does not pass them on — so a client that arrives fourth learns about peers
## two and three only if they leave. The host's screen is the one being read
## aloud from, so that is where the roster is shown. Completing it is one
## accessor in the transport and belongs to WP-4.6 with the rest of
## join/leave/reconnect.
var peers: Array[int] = []

var _adopted := false


func _ready() -> void:
	service = RoomService.new()
	service.name = "RoomService"
	add_child(service)
	service.room_created.connect(_on_code_minted)
	service.failed.connect(failed.emit)
	set_process(false)


func _process(_delta: float) -> void:
	if transport != null:
		transport.poll()


# --- Getting in ----------------------------------------------------------------

## Host: ask the relay for an empty room, then sit in it.
func host_new_room() -> void:
	service.request_new_room()


## Client: join a code somebody read aloud.
func join(text: String) -> void:
	if not RoomCode.is_valid(text):
		failed.emit(E_BAD_CODE)
		return
	_open(RoomCode.normalize(text), false)


func _on_code_minted(minted: String) -> void:
	_open(minted, true)


func _open(room: String, as_host: bool) -> void:
	code = room
	is_host = as_host
	# Build the world first (see the class note). The session is started only to
	# construct it and is stopped again immediately — no clock, no commands.
	GameSession.start_level(level_id, RoomCode.seed_for(code))
	GameSession.stop_level()
	transport = WebSocketTransport.new(
		RelayEndpoint.ws_base(), code, as_host, GameSession.processor, GameSession.state)
	transport.joined.connect(_on_joined)
	transport.peer_joined.connect(_on_peer_joined)
	transport.peer_left.connect(_on_peer_left)
	transport.disconnected.connect(_on_disconnected)
	set_process(true)


func _on_joined(peer_id: int, relay_says_host: bool) -> void:
	if not is_host and relay_says_host:
		# We asked to be a client and the relay made us the host, which it only
		# does for the first socket in a room. So the room was empty: nobody is
		# hosting this code and the six characters were a typo. Becoming the
		# host of a room nobody will join is the one failure that looks exactly
		# like success, so it is caught here rather than left to puzzle someone.
		leave()
		failed.emit(E_NO_SUCH_ROOM)
		return
	is_host = relay_says_host
	peers = [peer_id]
	if not is_host:
		# A client is in the game from the moment it is connected: the host's
		# broadcasts have to land somewhere, and the transport can only apply
		# them into the session's state if the session owns the transport.
		adopt_into_session()
		transport.command_applied.connect(_on_first_command, CONNECT_ONE_SHOT)
	room_opened.emit(code, is_host)
	peers_changed.emit(peers)


func _on_peer_joined(peer_id: int) -> void:
	if not peers.has(peer_id):
		peers.append(peer_id)
		peers.sort()
		peers_changed.emit(peers)


func _on_peer_left(peer_id: int) -> void:
	if peers.has(peer_id):
		peers.erase(peer_id)
		peers_changed.emit(peers)


func _on_disconnected(reason: String) -> void:
	set_process(false)
	closed.emit(_reason_key(reason))


static func _reason_key(reason: String) -> String:
	match reason:
		WebSocketTransport.R_HOST_GONE:
			return "ui.lobby.error.host_left"
		WebSocketTransport.R_ROOM_FULL:
			return "ui.lobby.error.full"
		_:
			return E_LOST


# --- Starting -------------------------------------------------------------------

## Host only: everybody who is coming is here.
func start_game() -> void:
	if not is_host:
		return
	adopt_into_session()
	game_started.emit()


## A client leaves the lobby when the host's first command arrives. There is no
## "the game has begun" message and there does not need to be one: a broadcast
## is proof, and the tick that carries it is the same clock everyone else is on.
func _on_first_command(_command: Dictionary, _result: Dictionary) -> void:
	game_started.emit()


## Hand the live socket to [GameSession].
##
## [method GameSession.start_level] builds a fresh [WorldState] from the seed.
## It is identical in content to the one the lobby made — same seed, same
## generator, and `test_lobby.gd` asserts exactly that — but it is a different
## object, and the transport is still holding the old one. Two objects for one
## world is a desync that no hash would catch, because each side would be
## perfectly consistent with itself. So the transport is re-pointed, here, once.
func adopt_into_session() -> void:
	if _adopted:
		return
	_adopted = true
	GameSession.start_level(level_id, RoomCode.seed_for(code), transport)
	transport.state = GameSession.state
	transport.processor = GameSession.processor


func leave() -> void:
	set_process(false)
	if transport != null:
		transport.close()
	GameSession.stop_level()
