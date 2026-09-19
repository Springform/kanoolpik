class_name RoomService
extends Node
## `GET /new` — asking the relay for a code nobody is sitting in (WP-4.4).
##
## The only HTTP the game speaks. Everything after this is the WebSocket, so
## this class exists to turn one request into either a code or a sentence a
## person can act on. It never retries: a friend staring at a spinner learns
## nothing, and pressing the button again is a retry they chose.
##
## Failure comes back as a translation key rather than a message, because the
## lobby is Danish by default and the reason has to survive a language toggle.

## A code for a room nobody is in.
signal room_created(code: String)
## Nothing to show yet. [param reason_key] goes straight to [method Object.tr].
signal failed(reason_key: String)

const ENDPOINT := "/new"
## Long enough for a cold Worker on a phone, short enough that a dead relay is
## an answer rather than a mood.
const TIMEOUT_SECONDS := 10.0

const E_NETWORK := "ui.lobby.error.network"
const E_RELAY := "ui.lobby.error.relay"
const E_BUSY := "ui.lobby.error.busy"

var _http: HTTPRequest
var _in_flight := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "HTTPRequest"
	_http.timeout = TIMEOUT_SECONDS
	# Web export is single-threaded (GL Compatibility, no COOP/COEP): threading
	# the request here would work on desktop and fail on the thing we ship.
	_http.use_threads = false
	add_child(_http)
	_http.request_completed.connect(_on_completed)


## Ask for a room. One at a time — a second press while the first is in flight
## is refused rather than queued, so two codes can never come back for one
## button.
func request_new_room() -> void:
	if _in_flight:
		failed.emit(E_BUSY)
		return
	var url := RelayEndpoint.http_base() + ENDPOINT
	var err := _http.request(url)
	if err != OK:
		failed.emit(E_NETWORK)
		return
	_in_flight = true


func is_in_flight() -> bool:
	return _in_flight


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		# No answer at all: no network, DNS, TLS, or the Worker is down. The
		# player cannot tell those apart and neither can we.
		failed.emit(E_NETWORK)
		return
	if code != 200:
		failed.emit(E_RELAY)
		return
	# Quietly: a relay that answered with something odd must not be able to put
	# an engine error in the log, because `run_tests.sh` fails the whole run on
	# those and this body arrives from across the internet.
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		failed.emit(E_RELAY)
		return
	var answer: Dictionary = json.data
	var room: String = RoomCode.normalize(String(answer.get("code", "")))
	# The relay minted it, but we validate anyway: this string decides which
	# island six people stand on, and it is the first thing we read from a
	# stranger's response.
	if not RoomCode.is_valid(room):
		failed.emit(E_RELAY)
		return
	room_created.emit(room)
