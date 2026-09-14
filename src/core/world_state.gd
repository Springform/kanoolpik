class_name WorldState
extends RefCounted
## The complete, serialisable truth about where every item is.
##
## This is the object that gets replicated in multiplayer (host-authoritative),
## saved to disk, and inspected by [Evaluation]. It is deliberately dumb: it
## stores locations and answers queries. All rule checking lives in
## [PlacementRules] and all mutation-with-validation in [CommandProcessor].
##
## Determinism rule: never iterate a Dictionary and depend on order for game
## logic — use the sorted helpers below.

enum Kind { GROUND, CARRIED, PLACED }

## item_id -> Dictionary { kind, position: Vector3, player_id: int, container_id: String, slot: int, carry_seq: int }
var _locations: Dictionary = {}
## Monotonic counter so carried_by() can return items in pick-up order (deterministic, serialised).
var _carry_counter: int = 0
## player_id -> Dictionary { capacity: int }
var _players: Dictionary = {}
var rng_seed: int = 0
var elapsed_ticks: int = 0 ## Simulation ticks since level start (fixed step), for scoring.
## Cumulative counters used by [Evaluation]. Keys: placements, wrong_placements, pickups.
var stats: Dictionary = {"placements": 0, "wrong_placements": 0, "pickups": 0}
## Skill points and unlocked abilities — party-wide, and part of the replicated
## snapshot since ADR 0010. Only [CommandProcessor] may change it during play.
var progression: Progression = Progression.new()
## Walkable bounds, copied from the level so the core can keep commands that
## move items from putting them in the lake. radius <= 0 means "unbounded",
## which is what a bare WorldState in a unit test gets.
var island_radius: float = 0.0
var ground_y: float = 0.0


