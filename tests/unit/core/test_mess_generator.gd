extends GdUnitTestSuite

var cat: Catalog


func before_test() -> void:
	cat = TestFixtures.catalog()


func test_every_item_ends_up_on_the_ground() -> void:
	var state := MessGenerator.generate(1, cat, TestFixtures.zones())
	assert_int(state.items_of_kind(WorldState.Kind.GROUND).size()).is_equal(cat.item_count())
	assert_int(state.rng_seed).is_equal(1)


func test_same_seed_is_deterministic() -> void:
	var a := MessGenerator.generate(12345, cat, TestFixtures.zones())
	var b := MessGenerator.generate(12345, cat, TestFixtures.zones())
	assert_dict(a.to_dict()).is_equal(b.to_dict())


func test_different_seeds_differ() -> void:
	var a := MessGenerator.generate(1, cat, TestFixtures.zones())
	var b := MessGenerator.generate(2, cat, TestFixtures.zones())
	assert_dict(a.to_dict()).is_not_equal(b.to_dict())


func test_items_land_inside_an_allowed_zone() -> void:
	var zones := TestFixtures.zones()
	for s in range(20):
		var state := MessGenerator.generate(s, cat, zones)
		for id in cat.item_ids():
			var pos: Vector3 = state.location(id)["position"]
			var inside := false
			for z in zones:
				var cats: Array = z.get("categories", [])
				if (cats.is_empty() or cats.has(cat.get_item(id).category)) and MessGenerator.zone_contains(z, pos):
					inside = true
			assert_bool(inside).override_failure_message("%s at %s (seed %d) is outside every allowed zone" % [id, pos, s]).is_true()


func test_category_restricted_zone_never_gets_other_categories() -> void:
	var zones := [
		{"id": "a", "center": [0, 0, 0], "radius": 1.0, "weight": 1.0, "categories": ["can"]},
		{"id": "b", "center": [100, 0, 0], "radius": 1.0, "weight": 1.0, "categories": ["pole", "peg", "food"]},
	]
	var state := MessGenerator.generate(3, cat, zones)
	for id in cat.item_ids():
		var pos: Vector3 = state.location(id)["position"]
		if cat.get_item(id).category == "can":
			assert_bool(MessGenerator.zone_contains(zones[0], pos)).is_true()
		else:
			assert_bool(MessGenerator.zone_contains(zones[1], pos)).is_true()


func test_ground_y_is_applied() -> void:
	var state := MessGenerator.generate(3, cat, TestFixtures.zones(), 0.25)
	for id in cat.item_ids():
		assert_float(state.location(id)["position"].y).is_equal(0.25)
