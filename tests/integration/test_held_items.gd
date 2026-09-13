extends GdUnitTestSuite
## WP-1.1 — the in-hand stack mirrors state.carried_by() in pick-up order.

var held: HeldItems
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	pid = GameSession.local_player_id()
	held = auto_free(HeldItems.new())
	held.set_player(pid)
	add_child(held)


func after_test() -> void:
	GameSession.stop_level()


func test_starts_empty() -> void:
	assert_int(held.item_count()).is_equal(0)
	assert_str(held.top_item_id()).is_equal("")


func test_pick_up_adds_nodes_in_pick_up_order_with_top_active() -> void:
	GameSession.submit(Commands.pick_up(pid, "sock_right"))
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	assert_int(held.item_count()).is_equal(2)
	assert_array(held.held_ids()).is_equal(["sock_right", "can_tuborg_1"])
	assert_str(held.top_item_id()).is_equal("can_tuborg_1")
	assert_object(held.get_node("Held_sock_right")).is_not_null()
	assert_object(held.get_node("Held_can_tuborg_1")).is_not_null()


func test_place_removes_the_placed_item_only() -> void:
	GameSession.submit(Commands.pick_up(pid, "sock_right"))
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	GameSession.submit(Commands.place(pid, "can_tuborg_1", "pant_bag", 0))
	assert_int(held.item_count()).is_equal(1)
	assert_str(held.top_item_id()).is_equal("sock_right")
	await await_millis(int(HeldItems.ANIM_SECONDS * 1000) + 100)
	assert_bool(held.has_node("Held_can_tuborg_1")).is_false()


func test_drop_removes_and_pick_up_again_reappears() -> void:
	GameSession.submit(Commands.pick_up(pid, "food_bread"))
	GameSession.submit(Commands.drop(pid, "food_bread", Vector3(1, 0, 1)))
	assert_int(held.item_count()).is_equal(0)
	GameSession.submit(Commands.pick_up(pid, "food_bread"))
	assert_int(held.item_count()).is_equal(1)


func test_take_out_adds_to_hand() -> void:
	GameSession.submit(Commands.pick_up(pid, "food_bread"))
	GameSession.submit(Commands.place(pid, "food_bread", "canoe", 0)) # wrong on purpose
	assert_int(held.item_count()).is_equal(0)
	GameSession.submit(Commands.take_out(pid, "food_bread"))
	assert_int(held.item_count()).is_equal(1)


func test_ignores_other_players() -> void:
	GameSession.state.add_player(7, 3)
	GameSession.submit(Commands.pick_up(7, "food_bread"))
	assert_int(held.item_count()).is_equal(0)


func test_first_person_meshes_draw_on_top_and_cast_no_shadow() -> void:
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	var m: MeshInstance3D = held.get_node("Held_can_tuborg_1")
	var mat: StandardMaterial3D = m.material_override
	assert_bool(mat.no_depth_test).is_true()
	assert_int(m.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_object(mat.albedo_color).is_equal(ItemPalette.color_for("can"))


func test_player_scene_carries_a_held_items_node_for_its_player_id() -> void:
	var player: Player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = false # no mouse capture / input in tests
	player.player_id = pid
	add_child(player)
	assert_int(player.held_items.player_id).is_equal(pid)
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	assert_int(player.held_items.item_count()).is_equal(1)
