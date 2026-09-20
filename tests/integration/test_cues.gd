extends GdUnitTestSuite
## WP-5.3 — nothing is told by one channel only.
##
## A chime, a glow or a colour is a nice way to say something and a bad way to
## say it *once*. These tests pin the three places where the game was saying
## something once: the chime that climbed a semitone and told nobody, the shout
## that was audible to five people and visible to one, and six avatar colours
## walked evenly round a wheel that is not even.


func _hud() -> HUD:
	var hud: HUD = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)
	return hud


# --- The six avatar colours ----------------------------------------------------------

func test_no_two_players_are_the_same_colour_to_anybody() -> void:
	# The measurement the palette was chosen by. Ten is "a difference nobody
	# argues about"; the six that ship come out at about fourteen.
	#
	# Built from colour_for(), not from PEER_COLOURS. Asserting on the constant
	# passes happily while the function ignores it and goes back to walking the
	# wheel — a mutation run demonstrated exactly that. What a player sees is
	# what the function returns.
	var palette: Array[Color] = []
	for id in range(1, 7):
		palette.append(RemoteAvatar.colour_for(id))
	var worst := ColourVision.worst_distance(palette)
	assert_float(worst).override_failure_message(
		"the closest pair of avatar colours is deltaE %.1f to somebody" % worst
	).is_greater(10.0)


func test_the_palette_this_replaced_would_fail_that() -> void:
	# The point of the test above is that it can fail, so here is the thing it
	# fails on: six even steps round the HSV wheel, which is what shipped until
	# WP-5.3. Peers 1 and 2 land at deltaE 1.9 under protanopia — the same
	# colour. Kept as a test rather than as a sentence in a comment, because a
	# sentence cannot be run.
	var computed: Array[Color] = []
	for id in range(1, 7):
		computed.append(Color.from_hsv(fposmod(float(id) * 0.16, 1.0), 0.8, 0.9))
	assert_float(ColourVision.worst_distance(computed)).override_failure_message(
		"the old computed palette turns out to be fine, which would make this WP wrong"
	).is_less(5.0)


func test_every_peer_in_a_full_room_gets_one_of_them() -> void:
	var seen: Array[Color] = []
	for id in range(1, 7):
		var c := RemoteAvatar.colour_for(id)
		assert_bool(seen.has(c)).override_failure_message(
			"peer %d repeats a colour already handed out" % id).is_false()
		seen.append(c)
	assert_int(seen.size()).is_equal(RemoteAvatar.PEER_COLOURS.size())


func test_a_peer_id_outside_the_room_is_somebody_rather_than_a_crash() -> void:
	assert_object(RemoteAvatar.colour_for(0)).is_not_null()
	assert_object(RemoteAvatar.colour_for(99)).is_not_null()
	assert_object(RemoteAvatar.colour_for(-3)).is_not_null()


# --- Toasts with the colour taken away ------------------------------------------------

func test_your_mistake_and_somebody_elses_news_differ_without_colour() -> void:
	# The pair the WP names: "dimmed blue-grey" against "warm orange". In
	# greyscale they are two grey labels, and the only thing left is the text.
	var mine_bad := HUD.mark_for(HUD.COLOR_ERROR, true)
	var theirs := HUD.mark_for(HUD.COLOR_OTHER, false)
	assert_str(mine_bad).is_not_equal(theirs)
	assert_bool(mine_bad.is_empty()).override_failure_message(
		"your own error carries no mark, so in greyscale it is just a line of text"
	).is_false()
	assert_bool(theirs.is_empty()).is_false()


func test_a_wrong_placement_is_marked_the_same_way_the_slot_is() -> void:
	# The slot already draws VerdictStyle.MARK_WRONG. One mark, two places, so a
	# player learns it once.
	assert_str(HUD.mark_for(VerdictStyle.COLOR_WRONG, true)).contains(VerdictStyle.MARK_WRONG)


func test_good_news_of_your_own_carries_no_mark() -> void:
	# Marks are for telling things apart, not decoration. If everything is
	# marked, nothing is.
	assert_str(HUD.mark_for(HUD.COLOR_INFO, true)).is_empty()
	assert_str(HUD.mark_for(VerdictStyle.COLOR_COMPLETE, true)).is_empty()


func test_the_marks_are_characters_the_font_actually_has() -> void:
	# Godot's default font has no Dingbats or Geometric Shapes, and draws them
	# as nothing at all while every string assertion stays green. Latin-1 only.
	for mark: String in [HUD.MARK_ERROR, HUD.MARK_OTHER]:
		for i in mark.length():
			assert_int(mark.unicode_at(i)).override_failure_message(
				"the mark %s is outside Latin-1 and will draw as nothing" % mark
			).is_less(256)


