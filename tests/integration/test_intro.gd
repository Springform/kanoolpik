extends GdUnitTestSuite
## WP-5.4 — the morning after.
##
## Almost nothing here is about how it looks; a test cannot tell you whether
## seven seconds of blinking is charming. What it can tell you is the part that
## would actually hurt: **that the intro is an overlay and nothing else.** The
## world is running underneath it, skipping it leaves nothing behind, and a
## player still watching it does not hold up anybody's round.


func after_test() -> void:
	# Statics with a file behind them. A suite that leaves fx.intro off makes the
	# next suite's intro vanish for no visible reason — the WP-5.1 lesson.
	Settings.forget()
	if GameSession.is_running():
		GameSession.stop_level()


func _intro() -> WakeUp:
	var made: WakeUp = auto_free(WakeUp.new())
	add_child(made)
	# Driven by hand: _process would run its own clock between the assertions
	# and every number below would be about the frame rate.
	made.set_process(false)
	return made


# --- The storyboard ------------------------------------------------------------------

func test_it_starts_with_your_eyes_shut() -> void:
	var at_zero := WakeUp.state_at(0.0)
	assert_float(at_zero["open"]).is_equal_approx(0.0, 0.001)
	assert_float(at_zero["blur"]).is_equal_approx(1.0, 0.001)


func test_it_ends_with_nothing_on_the_screen() -> void:
	# Whatever happens in the middle, the last frame has to be the island and
	# not a film over it.
	for at: float in [WakeUp.DURATION, WakeUp.DURATION + 5.0]:
		var frame := WakeUp.state_at(at)
		assert_float(frame["open"]).override_failure_message(
			"the eyelids are still %.2f closed at %.1f s" % [1.0 - float(frame["open"]), at]
		).is_equal_approx(1.0, 0.001)
		assert_float(frame["blur"]).override_failure_message(
			"the blur is still %.2f at %.1f s" % [frame["blur"], at]).is_equal_approx(0.0, 0.001)


func test_somebody_waking_up_blinks() -> void:
	# The one thing that makes it read as coming round rather than as a fade:
	# the lids close again after the first glimpse. Counted rather than assumed,
	# because a storyboard is easy to edit into a straight line by accident.
	var dips := 0
	var previous := WakeUp.state_at(0.0)["open"] as float
	var rising := true
	var at := 0.0
	while at < WakeUp.DURATION:
		at += 0.05
		var now: float = WakeUp.state_at(at)["open"]
		if rising and now < previous - 0.01:
			dips += 1
			rising = false
		elif not rising and now > previous + 0.01:
			rising = true
		previous = now
	assert_int(dips).override_failure_message(
		"the eyelids closed again %d times; waking up is two blinks" % dips).is_equal(2)


func test_it_is_over_in_under_ten_seconds() -> void:
	# The WP says ten at most. Seven, because the fifth restart of an evening is
	# not the first one.
	assert_float(WakeUp.DURATION).is_between(3.0, 10.0)


# --- Off means off --------------------------------------------------------------------

func test_switching_it_off_builds_nothing_at_all() -> void:
	# Not "builds it and draws nothing". One frame of blur is precisely what
	# somebody who turned this off is complaining about.
	Settings.set_value(Settings.FX_INTRO, false)
	var made := WakeUp.install(self)
	assert_object(made).override_failure_message(
		"fx.intro is off and an intro was built anyway").is_null()
	assert_int(get_children().filter(func(c: Node) -> bool: return c is WakeUp).size()).is_equal(0)


func test_it_is_on_unless_somebody_turns_it_off() -> void:
	assert_bool(bool(Settings.DEFAULTS[Settings.FX_INTRO])).is_true()
	var made := WakeUp.install(self)
	assert_object(made).is_not_null()
	made.finish()


# --- Skipping -------------------------------------------------------------------------

