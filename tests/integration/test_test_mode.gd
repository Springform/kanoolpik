extends GdUnitTestSuite
## WP-3.10 — the test-mode panel, and the win condition it was built to reach.
##
## The reason this suite matters beyond the panel itself: `island_clean` had
## never been seen happen. Verifying it by hand cost a full tidy-up of 162
## items, so it never got done. `pack_all_but_one()` makes it a two-line test,
## and now CI checks the ending of the game on every push.

const SLOT := "test_mode_integration"

var main: Main


func before_test() -> void:
	TestMode.reset()
	main = auto_free(load("res://src/game/main/main.tscn").instantiate())
	main.skip_title = true
	add_child(main)
	GameSession.autosave_enabled = false


func after_test() -> void:
	GameSession.autosave_enabled = true
	TestMode.reset()
	SaveGame.erase(SLOT)
	GameSession.stop_level()


func _panel() -> TestPanel:
	return main.test_panel


# --- Availability -------------------------------------------------------------

func test_the_panel_is_there_when_test_mode_is_on() -> void:
	assert_bool(TestMode.is_available()).override_failure_message(
		"the suite runs on a debug build, so test mode should be available").is_true()
	assert_object(_panel()).is_not_null()


func test_no_panel_and_no_debug_commands_when_test_mode_is_off() -> void:
	TestMode.set_enabled(false)
	main.start_game(4242)
	await get_tree().process_frame
	assert_object(main.test_panel).override_failure_message(
		"test mode is off but the panel was built anyway").is_null()
	# And the door is locked at the other end too, not just in the UI.
	assert_bool(GameSession.processor.allow_debug_commands).is_false()
	var before := GameSession.progression.available_points()
	GameSession.submit(Commands.grant_points(GameSession.local_player_id(), 5))
	assert_int(GameSession.progression.available_points()).override_failure_message(
		"a build with test mode off still handed out points").is_equal(before)


func test_the_toggle_survives_into_the_next_game() -> void:
	TestMode.set_enabled(false)
	assert_bool(TestMode.is_enabled()).is_false()
	TestMode.set_enabled(true)
	main.start_game(4242)
	await get_tree().process_frame
	assert_object(main.test_panel).is_not_null()


# --- The win condition --------------------------------------------------------

func test_packing_all_but_one_leaves_exactly_one_thing_out() -> void:
	var survivor := _panel().pack_all_but_one()
	assert_str(survivor).is_not_empty()
	var loose := GameSession.state.items_of_kind(WorldState.Kind.GROUND)
	var carried := GameSession.state.carried_by(GameSession.local_player_id())
	assert_int(loose.size() + carried.size()).override_failure_message(
		"the island should have exactly one thing left on it").is_equal(1)
	assert_bool(PlacementRules.is_island_clean(GameSession.catalog, GameSession.state)) \
		.override_failure_message("the island counted as clean while something was still out") \
		.is_false()


func test_putting_the_last_thing_away_ends_the_game() -> void:
	# This is the assertion the whole work package exists for.
	var survivor := _panel().pack_all_but_one()
	var monitor := monitor_signals(GameEvents, false)
	var pid := GameSession.local_player_id()
	var item := GameSession.catalog.get_item(survivor)
	var placed := false
	for container in GameSession.catalog.containers_accepting(item.category):
		var slot := PlacementRules.find_correct_slot(
			GameSession.catalog, GameSession.state, survivor, container.id)
		if slot < 0:
			continue
		if GameSession.state.kind_of(survivor) != WorldState.Kind.CARRIED:
			GameSession.submit(Commands.pick_up(pid, survivor))
		GameSession.submit(Commands.place(pid, survivor, container.id, slot))
		placed = true
		break
	assert_bool(placed).override_failure_message(
		"the item left behind had nowhere correct to go, so the run cannot be finished").is_true()
	assert_bool(PlacementRules.is_island_clean(GameSession.catalog, GameSession.state)).is_true()
	await assert_signal(monitor).is_emitted("island_clean")


