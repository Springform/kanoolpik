extends GdUnitTestSuite
## Dropping an item puts it on the ground you are standing on.
##
## [b]Found by playing, not by a test.[/b] `Island` lifted items onto the
## terrain when it spawned them and the summon animator lifted them when they
## landed, but [method PickupItem._on_dropped] did not — so anything dropped
## with Q kept the flat `ground_y` the core stores and sank into whatever hill
## the player was standing on. Invisible, and with its collider under the
## ground, unpickable. It looked like the item had been deleted.
##
## It is not a multiplayer bug, though that is where it was noticed: the same
## thing happens alone. It only needed somebody to press Q on a slope.

const HILL_MARGIN := 0.5


func before_test() -> void:
	GameSession.start_level("island_01", 4242)


func after_test() -> void:
	GameSession.stop_level()


func test_a_dropped_item_rests_on_the_terrain_not_inside_it() -> void:
	var island: Island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	await get_tree().process_frame

	var spot := _a_hill(island)
	assert_float(spot.y).override_failure_message(
		"no hill found on island_01 — this test cannot tell the two behaviours apart"
	).is_greater(GameSession.ground_y() + HILL_MARGIN)

	var pid := GameSession.local_player_id()
	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	GameSession.submit(Commands.pick_up(pid, item_id))
	await get_tree().process_frame

	# The core is handed a FLAT position, exactly as Player._drop_one sends one.
	GameSession.submit(Commands.drop(pid, item_id, Vector3(spot.x, GameSession.ground_y(), spot.z)))
	await get_tree().process_frame

	var node: PickupItem = island.items_root.get_node("Item_" + item_id)
	assert_bool(node.visible).override_failure_message(
		"the dropped item is not shown at all").is_true()
	assert_float(node.global_position.y).override_failure_message(
		"dropped at y=%.2f but the ground there is y=%.2f — the item is inside the hill"
		% [node.global_position.y, spot.y]
	).is_equal_approx(spot.y + Island.ITEM_LIFT, 0.01)


func test_a_dropped_item_stays_where_it_was_dropped_horizontally() -> void:
	# The lift changes y and nothing else: an item must not slide somewhere
	# else on the way down.
	var island: Island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	await get_tree().process_frame

	var pid := GameSession.local_player_id()
	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	var where := Vector3(3.0, GameSession.ground_y(), -2.0)
	GameSession.submit(Commands.pick_up(pid, item_id))
	GameSession.submit(Commands.drop(pid, item_id, where))
	await get_tree().process_frame

	var node: PickupItem = island.items_root.get_node("Item_" + item_id)
	assert_float(node.global_position.x).is_equal_approx(where.x, 0.001)
	assert_float(node.global_position.z).is_equal_approx(where.z, 0.001)


## A point on the island where the terrain is clearly above the level's flat
## `ground_y`. Returns it with the real height in y, or ground_y if the island
## turns out to be a pancake — which the caller asserts against, because a flat
## island would make this whole suite pass for the wrong reason.
func _a_hill(island: Island) -> Vector3:
	var radius := GameSession.island_radius()
	var best := Vector3(0.0, GameSession.ground_y(), 0.0)
	for i in 64:
		var angle := TAU * float(i) / 64.0
		for step in [0.3, 0.5, 0.7]:
			var x: float = cos(angle) * radius * step
			var z: float = sin(angle) * radius * step
			var h := island.height_at(x, z)
			if h > best.y:
				best = Vector3(x, h, z)
	return best
