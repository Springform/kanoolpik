class_name SimTransport
extends Transport
## One peer's end of a simulated network (WP-4.3). Built by [SimNetwork]; not
## useful on its own.
##
## It implements the same [Transport] seam the real game uses, so gameplay code
## driven by a [SimTransport] cannot tell it is not on a network. What it adds is
## a set of knobs no real network gives you: exact latency, deliberate drops,
## deliberate reordering, and a disconnect at a chosen moment.
##
## See [SimNetwork] for what is being simulated and why it is worth simulating.


## The network this peer belongs to.
var network: SimNetwork
## This peer's id. Peer 1 is the authority, as in [Transport]'s default.
var peer_id: int
## Applied to this peer's own copy of the world.
var state: WorldState
var processor: CommandProcessor
## False once [method SimNetwork.disconnect_peer] has cut this peer off.
var connected := true


func _init(p_network: SimNetwork, p_peer_id: int, p_state: WorldState,
		p_processor: CommandProcessor) -> void:
	network = p_network
	peer_id = p_peer_id
	state = p_state
	processor = p_processor


func local_player_id() -> int:
	return peer_id


func is_authority() -> bool:
	return peer_id == SimNetwork.AUTHORITY_ID


## Hand the command to the authority. Note what does NOT happen here: a client
## does not apply its own command locally first. It waits to be told, exactly as
## WP-4.2 requires of the real transport — optimistic local prediction is a
## rollback problem, and this game is about walking to a bin.
func submit_command(command: Dictionary) -> void:
	if not connected:
		command_rejected.emit(command, SimNetwork.E_DISCONNECTED)
		return
	network.send_to_authority(peer_id, command)


## The authority owns the clock. A client ticking its own state would drift from
## the first frame.
func tick(_delta: float) -> void:
	if is_authority():
		network.send_to_authority(peer_id, Commands.tick(1))


# --- Called by SimNetwork ------------------------------------------------------

## Apply a command the authority has accepted. Every peer runs the same
## [CommandProcessor] over the same state, which is the whole bet: the authority
## decides *whether* and *in what order*, never *what the result is*.
func apply_accepted(command: Dictionary) -> Dictionary:
	var result := processor.apply(state, command)
	if result["ok"]:
		command_applied.emit(command, result)
	else:
		# A command the authority accepted and we refused means the two states
		# had already drifted. Loud, not silent.
		command_rejected.emit(command, result["error"])
	return result


func replace_state(snapshot: Dictionary) -> void:
	state = WorldState.from_dict(snapshot)
	state_replaced.emit(state)


func reject(command: Dictionary, error: String) -> void:
	command_rejected.emit(command, error)


## A cheap fingerprint of this peer's world, used to catch a divergence the
## moment it happens rather than at the end of a test.
func state_hash() -> int:
	return SimNetwork.hash_state(state)
