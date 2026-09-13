extends GdUnitTestSuite
## WP-2.3 — container models, and the slots that have to survive them.
##
## The model is the easy half (it goes through [ItemVisual], same as items).
## The half worth testing is that a real shape does not make a slot unreachable
## or unaimable — those failures look fine in a screenshot and only show up
## when you stand in front of the thing and cannot put a bottle down.

var island: Island


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)


func after_test() -> void:
	GameSession.stop_level()


func _container(id: String) -> ContainerNode:
	return island.get_node("Containers/Container_" + id)


func _body_box(c: ContainerNode) -> AABB:
	var shape: BoxShape3D = c.get_node("Collision").shape
	var centre: Vector3 = c.get_node("Collision").position
	return AABB(centre - shape.size * 0.5, shape.size)


# --- The model itself ---------------------------------------------------------------

func test_a_container_with_a_model_draws_it() -> void:
	var pit := _container("fire_pit")
	assert_bool(ItemVisual.has_model(GameSession.catalog.get_container("fire_pit").scene)).is_true()
	assert_int(pit.visual.find_children("*", "MeshInstance3D", true, false).size()).is_greater(0)


func test_every_container_in_the_catalog_has_a_model_that_loads() -> void:
	# The kit is complete as of WP-2.3's second pass. If a container loses its
	# model this fails here rather than showing up as a grey box in a playtest.
	for cid in GameSession.catalog.container_ids():
		var scene := GameSession.catalog.get_container(cid).scene
		assert_str(scene).override_failure_message("'%s' has no model" % cid).is_not_empty()
		assert_bool(ItemVisual.has_model(scene)).override_failure_message(
			"'%s' names '%s', which does not load — is the .import file there?" % [cid, scene]).is_true()


func test_collision_follows_the_model_not_the_placeholder() -> void:
	var pit := _container("fire_pit")
	var drawn := ItemVisual.visual_size(pit.visual, Vector3.ONE)
	var shape: BoxShape3D = pit.get_node("Collision").shape
	assert_vector(shape.size).is_equal_approx(drawn, Vector3.ONE * 0.001)


# --- Slots survive the model ---------------------------------------------------------

func test_every_slot_sits_outside_the_body_collider() -> void:
	# A slot inside the body box can never be hit: the ray meets the box first.
	# This is the failure WP-1.3 shipped once already.
	for cid in GameSession.catalog.container_ids():
		var c := _container(cid)
		var body := _body_box(c)
		for i in range(c.slot_count()):
			var p := c.slot_node(i).position
			assert_bool(body.has_point(p)).override_failure_message(
				"'%s' slot %d at %v is inside its own body box %s" % [cid, i, p, body]).is_false()


func test_no_two_slots_crowd_closer_than_you_can_aim() -> void:
	for cid in GameSession.catalog.container_ids():
		var c := _container(cid)
		for i in range(c.slot_count()):
			for j in range(i + 1, c.slot_count()):
				var gap := c.slot_node(i).position.distance_to(c.slot_node(j).position)
				assert_float(gap).override_failure_message(
					"'%s' slots %d and %d are %.3f m apart" % [cid, i, j, gap]
				).is_greater_equal(SlotLayout.MIN_SPACING - 0.001)


func test_the_fire_pit_lays_its_slots_in_a_ring() -> void:
	var pit := _container("fire_pit")
	assert_str(GameSession.catalog.get_container("fire_pit").slot_layout).is_equal("ring")
	var radii: Array[float] = []
	for i in range(pit.slot_count()):
		var p := pit.slot_node(i).position
		radii.append(Vector2(p.x, p.z).length())
	for r in radii:
		assert_float(r).is_equal_approx(radii[0], 0.001) # all the same distance out
	# ...and actually spread around, not stacked on one spot.
	assert_float(pit.slot_node(0).position.distance_to(pit.slot_node(3).position)
		).is_greater(radii[0])


func test_no_slot_sits_outside_the_space_the_container_reserves() -> void:
	# footprint_radius() is what keeps items from spawning on the container. A
	# slot outside that circle can get an item dropped on top of it.
	for cid in GameSession.catalog.container_ids():
		var c := _container(cid)
		var allowed := GameSession.catalog.get_container(cid).footprint_radius()
		for i in range(c.slot_count()):
			var p := c.slot_node(i).position
			assert_float(Vector2(p.x, p.z).length()).override_failure_message(
				"'%s' slot %d reaches outside its reserved footprint" % [cid, i]
			).is_less_equal(allowed)


func test_the_slot_tray_stays_a_hands_reach_across() -> void:
	# 34 slots in a row would be 8.8 m of shelf; in one column they would be a
	# tower. Roughly square keeps every slot reachable from where you stand.
	var def := ContainerDef.from_dict({"id": "x", "accepts": ["can"], "slot_count": 34})
	var places := SlotLayout.positions(def, AABB(Vector3(-0.5, 0, -0.3), Vector3(1.0, 0.5, 0.6)))
	assert_int(places.size()).is_equal(34)
	var heights := {}
	var span := 0.0
	for p in places:
		heights[snappedf(p.y, 0.001)] = true
		span = maxf(span, maxf(absf(p.x), absf(p.z)) * 2.0)
	assert_int(heights.size()).override_failure_message("the tray should be flat").is_equal(1)
	assert_float(span).override_failure_message(
		"34 slots span %.2f m" % span).is_less(2.0)


func test_slots_always_sit_above_the_model() -> void:
	var bounds := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.4, 1.0))
	for layout in ["grid", "ring"]:
		var def := ContainerDef.from_dict({"id": "x", "accepts": ["can"], "slot_count": 6, "slot_layout": layout})
		for p in SlotLayout.positions(def, bounds):
			assert_float(p.y).is_equal_approx(bounds.size.y + SlotLayout.LIFT, 0.001)


func test_an_unknown_layout_name_falls_back_rather_than_breaking() -> void:
	# A typo in content data should not take a container out of the game.
	assert_int(SlotLayout.kind_from("sfæriskt")).is_equal(SlotLayout.Kind.GRID)
	assert_int(SlotLayout.kind_from("")).is_equal(SlotLayout.Kind.GRID)
	assert_int(SlotLayout.kind_from("ring")).is_equal(SlotLayout.Kind.RING)


# --- Feedback still reads --------------------------------------------------------

func test_placement_feedback_still_works_on_a_model() -> void:
	var pit := _container("fire_pit")
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "firewood_1"))
	GameSession.submit(Commands.place(pid, "firewood_1", "fire_pit", 0))
	assert_str(pit.resting_material_kind(0)).is_not_equal("empty")
	assert_object(pit.slot_mesh(0).material_override).is_not_null()


func test_the_label_clears_a_tall_model() -> void:
	for cid in GameSession.catalog.container_ids():
		var c := _container(cid)
		var top: float = _body_box(c).position.y + _body_box(c).size.y
		assert_float(c.label.position.y).override_failure_message(
			"'%s' label is inside its own model" % cid).is_greater(top)
