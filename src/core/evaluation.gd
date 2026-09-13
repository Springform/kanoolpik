class_name Evaluation
extends RefCounted
## "Lejrlederens vurdering" — the hidden judge that watches how tidy and how
## fast the group is. Analogue of the reference game's Principal's Evaluation.
##
## Pure functions over ([Catalog], [WorldState]) so the HUD, the end screen and
## tests all compute the exact same numbers.

const TICKS_PER_SECOND := 60 # Must match the simulation fixed step.

## Grade thresholds on the final score (0..100).
const GRADES := [
	{"min": 95, "grade": "S", "key": "grade.s"},
	{"min": 85, "grade": "A", "key": "grade.a"},
	{"min": 70, "grade": "B", "key": "grade.b"},
	{"min": 50, "grade": "C", "key": "grade.c"},
	{"min": 0, "grade": "D", "key": "grade.d"},
]

## Time (seconds) within which no speed penalty applies, and the horizon after
## which the time score bottoms out. Tune per level via [method score].
const DEFAULT_PAR_SECONDS := 600.0
const DEFAULT_MAX_SECONDS := 1800.0


## Snapshot of progress for the HUD.
static func progress(catalog: Catalog, state: WorldState) -> Dictionary:
	var total := catalog.item_count()
	var correct := 0
	var wrong := 0
	var ground := 0
	var carried := 0
	for id in catalog.item_ids():
		var loc := state.location(id)
		match int(loc.get("kind", WorldState.Kind.GROUND)):
			WorldState.Kind.GROUND:
				ground += 1
			WorldState.Kind.CARRIED:
				carried += 1
			WorldState.Kind.PLACED:
				if PlacementRules.evaluate(catalog, state, id, loc["container_id"], loc["slot"]) == PlacementRules.Verdict.CORRECT:
					correct += 1
				else:
					wrong += 1
	var completed := 0
	for cid in catalog.container_ids():
		if PlacementRules.is_container_complete(catalog, state, cid):
			completed += 1
	return {
		"total": total,
		"correct": correct,
		"wrong": wrong,
		"on_ground": ground,
		"carried": carried,
		"completion": 0.0 if total == 0 else float(correct) / float(total),
		"containers_total": catalog.container_ids().size(),
		"containers_completed": completed,
		"elapsed_seconds": float(state.elapsed_ticks) / TICKS_PER_SECOND,
		"is_clean": PlacementRules.is_island_clean(catalog, state),
	}


## Final score 0..100 and grade.
##   completion  60% weight — share of items correctly home
##   accuracy    25% weight — 1 - (wrong_placements / placements), cumulative over the run
##   speed       15% weight — 1 within par, linear to 0 at max_seconds
static func score(catalog: Catalog, state: WorldState, par_seconds: float = DEFAULT_PAR_SECONDS, max_seconds: float = DEFAULT_MAX_SECONDS) -> Dictionary:
	var p := progress(catalog, state)
	var placements := int(state.stats.get("placements", 0))
	var wrong := int(state.stats.get("wrong_placements", 0))
	var accuracy := 1.0 if placements == 0 else 1.0 - float(wrong) / float(placements)
	var completion: float = p["completion"]
	var elapsed: float = p["elapsed_seconds"]
	var speed := time_factor(elapsed, par_seconds, max_seconds)
	var total: float = 100.0 * (0.60 * completion + 0.25 * accuracy + 0.15 * speed)
	var points := int(round(total))
	return {
		"points": points,
		"grade": grade_for(points),
		"completion": completion,
		"accuracy": accuracy,
		"speed": speed,
		"elapsed_seconds": elapsed,
	}


static func time_factor(elapsed_seconds: float, par_seconds: float, max_seconds: float) -> float:
	if elapsed_seconds <= par_seconds:
		return 1.0
	if elapsed_seconds >= max_seconds:
		return 0.0
	return 1.0 - (elapsed_seconds - par_seconds) / (max_seconds - par_seconds)


static func grade_for(points: int) -> String:
	for g in GRADES:
		if points >= g["min"]:
			return g["grade"]
	return "D"
