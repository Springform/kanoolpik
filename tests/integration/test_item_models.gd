extends GdUnitTestSuite
## WP-2.2 — models load, fit themselves, and never take the game down with them.

var island: Island


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)


func after_test() -> void:
	GameSession.stop_level()


func _item(id: String) -> PickupItem:
	return island.get_node("Items/Item_" + id)


# --- Falling back ------------------------------------------------------------------

## The first catalog item still drawn as a generated box, or "" when the model
## kit is complete. Found rather than hard-coded: the kit keeps filling up, and
## whichever item is "the one without a model" changes week to week.
func _id_without_a_model() -> String:
	for id in GameSession.catalog.item_ids():
		if GameSession.catalog.get_item(id).model.is_empty():
			return id
	return ""


func test_an_item_with_no_model_still_gets_a_visual() -> void:
	var id := _id_without_a_model()
	assert_str(id).override_failure_message(
		"every item has a model now — this test has nothing left to guard").is_not_empty()
	var without := _item(id)
	assert_object(without.visual).is_not_null()
	assert_int(without.visual.find_children("*", "MeshInstance3D", true, false).size()).is_greater(0)


func test_a_missing_file_falls_back_instead_of_crashing() -> void:
	var node := ItemVisual.build("res://assets/models/items/no_such_thing.glb",
		Vector3(0.3, 0.3, 0.3), Color.RED)
	assert_object(node).is_not_null()
	assert_bool(ItemVisual.has_model("res://assets/models/items/no_such_thing.glb")).is_false()
	node.free()


func test_a_path_that_is_not_a_model_falls_back() -> void:
	var node := ItemVisual.build("res://data/catalog/items.json", Vector3.ONE, Color.WHITE)
	assert_object(node).is_not_null()
	node.free()


func test_the_game_is_playable_with_no_models_at_all() -> void:
	# The normal state for a long while: a half-populated kit, or none.
	for id in GameSession.catalog.item_ids():
		assert_object(_item(id)).override_failure_message("'%s' did not spawn" % id).is_not_null()
	assert_int(island.get_node("Items").get_child_count()).is_equal(GameSession.catalog.item_count())


# --- Models that are there ------------------------------------------------------------

func test_the_supplied_firewood_model_actually_loads() -> void:
	var def := GameSession.catalog.get_item("firewood_1")
	assert_str(def.model).is_not_empty()
	assert_bool(ItemVisual.has_model(def.model)).override_failure_message(
		"'%s' did not load — check the .import file came across too" % def.model).is_true()


func test_one_model_serves_every_firewood_item() -> void:
	var paths := {}
	for id in GameSession.catalog.item_ids():
		var def := GameSession.catalog.get_item(id)
		if def.category == "firewood":
			paths[def.model] = true
	assert_int(paths.size()).override_failure_message(
		"five logs should share one file, not five").is_equal(1)


func test_a_model_is_fitted_to_the_item_size_budget() -> void:
	# Asset-library models arrive in arbitrary units; nothing should need measuring.
	var def := GameSession.catalog.get_item("firewood_1")
	var budget := ItemPalette.box_size(def)
	var node: Node3D = _item("firewood_1").visual
	var drawn := ItemVisual.combined_aabb(node).size * node.scale
	var longest := maxf(drawn.x, maxf(drawn.y, drawn.z))
	# The item asks for a nudge on top of the fit, so that is what it should get.
	var nudge := def.model_scale if def.model_scale > 0.0 else 1.0
	var allowed := maxf(budget.x, maxf(budget.y, budget.z)) * nudge
	assert_float(longest).override_failure_message(
		"the model is %.2f m across but its budget (with nudge) is %.2f m" % [longest, allowed]
	).is_equal_approx(allowed, 0.01)


func test_items_are_sized_in_metres_not_in_carry_slots() -> void:
	# ItemDef.size is how many hands an item takes up, a gameplay number. Deriving
	# metres from it made a paddle 34 cm long. Every category that has arrived
	# should have a real-world length.
	var missing: Array[String] = []
	for id in GameSession.catalog.item_ids():
		var def := GameSession.catalog.get_item(id)
		if not def.model.is_empty() and not ItemPalette.CATEGORY_LENGTHS.has(def.category):
			missing.append(def.category)
	assert_array(missing).override_failure_message(
		"modelled categories with no real-world length: %s" % [missing]).is_empty()


func test_a_paddle_is_paddle_sized() -> void:
	var node: Node3D = _item("paddle_1").visual
	var drawn := ItemVisual.visual_size(node, Vector3.ONE)
	var longest := maxf(drawn.x, maxf(drawn.y, drawn.z))
	assert_float(longest).override_failure_message(
		"a paddle you can hold in one hand is %.2f m long" % longest).is_greater(1.0)


func test_model_scale_nudges_the_fit_rather_than_replacing_it() -> void:
	# 1.5 must mean "half again as big as the automatic size" whatever units the
	# file arrived in — otherwise tuning by eye needs a ruler on the raw model.
	var path := GameSession.catalog.get_item("firewood_1").model
	var budget := Vector3(0.3, 0.3, 0.3)
	var plain := ItemVisual.build(path, budget, Color.WHITE)
	var nudged := ItemVisual.build(path, budget, Color.WHITE, 1.5)
	assert_float(nudged.scale.x).is_equal_approx(plain.scale.x * 1.5, 0.0001)
	plain.free()
	nudged.free()


