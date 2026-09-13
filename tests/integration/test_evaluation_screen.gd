extends GdUnitTestSuite
## WP-1.5 — the end-of-level evaluation, and restarting from it.
## Drives the real Main scene so the rebuild path is exercised, not mocked.

var main: Main


func before_test() -> void:
	main = auto_free(load("res://src/game/main/main.tscn").instantiate())
	main.skip_title = true # this suite is about the end of a game, not the flow
	add_child(main)


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSession.stop_level()


## Put every item where it belongs, so the island ends up clean.
func _clean_the_island() -> void:
	var pid := GameSession.local_player_id()
	for item_id in GameSession.catalog.item_ids():
		var item := GameSession.catalog.get_item(item_id)
		for container in GameSession.catalog.containers_accepting(item.category):
			var slot := PlacementRules.find_correct_slot(GameSession.catalog, GameSession.state, item_id, container.id)
			if slot < 0:
				continue
			GameSession.submit(Commands.pick_up(pid, item_id))
			GameSession.submit(Commands.place(pid, item_id, container.id, slot))
			break


# --- Appearing ------------------------------------------------------------------

func test_hidden_until_the_island_is_clean() -> void:
	assert_bool(main.evaluation.is_showing()).is_false()
	assert_bool(GameSession.is_running()).is_true()
	GameSession.submit(Commands.pick_up(GameSession.local_player_id(), "can_tuborg_1"))
	assert_bool(main.evaluation.is_showing()).is_false()


func test_appears_and_ends_the_session_when_the_island_is_clean() -> void:
	_clean_the_island()
	assert_bool(PlacementRules.is_island_clean(GameSession.catalog, GameSession.state)).is_true()
	assert_bool(main.evaluation.is_showing()).is_true()
	assert_bool(GameSession.is_running()).is_false()
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)


func test_the_clock_stops_when_the_level_ends() -> void:
	_clean_the_island()
	var ticks := GameSession.state.elapsed_ticks
	await await_millis(250)
	assert_int(GameSession.state.elapsed_ticks).is_equal(ticks)


func test_the_player_cannot_move_once_the_level_is_over() -> void:
	_clean_the_island()
	var where := main.player.global_position
	main.player.velocity = Vector3(10, 0, 10)
	main.player._physics_process(1.0 / 60.0)
	assert_vector(main.player.global_position).is_equal(where)


# --- Figures ---------------------------------------------------------------------

func test_shows_exactly_what_evaluation_computes() -> void:
	_clean_the_island()
	var expected := Evaluation.score(
		GameSession.catalog, GameSession.state,
		float(GameSession.level["par_seconds"]), float(GameSession.level["max_seconds"]))
	assert_dict(main.evaluation.score).is_equal(expected)
	main.evaluation.skip_count_up()
	assert_str(main.evaluation.points_label.text).is_equal(tr("ui.eval.points") % expected["points"])
	assert_str(main.evaluation.completion_value.text).is_equal(tr("ui.eval.percent") % 100)
	assert_str(main.evaluation.grade_label.text).is_equal(tr(Evaluation.grade_key(expected["grade"])))


func test_a_perfect_clean_run_scores_top_marks() -> void:
	_clean_the_island()
	# Every item placed correctly on the first try, well inside par time.
	assert_int(GameSession.state.stats["wrong_placements"]).is_equal(0)
	assert_float(main.evaluation.score["completion"]).is_equal(1.0)
	assert_str(main.evaluation.score["grade"]).is_equal("S")


func test_mistakes_show_up_as_lower_accuracy() -> void:
	var pid := GameSession.local_player_id()
	for item_id in ["food_bread", "food_cheese", "food_milk", "cloth_cap"]:
		GameSession.submit(Commands.pick_up(pid, item_id))
		GameSession.submit(Commands.place(pid, item_id, "canoe", 0)) # wrong on purpose
		GameSession.submit(Commands.take_out(pid, item_id))
		GameSession.submit(Commands.drop(pid, item_id, Vector3.ZERO))
	_clean_the_island()
	assert_float(main.evaluation.score["accuracy"]).is_less(1.0)
	assert_int(main.evaluation.score["points"]).is_less(100)


