extends GdUnitTestSuite
## WP-5.1 — the first thing in this project that remembers anything about the
## player.
##
## Two claims are worth more than the rest. **A missing or broken file is the
## normal case**, not an error path: a first run, a cleared browser and a
## half-written file all have to land on the defaults the game shipped with.
## And **a value the player did not change is not a change** — a slider emits
## `value_changed` while it is dragged and again on release with the same
## number, so without that rule every drag writes the file dozens of times and
## every listener re-applies what it already has.

## A scratch file of this suite's own. The real store writes nothing headless
## (see [method Settings._persists]) precisely so a test run cannot leave a
## player's preferences behind — so the suite that is actually testing the file
## has to ask for one by name.
const TEST_PATH := "user://settings_test_probe.cfg"


func before_test() -> void:
	# Nothing may inherit a sensitivity from whatever ran before it.
	Settings.use_store(TEST_PATH)
	_delete_settings_file()


func after_test() -> void:
	_delete_settings_file()
	Settings.use_default_store()
	# Put the buses back where the project's layout has them, so a volume set
	# here does not silence the next suite.
	for bus_key: String in Settings.BUSES:
		var index := AudioServer.get_bus_index(String(Settings.BUSES[bus_key]))
		if index >= 0:
			AudioServer.set_bus_volume_db(index, 0.0)
	TranslationServer.set_locale("da")


# --- Defaults and absence ------------------------------------------------------------

func test_a_first_run_is_the_game_as_it_shipped() -> void:
	# Not arbitrary numbers: these are Player's own sensitivity and its camera's
	# FOV, so a player who never opens the panel gets exactly what every build
	# before this WP felt like.
	assert_float(Settings.get_float(Settings.LOOK_SENSITIVITY)).is_equal_approx(0.0025, 0.00001)
	assert_float(Settings.get_float(Settings.LOOK_FOV)).is_equal_approx(90.0, 0.01)
	assert_float(Settings.get_float(Settings.AUDIO_MUSIC)).is_equal_approx(1.0, 0.01)
	assert_str(Settings.get_string(Settings.UI_LOCALE)).is_equal("da")


