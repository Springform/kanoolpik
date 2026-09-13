class_name Commands
extends RefCounted
## Builders for the plain-Dictionary commands that [CommandProcessor] accepts.
##
## Commands are Dictionaries (not objects) on purpose: they travel over RPC,
## are trivially logged/replayed, and need no class registration on peers.
## Every command carries "type" and "player_id".

const PICK_UP := "pick_up"
const DROP := "drop"
const PLACE := "place"
const TAKE_OUT := "take_out"
const TICK := "tick"


static func pick_up(player_id: int, item_id: String) -> Dictionary:
	return {"type": PICK_UP, "player_id": player_id, "item_id": item_id}


static func drop(player_id: int, item_id: String, position: Vector3) -> Dictionary:
	return {"type": DROP, "player_id": player_id, "item_id": item_id, "position": position}


static func place(player_id: int, item_id: String, container_id: String, slot: int) -> Dictionary:
	return {"type": PLACE, "player_id": player_id, "item_id": item_id, "container_id": container_id, "slot": slot}


## Take a placed item back out of a container into the player's hands.
static func take_out(player_id: int, item_id: String) -> Dictionary:
	return {"type": TAKE_OUT, "player_id": player_id, "item_id": item_id}


## Advance the simulation clock (host only, once per fixed step).
static func tick(ticks: int = 1) -> Dictionary:
	return {"type": TICK, "player_id": -1, "ticks": ticks}
