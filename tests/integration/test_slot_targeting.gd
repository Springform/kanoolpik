extends GdUnitTestSuite
## WP-1.3 — aiming at a specific slot: place exactly there, or take the item
## back out. Drives Player.interact_with_container() directly so no raycast
## simulation is needed; slot_at() is tested separately against real colliders.

var island: Island
var player: Player
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	pid = GameSession.local_player_id()
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = false # no input, no mouse capture
	player.player_id = pid
	add_child(player)


func after_test() -> void:
	GameSession.stop_level()


func _container(id: String) -> ContainerNode:
	return island.get_node("Containers/Container_" + id)


# --- Slot colliders ---------------------------------------------------------------

func test_every_slot_has_its_own_aimable_node() -> void:
	for cid in GameSession.catalog.container_ids():
		var c := _container(cid)
		assert_int(c.slot_count()).is_equal(GameSession.catalog.get_container(cid).slot_count)
		for i in range(c.slot_count()):
			var slot := c.slot_node(i)
			assert_str(slot.container_id).is_equal(cid)
			assert_int(slot.slot_index).is_equal(i)
			assert_int(slot.get_child_count()).is_greater_equal(3) # shape + mesh + mark


func test_slot_hitbox_is_larger_than_the_visible_cube() -> void:
	assert_bool(SlotNode.HITBOX_SIZE.x > SlotNode.CUBE_SIZE.x).is_true()
	assert_bool(SlotNode.HITBOX_SIZE.y > SlotNode.CUBE_SIZE.y).is_true()


func test_slot_at_resolves_colliders_and_body() -> void:
	var bag := _container("pant_bag")
	assert_int(bag.slot_at(bag.slot_node(3))).is_equal(3)
	assert_int(bag.slot_at(bag.slot_node(3).mesh)).is_equal(3) # a child of the slot
	assert_int(bag.slot_at(bag)).is_equal(-1) # the container body itself
	assert_int(bag.slot_at(null)).is_equal(-1)


func test_slot_node_knows_what_it_holds() -> void:
	var bag := _container("pant_bag")
	assert_bool(bag.slot_node(0).is_empty()).is_true()
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	GameSession.submit(Commands.place(pid, "can_tuborg_1", "pant_bag", 0))
	assert_str(bag.slot_node(0).item_id()).is_equal("can_tuborg_1")
	assert_bool(bag.slot_node(0).is_empty()).is_false()


# --- Interaction ------------------------------------------------------------------

func test_aiming_at_an_empty_slot_places_exactly_there() -> void:
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	player.interact_with_container(_container("pant_bag"), 5)
	assert_str(GameSession.state.item_in_slot("pant_bag", 5)).is_equal("can_tuborg_1")


func test_aiming_at_an_occupied_slot_takes_the_item_out() -> void:
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	GameSession.submit(Commands.place(pid, "can_tuborg_1", "pant_bag", 2))
	assert_int(GameSession.state.kind_of("can_tuborg_1")).is_equal(WorldState.Kind.PLACED)
	player.interact_with_container(_container("pant_bag"), 2)
	assert_int(GameSession.state.kind_of("can_tuborg_1")).is_equal(WorldState.Kind.CARRIED)
	assert_str(GameSession.state.item_in_slot("pant_bag", 2)).is_equal("")


func test_taking_out_works_even_with_a_full_hand_of_one_free_size() -> void:
	# capacity 3: hold two, take out a third → fits.
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	GameSession.submit(Commands.place(pid, "can_tuborg_1", "pant_bag", 0))
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_2"))
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_3"))
	player.interact_with_container(_container("pant_bag"), 0)
	assert_int(GameSession.processor.carried_load(GameSession.state, pid)).is_equal(3)


func test_taking_out_with_full_hands_is_rejected_not_crashing() -> void:
	var errors: Array[String] = []
	GameEvents.command_rejected.connect(func(_c: Dictionary, e: String) -> void: errors.append(e))
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	GameSession.submit(Commands.place(pid, "can_tuborg_1", "pant_bag", 0))
	GameSession.submit(Commands.pick_up(pid, "tent_canvas")) # size 3 of capacity 3 → no room
	player.interact_with_container(_container("pant_bag"), 0)
	assert_array(errors).contains([CommandProcessor.E_HANDS_FULL])
	assert_str(GameSession.state.item_in_slot("pant_bag", 0)).is_equal("can_tuborg_1")