func test_the_evaluation_screen_comes_up_when_the_island_is_clean() -> void:
	var survivor := _panel().pack_all_but_one()
	var pid := GameSession.local_player_id()
	var item := GameSession.catalog.get_item(survivor)
	for container in GameSession.catalog.containers_accepting(item.category):
		var slot := PlacementRules.find_correct_slot(
			GameSession.catalog, GameSession.state, survivor, container.id)
		if slot < 0:
			continue
		if GameSession.state.kind_of(survivor) != WorldState.Kind.CARRIED:
			GameSession.submit(Commands.pick_up(pid, survivor))
		GameSession.submit(Commands.place(pid, survivor, container.id, slot))
		break
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(main.evaluation.is_showing()).override_failure_message(
		"the island was clean but the camp leader never gave his verdict").is_true()


# --- The other tools ----------------------------------------------------------

func test_granting_points_and_buying_an_ability() -> void:
	_panel().grant_points(4)
	assert_int(GameSession.progression.available_points()).is_equal(4)
	_panel().unlock("auto_place") # costs 3
	assert_bool(GameSession.progression.has("auto_place")).is_true()
	assert_int(GameSession.progression.available_points()).is_equal(1)


func test_buying_an_ability_tops_up_the_points_it_is_short() -> void:
	# No points at all, and the panel still buys it — by granting the difference
	# and then going through the ordinary unlock command.
	assert_int(GameSession.progression.available_points()).is_equal(0)
	_panel().unlock("call_mate") # costs 2
	assert_bool(GameSession.progression.has("call_mate")).is_true()
	assert_int(GameSession.progression.available_points()).is_equal(0)


func test_setting_the_clock_moves_the_speed_score() -> void:
	_panel().set_clock_minutes(45) # past the 40-minute maximum
	assert_int(GameSession.state.elapsed_ticks).is_equal(45 * 60 * 60)
	var evaluation := Evaluation.score(GameSession.catalog, GameSession.state,
		float(GameSession.level.get("par_seconds", Evaluation.DEFAULT_PAR_SECONDS)),
		float(GameSession.level.get("max_seconds", Evaluation.DEFAULT_MAX_SECONDS)))
	assert_float(float(evaluation["speed"])).override_failure_message(
		"45 minutes is past max, so speed should have bottomed out").is_equal_approx(0.0, 0.001)


func test_the_clock_only_ever_goes_forward() -> void:
	_panel().set_clock_minutes(30)
	var ticks := GameSession.state.elapsed_ticks
	_panel().set_clock_minutes(5)
	assert_int(GameSession.state.elapsed_ticks).override_failure_message(
		"the clock went backwards, which the tick command cannot express").is_equal(ticks)


func test_teleporting_puts_the_player_next_to_the_container() -> void:
	var player := GameSession.local_player_id()
	assert_int(player).is_greater(0)
	var target_id: String = GameSession.catalog.container_ids()[0]
	_panel().teleport_to(target_id)
	var target := GameSession.container_position(target_id)
	var here := main.player.global_position
	assert_float(Vector2(here.x - target.x, here.z - target.z).length()) \
		.override_failure_message("the teleport did not land near the container").is_less(5.0)


func test_the_container_readout_empties_as_things_are_packed() -> void:
	var before := _panel().missing_by_container()
	assert_dict(before).is_not_empty()
	var total_before := 0
	for cid: String in before.keys():
		total_before += (before[cid] as Array).size()
	assert_int(total_before).is_greater(0)
	_panel().pack_all_but_one()
	var after := _panel().missing_by_container()
	var total_after := 0
	for cid: String in after.keys():
		total_after += (after[cid] as Array).size()
	assert_int(total_after).override_failure_message(
		"one item is left, so exactly one container should still be waiting").is_equal(1)


func test_the_panel_opens_and_closes() -> void:
	assert_bool(_panel().is_open()).is_false()
	_panel().toggle()
	assert_bool(_panel().is_open()).is_true()
	_panel().toggle()
	assert_bool(_panel().is_open()).is_false()
