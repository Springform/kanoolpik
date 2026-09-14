extends GdUnitTestSuite
## WP-1.6 — TITLE → PLAYING → EVALUATION → TITLE, plus the pause menu.
##
## Pausing really does pause the tree, so no test here may await while paused:
## the awaited timer would never fire and the whole suite would hang.
##
## Screen changes are connected deferred (acting on them frees the node that is
## still emitting the signal), so each one needs a frame before asserting.

var main: Main


func before_test() -> void:
	main = auto_free(load("res://src/game/main/main.tscn").instantiate())
	add_child(main)


func after_test() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	TranslationServer.set_locale("da")
	GameSession.stop_level()


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


# --- Title ---------------------------------------------------------------------------

func test_boots_to_the_title_with_no_player_and_no_clock() -> void:
	assert_int(main.state).is_equal(Main.State.TITLE)
	assert_object(main.title_screen).is_not_null()
	assert_object(main.player).is_null()
	assert_object(main.hud).is_null()
	assert_bool(GameSession.is_running()).is_false()


func test_the_island_drifts_behind_the_title() -> void:
	assert_object(main.island).is_not_null()
	assert_object(main.backdrop).is_not_null()
	assert_bool(main.backdrop.current).is_true()
	var where := main.backdrop.global_position
	main.backdrop._process(0.5)
	assert_vector(main.backdrop.global_position).is_not_equal(where)


func test_the_clock_never_starts_on_the_title() -> void:
	await await_millis(200)
	assert_int(GameSession.state.elapsed_ticks).is_equal(0)


# --- Starting a game -------------------------------------------------------------------

func test_start_builds_a_playable_level() -> void:
	main.title_screen.start_requested.emit(Main.LEVEL_DEFAULT_SEED)
	await await_millis(50)
	assert_int(main.state).is_equal(Main.State.PLAYING)
	assert_object(main.player).is_not_null()
	assert_object(main.hud).is_not_null()
	assert_object(main.pause_menu).is_not_null()
	assert_object(main.title_screen).is_null()
	assert_bool(GameSession.is_running()).is_true()


func test_a_typed_island_code_is_used_as_the_seed() -> void:
	main.title_screen.seed_input.text = "12345"
	assert_int(main.title_screen.chosen_seed()).is_equal(12345)
	main.title_screen._on_start()
	await await_millis(50)
	assert_int(GameSession.state.rng_seed).is_equal(12345)


func test_a_blank_or_nonsense_code_falls_back_to_the_level_default() -> void:
	main.title_screen.seed_input.text = ""
	assert_int(main.title_screen.chosen_seed()).is_equal(Main.LEVEL_DEFAULT_SEED)
	main.title_screen.seed_input.text = "hey"
	assert_int(main.title_screen.chosen_seed()).is_equal(Main.LEVEL_DEFAULT_SEED)
	main.title_screen._on_start()
	await await_millis(50)
	assert_int(GameSession.state.rng_seed).is_equal(int(GameSession.level["seed_default"]))


# --- Language ---------------------------------------------------------------------------

func test_the_language_toggle_swaps_the_text_live() -> void:
	var danish := main.title_screen.start_button.text
	assert_str(danish).is_equal(tr("ui.title.start"))
	main.title_screen.toggle_language()
	assert_str(TranslationServer.get_locale()).is_equal("en")
	assert_str(main.title_screen.start_button.text).is_equal("Start cleaning")
	assert_str(main.title_screen.start_button.text).is_not_equal(danish)
	main.title_screen.toggle_language()
	assert_str(TranslationServer.get_locale()).is_equal("da")
	assert_str(main.title_screen.start_button.text).is_equal(danish)


# --- Pause -------------------------------------------------------------------------------

func test_pause_freezes_the_tree_and_resume_restores_it() -> void:
	main.start_game(Main.LEVEL_DEFAULT_SEED)
	assert_bool(main.is_paused()).is_false()
	main.pause_menu.open()
	assert_bool(main.is_paused()).is_true()
	assert_bool(get_tree().paused).is_true()
	main.pause_menu.close()
	assert_bool(main.is_paused()).is_false()
	assert_bool(get_tree().paused).is_false()
	# Mouse capture is deliberately not asserted: headless has no window, so
	# Input.mouse_mode never leaves VISIBLE. That one is on the playtest list.


func test_the_player_is_pausable_so_it_stops_while_the_menu_is_open() -> void:
	main.start_game(Main.LEVEL_DEFAULT_SEED)
	assert_bool(main.player.can_process()).is_true()
	main.pause_menu.open()
	assert_bool(main.player.can_process()).is_false()
	assert_bool(main.pause_menu.can_process()).is_true() # must be able to unpause itself
	main.pause_menu.close()


