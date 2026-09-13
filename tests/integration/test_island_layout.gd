extends GdUnitTestSuite
## Regression tests for three bugs that made parts of the level unplayable:
##   1. items spawning inside a container, where they cannot be picked up
##   2. container footprints overlapping each other
##   3. the player falling into the lake with no way back

var island: Island
var player: Player
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	pid = GameSession.local_player_id()
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = false
	player.player_id = pid
	player.spawn_position = GameSession.player_spawn(0)
	add_child(player)


func after_test() -> void:
	GameSession.stop_level()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- 1. Nothing spawns inside a container --------------------------------------------

func test_no_item_spawns_inside_a_container_footprint() -> void:
	for seed in [0, 1, 4242, 99999]:
		var state := MessGenerator.generate(
			seed, GameSession.catalog, GameSession.level["spawn_zones"], GameSession.ground_y(),
			MessGenerator.container_exclusions(GameSession.catalog, GameSession.level["container_positions"]))
		for item_id in GameSession.catalog.item_ids():
			var pos: Vector3 = state.location(item_id)["position"]
			for cid in GameSession.catalog.container_ids():
				var c := GameSession.catalog.get_container(cid)
				var d := _flat_distance(pos, GameSession.container_position(cid))
				assert_float(d).override_failure_message(
					"seed %d: '%s' spawned %.2f m from '%s' (footprint %.2f m)" % [seed, item_id, d, cid, c.footprint_radius()]
				).is_greater(c.footprint_radius())


func test_the_running_level_has_every_item_reachable() -> void:
	for item_id in GameSession.catalog.item_ids():
		var pos: Vector3 = GameSession.state.location(item_id)["position"]
		assert_float(Vector2(pos.x, pos.z).length()).override_failure_message(
			"'%s' spawned off the island at %s" % [item_id, pos]).is_less(GameSession.island_radius())


func test_exclusions_are_derived_from_the_real_footprints() -> void:
	var exclusions := MessGenerator.container_exclusions(
		GameSession.catalog, GameSession.level["container_positions"], 0.4)
	assert_int(exclusions.size()).is_equal(GameSession.catalog.container_ids().size())
	for e in exclusions:
		var c := GameSession.catalog.get_container(e["id"])
		assert_float(e["radius"]).is_equal_approx(c.footprint_radius() + 0.4, 0.001)


func test_blocked_points_are_pushed_out_rather_than_dropped() -> void:
	# A zone sitting exactly on top of an exclusion: every roll is blocked, so the
	# fallback must still place every item, outside the circle.
	var cat := TestFixtures.catalog()
	var zones := [{"id": "z", "center": [0, 0, 0], "radius": 1.0, "weight": 1.0}]
	var exclusions := [{"id": "x", "center": [0, 0, 0], "radius": 2.0}]
	var state := MessGenerator.generate(7, cat, zones, 0.0, exclusions)
	assert_int(state.items_of_kind(WorldState.Kind.GROUND).size()).is_equal(cat.item_count())
	for id in cat.item_ids():
		var pos: Vector3 = state.location(id)["position"]
		assert_float(Vector2(pos.x, pos.z).length()).is_greater(2.0)


func test_generation_with_exclusions_is_still_deterministic() -> void:
	var cat := TestFixtures.catalog()
	var exclusions := [{"id": "x", "center": [0, 0, 0], "radius": 1.5}]
	var a := MessGenerator.generate(123, cat, TestFixtures.zones(), 0.0, exclusions)
	var b := MessGenerator.generate(123, cat, TestFixtures.zones(), 0.0, exclusions)
	assert_dict(a.to_dict()).is_equal(b.to_dict())


# --- 2. Containers do not overlap -----------------------------------------------------

func test_container_footprints_do_not_overlap() -> void:
	var ids := GameSession.catalog.container_ids()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a := GameSession.catalog.get_container(ids[i])
			var b := GameSession.catalog.get_container(ids[j])
			var d := _flat_distance(GameSession.container_position(ids[i]), GameSession.container_position(ids[j]))
			assert_float(d).override_failure_message(
				"'%s' and '%s' are %.2f m apart but need %.2f m" % [ids[i], ids[j], d, a.footprint_radius() + b.footprint_radius()]
			).is_greater(a.footprint_radius() + b.footprint_radius())


