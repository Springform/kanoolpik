class_name Progression
extends RefCounted
## Skill points and ability unlocks. Analogue of the reference game's Assemble /
## Insight / Auto-Shelving magic — re-themed as a hungover group getting its act
## together.
##
## Points are awarded per completed container; abilities are bought with them.
## Serialisable so it can be part of a save / multiplayer state.

const POINTS_PER_CONTAINER := 1
## Carry capacity every player starts with (GAME_DESIGN §4). Abilities add to it.
const BASE_CAPACITY := 3

## id -> { cost, name_key }
const ABILITIES := {
	"insight": {"cost": 1, "name_key": "ability.insight"}, # Highlight items of the same series as the one held.
	"call_mate": {"cost": 2, "name_key": "ability.call_mate"}, # A mate throws you the remaining series members.
	"steady_hands": {"cost": 2, "name_key": "ability.steady_hands"}, # +2 carry capacity.
	"auto_place": {"cost": 3, "name_key": "ability.auto_place"}, # Held item snaps to its correct slot when near its container.
	"map_sense": {"cost": 1, "name_key": "ability.map_sense"}, # Arrow towards the container for the held item.
}

## Hidden collectibles (WP-3.7). Four per island, found rather than bought, and
## deliberately not items: they never count toward completion or the island-clean
## check. The effects table lives here for the same reason [constant ABILITIES]
## does — the core has to know what finding one changes. Where they hide and what
## they look like is level data and presentation, and belongs to WP-3.7.
##
## `capacity_bonus` composes with Rolige hænder rather than replacing it; see
## [method capacity_bonus]. The other two are flags phase 5 and phase 4 will read
## and do nothing today, which is deliberate: finding one should already stick.
const COLLECTIBLES := {
	"trolley": {"capacity_bonus": 3, "name_key": "collectible.trolley"}, # +3 carry capacity.
	"sunglasses": {"capacity_bonus": 0, "name_key": "collectible.sunglasses"}, # Phase 5: eases the hangover blur.
	"headlamp": {"capacity_bonus": 0, "name_key": "collectible.headlamp"}, # Phase 5: light.
	"whistle": {"capacity_bonus": 0, "name_key": "collectible.whistle"}, # Phase 4: calls the crew to you.
}

var points: int = 0
var spent: int = 0
var unlocked: Array[String] = []
var _credited_containers: Dictionary = {}
## Series already summoned by "call a mate" — once each, for the whole party.
var _summoned_series: Dictionary = {}
## Collectibles the party has found. Shared, like the points.
var _found: Dictionary = {}


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


## Has this series already been summoned? "Råb på en kammerat" works once per series.
func can_summon(series: String) -> bool:
	return not series.is_empty() and not _summoned_series.has(series)


## Spend the summon for this series. Returns false if it was already spent.
func mark_summoned(series: String) -> bool:
	if not can_summon(series):
		return false
	_summoned_series[series] = true
	return true


## Series spent on summons, sorted — order matters for determinism and diffs.
func summoned_series() -> Array[String]:
	var out: Array[String] = []
	for k in _summoned_series.keys():
		out.append(String(k))
	out.sort()
	return out


## Has this collectible been found yet?
func has_found(collectible_id: String) -> bool:
	return _found.has(collectible_id)


## Record a find. False when the id is unknown or it was already found, so the
## caller can tell "nothing happened" from "something did".
func collect(collectible_id: String) -> bool:
	if not COLLECTIBLES.has(collectible_id) or has_found(collectible_id):
		return false
	_found[collectible_id] = true
	return true


## Everything found, sorted — order matters for determinism and for diffs.
func found_collectibles() -> Array[String]:
	var out: Array[String] = []
	for k in _found.keys():
		out.append(String(k))
	out.sort()
	return out


## The capacity every player should have right now, given what the party owns.
func capacity() -> int:
	return BASE_CAPACITY + capacity_bonus()


## Carry capacity bonus granted by abilities.
## Bought and found bonuses add up. Computed in ONE place on purpose: a second
## place that knows "+2 for steady hands" is a second place to forget the trolley.
func capacity_bonus() -> int:
	var bonus := 2 if has("steady_hands") else 0
	for collectible_id in found_collectibles():
		bonus += int(COLLECTIBLES[collectible_id]["capacity_bonus"])
	return bonus


func to_dict() -> Dictionary:
	return {
		"points": points,
		"spent": spent,
		"unlocked": unlocked.duplicate(),
		"credited": _credited_containers.keys(),
		"summoned": summoned_series(),
		"found": found_collectibles(),
	}


static func from_dict(d: Dictionary) -> Progression:
	var p := Progression.new()
	p.points = int(d.get("points", 0))
	p.spent = int(d.get("spent", 0))
	for a in d.get("unlocked", []):
		p.unlocked.append(String(a))
	for c in d.get("credited", []):
		p._credited_containers[String(c)] = true
	for s in d.get("summoned", []):
		p._summoned_series[String(s)] = true
	for f in d.get("found", []):
		p._found[String(f)] = true
	return p