func test_restart_from_the_pause_menu_keeps_the_same_island() -> void:
	main.start_game(4242)
	var before := GameSession.state.duplicate_state()
	var pid := GameSession.local_player_id()
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	main.pause_menu.open()
	main.pause_menu._request(main.pause_menu.restart_requested)
	await await_millis(50) # safe: _request unpauses before deferring
	assert_int(GameSession.state.rng_seed).is_equal(4242)
	assert_bool(get_tree().paused).is_false()
	assert_int(GameSession.state.kind_of("can_tuborg_1")).is_equal(WorldState.Kind.GROUND)
	for item_id in GameSession.catalog.item_ids():
		assert_vector(GameSession.state.location(item_id)["position"]).is_equal(before.location(item_id)["position"])


func test_back_to_the_title_from_the_pause_menu() -> void:
	main.start_game(Main.LEVEL_DEFAULT_SEED)
	main.pause_menu.open()
	main.pause_menu._request(main.pause_menu.title_requested)
	await await_millis(50)
	assert_int(main.state).is_equal(Main.State.TITLE)
	assert_object(main.player).is_null()
	assert_object(main.title_screen).is_not_null()
	assert_bool(get_tree().paused).is_false()
	assert_bool(GameSession.is_running()).is_false()


func test_escape_cannot_pause_once_the_score_is_up() -> void:
	main.start_game(Main.LEVEL_DEFAULT_SEED)
	_clean_the_island()
	assert_int(main.state).is_equal(Main.State.EVALUATION)
	assert_bool(main.pause_menu.can_open).is_false()
	main.pause_menu._unhandled_input(_escape())
	assert_bool(main.is_paused()).is_false()


func test_escape_opens_and_closes_the_menu() -> void:
	main.start_game(Main.LEVEL_DEFAULT_SEED)
	main.pause_menu._unhandled_input(_escape())
	assert_bool(main.is_paused()).is_true()
	main.pause_menu._unhandled_input(_escape())
	assert_bool(main.is_paused()).is_false()


# --- Full loop -----------------------------------------------------------------------------

func test_title_to_playing_to_evaluation_and_back_to_title() -> void:
	main.title_screen.start_requested.emit(Main.LEVEL_DEFAULT_SEED)
	await await_millis(50)
	assert_int(main.state).is_equal(Main.State.PLAYING)
	_clean_the_island()
	assert_int(main.state).is_equal(Main.State.EVALUATION)
	assert_bool(main.evaluation.is_showing()).is_true()
	main.to_title()
	assert_int(main.state).is_equal(Main.State.TITLE)
	assert_object(main.evaluation).is_null()
	assert_object(main.title_screen).is_not_null()
	# and a second run works exactly like the first
	main.title_screen.start_requested.emit(Main.LEVEL_DEFAULT_SEED)
	await await_millis(50)
	assert_int(main.state).is_equal(Main.State.PLAYING)
	assert_bool(PlacementRules.is_island_clean(GameSession.catalog, GameSession.state)).is_false()


func _escape() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	return event


# --- Phase-3 abilities reach the running game (wave-1 integration) ------------
#
# Every ability test builds its own ability node, which proves the ability works
# and proves nothing about whether the game ever creates one. Without the checks
# below, the whole of wave 1 could ship as code no player can reach.

func _abilities_under(node: Node, type_name: String) -> Array[Node]:
	return node.find_children("*", type_name, true, false)


func test_starting_a_game_installs_the_abilities() -> void:
	main.start_game(1234)
	await get_tree().process_frame
	assert_array(_abilities_under(main, "InsightAbility")).override_failure_message(
		"Klarsyn is never created, so F does nothing in the real game").has_size(1)
	assert_array(_abilities_under(main, "CallMateAbility")).override_failure_message(
		"Råb på en kammerat is never created, so R does nothing in the real game").has_size(1)


func test_the_hud_owns_the_summon_rejection_message_not_the_ability() -> void:
	# Both work packages wrote a rejection toast. HUD.error_key now maps the
	# summon errors, so the ability's own fallback must be off or the player is
	# told the same thing twice.
	main.start_game(1234)
	await get_tree().process_frame
	var call_mate: CallMateAbility = _abilities_under(main, "CallMateAbility")[0]
	assert_bool(call_mate.own_rejection_toasts).override_failure_message(
		"the player gets two toasts for one refused shout").is_false()
	assert_str(HUD.error_key(CommandProcessor.E_SERIES_SPENT)).is_equal(
		"ui.error." + CommandProcessor.E_SERIES_SPENT)


func test_restarting_does_not_leave_a_second_set_of_abilities() -> void:
	# _build_playing_scene() runs again on every restart. Two Klarsyn nodes mean
	# two sets of highlights and a doubled toast.
	main.start_game(1234)
	await get_tree().process_frame
	main.restart_new_mess()
	await get_tree().process_frame
	assert_array(_abilities_under(main, "InsightAbility")).has_size(1)
	assert_array(_abilities_under(main, "CallMateAbility")).has_size(1)