func test_a_single_slip_in_a_long_run_rounds_away() -> void:
	# Deliberate: accuracy is 25 % of the score, so one mistake in ~58 placements
	# costs under half a point. Forgiving a single fumble is the intent.
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "food_bread"))
	GameSession.submit(Commands.place(pid, "food_bread", "canoe", 0))
	GameSession.submit(Commands.take_out(pid, "food_bread"))
	GameSession.submit(Commands.drop(pid, "food_bread", Vector3.ZERO))
	_clean_the_island()
	assert_float(main.evaluation.score["accuracy"]).is_less(1.0)
	assert_int(main.evaluation.score["points"]).is_equal(100)


func test_count_up_starts_at_zero_and_skip_jumps_to_the_result() -> void:
	_clean_the_island()
	assert_str(main.evaluation.points_label.text).is_equal(tr("ui.eval.points") % 0)
	assert_str(main.evaluation.grade_label.text).is_equal("") # grade only after the count-up
	main.evaluation.skip_count_up()
	assert_str(main.evaluation.points_label.text).is_equal(tr("ui.eval.points") % main.evaluation.score["points"])
	assert_str(main.evaluation.skip_label.text).is_equal("")


func test_the_seed_is_shown_so_it_can_be_shared() -> void:
	_clean_the_island()
	assert_str(main.evaluation.seed_label.text).is_equal(tr("ui.eval.seed") % GameSession.state.rng_seed)


# --- Restarting --------------------------------------------------------------------

func test_same_island_reproduces_the_identical_mess() -> void:
	var before := GameSession.state.duplicate_state()
	var seed_before := GameSession.state.rng_seed
	_clean_the_island()
	main.restart_same_island()
	await await_millis(50)
	assert_int(GameSession.state.rng_seed).is_equal(seed_before)
	for item_id in GameSession.catalog.item_ids():
		assert_vector(GameSession.state.location(item_id)["position"]).override_failure_message(
			"'%s' moved between runs of the same seed" % item_id
		).is_equal(before.location(item_id)["position"])


func test_new_mess_uses_a_different_seed_and_scatters_differently() -> void:
	var before := GameSession.state.duplicate_state()
	_clean_the_island()
	main.restart_new_mess()
	await await_millis(50)
	assert_int(GameSession.state.rng_seed).is_not_equal(before.rng_seed)
	assert_dict(GameSession.state.to_dict()).is_not_equal(before.to_dict())


func test_restart_gives_a_fresh_playable_level() -> void:
	_clean_the_island()
	main.restart_same_island()
	await await_millis(50)
	assert_bool(GameSession.is_running()).is_true()
	assert_bool(main.evaluation.is_showing()).is_false()
	assert_bool(PlacementRules.is_island_clean(GameSession.catalog, GameSession.state)).is_false()
	assert_int(GameSession.state.stats["placements"]).is_equal(0)
	assert_int(main.island.get_node("Items").get_child_count()).is_equal(GameSession.catalog.item_count())


func test_restart_leaves_no_stale_nodes_reacting_to_events() -> void:
	# The old HUD/island must be gone, not merely queued, or they would respond
	# to the new level's events and double-count progress.
	var old_hud := main.hud
	var old_island := main.island
	_clean_the_island()
	main.restart_same_island()
	await await_millis(50)
	assert_bool(is_instance_valid(old_hud)).is_false()
	assert_bool(is_instance_valid(old_island)).is_false()
	assert_object(main.hud).is_not_same(old_hud)
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "firewood_1"))
	GameSession.submit(Commands.place(pid, "firewood_1", "fire_pit", 0))
	assert_str(main.hud.progress_label.text).is_equal(
		tr("ui.hud.progress") % [1, GameSession.catalog.item_count()])
