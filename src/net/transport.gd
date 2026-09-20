class_name Transport
extends RefCounted
## Seam between gameplay and networking.
##
## Gameplay code never calls RPCs directly. It calls
## [method submit_command] and listens for [signal command_applied] /
## [signal state_replaced]. In single player the [LocalTransport] applies the
## command immediately. In multiplayer (phase 4) a WebRtcTransport forwards
## the command to the host, which applies it to the authoritative state and
## broadcasts the resulting events (or a full state snapshot on join).
##
## Implementations must guarantee: every command is applied at most once, in
## the same order on every peer, against the same [WorldState].

## Emitted after a command was accepted by the authority and applied locally.
signal command_applied(command: Dictionary, result: Dictionary)
## Emitted when the authority rejected the command (never mutates state).
signal command_rejected(command: Dictionary, error: String)
## Emitted when a full snapshot replaces the local state (join / resync).
signal state_replaced(state: WorldState)
## Somebody arrived in the room. Declared here rather than on the one
## implementation that can emit it, so a listener — the lobby, [GameSession] —
## connects the same way whatever transport it was handed. Single player simply
## never fires them.
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
## The connection is gone and is not coming back on its own: host left, room
## full, network died. Carries a reason fit to show a person.
signal disconnected(reason: String)


## The peer id of the local player (1 in single player / for the host).
func local_player_id() -> int:
	return 1


func is_authority() -> bool:
	return true


## Everyone the transport knows is in the room, us included, lowest first.
##
## Single player is a room of one. The point of having it on the seam is that
## the lobby can draw a roster without asking which transport it has — see the
## note on [member LobbyController.peers], which this replaces (WP-4.6).
func known_peers() -> Array[int]:
	return [local_player_id()]


## The room this transport is in, or "" when there is no room — which is what
## single player is. The HUD shows it so a friend arriving late has something to
## be told; joining a running round already works (WP-4.6), it just needed the
## six characters to still be readable once the lobby is gone.
func room_code() -> String:
	return ""


## Somebody else moved. [param presence] is presentation only — a position and
## a facing — and is never applied to [WorldState] by anybody (WP-4.5).
##
## It is a separate channel from [signal command_applied] on purpose. A
## transform is not a command: it needs no judging, no ordering and no hash,
## it is worthless a tenth of a second later, and routing twenty of them a
## second through [CommandProcessor] would put the one thing that must stay
## deterministic at the mercy of the one thing that cannot be.
signal presence_received(peer_id: int, presence: Dictionary)


## Fire-and-forget. Results arrive via signals.
func submit_command(_command: Dictionary) -> void:
	push_error("Transport.submit_command not implemented")


## Tell the room where we are. An empty [param presence] means "nothing of mine
## changed" — which the host still needs to hear, because it is also the tick on
## which it forwards everyone else's (see [method WebSocketTransport.send_presence]).
##
## Single player has nobody to tell, so the seam's answer is to do nothing.
func send_presence(_presence: Dictionary) -> void:
	pass


## Called by the session once per fixed physics step.
func tick(_delta: float) -> void:
	pass