func test_a_model_sits_on_the_ground_not_half_buried() -> void:
	var node: Node3D = _item("firewood_1").visual
	var bottom := (ItemVisual.combined_aabb(node).position.y * node.scale.y) + node.position.y
	assert_float(bottom).override_failure_message(
		"the model's lowest point is at y=%.3f relative to the item" % bottom).is_equal_approx(0.0, 0.01)


func test_collision_follows_what_is_actually_drawn() -> void:
	var item := _item("firewood_1")
	var shape: BoxShape3D = item.get_node("Collision").shape
	var drawn := ItemVisual.visual_size(item.visual, ItemPalette.box_size(item.def))
	assert_vector(shape.size).is_equal_approx(drawn, Vector3.ONE * 0.001)


func test_the_container_model_loads_and_the_slots_stay_aimable() -> void:
	var pit: ContainerNode = island.get_node("Containers/Container_fire_pit")
	assert_bool(ItemVisual.has_model(GameSession.catalog.get_container("fire_pit").scene)).is_true()
	assert_object(pit.visual).is_not_null()
	# The whole point of WP-1.3: every slot must still be its own aimable body.
	assert_int(pit.slot_count()).is_equal(GameSession.catalog.get_container("fire_pit").slot_count)
	for i in range(pit.slot_count()):
		assert_object(pit.slot_node(i)).is_not_null()
		assert_int(pit.slot_at(pit.slot_node(i))).is_equal(i)


func test_a_container_without_a_model_keeps_its_translucent_box() -> void:
	# Every container in the catalog has a model now, so this is built from a
	# definition rather than found on the island — the fallback still has to work
	# for the next container somebody adds.
	var def := ContainerDef.from_dict({"id": "no_model_yet", "accepts": ["trash"], "slot_count": 4})
	var node: ContainerNode = auto_free(load("res://src/game/containers/container_node.tscn").instantiate())
	node.setup(def)
	add_child(node)
	assert_object(node.visual).is_not_null()
	var meshes: Array[Node] = node.visual.find_children("*", "MeshInstance3D", true, false)
	assert_array(meshes).is_not_empty()
	var mesh: MeshInstance3D = meshes[0]
	var mat: StandardMaterial3D = mesh.material_override
	assert_int(mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)


func test_held_items_use_the_same_visual_as_the_world() -> void:
	var pid := GameSession.local_player_id()
	var held: HeldItems = auto_free(HeldItems.new())
	held.set_player(pid)
	add_child(held)
	GameSession.submit(Commands.pick_up(pid, "firewood_1"))
	var node: Node3D = held.get_node("Held_firewood_1")
	assert_int(node.find_children("*", "MeshInstance3D", true, false).size()).is_greater(0)


func test_tint_is_applied_only_when_asked_for() -> void:
	var def := ItemDef.from_dict({"id": "x", "category": "can", "tint": "#ff0000"})
	assert_object(def.tint_color(Color.WHITE)).is_equal(Color.RED)
	var plain := ItemDef.from_dict({"id": "y", "category": "can"})
	assert_object(plain.tint_color(Color.BLUE)).is_equal(Color.BLUE)
	var nonsense := ItemDef.from_dict({"id": "z", "category": "can", "tint": "not a colour"})
	assert_object(nonsense.tint_color(Color.BLUE)).is_equal(Color.BLUE)


func test_a_model_keeps_its_own_colours_unless_a_tint_is_asked_for() -> void:
	# Multiplying albedo over a textured model darkens it as much as it colours
	# it, so the category colour is for placeholders only.
	var modelled := ItemDef.from_dict({"id": "a", "category": "firewood", "model": "res://x.glb"})
	assert_object(ItemPalette.visual_color(modelled)).is_equal(Color.WHITE)
	var tinted := ItemDef.from_dict({"id": "b", "category": "firewood", "model": "res://x.glb", "tint": "#ff0000"})
	assert_object(ItemPalette.visual_color(tinted)).is_equal(Color.RED)
	var box := ItemDef.from_dict({"id": "c", "category": "firewood"})
	assert_object(ItemPalette.visual_color(box)).is_equal(ItemPalette.color_for("firewood"))


func test_every_item_has_its_own_collision_shape() -> void:
	# Regression: the shape was a .tscn sub-resource, which Godot shares between
	# every instance of the scene — so all 150 items collided as whatever size
	# the last one to spawn happened to be.
	var seen := {}
	for id in GameSession.catalog.item_ids():
		var shape: Shape3D = _item(id).get_node("Collision").shape
		assert_bool(seen.has(shape.get_instance_id())).override_failure_message(
			"'%s' shares its collision shape with another item" % id).is_false()
		seen[shape.get_instance_id()] = true


func test_a_model_and_a_box_get_different_collision_sizes() -> void:
	var with_model: BoxShape3D = _item("firewood_1").get_node("Collision").shape
	var without: BoxShape3D = _item(_id_without_a_model()).get_node("Collision").shape
	assert_vector(with_model.size).is_not_equal(without.size)
