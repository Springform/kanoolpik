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


## The peer id of the local player (1 in single player / for the host).
func local_player_id() -> int:
	return 1


func is_authority() -> bool:
	return true


## Fire-and-forget. Results arrive via signals.
func submit_command(_command: Dictionary) -> void:
	push_error("Transport.submit_command not implemented")


## Called by the session once per fixed physics step.
func tick(_delta: float) -> void:
	pass