func test_a_garbage_file_is_a_first_run() -> void:
	# A browser closed mid-write. There is nothing a player can do about it and
	# nothing worth telling them, so it must be silent and it must not throw.
	var file := FileAccess.open(Settings.path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string("this is not a config file [[[ = = unterminated \"")
	file.close()
	Settings.forget()
	# The engine prints "ConfigFile parse error" for this one. That is the
	# parser reporting, not a failure — run_tests.sh fails on SCRIPT ERROR and
	# Parse Error, not on a bare ERROR line. Expected, and noted here so nobody
	# chases it.

	assert_float(Settings.get_float(Settings.LOOK_FOV)).override_failure_message(
		"a corrupt settings file was allowed to decide the field of view"
	).is_equal_approx(90.0, 0.01)


func test_a_file_from_the_future_cannot_smuggle_a_value_in() -> void:
	# A key we do not know, and a known key holding the wrong type. Both are
	# what a hand-edited file or a later version looks like.
	var file := ConfigFile.new()
	file.set_value(Settings.SECTION, "look.telepathy", 7)
	file.set_value(Settings.SECTION, Settings.LOOK_FOV, "very wide")
	file.save(Settings.path)
	Settings.forget()

	assert_float(Settings.get_float(Settings.LOOK_FOV)).override_failure_message(
		"a string was accepted as a field of view").is_equal_approx(90.0, 0.01)
	assert_object(Settings.get_value("look.telepathy")).is_null()


func test_a_value_outside_its_range_is_pulled_back_in() -> void:
	Settings.set_value(Settings.LOOK_FOV, 400.0)
	var bounds := Settings.range_for(Settings.LOOK_FOV)
	assert_float(Settings.get_float(Settings.LOOK_FOV)).override_failure_message(
		"a hand-edited file handed the camera a 400 degree field of view"
	).is_equal_approx(float(bounds["max"]), 0.01)


func test_a_test_run_leaves_no_settings_behind() -> void:
	# The guarantee this whole store depends on, and the only one that cannot be
	# seen from inside a single suite. These are statics with a file behind
	# them, so a slider moved in ANY suite used to write the player's real
	# settings.cfg — and the next run of the whole suite then started in
	# whatever language that file said. One failed language test left it on
	# English and test_hud's Danish-glyph assertions failed in a different
	# suite, on the next run, for no visible reason.
	#
	# The first version of this test asserted the real file did not EXIST, and
	# that is a different claim. The file legitimately exists on any machine
	# where the game has been played — and on this one, because the screenshot
	# harness is a real windowed run and therefore persists like the game does.
	# So it went red for the right reason and the wrong claim. What this test
	# owns is that a test run does not TOUCH it.
	Settings.use_default_store()
	var real_file := Settings.path
	var before := _file_bytes(real_file)

	Settings.set_value(Settings.LOOK_FOV, 101.0)
	Settings.set_value(Settings.UI_LOCALE, "en")

	assert_array(_file_bytes(real_file)).override_failure_message(
		"a test run wrote %s — the next run will start from it" % real_file).is_equal(before)
	# And it still behaved: in memory, everything works as it always did.
	assert_float(Settings.get_float(Settings.LOOK_FOV)).is_equal_approx(101.0, 0.01)

	Settings.use_store(TEST_PATH)


# --- Remembering ---------------------------------------------------------------------

func test_a_choice_survives_a_reload() -> void:
	# The whole point of the work package.
	Settings.set_value(Settings.LOOK_SENSITIVITY, 0.005)
	Settings.set_value(Settings.UI_LOCALE, "en")
	Settings.forget() # as though the game had been closed and opened again

	assert_float(Settings.get_float(Settings.LOOK_SENSITIVITY)).is_equal_approx(0.005, 0.00001)
	assert_str(Settings.get_string(Settings.UI_LOCALE)).is_equal("en")


func test_resetting_forgets_the_file_too() -> void:
	Settings.set_value(Settings.LOOK_FOV, 100.0)
	Settings.reset()
	Settings.forget()
	assert_float(Settings.get_float(Settings.LOOK_FOV)).is_equal_approx(90.0, 0.01)


# --- What counts as a change ---------------------------------------------------------

func test_writing_the_same_value_is_not_a_change() -> void:
	# A slider emits value_changed on release with the number it already had.
	var heard: Array[String] = []
	var listener := func(key: String) -> void: heard.append(key)
	Settings.changed().connect(listener)

	Settings.set_value(Settings.LOOK_FOV, 100.0)
	Settings.set_value(Settings.LOOK_FOV, 100.0)
	Settings.set_value(Settings.LOOK_FOV, 100.0)

	Settings.changed().disconnect(listener)
	assert_int(heard.size()).override_failure_message(
		"one change was announced %d times" % heard.size()).is_equal(1)


func test_a_change_says_which_key() -> void:
	var heard: Array[String] = []
	var listener := func(key: String) -> void: heard.append(key)
	Settings.changed().connect(listener)
	Settings.set_value(Settings.AUDIO_MUSIC, 0.5)
	Settings.changed().disconnect(listener)
	assert_array(heard).is_equal([Settings.AUDIO_MUSIC])


# --- Applying ------------------------------------------------------------------------

func test_a_volume_moves_its_own_bus_and_nobody_elses() -> void:
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	assert_int(music).override_failure_message(
		"the project's bus layout is not loaded — this test proves nothing").is_greater_equal(0)

	Settings.set_value(Settings.AUDIO_MUSIC, 0.5)

	assert_float(AudioServer.get_bus_volume_db(music)).is_less(-1.0)
	assert_float(AudioServer.get_bus_volume_db(sfx)).override_failure_message(
		"turning the music down turned the sound effects down too"
	).is_equal_approx(0.0, 0.01)


func test_zero_is_silence_not_a_very_quiet_sound() -> void:
	# linear_to_db(0.0) is -inf, which Godot accepts and which no slider comes
	# back from cleanly.
	var music := AudioServer.get_bus_index("Music")
	Settings.set_value(Settings.AUDIO_MUSIC, 0.0)
	var db := AudioServer.get_bus_volume_db(music)
	assert_bool(is_finite(db)).override_failure_message(
		"the music bus is at %s dB, which is not a number" % db).is_true()
	assert_float(db).is_less_equal(Settings.MUTED_DB)


func test_the_locale_follows_the_setting() -> void:
	Settings.set_value(Settings.UI_LOCALE, "en")
	assert_str(TranslationServer.get_locale()).is_equal("en")


# --- The panel -----------------------------------------------------------------------

func test_the_panel_opens_showing_what_is_stored() -> void:
	Settings.set_value(Settings.LOOK_FOV, 105.0)
	var panel: SettingsPanel = await _open_panel()
	var slider: HSlider = panel._controls[Settings.LOOK_FOV]
	assert_float(slider.value).is_equal_approx(105.0, 0.01)
	assert_bool(panel.is_open()).is_true()


func test_moving_a_slider_changes_the_setting() -> void:
	var panel: SettingsPanel = await _open_panel()
	var slider: HSlider = panel._controls[Settings.AUDIO_AMBIENCE]
	slider.value = 0.25
	await get_tree().process_frame
	assert_float(Settings.get_float(Settings.AUDIO_AMBIENCE)).is_equal_approx(0.25, 0.01)


func test_refreshing_the_panel_is_not_the_player_choosing() -> void:
	# Writing slider.value emits value_changed, which would be read as a choice
	# — harmless until reset() writes a default and the slider writes it
	# straight back as an explicit one. The guard is _syncing.
	var panel: SettingsPanel = await _open_panel()
	Settings.set_value(Settings.LOOK_FOV, 105.0)
	var heard: Array[String] = []
	var listener := func(key: String) -> void: heard.append(key)
	Settings.changed().connect(listener)

	panel.refresh()
	await get_tree().process_frame

	Settings.changed().disconnect(listener)
	assert_array(heard).override_failure_message(
		"opening the panel announced changes nobody made: %s" % [heard]).is_empty()


func test_reset_puts_the_controls_back_too() -> void:
	var panel: SettingsPanel = await _open_panel()
	Settings.set_value(Settings.LOOK_FOV, 105.0)
	panel.refresh()

	panel._on_reset()
	await get_tree().process_frame

	var slider: HSlider = panel._controls[Settings.LOOK_FOV]
	assert_float(slider.value).override_failure_message(
		"the store was reset and the slider still shows the old value"
	).is_equal_approx(90.0, 0.01)


func test_every_row_has_a_translated_label() -> void:
	# A missing CSV row shows the key itself, which looks like a bug and is one.
	var panel: SettingsPanel = await _open_panel()
	for row: Dictionary in SettingsPanel.ROWS:
		if not row.has("label"):
			continue
		var key := String(row["label"])
		assert_str(TranslationServer.translate(key)).override_failure_message(
			"%s has no row in strings.csv" % key).is_not_equal(key)
	panel.close()


func test_the_panel_only_shows_settings_something_reads() -> void:
	# A switch for a setting nothing reads is a bug report from whoever flicked
	# it and watched carefully. `fx.intro` is still that: the key exists so
	# WP-5.4 has somewhere to write and nothing reads it yet.
	#
	# `look.head_bob` was in the same state until WP-5.2 made it do something,
	# and this test going red is how that arrived — which is the whole point of
	# it. The rule did not change; the world did.
	var shown: Array[String] = []
	for row: Dictionary in SettingsPanel.ROWS:
		if row.has("key"):
			shown.append(String(row["key"]))
	assert_array(shown).contains([Settings.LOOK_HEAD_BOB])
	assert_array(shown).not_contains([Settings.FX_INTRO])


# --- The player actually uses them ----------------------------------------------------

func test_the_camera_follows_the_sliders_while_they_move() -> void:
	# A slider that stores a number nothing reads is worse than no slider.
	GameSession.start_level("island_01", 7)
	var player: Player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame

	Settings.set_value(Settings.LOOK_FOV, 105.0)
	Settings.set_value(Settings.LOOK_SENSITIVITY, 0.006)
	await get_tree().process_frame

	assert_float(player.camera.fov).override_failure_message(
		"the field-of-view slider does nothing").is_equal_approx(105.0, 0.01)
	assert_float(player.mouse_sensitivity).override_failure_message(
		"the sensitivity slider does nothing").is_equal_approx(0.006, 0.00001)
	GameSession.stop_level()


func test_restarting_a_level_does_not_stack_up_listeners() -> void:
	# Settings is static and lives for the whole process, so every level that
	# builds a player adds a listener to it. Godot drops a freed object's
	# connections itself — what this pins is that Main's teardown really frees
	# the player, so an evening of restarts does not end with forty cameras
	# reacting to one slider.
	GameSession.start_level("island_01", 7)
	var baseline := Settings.changed().get_connections().size()

	for i in 3:
		var player: Player = load("res://src/game/player/player.tscn").instantiate()
		add_child(player)
		await get_tree().process_frame
		assert_int(Settings.changed().get_connections().size()).is_equal(baseline + 1)
		remove_child(player)
		player.free()
		await get_tree().process_frame

	assert_int(Settings.changed().get_connections().size()).override_failure_message(
		"three levels left %d listeners behind"
		% (Settings.changed().get_connections().size() - baseline)).is_equal(baseline)
	GameSession.stop_level()


# --- Helpers -------------------------------------------------------------------------

func _open_panel() -> SettingsPanel:
	var panel: SettingsPanel = auto_free(SettingsPanel.new())
	add_child(panel)
	await get_tree().process_frame
	panel.open()
	await get_tree().process_frame
	return panel


func _delete_settings_file() -> void:
	if FileAccess.file_exists(Settings.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))


## The file's contents, or an empty array when it is not there. Compared rather
## than hashed so a failure message could show what changed; and by content
## rather than by modification time, which has one-second resolution and would
## miss a write in the same second as the file it overwrote.
func _file_bytes(at: String) -> PackedByteArray:
	if not FileAccess.file_exists(at):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(at)
