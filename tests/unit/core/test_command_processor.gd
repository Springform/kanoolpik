extends GdUnitTestSuite

const V := PlacementRules.Verdict

var cat: Catalog
var state: WorldState
var proc: CommandProcessor


func before_test() -> void:
	cat = TestFixtures.catalog()
	state = TestFixtures.ground_state(cat, 4)
	proc = CommandProcessor.new(cat)


func test_unknown_command_type_fails() -> void:
	var r := proc.apply(state, {"type": "dance", "player_id": 1})
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_UNKNOWN_TYPE)


func test_pick_up_moves_item_to_hands_and_emits_event() -> void:
	var r := proc.apply(state, Commands.pick_up(1, "can_a1"))
	assert_bool(r["ok"]).is_true()
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.CARRIED)
	assert_array(state.carried_by(1)).contains_exactly(["can_a1"])
	assert_int(r["events"].size()).is_equal(1)
	assert_str(r["events"][0]["type"]).is_equal("item_picked_up")
	assert_int(state.stats["pickups"]).is_equal(1)


func test_pick_up_rejects_unknown_player_or_item() -> void:
	assert_str(proc.apply(state, Commands.pick_up(99, "can_a1"))["error"]).is_equal(CommandProcessor.E_UNKNOWN_PLAYER)
	assert_str(proc.apply(state, Commands.pick_up(1, "ghost"))["error"]).is_equal(CommandProcessor.E_UNKNOWN_ITEM)


func test_pick_up_rejects_item_not_on_ground() -> void:
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.pick_up(1, "can_a1"))
	assert_str(r["error"]).is_equal(CommandProcessor.E_NOT_ON_GROUND)


func test_capacity_counts_item_size() -> void:
	# capacity 4: two poles (size 2 each) fill the hands.
	assert_bool(proc.apply(state, Commands.pick_up(1, "pole_1"))["ok"]).is_true()
	assert_bool(proc.apply(state, Commands.pick_up(1, "pole_2"))["ok"]).is_true()
	var r := proc.apply(state, Commands.pick_up(1, "can_a1"))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_HANDS_FULL)
	assert_int(proc.carried_load(state, 1)).is_equal(4)


func test_drop_puts_item_back_on_ground_at_position() -> void:
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.drop(1, "can_a1", Vector3(1, 0, 2)))
	assert_bool(r["ok"]).is_true()
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.GROUND)
	assert_vector(state.location("can_a1")["position"]).is_equal(Vector3(1, 0, 2))


func test_drop_requires_carrying() -> void:
	var r := proc.apply(state, Commands.drop(1, "can_a1", Vector3.ZERO))
	assert_str(r["error"]).is_equal(CommandProcessor.E_NOT_CARRIED)


func test_place_correct_emits_verdict() -> void:
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.place(1, "can_a1", "pant_bag", 0))
	assert_bool(r["ok"]).is_true()
	assert_int(r["verdict"]).is_equal(V.CORRECT)
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.PLACED)
	assert_int(state.stats["placements"]).is_equal(1)
	assert_int(state.stats["wrong_placements"]).is_equal(0)


func test_wrong_placement_is_allowed_but_counted() -> void:
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.place(1, "can_a1", "cooler", 0))
	assert_bool(r["ok"]).is_true()
	assert_int(r["verdict"]).is_equal(V.WRONG_CATEGORY)
	assert_int(state.stats["wrong_placements"]).is_equal(1)
	assert_str(state.container_of("can_a1")).is_equal("cooler")


func test_place_into_occupied_slot_is_rejected() -> void:
	state.set_placed("can_b1", "pant_bag", 0)
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.place(1, "can_a1", "pant_bag", 0))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_BAD_SLOT)
	assert_int(r["verdict"]).is_equal(V.SLOT_OCCUPIED)
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.CARRIED)


func test_place_emits_container_completed() -> void:
	proc.apply(state, Commands.pick_up(1, "food_bread"))
	var r := proc.apply(state, Commands.place(1, "food_bread", "cooler", 0))
	var types: Array = r["events"].map(func(e): return e["type"])
	assert_array(types).contains_exactly(["item_placed", "container_completed"])


func test_place_emits_island_clean_on_last_item() -> void:
	var placements := [
		["can_a1", "pant_bag", 0], ["can_a2", "pant_bag", 1], ["can_b1", "pant_bag", 2],
		["pole_1", "tent_bag", 0], ["pole_2", "tent_bag", 1], ["pole_3", "tent_bag", 2],
		["peg_1", "tent_bag", 3], ["peg_2", "tent_bag", 4], ["food_bread", "cooler", 0],
	]
	var last: Dictionary = {}
	for p in placements:
		assert_bool(proc.apply(state, Commands.pick_up(1, p[0]))["ok"]).is_true()
		last = proc.apply(state, Commands.place(1, p[0], p[1], p[2]))
		assert_bool(last["ok"]).is_true()
	var types: Array = last["events"].map(func(e): return e["type"])
	assert_array(types).contains("island_clean")


func test_take_out_returns_item_to_hands() -> void:
	state.set_placed("can_a1", "cooler", 0)
	var r := proc.apply(state, Commands.take_out(1, "can_a1"))
	assert_bool(r["ok"]).is_true()
	assert_str(r["events"][0]["container_id"]).is_equal("cooler")
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.CARRIED)


func test_take_out_requires_placed_item_and_capacity() -> void:
	assert_str(proc.apply(state, Commands.take_out(1, "can_a1"))["error"]).is_equal(CommandProcessor.E_NOT_PLACED)
	state.set_placed("pole_1", "tent_bag", 0)
	state.set_player_capacity(1, 1)
	assert_str(proc.apply(state, Commands.take_out(1, "pole_1"))["error"]).is_equal(CommandProcessor.E_HANDS_FULL)


func test_tick_advances_clock() -> void:
	proc.apply(state, Commands.tick(60))
	proc.apply(state, Commands.tick())
	assert_int(state.elapsed_ticks).is_equal(61)


func test_same_commands_produce_identical_states() -> void:
	# Determinism is the foundation of host/client agreement in multiplayer.
	var cmds := [
		Commands.pick_up(1, "can_a1"), Commands.place(1, "can_a1", "pant_bag", 3),
		Commands.pick_up(1, "pole_2"), Commands.place(1, "pole_2", "tent_bag", 2),
		Commands.pick_up(1, "pole_1"), Commands.place(1, "pole_1", "tent_bag", 4), # wrong order
		Commands.tick(120),
	]
	var a := TestFixtures.ground_state(cat)
	var b := TestFixtures.ground_state(cat)
	for c in cmds:
		proc.apply(a, c)
		proc.apply(b, c)
	assert_dict(a.to_dict()).is_equal(b.to_dict())
	assert_int(a.stats["wrong_placements"]).is_equal(1)
