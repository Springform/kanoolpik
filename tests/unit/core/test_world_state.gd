extends GdUnitTestSuite


func test_round_trip_serialisation() -> void:
	var state := WorldState.new()
	state.rng_seed = 77
	state.elapsed_ticks = 1234
	state.add_player(1, 3)
	state.add_player(5, 5)
	state.set_on_ground("a", Vector3(1.5, 0, -2))
	state.set_carried("b", 5)
	state.set_placed("c", "bag", 2)
	state.bump_stat("wrong_placements", 3)
	var copy := WorldState.from_dict(state.to_dict())
	assert_dict(copy.to_dict()).is_equal(state.to_dict())
	assert_vector(copy.location("a")["position"]).is_equal(Vector3(1.5, 0, -2))
	assert_int(copy.player_capacity(5)).is_equal(5)
	assert_int(copy.stats["wrong_placements"]).is_equal(3)
	assert_str(copy.container_of("c")).is_equal("bag")


func test_duplicate_state_is_independent() -> void:
	var state := WorldState.new()
	state.set_on_ground("a", Vector3.ZERO)
	var copy := state.duplicate_state()
	copy.set_carried("a", 1)
	assert_int(state.kind_of("a")).is_equal(WorldState.Kind.GROUND)
	assert_int(copy.kind_of("a")).is_equal(WorldState.Kind.CARRIED)


func test_items_in_container_sorted_by_slot() -> void:
	var state := WorldState.new()
	state.set_placed("z", "bag", 3)
	state.set_placed("a", "bag", 1)
	state.set_placed("m", "other", 0)
	var entries := state.items_in_container("bag")
	assert_int(entries.size()).is_equal(2)
	assert_str(entries[0]["item_id"]).is_equal("a")
	assert_str(entries[1]["item_id"]).is_equal("z")
	assert_str(state.item_in_slot("bag", 3)).is_equal("z")
	assert_str(state.item_in_slot("bag", 0)).is_equal("")


func test_remove_player_drops_carried_items() -> void:
	var state := WorldState.new()
	state.add_player(2)
	state.set_carried("a", 2)
	state.remove_player(2)
	assert_bool(state.has_player(2)).is_false()
	assert_int(state.kind_of("a")).is_equal(WorldState.Kind.GROUND)


func test_player_ids_sorted() -> void:
	var state := WorldState.new()
	state.add_player(9)
	state.add_player(2)
	state.add_player(5)
	assert_array(state.player_ids()).is_equal([2, 5, 9])