func test_any_key_ends_it_on_the_first_frame() -> void:
	var intro := _intro()
	await get_tree().process_frame
	var ended := [false]
	intro.finished.connect(func() -> void: ended[0] = true)

	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	intro._input(key)

	assert_bool(ended[0]).override_failure_message(
		"a key press did not end the intro").is_true()
	assert_bool(intro.is_queued_for_deletion()).is_true()


func test_a_mouse_click_ends_it_too() -> void:
	var intro := _intro()
	await get_tree().process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	intro._input(click)
	assert_bool(intro.is_queued_for_deletion()).is_true()


func test_letting_go_of_a_key_does_not_count() -> void:
	# Otherwise the key that started the round ends the intro on its own release
	# and nobody sees a frame of it.
	var intro := _intro()
	await get_tree().process_frame
	var release := InputEventKey.new()
	release.keycode = KEY_SPACE
	release.pressed = false
	intro._input(release)
	assert_bool(intro.is_queued_for_deletion()).is_false()
	intro.finish()


func test_ending_it_twice_is_not_an_error() -> void:
	var intro := _intro()
	await get_tree().process_frame
	var ends := [0]
	intro.finished.connect(func() -> void: ends[0] += 1)
	intro.finish()
	intro.finish()
	assert_int(ends[0]).is_equal(1)


func test_it_frees_itself_when_it_runs_out() -> void:
	var intro := _intro()
	await get_tree().process_frame
	intro.set_process(true)
	intro.elapsed = WakeUp.DURATION - 0.001
	intro._process(0.1)
	assert_bool(intro.is_queued_for_deletion()).override_failure_message(
		"the intro ran past its own duration").is_true()


# --- It is an overlay and nothing else ------------------------------------------------

func test_the_round_is_already_running_underneath_it() -> void:
	# The intro initialises nothing, which is why skipping it cannot leave
	# anything half-built. Proved by playing through it: a command submitted
	# while the intro is up lands in the world exactly as it would without one.
	GameSession.start_level("island_01", 77)
	var intro := _intro()
	await get_tree().process_frame

	var pid := GameSession.local_player_id()
	var item: String = GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	GameSession.submit(Commands.pick_up(pid, item))

	assert_array(GameSession.state.carried_by(pid)).override_failure_message(
		"a command submitted during the intro did not reach the world").contains([item])
	intro.finish()


func test_it_holds_no_opinion_about_the_world() -> void:
	# A file that never mentions the session cannot delay it, desync it, or stop
	# its clock. Cheaper and more honest than simulating six peers to find out.
	var source := FileAccess.get_file_as_string("res://src/game/fx/wake_up.gd")
	var body := ""
	for line: String in source.split("\n"):
		if not line.strip_edges().begins_with("#"):
			body += line + "\n"
	for forbidden: String in ["GameSession", "GameEvents", "Commands", "WorldState"]:
		assert_bool(body.contains(forbidden)).override_failure_message(
			"the intro reaches for %s; it is meant to be a layer of paint" % forbidden
		).is_false()


func test_it_keeps_running_while_the_tree_is_paused() -> void:
	# Esc during the intro should show the pause menu over it, not freeze it
	# half-blinked behind the menu.
	var intro := _intro()
	await get_tree().process_frame
	assert_int(intro.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	intro.finish()


func test_it_draws_over_the_hud_and_under_nothing_it_should_not() -> void:
	# The pause menu and the settings panel are layers 9 and above; the HUD is
	# below. The intro belongs between them.
	var intro := _intro()
	await get_tree().process_frame
	assert_int(intro.layer).is_between(1, 8)
	intro.finish()


# --- The string -----------------------------------------------------------------------

func test_the_hint_says_something_in_both_languages() -> void:
	var text := FileAccess.get_file_as_string("res://assets/i18n/strings.csv")
	var found := false
	for line: String in text.split("\n"):
		if line.begins_with("ui.intro.skip,"):
			var columns := line.split(",")
			found = columns.size() >= 3 and not columns[1].strip_edges().is_empty() \
				and not columns[2].strip_edges().is_empty()
	assert_bool(found).override_failure_message(
		"there is no translated hint telling anybody they can skip it").is_true()
