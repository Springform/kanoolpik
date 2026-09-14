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
##   points_awarded   { container_id, points, total_available }
##   ability_unlocked { ability_id, player_id, points_left }
##   capacity_changed { player_id, capacity }
##   item_summoned    { item_id, player_id, position }
##   points_granted   { player_id, points, total_available }
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
const E_UNKNOWN_ABILITY := "unknown_ability"
const E_ALREADY_UNLOCKED := "already_unlocked"
const E_NOT_ENOUGH_POINTS := "not_enough_points"
const E_ABILITY_LOCKED := "ability_locked"
const E_UNKNOWN_SERIES := "unknown_series"
const E_SERIES_SPENT := "series_already_summoned"
const E_NOTHING_TO_SUMMON := "nothing_to_summon"
const E_DEBUG_DISABLED := "debug_disabled"

## Where summoned items land, as a ring around the caller's feet: close enough
## to reach without moving, far enough apart that six paddles do not z-fight.
const SUMMON_RING_RADIUS := 1.1

var catalog: Catalog
## Whether test-mode commands are accepted. Off by default, and off in every
## unit test that does not deliberately turn it on: a debug command must never
## be something a build can do by accident. [GameSession] sets it from
## [method TestMode.is_enabled].
var allow_debug_commands := false


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
		Commands.UNLOCK:
			return _unlock(state, cmd)
		Commands.SUMMON:
			return _summon(state, cmd)
		Commands.GRANT_POINTS:
			return _grant_points(state, cmd)
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
		# The skill point is part of the same transaction as the placement that
		# earned it — not a side effect a listener applies afterwards (ADR 0010).
		if state.progression.credit_container(container_id):
			events.append({
				"type": "points_awarded", "container_id": container_id,
				"points": Progression.POINTS_PER_CONTAINER,
				"total_available": state.progression.available_points(),
			})
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


func _unlock(state: WorldState, cmd: Dictionary) -> Dictionary:
	var pid := int(cmd["player_id"])
	var ability_id := String(cmd.get("ability_id", ""))
	if not state.has_player(pid):
		return _fail(E_UNKNOWN_PLAYER)
	if not Progression.ABILITIES.has(ability_id):
		return _fail(E_UNKNOWN_ABILITY)
	if state.progression.has(ability_id):
		return _fail(E_ALREADY_UNLOCKED)
	if not state.progression.unlock(ability_id):
		return _fail(E_NOT_ENOUGH_POINTS)
	var events: Array[Dictionary] = [{
		"type": "ability_unlocked", "ability_id": ability_id, "player_id": pid,
		"points_left": state.progression.available_points(),
	}]
	# Capacity is a party upgrade: everyone in the state gets it, now and on join.
	var capacity := state.progression.capacity()
	for other in state.player_ids():
		if state.player_capacity(other) != capacity:
			state.set_player_capacity(other, capacity)
			events.append({"type": "capacity_changed", "player_id": other, "capacity": capacity})
	return _ok(events)


func _summon(state: WorldState, cmd: Dictionary) -> Dictionary:
	var pid := int(cmd["player_id"])
	var series := String(cmd.get("series", ""))
	if not state.has_player(pid):
		return _fail(E_UNKNOWN_PLAYER)
	if not state.progression.has("call_mate"):
		return _fail(E_ABILITY_LOCKED)
	if series.is_empty() or catalog.series_members(series).is_empty():
		return _fail(E_UNKNOWN_SERIES)
	if not state.progression.can_summon(series):
		return _fail(E_SERIES_SPENT)
	# Only what is still lying about: never a placed item, never out of someone
	# else's hands. Sorted so every peer moves the same item to the same spot.
	var loose: Array[String] = []
	for def in catalog.series_members(series):
		var item_id: String = def.id
		if state.has_item(item_id) and state.kind_of(item_id) == WorldState.Kind.GROUND:
			loose.append(item_id)
	loose.sort()
	if loose.is_empty():
		return _fail(E_NOTHING_TO_SUMMON)
	var centre: Vector3 = state.clamp_to_island(cmd.get("position", Vector3.ZERO))
	state.progression.mark_summoned(series)
	var events: Array[Dictionary] = []
	for i in range(loose.size()):
		var angle := TAU * float(i) / float(loose.size())
		var spot := state.clamp_to_island(
			centre + Vector3(cos(angle), 0.0, sin(angle)) * SUMMON_RING_RADIUS)
		state.set_on_ground(loose[i], spot)
		events.append({"type": "item_summoned", "item_id": loose[i], "player_id": pid, "position": spot})
	return _ok(events)


## Test mode: skill points without the packing. See [method Commands.grant_points].
func _grant_points(state: WorldState, cmd: Dictionary) -> Dictionary:
	if not allow_debug_commands:
		return _fail(E_DEBUG_DISABLED)
	var pid := int(cmd["player_id"])
	if not state.has_player(pid):
		return _fail(E_UNKNOWN_PLAYER)
	var points := maxi(0, int(cmd.get("points", 0)))
	state.progression.points += points
	return _ok([{
		"type": "points_granted", "player_id": pid, "points": points,
		"total_available": state.progression.available_points(),
	}])


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
