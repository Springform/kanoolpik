extends GdUnitTestSuite

const V := PlacementRules.Verdict

var cat: Catalog
var state: WorldState


func before_test() -> void:
	cat = TestFixtures.catalog()
	state = TestFixtures.ground_state(cat)


func test_correct_category_in_free_slot() -> void:
	assert_int(PlacementRules.evaluate(cat, state, "can_a1", "pant_bag", 0)).is_equal(V.CORRECT)


func test_wrong_category() -> void:
	assert_int(PlacementRules.evaluate(cat, state, "can_a1", "cooler", 0)).is_equal(V.WRONG_CATEGORY)


func test_unknown_item_and_container() -> void:
	assert_int(PlacementRules.evaluate(cat, state, "ghost", "pant_bag", 0)).is_equal(V.UNKNOWN_ITEM)
	assert_int(PlacementRules.evaluate(cat, state, "can_a1", "ghost", 0)).is_equal(V.UNKNOWN_CONTAINER)


func test_invalid_slot() -> void:
	assert_int(PlacementRules.evaluate(cat, state, "can_a1", "pant_bag", -1)).is_equal(V.INVALID_SLOT)
	assert_int(PlacementRules.evaluate(cat, state, "can_a1", "pant_bag", 4)).is_equal(V.INVALID_SLOT)


func test_slot_occupied_by_other_item() -> void:
	state.set_placed("can_b1", "pant_bag", 0)
	assert_int(PlacementRules.evaluate(cat, state, "can_a1", "pant_bag", 0)).is_equal(V.SLOT_OCCUPIED)
	# Re-evaluating the occupant itself is fine.
	assert_int(PlacementRules.evaluate(cat, state, "can_b1", "pant_bag", 0)).is_equal(V.CORRECT)


func test_split_series_is_detected() -> void:
	# Two containers accept "can" in this catalog variant.
	var cat2 := Catalog.from_dicts([
		{"id": "can_a1", "category": "can", "series": "brand_a"},
		{"id": "can_a2", "category": "can", "series": "brand_a"},
	], [
		{"id": "bag_1", "accepts": ["can"]},
		{"id": "bag_2", "accepts": ["can"]},
	])
	var s := TestFixtures.ground_state(cat2)
	s.set_placed("can_a1", "bag_1", 0)
	assert_int(PlacementRules.evaluate(cat2, s, "can_a2", "bag_2", 0)).is_equal(V.SPLIT_SERIES)
	assert_int(PlacementRules.evaluate(cat2, s, "can_a2", "bag_1", 1)).is_equal(V.CORRECT)


func test_ordered_container_accepts_ascending_sequence() -> void:
	state.set_placed("pole_1", "tent_bag", 0)
	assert_int(PlacementRules.evaluate(cat, state, "pole_2", "tent_bag", 1)).is_equal(V.CORRECT)
	assert_int(PlacementRules.evaluate(cat, state, "pole_3", "tent_bag", 5)).is_equal(V.CORRECT)


func test_ordered_container_rejects_descending_sequence() -> void:
	state.set_placed("pole_2", "tent_bag", 2)
	assert_int(PlacementRules.evaluate(cat, state, "pole_1", "tent_bag", 3)).is_equal(V.WRONG_ORDER)
	assert_int(PlacementRules.evaluate(cat, state, "pole_3", "tent_bag", 1)).is_equal(V.WRONG_ORDER)
	assert_int(PlacementRules.evaluate(cat, state, "pole_1", "tent_bag", 0)).is_equal(V.CORRECT)


func test_unordered_series_in_ordered_container_ignores_order() -> void:
	state.set_placed("peg_2", "tent_bag", 0)
	assert_int(PlacementRules.evaluate(cat, state, "peg_1", "tent_bag", 1)).is_equal(V.CORRECT)


func test_order_only_applies_within_same_series() -> void:
	state.set_placed("peg_1", "tent_bag", 0)
	state.set_placed("pole_3", "tent_bag", 1)
	# peg is a different series: no ordering constraint against poles.
	assert_int(PlacementRules.evaluate(cat, state, "peg_2", "tent_bag", 2)).is_equal(V.CORRECT)


func test_container_complete_requires_all_series_members() -> void:
	state.set_placed("can_a1", "pant_bag", 0)
	assert_bool(PlacementRules.is_container_complete(cat, state, "pant_bag")).is_false()
	state.set_placed("can_a2", "pant_bag", 1)
	# brand_a complete, but brand_b's can is still on the ground → still complete?
	# No: completion is about series PRESENT in the container, so yes it is complete
	# for brand_a. can_b1 is not present, so it imposes nothing.
	assert_bool(PlacementRules.is_container_complete(cat, state, "pant_bag")).is_true()
	state.set_placed("can_b1", "pant_bag", 2)
	assert_bool(PlacementRules.is_container_complete(cat, state, "pant_bag")).is_true()


func test_container_complete_fails_on_wrong_item() -> void:
	state.set_placed("food_bread", "cooler", 0)
	assert_bool(PlacementRules.is_container_complete(cat, state, "cooler")).is_true()
	state.set_placed("can_a1", "cooler", 1)
	assert_bool(PlacementRules.is_container_complete(cat, state, "cooler")).is_false()


func test_empty_container_is_not_complete() -> void:
	assert_bool(PlacementRules.is_container_complete(cat, state, "cooler")).is_false()


func test_island_clean_only_when_everything_correctly_home() -> void:
	assert_bool(PlacementRules.is_island_clean(cat, state)).is_false()
	_place_everything_correctly()
	assert_bool(PlacementRules.is_island_clean(cat, state)).is_true()
	state.set_placed("food_bread", "pant_bag", 3)
	assert_bool(PlacementRules.is_island_clean(cat, state)).is_false()


func test_find_correct_slot_skips_occupied_and_respects_order() -> void:
	state.set_placed("pole_2", "tent_bag", 0)
	# pole_1 must go before slot 0 → impossible.
	assert_int(PlacementRules.find_correct_slot(cat, state, "pole_1", "tent_bag")).is_equal(-1)
	assert_int(PlacementRules.find_correct_slot(cat, state, "pole_3", "tent_bag")).is_equal(1)
	assert_int(PlacementRules.find_correct_slot(cat, state, "can_a1", "tent_bag")).is_equal(-1)


func test_verdicts_in_container() -> void:
	state.set_placed("can_a1", "pant_bag", 0)
	state.set_placed("food_bread", "pant_bag", 1)
	var v := PlacementRules.verdicts_in_container(cat, state, "pant_bag")
	assert_int(v["can_a1"]).is_equal(V.CORRECT)
	assert_int(v["food_bread"]).is_equal(V.WRONG_CATEGORY)


func test_verdict_name() -> void:
	assert_str(PlacementRules.verdict_name(V.WRONG_ORDER)).is_equal("WRONG_ORDER")


func _place_everything_correctly() -> void:
	state.set_placed("can_a1", "pant_bag", 0)
	state.set_placed("can_a2", "pant_bag", 1)
	state.set_placed("can_b1", "pant_bag", 2)
	state.set_placed("pole_1", "tent_bag", 0)
	state.set_placed("pole_2", "tent_bag", 1)
	state.set_placed("pole_3", "tent_bag", 2)
	state.set_placed("peg_1", "tent_bag", 3)
	state.set_placed("peg_2", "tent_bag", 4)
	state.set_placed("food_bread", "cooler", 0)
