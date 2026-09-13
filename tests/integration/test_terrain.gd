extends GdUnitTestSuite
## Tests for the procedurally generated island terrain (WP-2.1): determinism,
## collision agreement, slope limits, and the mesh's vertex budget.

var island: Island


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)


func after_test() -> void:
	GameSession.stop_level()


func _radius() -> float:
	return GameSession.island_radius()


# --- Determinism -------------------------------------------------------------------

func test_same_seed_gives_the_same_heights() -> void:
	var other: Island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	other.terrain_seed = island.terrain_seed
	add_child(other)
	var points := [Vector2(0, 0), Vector2(5.5, -3.2), Vector2(-9.0, 4.0), Vector2(15.9, 0.1)]
	for p in points:
		assert_float(other.height_at(p.x, p.y)).is_equal_approx(island.height_at(p.x, p.y), 0.0001)


func test_different_seeds_change_the_shape() -> void:
	var other: Island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	other.terrain_seed = island.terrain_seed + 1
	add_child(other)
	var differs := false
	for i in range(20):
		var x := -14.0 + i * 1.3
		var z := 6.0
		if not is_equal_approx(other.height_at(x, z), island.height_at(x, z)):
			differs = true
			break
	assert_bool(differs).override_failure_message(
		"expected a different terrain_seed to change at least one sampled height").is_true()


func test_rebuilding_the_scene_reproduces_the_same_mesh() -> void:
	var rebuilt: Island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(rebuilt)
	assert_int(rebuilt.terrain_vertex_count()).is_equal(island.terrain_vertex_count())
	for i in range(10):
		var x := -10.0 + i * 2.0
		var z := 3.0
		assert_float(rebuilt.height_at(x, z)).is_equal_approx(island.height_at(x, z), 0.0001)


# --- height_at() agrees with the collision surface --------------------------------

## Every collider on the island that is not the ground: containers, their slots
## and loose items. The ray has to ignore them, or this test measures whatever
## furniture happens to stand on the sample point (which is how it first failed,
## after WP-2.4 moved the cooler onto one of the sampled spots).
func _furniture_rids() -> Array[RID]:
	var out: Array[RID] = []
	for root_name in ["Containers", "Items"]:
		for node in island.get_node(root_name).find_children("*", "CollisionObject3D", true, false):
			out.append((node as CollisionObject3D).get_rid())
	return out


func test_height_at_agrees_with_the_collision_surface() -> void:
	var space := get_tree().root.get_world_3d().direct_space_state
	var furniture := _furniture_rids()
	assert_array(furniture).override_failure_message("expected containers and items to have colliders").is_not_empty()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var radius := _radius()
	var sampled := 0
	for i in range(20):
		var x := rng.randf_range(-radius * 0.9, radius * 0.9)
		var z := rng.randf_range(-radius * 0.9, radius * 0.9)
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 50.0, z), Vector3(x, -50.0, z))
		query.exclude = furniture
		var hit := space.intersect_ray(query)
		assert_dict(hit).override_failure_message(
			"no collision under (%.2f, %.2f) even though it's inside the island" % [x, z]).is_not_empty()
		if hit.is_empty():
			continue
		assert_str(String(hit["collider"].name)).override_failure_message(
			"ray at (%.2f,%.2f) hit '%s', not the ground" % [x, z, hit["collider"].name]).is_equal("Ground")
		var hit_y: float = hit["position"].y
		var expected: float = island.height_at(x, z)
		assert_float(hit_y).override_failure_message(
			"collision at (%.2f,%.2f) is y=%.3f but height_at() says %.3f" % [x, z, hit_y, expected]
		).is_equal_approx(expected, 0.15)
		sampled += 1
	assert_int(sampled).is_equal(20)


# --- Slopes stay walkable ------------------------------------------------------------

func test_no_face_is_steeper_than_the_walkable_limit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var radius := _radius()
	for i in range(400):
		var r := rng.randf_range(0.0, radius + island.beach_width)
		var a := rng.randf_range(0.0, TAU)
		var x := cos(a) * r
		var z := sin(a) * r
		var slope := island.slope_degrees_at(x, z)
		assert_float(slope).override_failure_message(
			"slope at (%.2f, %.2f) is %.1f°, over the %.0f° walkable limit" % [x, z, slope, Island.MAX_WALKABLE_SLOPE_DEG]
		).is_less_equal(Island.MAX_WALKABLE_SLOPE_DEG)


# --- Vertex budget --------------------------------------------------------------------

func test_terrain_mesh_stays_within_the_vertex_budget() -> void:
	assert_int(island.terrain_vertex_count()).is_greater(0)
	assert_int(island.terrain_vertex_count()).is_less(Island.MAX_TERRAIN_VERTICES)
	var mesh: ArrayMesh = island.get_node("Ground/Mesh").mesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_equal(island.terrain_vertex_count())


# --- Shape sanity ------------------------------------------------------------------

func test_every_point_within_island_radius_is_on_land() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var radius := _radius()
	for i in range(200):
		var r := rng.randf_range(0.0, radius)
		var a := rng.randf_range(0.0, TAU)
		var x := cos(a) * r
		var z := sin(a) * r
		assert_bool(island.is_on_land(x, z)).override_failure_message(
			"(%.2f, %.2f) at r=%.2f <= island_radius=%.2f should be land" % [x, z, r, radius]).is_true()


func test_far_beyond_the_beach_is_not_on_land() -> void:
	var radius := _radius()
	assert_bool(island.is_on_land(radius + island.beach_width + 20.0, 0.0)).is_false()


func test_land_never_dips_below_the_players_water_threshold() -> void:
	# Player.gd respawns anyone who falls more than `water_depth` (2m) below
	# GameSession.ground_y(); land inside island_radius must stay well clear of
	# that so nobody standing on a low point gets treated as swimming.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var radius := _radius()
	var ground_y := GameSession.ground_y()
	for i in range(200):
		var r := rng.randf_range(0.0, radius)
		var a := rng.randf_range(0.0, TAU)
		var x := cos(a) * r
		var z := sin(a) * r
		assert_float(island.height_at(x, z)).is_greater(ground_y - 1.5)


# --- Items and containers are lifted onto the terrain --------------------------------

func test_containers_are_lifted_to_the_terrain_height() -> void:
	for cid in GameSession.catalog.container_ids():
		var node: ContainerNode = island.get_node("Containers/Container_" + cid)
		var xz := GameSession.container_position(cid)
		var expected := island.height_at(xz.x, xz.z)
		assert_float(node.position.y).is_equal_approx(expected, 0.0001)


func test_loose_items_are_lifted_to_the_terrain_height() -> void:
	for id in GameSession.catalog.item_ids():
		var loc: Dictionary = GameSession.state.location(id)
		if loc["kind"] != WorldState.Kind.GROUND:
			continue
		var node: PickupItem = island.get_node("Items/Item_" + id)
		var pos: Vector3 = loc["position"]
		var expected := island.height_at(pos.x, pos.z) + 0.15
		assert_float(node.position.y).is_equal_approx(expected, 0.0001)
