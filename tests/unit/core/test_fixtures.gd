class_name TestFixtures
extends RefCounted
## Small hand-built catalog used across core unit tests. Keep it tiny and
## readable — the real catalog is exercised by test_data_integrity.gd.
##
## Containers:
##   pant_bag   accepts can            unordered, 4 slots
##   tent_bag   accepts pole, peg      ORDERED,   6 slots
##   cooler     accepts food           unordered, 2 slots
## Items:
##   can_a1, can_a2   series brand_a
##   can_b1           series brand_b
##   pole_1..pole_3   series poles, sequence 1..3 (size 2)
##   peg_1, peg_2     series pegs (unordered)
##   food_bread       no series


static func catalog() -> Catalog:
	return Catalog.from_dicts([
		{"id": "can_a1", "category": "can", "series": "brand_a"},
		{"id": "can_a2", "category": "can", "series": "brand_a"},
		{"id": "can_b1", "category": "can", "series": "brand_b"},
		{"id": "pole_1", "category": "pole", "series": "poles", "sequence": 1, "size": 2},
		{"id": "pole_2", "category": "pole", "series": "poles", "sequence": 2, "size": 2},
		{"id": "pole_3", "category": "pole", "series": "poles", "sequence": 3, "size": 2},
		{"id": "peg_1", "category": "peg", "series": "pegs"},
		{"id": "peg_2", "category": "peg", "series": "pegs"},
		{"id": "food_bread", "category": "food"},
	], [
		{"id": "pant_bag", "accepts": ["can"], "slot_count": 4},
		{"id": "tent_bag", "accepts": ["pole", "peg"], "slot_count": 6, "ordered": true},
		{"id": "cooler", "accepts": ["food"], "slot_count": 2},
	])


## All items on the ground at origin, one player (id 1) with the given capacity.
static func ground_state(cat: Catalog, capacity: int = 4) -> WorldState:
	var state := WorldState.new()
	state.add_player(1, capacity)
	for id in cat.item_ids():
		state.set_on_ground(id, Vector3.ZERO)
	return state


static func zones() -> Array:
	return [
		{"id": "camp", "center": [0, 0, 0], "radius": 5.0, "weight": 3.0},
		{"id": "tents", "center": [10, 0, 0], "radius": 2.0, "weight": 1.0, "categories": ["pole", "peg"]},
	]
