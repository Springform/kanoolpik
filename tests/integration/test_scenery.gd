extends GdUnitTestSuite
## WP-2.5 — scenery dresses the island without standing where the game happens.

var island: Island
var scenery: Scenery


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	scenery = island.get_node("Scenery")


func after_test() -> void:
	GameSession.stop_level()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- It exists -------------------------------------------------------------------

func test_the_island_is_dressed() -> void:
	assert_int(scenery.grass_count()).is_greater(1000)
	assert_int(scenery.tree_positions().size()).is_greater(10)
	assert_int(scenery.bush_positions().size()).is_greater(5)
	assert_int(scenery.reed_count()).is_greater(10)


func test_grass_is_one_draw_call_not_thousands_of_nodes() -> void:
	# 4000 grass nodes would cost more than the rest of the game put together.
	var grass: MultiMeshInstance3D = scenery.get_node("Grass")
	assert_object(grass.multimesh).is_not_null()
	assert_int(grass.get_child_count()).is_equal(0)


func test_scenery_is_deterministic_for_a_seed() -> void:
	var second: Island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(second)
	var other: Scenery = second.get_node("Scenery")
	assert_array(other.tree_positions()).is_equal(scenery.tree_positions())
	assert_int(other.grass_count()).is_equal(scenery.grass_count())


# --- It stays out of the way -------------------------------------------------------

func test_nothing_solid_stands_on_a_container() -> void:
	for cid in GameSession.catalog.container_ids():
		var at := GameSession.container_position(cid)
		var keep_out := GameSession.catalog.get_container(cid).footprint_radius() + Scenery.CLEARANCE_CONTAINER
		for kind in [scenery.tree_positions(), scenery.bush_positions()]:
			for position: Vector3 in kind:
				assert_float(_flat(position, at)).override_failure_message(
					"scenery at %s is %.2f m from container '%s', needs %.2f m" % [position, _flat(position, at), cid, keep_out]
				).is_greater_equal(keep_out)


func test_nothing_solid_stands_where_items_land() -> void:
	# A tree in a spawn zone eventually swallows a sock, and a sock you cannot
	# see is a run you cannot finish.
	for zone: Dictionary in GameSession.level["spawn_zones"]:
		var centre: Array = zone["center"]
		var at := Vector3(float(centre[0]), 0.0, float(centre[2]))
		var keep_out := float(zone["radius"]) + Scenery.CLEARANCE_ZONE
		for kind in [scenery.tree_positions(), scenery.bush_positions()]:
			for position: Vector3 in kind:
				assert_float(_flat(position, at)).override_failure_message(
					"scenery at %s sits inside spawn zone '%s'" % [position, zone["id"]]
				).is_greater_equal(keep_out)


func test_no_item_is_hidden_inside_scenery() -> void:
	for item_id in GameSession.catalog.item_ids():
		var at: Vector3 = GameSession.state.location(item_id)["position"]
		for position: Vector3 in scenery.tree_positions():
			assert_float(_flat(position, at)).override_failure_message(
				"'%s' spawned inside a tree" % item_id).is_greater(1.0)


func test_nothing_stands_on_a_player_spawn() -> void:
	for spawn: Array in GameSession.level["player_spawns"]:
		var at := Vector3(float(spawn[0]), 0.0, float(spawn[2]))
		for position: Vector3 in scenery.tree_positions():
			assert_float(_flat(position, at)).is_greater_equal(Scenery.CLEARANCE_SPAWN)


func test_scenery_sits_on_the_ground_and_on_land() -> void:
	for position: Vector3 in scenery.tree_positions() + scenery.bush_positions():
		assert_bool(island.is_on_land(position.x, position.z)).override_failure_message(
			"scenery at %s is in the water" % position).is_true()
		assert_float(position.y).is_equal_approx(island.height_at(position.x, position.z), 0.05)


func test_trees_block_the_player_but_leaves_do_not() -> void:
	var trees: Node3D = scenery.get_node("Trees")
	assert_int(trees.get_child_count()).is_greater(0)
	var tree: StaticBody3D = trees.get_child(0)
	assert_int(tree.find_children("*", "CollisionShape3D", true, false).size()).override_failure_message(
		"a tree you can walk through is worse than no tree").is_equal(1)
	var bushes: Node3D = scenery.get_node("Bushes")
	assert_int((bushes.get_child(0) as Node3D).find_children("*", "CollisionShape3D", true, false).size()
		).override_failure_message("bushes must not be obstacles").is_equal(0)


func test_the_clearance_rule_is_honest_about_grass() -> void:
	# Grass is ankle-high and may grow among the litter; solid things may not.
	assert_bool(Scenery.GRASS_CLEARANCE_CONTAINER < Scenery.CLEARANCE_CONTAINER).is_true()
	var at := GameSession.container_position("pant_bag")
	assert_bool(scenery.is_clear(at.x, at.z, false)).is_false()


func test_grass_borrows_the_ground_normal_so_it_is_not_a_field_of_black_spikes() -> void:
	# Vertical blades shaded by their own face normals came out near-black under
	# GL Compatibility. Pointing every normal up makes grass catch the same light
	# as the terrain. Only visible on screen, so pin it here.
	var grass: MultiMeshInstance3D = scenery.get_node("Grass")
	var arrays := grass.multimesh.mesh.surface_get_arrays(0)
	# Godot compresses mesh normals, so they come back as (0, 1, -0.000015)
	# rather than exactly UP — compare by direction, not by equality.
	for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
		assert_float(normal.dot(Vector3.UP)).override_failure_message(
			"a grass normal points %s, not up" % normal).is_greater(0.999)