func test_aiming_at_the_body_keeps_the_auto_slot_behaviour() -> void:
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	player.interact_with_container(_container("pant_bag"), -1)
	# find_correct_slot returns the first correct slot → 0
	assert_str(GameSession.state.item_in_slot("pant_bag", 0)).is_equal("can_tuborg_1")


func test_body_aim_falls_back_to_first_free_slot_when_nothing_is_correct() -> void:
	GameSession.submit(Commands.pick_up(pid, "food_bread"))
	player.interact_with_container(_container("canoe"), -1) # bread does not belong in the canoe
	assert_str(GameSession.state.item_in_slot("canoe", 0)).is_equal("food_bread")


func test_empty_hands_on_an_empty_slot_does_nothing() -> void:
	player.interact_with_container(_container("pant_bag"), 0)
	assert_str(GameSession.state.item_in_slot("pant_bag", 0)).is_equal("")


func test_ordered_container_can_be_filled_deliberately_out_of_order() -> void:
	# The point of slot targeting: the player, not the game, decides where poles go.
	var bag := _container("tent_bag")
	for i in [4, 3, 2, 1]:
		GameSession.submit(Commands.pick_up(pid, "tent_pole_%d" % i))
		player.interact_with_container(bag, i - 1)
		GameSession.submit(Commands.tick(1))
	assert_str(GameSession.state.item_in_slot("tent_bag", 0)).is_equal("tent_pole_1")
	assert_str(GameSession.state.item_in_slot("tent_bag", 3)).is_equal("tent_pole_4")
	for i in range(4):
		assert_int(bag.slot_verdict(i)).is_equal(PlacementRules.Verdict.CORRECT)


func test_wrong_order_is_possible_and_fixable_by_taking_out() -> void:
	var bag := _container("tent_bag")
	GameSession.submit(Commands.pick_up(pid, "tent_pole_2"))
	player.interact_with_container(bag, 0)
	GameSession.submit(Commands.pick_up(pid, "tent_pole_1"))
	player.interact_with_container(bag, 1) # pole 1 after pole 2 → wrong order
	assert_int(bag.slot_verdict(1)).is_equal(PlacementRules.Verdict.WRONG_ORDER)
	player.interact_with_container(bag, 1) # take it out again
	assert_int(GameSession.state.kind_of("tent_pole_1")).is_equal(WorldState.Kind.CARRIED)
	# Poles are size 2 and capacity is 3, so the hands must be freed before the next one.
	GameSession.submit(Commands.drop(pid, "tent_pole_1", Vector3.ZERO))
	player.interact_with_container(bag, 0) # slot 0 still holds pole 2 → takes that out
	assert_int(GameSession.state.kind_of("tent_pole_2")).is_equal(WorldState.Kind.CARRIED)
	assert_bool(bag.slot_node(0).is_empty()).is_true()


# --- HUD prompts ---------------------------------------------------------------------

func test_prompts_describe_the_targeted_slot() -> void:
	var hud: HUD = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)
	var bag := _container("pant_bag")
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	var held := GameSession.state.carried_by(pid)
	var can_name := tr("item.can_tuborg_1")
	# empty slot 2 → place there, shown 1-based
	assert_str(hud._prompt_for(bag, held, 2)).is_equal(tr("ui.hud.place_slot") % [can_name, 3])
	# body → generic place
	assert_str(hud._prompt_for(bag, held, -1)).is_equal(tr("ui.hud.place") % [can_name, tr("container.pant_bag")])
	# occupied slot → take out, even with a full hand
	GameSession.submit(Commands.place(pid, "can_tuborg_1", "pant_bag", 2))
	assert_str(hud._prompt_for(bag, [], 2)).is_equal(tr("ui.hud.take_out") % can_name)


func test_aimed_slot_is_minus_one_when_not_aiming_at_anything() -> void:
	assert_int(player.aimed_slot()).is_equal(-1)
