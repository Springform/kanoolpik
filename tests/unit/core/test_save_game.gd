extends GdUnitTestSuite
## WP-1.8 — packing a run into JSON and getting the identical run back.
## This is the same snapshot multiplayer will hand a late joiner, so the
## round-trip equality here is load-bearing beyond save files.

const SLOT := "unit_test"

var cat: Catalog


func before_test() -> void:
	cat = TestFixtures.catalog()


func after_test() -> void:
	SaveGame.erase(SLOT)


func _a_run() -> Dictionary:
	var state := TestFixtures.ground_state(cat, 4)
	state.rng_seed = 987
	state.elapsed_ticks = 4321
	state.set_carried("can_a1", 1)
	state.set_placed("pole_1", "tent_bag", 0)
	state.bump_stat("placements", 7)
	state.bump_stat("wrong_placements", 2)
	# Since ADR 0010 the progression is part of the state, not a sibling of it.
	state.progression.credit_container("tent_bag")
	state.progression.credit_container("cooler")
	state.progression.unlock("insight")
	return {"state": state, "progression": state.progression}


# --- Round trip -------------------------------------------------------------------

func test_pack_then_unpack_returns_an_identical_run() -> void:
	var run := _a_run()
	var packed := SaveGame.pack(run["state"], "island_01")
	var back := SaveGame.unpack(packed)
	assert_dict(back["state"].to_dict()).is_equal(run["state"].to_dict())
	assert_dict(back["progression"].to_dict()).is_equal(run["progression"].to_dict())
	assert_str(back["level_id"]).is_equal("island_01")


func test_survives_a_trip_through_actual_json() -> void:
	# JSON has one number type: every int comes back a float. If the casts in
	# from_dict() ever go missing, this is what catches it.
	var run := _a_run()
	var packed := SaveGame.pack(run["state"], "island_01")
	var text := JSON.stringify(packed)
	var parsed: Variant = JSON.parse_string(text)
	assert_object(parsed).is_not_null()
	var back := SaveGame.unpack(parsed)
	assert_dict(back["state"].to_dict()).is_equal(run["state"].to_dict())
	assert_int(back["state"].elapsed_ticks).is_equal(4321)
	assert_int(back["state"].rng_seed).is_equal(987)
	assert_int(back["state"].stats["wrong_placements"]).is_equal(2)
	assert_int(back["state"].player_capacity(1)).is_equal(4)
	assert_array(back["state"].carried_by(1)).contains_exactly(["can_a1"])
	assert_str(back["state"].container_of("pole_1")).is_equal("tent_bag")
	assert_bool(back["progression"].has("insight")).is_true()
	assert_int(back["progression"].points).is_equal(2)


func test_pick_up_order_survives_a_save() -> void:
	var state := TestFixtures.ground_state(cat, 9)
	state.set_carried("pole_1", 1)
	state.set_carried("can_a1", 1)
	state.set_carried("peg_1", 1)
	var packed: Variant = JSON.parse_string(JSON.stringify(SaveGame.pack(state, "island_01")))
	var back := SaveGame.unpack(packed)
	assert_array(back["state"].carried_by(1)).is_equal(["pole_1", "can_a1", "peg_1"])
	assert_str(back["state"].active_item(1)).is_equal("peg_1")


func test_pack_records_the_schema_and_a_timestamp() -> void:
	var run := _a_run()
	var packed := SaveGame.pack(run["state"], "island_01")
	assert_int(packed["schema"]).is_equal(SaveGame.SCHEMA_VERSION)
	assert_int(packed["saved_at"]).is_greater(0)


# --- Refusing bad data --------------------------------------------------------------

func test_unusable_data_yields_nothing_rather_than_half_a_game() -> void:
	assert_dict(SaveGame.unpack({})).is_empty()
	assert_dict(SaveGame.unpack({"schema": SaveGame.SCHEMA_VERSION})).is_empty() # no state
	assert_dict(SaveGame.unpack({"schema": SaveGame.SCHEMA_VERSION, "state": {}})).is_empty() # no level
	assert_dict(SaveGame.unpack({"state": {}, "level_id": "island_01"})).is_empty() # no schema


func test_a_save_from_another_schema_version_is_refused() -> void:
	var run := _a_run()
	var packed := SaveGame.pack(run["state"], "island_01")
	packed["schema"] = SaveGame.SCHEMA_VERSION + 1
	assert_bool(SaveGame.is_usable(packed)).is_false()
	assert_dict(SaveGame.unpack(packed)).is_empty()
	packed["schema"] = SaveGame.SCHEMA_VERSION - 1
	assert_dict(SaveGame.unpack(packed)).is_empty()


# --- Files ----------------------------------------------------------------------------

func test_write_read_and_erase_a_slot() -> void:
	var run := _a_run()
	assert_bool(SaveGame.has_save(SLOT)).is_false()
	assert_bool(SaveGame.write(SLOT, SaveGame.pack(run["state"], "island_01"))).is_true()
	assert_bool(SaveGame.has_save(SLOT)).is_true()
	var back := SaveGame.unpack(SaveGame.read(SLOT))
	assert_dict(back["state"].to_dict()).is_equal(run["state"].to_dict())
	assert_bool(SaveGame.erase(SLOT)).is_true()
	assert_bool(SaveGame.has_save(SLOT)).is_false()
	assert_dict(SaveGame.read(SLOT)).is_empty()


func test_a_corrupt_file_reads_as_no_save_instead_of_crashing() -> void:
	DirAccess.make_dir_recursive_absolute(SaveGame.SAVE_DIR)
	var file := FileAccess.open(SaveGame.slot_path(SLOT), FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	assert_dict(SaveGame.read(SLOT)).is_empty()
	assert_bool(SaveGame.has_save(SLOT)).is_false()


func test_erasing_a_slot_that_does_not_exist_is_harmless() -> void:
	assert_bool(SaveGame.erase("never_written")).is_false()
