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
