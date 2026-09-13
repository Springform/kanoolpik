extends GdUnitTestSuite
## Guards the real content files in data/. Any agent adding items, containers or
## levels gets immediate feedback here instead of at runtime.

const ITEMS := "res://data/catalog/items.json"
const CONTAINERS := "res://data/catalog/containers.json"
const LEVEL := "res://data/levels/island_01.json"


func test_catalog_loads_and_validates() -> void:
	var cat := Catalog.load_from_files(ITEMS, CONTAINERS)
	assert_int(cat.item_count()).is_greater(0)
	assert_int(cat.container_ids().size()).is_greater(0)
	assert_array(cat.validate()).is_empty()


func test_level_references_every_container_position() -> void:
	var cat := Catalog.load_from_files(ITEMS, CONTAINERS)
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEVEL))
	var positions: Dictionary = level["container_positions"]
	for cid in cat.container_ids():
		assert_bool(positions.has(cid)).override_failure_message("level has no position for container '%s'" % cid).is_true()
	for cid in positions.keys():
		assert_object(cat.get_container(cid)).override_failure_message("level positions unknown container '%s'" % cid).is_not_null()


func test_level_zones_cover_every_category() -> void:
	var cat := Catalog.load_from_files(ITEMS, CONTAINERS)
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEVEL))
	var zones: Array = level["spawn_zones"]
	assert_int(zones.size()).is_greater(0)
	assert_int(level["player_spawns"].size()).is_greater_equal(6)
	var state := MessGenerator.generate(int(level["seed_default"]), cat, zones, float(level["ground_y"]))
	assert_int(state.items_of_kind(WorldState.Kind.GROUND).size()).is_equal(cat.item_count())


func test_real_level_is_solvable_with_enough_slots() -> void:
	# Every container must have room for all items whose ONLY home it is.
	var cat := Catalog.load_from_files(ITEMS, CONTAINERS)
	var demand := {}
	for id in cat.item_ids():
		var homes := cat.containers_accepting(cat.get_item(id).category)
		if homes.size() == 1:
			demand[homes[0].id] = int(demand.get(homes[0].id, 0)) + 1
	for cid in demand.keys():
		var c := cat.get_container(cid)
		assert_int(c.slot_count).override_failure_message("container '%s' has %d slots but %d items need it" % [cid, c.slot_count, demand[cid]]).is_greater_equal(demand[cid])


func test_i18n_has_a_key_for_every_item_and_container() -> void:
	var cat := Catalog.load_from_files(ITEMS, CONTAINERS)
	var csv := FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	assert_object(csv).is_not_null()
	var keys := {}
	var header := csv.get_csv_line()
	assert_str(header[0]).is_equal("keys")
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() > 0 and not row[0].is_empty():
			keys[row[0]] = true
	for id in cat.item_ids():
		var k: String = cat.get_item(id).name_key
		assert_bool(keys.has(k)).override_failure_message("missing i18n key '%s'" % k).is_true()
	for cid in cat.container_ids():
		var k: String = cat.get_container(cid).name_key
		assert_bool(keys.has(k)).override_failure_message("missing i18n key '%s'" % k).is_true()


func test_a_container_is_only_packed_when_everything_that_belongs_is_there() -> void:
	# Regression against the real catalog: dropping the tent canvas into the tent
	# bag as the first item used to announce the bag as packed.
	var cat := Catalog.load_from_files(ITEMS, CONTAINERS)
	var state := WorldState.new()
	for id in cat.item_ids():
		state.set_on_ground(id, Vector3.ZERO)

	state.set_placed("tent_canvas", "tent_bag", 11)
	assert_bool(PlacementRules.is_container_complete(cat, state, "tent_bag")).override_failure_message(
		"the canvas alone must not pack the tent bag").is_false()
	for i in range(1, 5):
		state.set_placed("tent_pole_%d" % i, "tent_bag", i - 1)
	assert_bool(PlacementRules.is_container_complete(cat, state, "tent_bag")).is_false()
	for i in range(1, 7):
		state.set_placed("tent_peg_%d" % i, "tent_bag", 3 + i)
	assert_bool(PlacementRules.is_container_complete(cat, state, "tent_bag")).is_true()


func test_no_lone_item_in_the_real_catalog_can_pack_a_container() -> void:
	# The canvas was not the only one: the schnapps bottle and the napkins have
	# no series either. Nothing may complete a container by itself.
	#
	# A category can now be accepted by more than one container (the two
	# canoes both take "paddle" and "life_vest" — the series is what tells
	# them apart), so [PlacementRules.required_items] alone no longer decides
	# whether a lone item is "enough": an item can still need its series
	# siblings even when its category is not exclusively this container's.
	var cat := Catalog.load_from_files(ITEMS, CONTAINERS)
	for item_id in cat.item_ids():
		var item := cat.get_item(item_id)
		for container in cat.containers_accepting(item.category):
			var state := WorldState.new()
			for id in cat.item_ids():
				state.set_on_ground(id, Vector3.ZERO)
			state.set_placed(item_id, container.id, 0)
			var required := PlacementRules.required_items(cat, container.id)
			required.erase(item_id)
			var other_series_members := 0
			if not item.series.is_empty():
				for member in cat.series_members(item.series):
					if member.id != item_id:
						other_series_members += 1
			var alone_is_enough := required.is_empty() and other_series_members == 0
			assert_bool(PlacementRules.is_container_complete(cat, state, container.id)).override_failure_message(
				"'%s' alone packs '%s'" % [item_id, container.id]).is_equal(alone_is_enough)


func test_every_container_has_room_for_everything_that_belongs_in_it() -> void:
	var cat := Catalog.load_from_files(ITEMS, CONTAINERS)
	for cid in cat.container_ids():
		var required := PlacementRules.required_items(cat, cid).size()
		assert_int(cat.get_container(cid).slot_count).override_failure_message(
			"'%s' has %d slots but %d items must fit" % [cid, cat.get_container(cid).slot_count, required]
		).is_greater_equal(required)
