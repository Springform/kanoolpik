extends GdUnitTestSuite
## WP-1.8 — saving and resuming a real run through Main, including the
## presentation rebuilding itself from a loaded state.

const SLOT := "integration_test"

var main: Main


func before_test() -> void:
	SaveGame.erase(SLOT)
	SaveGame.erase(SaveGame.DEFAULT_SLOT)
	main = auto_free(load("res://src/game/main/main.tscn").instantiate())
	main.skip_title = true
	add_child(main)
	GameSession.autosave_enabled = false


func after_test() -> void:
	GameSession.autosave_enabled = true
	SaveGame.erase(SLOT)
	SaveGame.erase(SaveGame.DEFAULT_SLOT)
	GameSession.stop_level()


## A few placements, one of them wrong, plus something still in hand.
func _play_a_bit() -> void:
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "firewood_1"))
	GameSession.submit(Commands.place(pid, "firewood_1", "fire_pit", 0))
	GameSession.submit(Commands.pick_up(pid, "food_bread"))
	GameSession.submit(Commands.place(pid, "food_bread", "canoe", 0)) # wrong on purpose
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	GameSession.submit(Commands.tick(60 * 90))


# --- Saving and resuming ---------------------------------------------------------

func test_a_resumed_run_is_identical_down_to_the_dictionary() -> void:
	_play_a_bit()
	var before := GameSession.state.to_dict()
	assert_bool(GameSession.save(SLOT)).is_true()
	main.start_game(999999) # a completely different game in between
	assert_dict(GameSession.state.to_dict()).is_not_equal(before)
	assert_bool(main.continue_game(SLOT)).is_true()
	assert_dict(GameSession.state.to_dict()).is_equal(before)


func test_resuming_restores_the_clock_the_score_and_the_progression() -> void:
	_play_a_bit()
	GameSession.progression.credit_container("fire_pit")
	var ticks := GameSession.state.elapsed_ticks
	GameSession.save(SLOT)
	main.continue_game(SLOT)
	assert_int(GameSession.state.elapsed_ticks).is_equal(ticks)
	assert_int(GameSession.state.stats["wrong_placements"]).is_equal(1)
	assert_int(GameSession.progression.points).is_equal(1)
	assert_bool(GameSession.is_running()).is_true()


func test_what_you_were_carrying_is_still_in_your_hands() -> void:
	_play_a_bit()
	GameSession.save(SLOT)
	main.continue_game(SLOT)
	var pid := GameSession.local_player_id()
	assert_array(GameSession.state.carried_by(pid)).contains_exactly(["can_tuborg_1"])
	assert_int(main.player.held_items.item_count()).is_equal(1)
	assert_str(main.player.held_items.top_item_id()).is_equal("can_tuborg_1")


# --- The world is rebuilt to match ---------------------------------------------------

func test_packed_and_carried_items_are_not_left_lying_around() -> void:
	_play_a_bit()
	GameSession.save(SLOT)
	main.continue_game(SLOT)
	var packed: PickupItem = main.island.get_node("Items/Item_firewood_1")
	var carried: PickupItem = main.island.get_node("Items/Item_can_tuborg_1")
	var loose: PickupItem = main.island.get_node("Items/Item_firewood_2")
	assert_bool(packed.visible).override_failure_message("a packed item is still lying on the island").is_false()
	assert_bool(carried.visible).override_failure_message("a carried item is still lying on the island").is_false()
	assert_bool(loose.visible).is_true()


func test_containers_come_back_showing_what_they_hold() -> void:
	_play_a_bit()
	GameSession.save(SLOT)
	main.continue_game(SLOT)
	var pit: ContainerNode = main.island.get_node("Containers/Container_fire_pit")
	var canoe: ContainerNode = main.island.get_node("Containers/Container_canoe")
	assert_str(pit.slot_node(0).item_id()).is_equal("firewood_1")
	assert_object(pit.slot_mesh(0).material_override).is_equal(VerdictStyle.material("correct"))
	assert_object(canoe.slot_mesh(0).material_override).is_equal(VerdictStyle.material("wrong"))
	assert_bool(canoe.slot_mark(0).visible).is_true()


func test_the_hud_shows_the_restored_progress_immediately() -> void:
	_play_a_bit()
	GameSession.save(SLOT)
	main.continue_game(SLOT)
	assert_str(main.hud.progress_label.text).is_equal(
		tr("ui.hud.progress") % [1, GameSession.catalog.item_count()])


func test_a_resumed_run_can_be_played_on() -> void:
	_play_a_bit()
	GameSession.save(SLOT)
	main.continue_game(SLOT)
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "firewood_2"))
	GameSession.submit(Commands.place(pid, "firewood_2", "fire_pit", 1))
	assert_str(GameSession.state.item_in_slot("fire_pit", 1)).is_equal("firewood_2")


# --- Autosave --------------------------------------------------------------------------

func test_autosave_writes_when_a_container_is_packed_and_not_before() -> void:
	GameSession.autosave_enabled = true
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "firewood_1"))
	GameSession.submit(Commands.place(pid, "firewood_1", "fire_pit", 0))
	assert_bool(GameSession.has_save()).override_failure_message(
		"autosaved before anything was finished").is_false()
	for i in range(2, 6):
		GameSession.submit(Commands.pick_up(pid, "firewood_%d" % i))
		GameSession.submit(Commands.place(pid, "firewood_%d" % i, "fire_pit", i - 1))
	assert_bool(GameSession.has_save()).is_true()
	var saved := SaveGame.unpack(SaveGame.read())
	assert_str(saved["state"].container_of("firewood_1")).is_equal("fire_pit")


func test_ticking_never_writes_a_save() -> void:
	GameSession.autosave_enabled = true
	GameSession.submit(Commands.tick(60 * 30))
	assert_bool(GameSession.has_save()).is_false()


# --- Refusing to load rubbish ------------------------------------------------------------

func test_loading_an_empty_slot_changes_nothing() -> void:
	_play_a_bit()
	var before := GameSession.state.to_dict()
	assert_bool(GameSession.load_save("no_such_slot")).is_false()
	assert_dict(GameSession.state.to_dict()).is_equal(before)


func test_continue_falls_back_to_a_fresh_game_rather_than_stranding_the_player() -> void:
	assert_bool(main.continue_game("no_such_slot")).is_false()
	assert_int(main.state).is_equal(Main.State.PLAYING)
	assert_bool(GameSession.is_running()).is_true()
	assert_object(main.player).is_not_null()


func test_a_save_naming_an_unknown_level_is_refused() -> void:
	_play_a_bit()
	var packed := SaveGame.pack(GameSession.state, GameSession.progression, "island_that_never_was")
	SaveGame.write(SLOT, packed)
	assert_bool(GameSession.load_save(SLOT)).is_false()


func test_a_finished_or_paused_session_can_still_be_saved() -> void:
	# stop_level() only stops the clock; the state is still there and worth
	# keeping, which is what lets the pause menu and the title backdrop coexist
	# with an autosave from earlier.
	_play_a_bit()
	var before := GameSession.state.to_dict()
	GameSession.stop_level()
	assert_bool(GameSession.save(SLOT)).is_true()
	assert_dict(SaveGame.unpack(SaveGame.read(SLOT))["state"].to_dict()).is_equal(before)