func test_a_marked_toast_shows_the_mark() -> void:
	var hud := _hud()
	await get_tree().process_frame
	hud.show_toast("noget gik galt", 5.0, HUD.COLOR_ERROR)
	hud.show_toast("Spiller 2 pakkede noget", 5.0, HUD.COLOR_OTHER, false)
	var texts := hud.toast_texts()
	assert_str(texts[0]).starts_with(HUD.MARK_ERROR)
	assert_str(texts[1]).starts_with(HUD.MARK_OTHER)


# --- The streak that only the chime knew about ----------------------------------------

func test_a_run_climbs_and_a_pause_ends_it() -> void:
	var streak := PlacementStreak.new()
	assert_int(streak.advance(10.0)).is_equal(0) # the first is not yet a run
	assert_int(streak.advance(10.5)).is_equal(1)
	assert_int(streak.advance(11.0)).is_equal(2)
	assert_int(streak.advance(11.0 + PlacementStreak.WINDOW_SECONDS + 0.1)).override_failure_message(
		"a pause longer than the window did not end the run").is_equal(0)


func test_a_run_stops_climbing_so_the_chime_stays_musical() -> void:
	var streak := PlacementStreak.new()
	var at := 0.0
	for _i in 40:
		at += 0.2
		streak.advance(at)
	assert_int(streak.steps).is_equal(PlacementStreak.MAX_STEPS)
	# Seven semitones is a fifth. Above that it stops sounding like a reward.
	assert_float(streak.pitch_scale()).is_between(1.0, 1.6)


func test_a_wrong_placement_ends_a_run() -> void:
	var streak := PlacementStreak.new()
	streak.advance(1.0)
	streak.advance(1.2)
	streak.broken()
	assert_int(streak.steps).is_equal(0)
	assert_float(streak.pitch_scale()).is_equal_approx(1.0, 0.0001)


func test_a_run_is_only_said_out_loud_once_it_is_one() -> void:
	var streak := PlacementStreak.new()
	streak.advance(1.0)
	assert_bool(streak.worth_showing()).override_failure_message(
		"one correct placement was announced as a run").is_false()
	streak.advance(1.2)
	assert_bool(streak.worth_showing()).is_false()
	streak.advance(1.4)
	assert_bool(streak.worth_showing()).override_failure_message(
		"three in a row is a run and should be said").is_true()
	assert_int(streak.run_length()).is_equal(3)


func test_the_number_on_screen_is_the_number_the_chime_is_playing() -> void:
	# One counter. The old code kept it per container, so the pitch and any
	# number would have disagreed the moment somebody used two containers.
	var hud := _hud()
	await get_tree().process_frame
	var streak := hud.streak()
	streak.advance(100.0)
	streak.advance(100.2)
	streak.advance(100.4)
	assert_int(streak.run_length()).is_equal(3)
	assert_float(streak.pitch_scale()).is_equal_approx(pow(2.0, 2.0 / 12.0), 0.0001)


func test_a_run_that_goes_quiet_expires_on_its_own() -> void:
	# It can end with nobody doing anything, and silence fires no event.
	var streak := PlacementStreak.new()
	streak.advance(5.0)
	streak.advance(5.2)
	assert_bool(streak.expired(5.3)).is_false()
	assert_bool(streak.expired(5.2 + PlacementStreak.WINDOW_SECONDS + 0.1)).is_true()


# --- What the ear knew and the eye did not --------------------------------------------

func test_a_mates_shout_is_written_down_as_well_as_heard() -> void:
	# The shout plays for everybody within sixty metres and used to toast only
	# for the shouter. Muted, or simply unable to hear it, you had a mate
	# hauling a whole series across the camp in secret.
	assert_bool(_csv_has("ui.multi.called")).override_failure_message(
		"there is no string for somebody else's shout").is_true()


func test_a_run_has_something_to_say_in_both_languages() -> void:
	assert_bool(_csv_has("ui.cue.streak")).is_true()


func _csv_has(key: String) -> bool:
	var text := FileAccess.get_file_as_string("res://assets/i18n/strings.csv")
	for line: String in text.split("\n"):
		if line.begins_with(key + ","):
			# key,da,en — three columns, none of them empty.
			var columns := line.split(",")
			return columns.size() >= 3 and not columns[1].strip_edges().is_empty() \
				and not columns[2].strip_edges().is_empty()
	return false