func bump_stat(key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


# --- Players -----------------------------------------------------------------

func add_player(player_id: int, capacity: int = 3) -> void:
	_players[player_id] = {"capacity": capacity}


func remove_player(player_id: int) -> void:
	# Anything the player was carrying falls to the ground at origin — the
	# presentation layer should reposition it via a DropCommand first.
	for item_id in carried_by(player_id):
		set_on_ground(item_id, Vector3.ZERO)
	_players.erase(player_id)


func has_player(player_id: int) -> bool:
	return _players.has(player_id)


func player_capacity(player_id: int) -> int:
	return int(_players.get(player_id, {}).get("capacity", 0))


func set_player_capacity(player_id: int, capacity: int) -> void:
	if _players.has(player_id):
		_players[player_id]["capacity"] = capacity


## Pull a position back onto walkable ground. Unbounded states return it as-is,
## so unit tests that never set bounds behave exactly as they did before.
func clamp_to_island(position: Vector3) -> Vector3:
	if island_radius <= 0.0:
		return position
	var flat := Vector2(position.x, position.z)
	if flat.length() > island_radius:
		flat = flat.normalized() * island_radius
	return Vector3(flat.x, ground_y, flat.y)


func player_ids() -> Array[int]:
	var out: Array[int] = []
	for k in _players.keys():
		out.append(int(k))
	out.sort()
	return out


# --- Item locations ----------------------------------------------------------

func has_item(item_id: String) -> bool:
	return _locations.has(item_id)


func location(item_id: String) -> Dictionary:
	return _locations.get(item_id, {})


func kind_of(item_id: String) -> int:
	return int(_locations.get(item_id, {}).get("kind", -1))


func set_on_ground(item_id: String, position: Vector3) -> void:
	_locations[item_id] = {"kind": Kind.GROUND, "position": position, "player_id": -1, "container_id": "", "slot": -1, "carry_seq": -1}


func set_carried(item_id: String, player_id: int) -> void:
	_carry_counter += 1
	_locations[item_id] = {"kind": Kind.CARRIED, "position": Vector3.ZERO, "player_id": player_id, "container_id": "", "slot": -1, "carry_seq": _carry_counter}


func set_placed(item_id: String, container_id: String, slot: int) -> void:
	_locations[item_id] = {"kind": Kind.PLACED, "position": Vector3.ZERO, "player_id": -1, "container_id": container_id, "slot": slot, "carry_seq": -1}


func remove_item(item_id: String) -> void:
	_locations.erase(item_id)


func item_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _locations.keys():
		out.append(k)
	out.sort()
	return out


func items_of_kind(kind: int) -> Array[String]:
	var out: Array[String] = []
	for id in item_ids():
		if kind_of(id) == kind:
			out.append(id)
	return out


## Items the player carries, in PICK-UP ORDER (first picked first). The last
## element is the "active" item that place/drop act on.
func carried_by(player_id: int) -> Array[String]:
	var entries: Array[Dictionary] = []
	for id in item_ids():
		var loc: Dictionary = _locations[id]
		if loc["kind"] == Kind.CARRIED and loc["player_id"] == player_id:
			entries.append({"id": id, "seq": int(loc.get("carry_seq", 0))})
	entries.sort_custom(func(a, b): return a["seq"] < b["seq"])
	var out: Array[String] = []
	for e in entries:
		out.append(e["id"])
	return out


## The most recently picked-up item, or "" when hands are empty.
func active_item(player_id: int) -> String:
	var held := carried_by(player_id)
	return "" if held.is_empty() else held[held.size() - 1]


## Returns Array of { "item_id": String, "slot": int } sorted by slot.
func items_in_container(container_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in item_ids():
		var loc: Dictionary = _locations[id]
		if loc["kind"] == Kind.PLACED and loc["container_id"] == container_id:
			out.append({"item_id": id, "slot": int(loc["slot"])})
	out.sort_custom(func(a, b): return a["slot"] < b["slot"])
	return out


func item_in_slot(container_id: String, slot: int) -> String:
	for entry in items_in_container(container_id):
		if entry["slot"] == slot:
			return entry["item_id"]
	return ""


func container_of(item_id: String) -> String:
	var loc := location(item_id)
	if loc.get("kind", -1) == Kind.PLACED:
		return loc["container_id"]
	return ""


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	var locs := {}
	for id in item_ids():
		var loc: Dictionary = _locations[id]
		var p: Vector3 = loc["position"]
		locs[id] = {
			"kind": loc["kind"],
			"position": [p.x, p.y, p.z],
			"player_id": loc["player_id"],
			"container_id": loc["container_id"],
			"slot": loc["slot"],
			"carry_seq": int(loc.get("carry_seq", -1)),
		}
	var players := {}
	for pid in player_ids():
		players[str(pid)] = _players[pid].duplicate()
	return {
		"rng_seed": rng_seed,
		"elapsed_ticks": elapsed_ticks,
		"carry_counter": _carry_counter,
		"stats": stats.duplicate(),
		"locations": locs,
		"players": players,
		"progression": progression.to_dict(),
		"island_radius": island_radius,
		"ground_y": ground_y,
	}


static func from_dict(d: Dictionary) -> WorldState:
	var state := WorldState.new()
	state.rng_seed = int(d.get("rng_seed", 0))
	state.elapsed_ticks = int(d.get("elapsed_ticks", 0))
	state._carry_counter = int(d.get("carry_counter", 0))
	for k in d.get("stats", {}).keys():
		state.stats[String(k)] = int(d["stats"][k])
	for id in d.get("locations", {}).keys():
		var loc: Dictionary = d["locations"][id]
		var pos_arr: Array = loc.get("position", [0, 0, 0])
		state._locations[String(id)] = {
			"kind": int(loc.get("kind", Kind.GROUND)),
			"position": Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
			"player_id": int(loc.get("player_id", -1)),
			"container_id": String(loc.get("container_id", "")),
			"slot": int(loc.get("slot", -1)),
			"carry_seq": int(loc.get("carry_seq", -1)),
		}
	for pid in d.get("players", {}).keys():
		state._players[int(pid)] = {"capacity": int(d["players"][pid].get("capacity", Progression.BASE_CAPACITY))}
	state.progression = Progression.from_dict(d.get("progression", {}))
	state.island_radius = float(d.get("island_radius", 0.0))
	state.ground_y = float(d.get("ground_y", 0.0))
	return state


func duplicate_state() -> WorldState:
	return WorldState.from_dict(to_dict())
