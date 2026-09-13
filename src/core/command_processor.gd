class_name CommandProcessor
extends RefCounted
## The ONLY thing allowed to mutate a [WorldState] during play.
##
## apply() validates a command, mutates the state, and returns a result with a
## list of events. Events are plain Dictionaries the presentation layer (and, in
## multiplayer, remote peers) react to — the core never touches Nodes, audio or
## UI. Because the processor is deterministic, host and clients that apply the
## same command sequence to the same starting state end up identical.
##
## Result shape:
##   { "ok": bool, "error": String, "verdict": int (PlacementRules.Verdict or -1),
##     "events": Array[Dictionary] }
## Event shapes (all have "type"):
##   item_picked_up   { item_id, player_id }
##   item_dropped     { item_id, player_id, position }
##   item_placed      { item_id, player_id, container_id, slot, verdict }
##   item_taken_out   { item_id, player_id, container_id }
##   container_completed { container_id }
##   island_clean     {}
##   ticked           { elapsed_ticks }

const E_UNKNOWN_TYPE := "unknown_command"
const E_UNKNOWN_PLAYER := "unknown_player"
const E_UNKNOWN_ITEM := "unknown_item"
const E_NOT_ON_GROUND := "item_not_on_ground"
const E_NOT_CARRIED := "item_not_carried_by_player"
const E_NOT_PLACED := "item_not_placed"
const E_HANDS_FULL := "hands_full"
const E_BAD_SLOT := "bad_slot"

var catalog: Catalog


func _init(p_catalog: Catalog) -> void:
	catalog = p_catalog


func apply(state: WorldState, cmd: Dictionary) -> Dictionary:
	match String(cmd.get("type", "")):
		Commands.PICK_UP:
			return _pick_up(state, cmd)
		Commands.DROP:
			return _drop(state, cmd)
		Commands.PLACE:
			return _place(state, cmd)
		Commands.TAKE_OUT:
			return _take_out(state, cmd)
		Commands.TICK:
			state.elapsed_ticks += int(cmd.get("ticks", 1))
			return _ok([{"type": "ticked", "elapsed_ticks": state.elapsed_ticks}])
		_:
			return _fail(E_UNKNOWN_TYPE)


## Sum of sizes of everything the player carries.
func carried_load(state: WorldState, player_id: int) -> int:
	var carried := 0
	for id in state.carried_by(player_id):
		var def := catalog.get_item(id)
		carried += def.size if def != null else 1
	return carried


func can_carry(state: WorldState, player_id: int, item_id: String) -> bool:
	var def := catalog.get_item(item_id)
	if def == null:
		return false
	return carried_load(state, player_id) + def.size <= state.player_capacity(player_id)


# --- Handlers ----------------------------------------------------------------

func _pick_up(state: WorldState, cmd: Dictionary) -> Dictionary:
	var pid := int(cmd["player_id"])
	var item_id := String(cmd["item_id"])
	if not state.has_player(pid):
		return _fail(E_UNKNOWN_PLAYER)
	if not catalog.has_item(item_id) or not state.has_item(item_id):
		return _fail(E_UNKNOWN_ITEM)
	if state.kind_of(item_id) != WorldState.Kind.GROUND:
		return _fail(E_NOT_ON_GROUND)
	if not can_carry(state, pid, item_id):
		return _fail(E_HANDS_FULL)
	state.set_carried(item_id, pid)
	state.bump_stat("pickups")
	return _ok([{"type": "item_picked_up", "item_id": item_id, "player_id": pid}])


func _drop(state: WorldState, cmd: Dictionary) -> Dictionary:
	var pid := int(cmd["player_id"])
	var item_id := String(cmd["item_id"])
	if not _is_carrying(state, pid, item_id):
		return _fail(E_NOT_CARRIED)
	var pos: Vector3 = cmd.get("position", Vector3.ZERO)
	state.set_on_ground(item_id, pos)
	return _ok([{"type": "item_dropped", "item_id": item_id, "player_id": pid, "position": pos}])


func _place(state: WorldState, cmd: Dictionary) -> Dictionary:
	var pid := int(cmd["player_id"])
	var item_id := String(cmd["item_id"])
	var container_id := String(cmd["container_id"])
	var slot := int(cmd["slot"])
	if not _is_carrying(state, pid, item_id):
		return _fail(E_NOT_CARRIED)
	var verdict := PlacementRules.evaluate(catalog, state, item_id, container_id, slot)
	match verdict:
		PlacementRules.Verdict.UNKNOWN_CONTAINER, PlacementRules.Verdict.INVALID_SLOT, PlacementRules.Verdict.SLOT_OCCUPIED:
			# Physically impossible — reject, nothing changes.
			return _fail(E_BAD_SLOT, verdict)
	# Wrong placements ARE allowed (that is the game) — they just score badly.
	state.set_placed(item_id, container_id, slot)
	state.bump_stat("placements")
	if verdict != PlacementRules.Verdict.CORRECT:
		state.bump_stat("wrong_placements")
	var events: Array[Dictionary] = [{
		"type": "item_placed", "item_id": item_id, "player_id": pid,
		"container_id": container_id, "slot": slot, "verdict": verdict,
	}]
	if PlacementRules.is_container_complete(catalog, state, container_id):
		events.append({"type": "container_completed", "container_id": container_id})
	if PlacementRules.is_island_clean(catalog, state):
		events.append({"type": "island_clean"})
	return _ok(events, verdict)


func _take_out(state: WorldState, cmd: Dictionary) -> Dictionary:
	var pid := int(cmd["player_id"])
	var item_id := String(cmd["item_id"])
	if not state.has_player(pid):
		return _fail(E_UNKNOWN_PLAYER)
	if not state.has_item(item_id):
		return _fail(E_UNKNOWN_ITEM)
	if state.kind_of(item_id) != WorldState.Kind.PLACED:
		return _fail(E_NOT_PLACED)
	if not can_carry(state, pid, item_id):
		return _fail(E_HANDS_FULL)
	var container_id := state.container_of(item_id)
	state.set_carried(item_id, pid)
	return _ok([{"type": "item_taken_out", "item_id": item_id, "player_id": pid, "container_id": container_id}])


# --- Helpers -----------------------------------------------------------------

func _is_carrying(state: WorldState, pid: int, item_id: String) -> bool:
	if not state.has_player(pid) or not state.has_item(item_id):
		return false
	var loc := state.location(item_id)
	return loc["kind"] == WorldState.Kind.CARRIED and loc["player_id"] == pid


static func _ok(events: Array[Dictionary], verdict: int = -1) -> Dictionary:
	return {"ok": true, "error": "", "verdict": verdict, "events": events}


static func _fail(error: String, verdict: int = -1) -> Dictionary:
	return {"ok": false, "error": error, "verdict": verdict, "events": []}
