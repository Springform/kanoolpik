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
const UNLOCK := "unlock"
const SUMMON := "summon"
const GRANT_POINTS := "grant_points"


static func pick_up(player_id: int, item_id: String) -> Dictionary:
	return {"type": PICK_UP, "player_id": player_id, "item_id": item_id}


static func drop(player_id: int, item_id: String, position: Vector3) -> Dictionary:
	return {"type": DROP, "player_id": player_id, "item_id": item_id, "position": position}


static func place(player_id: int, item_id: String, container_id: String, slot: int) -> Dictionary:
	return {"type": PLACE, "player_id": player_id, "item_id": item_id, "container_id": container_id, "slot": slot}


## Take a placed item back out of a container into the player's hands.
static func take_out(player_id: int, item_id: String) -> Dictionary:
	return {"type": TAKE_OUT, "player_id": player_id, "item_id": item_id}


## Buy an ability with the party's shared skill points (ADR 0010).
static func unlock(player_id: int, ability_id: String) -> Dictionary:
	return {"type": UNLOCK, "player_id": player_id, "ability_id": ability_id}


## "Råb på en kammerat": bring every loose member of [param series] to
## [param position]. Once per series; the position is clamped to the island.
static func summon(player_id: int, series: String, position: Vector3) -> Dictionary:
	return {"type": SUMMON, "player_id": player_id, "series": series, "position": position}


## Test-mode only: put skill points in the party's pocket without packing
## anything. Refused unless [member CommandProcessor.allow_debug_commands] is on,
## which [GameSession] sets from [method TestMode.is_enabled] — so in
## multiplayer the host decides whether the party may cheat, and it decides once.
##
## It is a command rather than a poke at the progression for the same reason
## everything else is (ADR 0010): a peer that replays the command list must end
## up in the same place, cheats included.
static func grant_points(player_id: int, points: int) -> Dictionary:
	return {"type": GRANT_POINTS, "player_id": player_id, "points": points}


## Advance the simulation clock (host only, once per fixed step).
static func tick(ticks: int = 1) -> Dictionary:
	return {"type": TICK, "player_id": -1, "ticks": ticks}