func test_every_container_sits_on_the_island() -> void:
	for cid in GameSession.catalog.container_ids():
		var c := GameSession.catalog.get_container(cid)
		var reach := Vector2(GameSession.container_position(cid).x, GameSession.container_position(cid).z).length() + c.footprint_radius()
		assert_float(reach).override_failure_message(
			"'%s' reaches %.2f m from the centre, island is %.2f m" % [cid, reach, GameSession.island_radius()]
		).is_less(GameSession.island_radius())


func test_drawn_box_matches_the_footprint_used_for_layout() -> void:
	for cid in GameSession.catalog.container_ids():
		var node: ContainerNode = island.get_node("Containers/Container_" + cid)
		if ItemVisual.has_model(GameSession.catalog.get_container(cid).scene):
			continue # a model is fitted to the footprint, not equal to the box
		var drawn := ItemVisual.visual_size(node.visual, Vector3.ONE)
		var cdef := GameSession.catalog.get_container(cid)
		assert_float(drawn.x).is_equal_approx(cdef.width(), 0.001)
		assert_float(drawn.z).is_equal_approx(cdef.depth(), 0.001)


# --- 3. Falling in the lake ------------------------------------------------------------

func test_player_below_the_waterline_is_put_back_on_the_island() -> void:
	var respawned: Array[int] = []
	GameEvents.player_respawned.connect(func(id: int) -> void: respawned.append(id))
	player.global_position = Vector3(30, GameSession.ground_y() - 5.0, 30)
	player.velocity = Vector3(0, -12, 0)
	player._physics_process(1.0 / 60.0)
	assert_vector(player.global_position).is_equal(player.spawn_position)
	assert_vector(player.velocity).is_equal(Vector3.ZERO)
	assert_array(respawned).contains_exactly([pid])


func test_standing_on_the_island_does_not_respawn() -> void:
	var respawned: Array[int] = []
	GameEvents.player_respawned.connect(func(id: int) -> void: respawned.append(id))
	player.global_position = Vector3(2, GameSession.ground_y() + 1.0, 2)
	player._physics_process(1.0 / 60.0)
	assert_array(respawned).is_empty()


func test_respawn_keeps_what_the_player_carries() -> void:
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	player.global_position = Vector3(0, GameSession.ground_y() - 10.0, 0)
	player.respawn()
	assert_array(GameSession.state.carried_by(pid)).contains_exactly(["can_tuborg_1"])


func test_dropped_items_are_clamped_to_the_island() -> void:
	var far := Vector3(200, 0, -200)
	var clamped := Player.clamp_to_island(far)
	assert_float(Vector2(clamped.x, clamped.z).length()).is_less(GameSession.island_radius())
	var near := Vector3(1, 0, 2)
	assert_vector(Player.clamp_to_island(near)).is_equal(near)


func test_player_spawns_standing_on_the_terrain_not_inside_it() -> void:
	# Regression from merging WP-2.1 (terrain) with flat spawn points in the
	# level data: the player started below the hill and fell through into the lake.
	var main: Main = auto_free(load("res://src/game/main/main.tscn").instantiate())
	main.skip_title = true
	add_child(main)
	for i in range(GameSession.level["player_spawns"].size()):
		var spawn := main.spawn_point(i)
		var ground := main.island.height_at(spawn.x, spawn.z)
		assert_float(spawn.y).override_failure_message(
			"spawn %d is at y=%.2f but the ground there is y=%.2f" % [i, spawn.y, ground]).is_greater(ground)
		assert_bool(main.island.is_on_land(spawn.x, spawn.z)).override_failure_message(
			"spawn %d is in the water" % i).is_true()
	assert_float(main.player.global_position.y).is_greater(
		main.island.height_at(main.player.global_position.x, main.player.global_position.z))
	GameSession.stop_level()


func test_item_labels_only_show_close_to_the_camera() -> void:
	# 150 items with always-on names turned the island into a wall of text.
	var node: PickupItem = island.get_node("Items/Item_can_tuborg_1")
	assert_bool(node.label.visible).override_failure_message(
		"labels must start hidden until the camera is judged").is_false()
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	camera.current = true
	camera.global_position = node.global_position + Vector3(0, 0, PickupItem.LABEL_VISIBLE_METRES * 2.0)
	node.refresh_label()
	assert_bool(node.label.visible).override_failure_message("a far-off name is still drawn").is_false()
	camera.global_position = node.global_position + Vector3(0, 0, 1.5)
	node.refresh_label()
	assert_bool(node.label.visible).override_failure_message("a nearby name is not drawn").is_true()
