class_name Progression
extends RefCounted
## Skill points and ability unlocks. Analogue of the reference game's Assemble /
## Insight / Auto-Shelving magic — re-themed as a hungover group getting its act
## together.
##
## Points are awarded per completed container; abilities are bought with them.
## Serialisable so it can be part of a save / multiplayer state.

const POINTS_PER_CONTAINER := 1

## id -> { cost, name_key }
const ABILITIES := {
	"insight": {"cost": 1, "name_key": "ability.insight"}, # Highlight items of the same series as the one held.
	"call_mate": {"cost": 2, "name_key": "ability.call_mate"}, # A mate throws you the remaining series members.
	"steady_hands": {"cost": 2, "name_key": "ability.steady_hands"}, # +2 carry capacity.
	"auto_place": {"cost": 3, "name_key": "ability.auto_place"}, # Held item snaps to its correct slot when near its container.
	"map_sense": {"cost": 1, "name_key": "ability.map_sense"}, # Arrow towards the container for the held item.
}

var points: int = 0
var spent: int = 0
var unlocked: Array[String] = []
var _credited_containers: Dictionary = {}


## Credit a completed container once. Returns true if points were awarded.
func credit_container(container_id: String) -> bool:
	if _credited_containers.has(container_id):
		return false
	_credited_containers[container_id] = true
	points += POINTS_PER_CONTAINER
	return true


func available_points() -> int:
	return points - spent


func has(ability_id: String) -> bool:
	return unlocked.has(ability_id)


func can_unlock(ability_id: String) -> bool:
	if not ABILITIES.has(ability_id) or has(ability_id):
		return false
	return available_points() >= int(ABILITIES[ability_id]["cost"])


func unlock(ability_id: String) -> bool:
	if not can_unlock(ability_id):
		return false
	spent += int(ABILITIES[ability_id]["cost"])
	unlocked.append(ability_id)
	return true


## Carry capacity bonus granted by abilities.
func capacity_bonus() -> int:
	return 2 if has("steady_hands") else 0


func to_dict() -> Dictionary:
	return {
		"points": points,
		"spent": spent,
		"unlocked": unlocked.duplicate(),
		"credited": _credited_containers.keys(),
	}


static func from_dict(d: Dictionary) -> Progression:
	var p := Progression.new()
	p.points = int(d.get("points", 0))
	p.spent = int(d.get("spent", 0))
	for a in d.get("unlocked", []):
		p.unlocked.append(String(a))
	for c in d.get("credited", []):
		p._credited_containers[String(c)] = true
	return p
