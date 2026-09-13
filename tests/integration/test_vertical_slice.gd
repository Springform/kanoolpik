extends GdUnitTestSuite
## Runs the real scenes headless: session → island spawn → commands → presentation reacts.
## This is the smoke test every agent must keep green; it proves the wiring, not the visuals.

var island: Island


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)


func after_test() -> void:
	GameSession.stop_level()


func test_island_spawns_every_item_and_container() -> void:
	assert_int(island.get_node("Items").get_child_count()).is_equal(GameSession.catalog.item_count())
	assert_int(island.get_node("Containers").get_child_count()).is_equal(GameSession.catalog.container_ids().size())


func test_pick_up_hides_item_and_place_colours_slot() -> void:
	var item_node: PickupItem = island.get_node("Items/Item_can_tuborg_1")
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	assert_bool(item_node.visible).is_false()
	assert_array(GameSession.state.carried_by(pid)).contains_exactly(["can_tuborg_1"])

	var bag: ContainerNode = island.get_node("Containers/Container_pant_bag")
	var slot := bag.first_free_slot()
	GameSession.submit(Commands.place(pid, "can_tuborg_1", "pant_bag", slot))
	assert_int(GameSession.state.kind_of("can_tuborg_1")).is_equal(WorldState.Kind.PLACED)
	assert_object(bag.get_node("Slots").get_child(slot).material_override).is_equal(bag._mat_correct)


func test_wrong_placement_colours_slot_red_and_counts() -> void:
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "food_bread"))
	GameSession.submit(Commands.place(pid, "food_bread", "canoe", 0))
	var canoe: ContainerNode = island.get_node("Containers/Container_canoe")
	assert_object(canoe.get_node("Slots").get_child(0).material_override).is_equal(canoe._mat_wrong)
	assert_int(GameSession.state.stats["wrong_placements"]).is_equal(1)


func test_rejected_command_is_reported_on_bus() -> void:
	var pid := GameSession.local_player_id()
	var rejected := []
	GameEvents.command_rejected.connect(func(_c, err): rejected.append(err))
	GameSession.submit(Commands.drop(pid, "can_tuborg_1", Vector3.ZERO))
	assert_array(rejected).contains_exactly([CommandProcessor.E_NOT_CARRIED])


func test_progress_signal_reflects_state() -> void:
	var received := [] # lambdas capture by value, so collect into an Array
	GameEvents.progress_changed.connect(func(p): received.append(p))
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "firewood_1"))
	GameSession.submit(Commands.place(pid, "firewood_1", "fire_pit", 0))
	var last: Dictionary = received[received.size() - 1]
	assert_int(last["correct"]).is_equal(1)
	assert_int(last["total"]).is_equal(GameSession.catalog.item_count())
