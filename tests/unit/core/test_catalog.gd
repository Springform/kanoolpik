extends GdUnitTestSuite


func test_from_dicts_registers_items_and_containers() -> void:
	var cat := TestFixtures.catalog()
	assert_int(cat.item_count()).is_equal(9)
	assert_array(cat.container_ids()).contains_exactly(["cooler", "pant_bag", "tent_bag"])
	assert_object(cat.get_item("pole_2")).is_not_null()
	assert_int(cat.get_item("pole_2").sequence).is_equal(2)
	assert_object(cat.get_item("nope")).is_null()


func test_item_ids_are_sorted_for_determinism() -> void:
	var cat := TestFixtures.catalog()
	var ids := cat.item_ids()
	var sorted := ids.duplicate()
	sorted.sort()
	assert_array(ids).is_equal(sorted)


func test_series_members() -> void:
	var cat := TestFixtures.catalog()
	assert_int(cat.series_members("poles").size()).is_equal(3)
	assert_int(cat.series_members("brand_a").size()).is_equal(2)
	assert_array(cat.series_members("unknown")).is_empty()


func test_containers_accepting() -> void:
	var cat := TestFixtures.catalog()
	var accepting := cat.containers_accepting("pole")
	assert_int(accepting.size()).is_equal(1)
	assert_str(accepting[0].id).is_equal("tent_bag")
	assert_array(cat.containers_accepting("rocket")).is_empty()


func test_validate_passes_for_fixture() -> void:
	assert_array(TestFixtures.catalog().validate()).is_empty()


func test_validate_reports_orphan_category() -> void:
	var cat := Catalog.from_dicts(
		[{"id": "x", "category": "rocket"}],
		[{"id": "bag", "accepts": ["can"]}])
	var problems := cat.validate()
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("rocket")


func test_validate_reports_non_contiguous_sequence() -> void:
	var cat := Catalog.from_dicts([
		{"id": "p1", "category": "pole", "series": "poles", "sequence": 1},
		{"id": "p3", "category": "pole", "series": "poles", "sequence": 3},
	], [{"id": "bag", "accepts": ["pole"], "ordered": true}])
	var problems := cat.validate()
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).contains("contiguous")


func test_item_def_defaults_and_validity() -> void:
	var def := ItemDef.from_dict({"id": "thing", "category": "trash"})
	assert_str(def.name_key).is_equal("item.thing")
	assert_int(def.size).is_equal(1)
	assert_bool(def.is_valid()).is_true()
	assert_bool(def.is_ordered()).is_false()
	var bad := ItemDef.from_dict({"id": "seq_without_series", "category": "x", "sequence": 2})
	assert_bool(bad.is_valid()).is_false()


func test_item_def_round_trips_through_dict() -> void:
	var src := {"id": "a", "category": "c", "series": "s", "sequence": 2, "size": 3, "name_key": "k", "model": "res://m.tscn"}
	assert_dict(ItemDef.from_dict(src).to_dict()).is_equal(src)
