extends GdUnitTestSuite
## WP-3.4 — "Råb på en kammerat".
##
## The thing these tests exist to pin down is the *shape* of the feature, not
## the pretty arc: the `summon` command moves the items, and the animation hangs
## off [signal GameEvents.item_summoned] rather than off the key. So the
## centrepiece here ([method test_the_arc_is_driven_by_the_event_not_the_key])
## emits that event by hand, with no input and no command anywhere near it, and
## watches the visual react. If that ever passes only because a keypress also
## happened, the feature has quietly stopped working in multiplayer and no one
## will notice until phase 4.
##
## Everything is stepped explicitly ([method SummonAnimator.advance]) instead of
## awaited, so no test depends on how many frames went by.

const SERIES := "tent_poles"
const EPSILON := 0.001

var island: Island
var player: Player
var hud: HUD
var ability: CallMateAbility
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	GameSession.autosave_enabled = false
	pid = GameSession.local_player_id()
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = false # no input processing, no mouse capture in a test
	player.player_id = pid
	add_child(player)
	# is_local = false skips the group the real local player joins; the ability
	# looks the player up there, so stand in for it explicitly.
	player.add_to_group(Player.LOCAL_GROUP)
	hud = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)
	ability = auto_free(CallMateAbility.new())
	add_child(ability)


func after_test() -> void:
	GameSession.autosave_enabled = true
	GameSession.stop_level()


# --- Helpers -----------------------------------------------------------------

func _unlock_call_mate() -> void:
	GameSession.state.progression.points = Progression.ABILITIES["call_mate"]["cost"]
	GameSession.submit(Commands.unlock(pid, "call_mate"))
	assert_bool(GameSession.progression.has("call_mate")).is_true()


func _members(series: String = SERIES) -> Array[String]:
	var out: Array[String] = []
	for def in GameSession.catalog.series_members(series):
		out.append((def as ItemDef).id)
	out.sort()
	return out


func _ground_positions(series: String = SERIES) -> Dictionary:
	var out: Dictionary = {}
	for id in _members(series):
		if GameSession.state.kind_of(id) == WorldState.Kind.GROUND:
			out[id] = GameSession.state.location(id)["position"]
	return out


func _item_node(item_id: String) -> PickupItem:
	return island.get_node("Items/Item_" + item_id)


func _stand_at(x: float, z: float) -> void:
	player.global_position = Vector3(x, island.height_at(x, z) + 0.9, z)


## An item id whose catalog entry belongs to no series at all.
func _loner() -> String:
	for id in GameSession.catalog.item_ids():
		if GameSession.catalog.get_item(id).series.is_empty() \
				and GameSession.state.kind_of(id) == WorldState.Kind.GROUND:
			return id
	return ""


# --- The arc itself, as geometry ---------------------------------------------

func test_the_arc_begins_and_ends_exactly_where_it_must() -> void:
	var from := Vector3(-4, 0.3, 7)
	var to := Vector3(1, 0.5, 1)
	# t = 1 is the position the core already committed to. A curve that only
	# gets close leaves the visual disagreeing with the world state forever.
	assert_vector(SummonArc.point(from, to, 0.0)).is_equal(from)
	assert_vector(SummonArc.point(from, to, 1.0)).is_equal(to)
	assert_vector(SummonArc.point(from, to, 2.0)).is_equal(to) # clamped, not extrapolated


func test_the_arc_goes_over_the_top_rather_than_through_the_ground() -> void:
	var from := Vector3(-4, 0.3, 7)
	var to := Vector3(1, 0.5, 1)
	var mid := SummonArc.point(from, to, 0.5)
	assert_float(mid.y).override_failure_message(
		"the item slid along the ground instead of being thrown").is_greater(maxf(from.y, to.y))


func test_a_longer_throw_is_a_higher_throw_up_to_a_ceiling() -> void:
	var near := SummonArc.height(Vector3.ZERO, Vector3(1, 0, 0))
	var far := SummonArc.height(Vector3.ZERO, Vector3(9, 0, 0))
	assert_float(near).is_equal_approx(SummonArc.MIN_HEIGHT, EPSILON)
	assert_float(far).is_greater(near)
	assert_float(SummonArc.height(Vector3.ZERO, Vector3(400, 0, 0))).override_failure_message(
		"a throw from the far shore left the frustum").is_equal_approx(SummonArc.MAX_HEIGHT, EPSILON)


func test_the_item_lands_facing_the_way_it_started() -> void:
	assert_float(SummonArc.spin(0.0)).is_equal_approx(0.0, EPSILON)
	assert_float(SummonArc.spin(1.0)).is_equal_approx(TAU, EPSILON)


# --- The central design point ------------------------------------------------

func test_the_arc_is_driven_by_the_event_not_the_key() -> void:
	# No input, no command, no ability unlocked — just the event the core would
	# have published. This is exactly the situation a remote player's shout
	# creates in phase 4, and the animation has to work in it.
	var item_id := _members()[0]
	var node := _item_node(item_id)
	var started_at := node.global_position
	var target := Vector3(2.0, 0.0, -3.0)
	GameEvents.item_summoned.emit(item_id, pid, target)

	assert_bool(ability.animator.is_flying(item_id)).override_failure_message(
		"the event alone did not start the flight — is the animation hanging off the keypress?"
	).is_true()
	ability.animator.advance(SummonArc.FLIGHT_SECONDS * 0.5)
	assert_vector(node.global_position).override_failure_message(
		"the item never left where it was lying").is_not_equal(started_at)

	ability.animator.advance(SummonArc.FLIGHT_SECONDS * 0.5)
	assert_bool(ability.animator.is_flying(item_id)).is_false()
	assert_float(node.global_position.x).is_equal_approx(target.x, EPSILON)
	assert_float(node.global_position.z).is_equal_approx(target.z, EPSILON)


func test_a_mates_shout_animates_here_too_without_claiming_to_be_ours() -> void:
	var item_id := _members()[1]
	GameEvents.item_summoned.emit(item_id, pid + 1, Vector3(1.0, 0.0, 1.0))
	assert_bool(ability.animator.is_flying(item_id)).is_true()
	assert_int(ability.shout_count()).override_failure_message(
		"someone else's shout should still be audible").is_equal(1)
	assert_array(hud.toast_texts()).override_failure_message(
		"the HUD told the player HE shouted, but it was someone else"
	).not_contains([tr("ui.ability.called")])


func test_the_flight_is_abandoned_when_someone_grabs_the_item_out_of_the_air() -> void:
	var item_id := _members()[0]
	GameEvents.item_summoned.emit(item_id, pid, Vector3(2.0, 0.0, -3.0))
	GameSession.submit(Commands.pick_up(pid, item_id))
	ability.animator.advance(SummonArc.FLIGHT_SECONDS * 0.5)
	assert_bool(ability.animator.is_flying(item_id)).override_failure_message(
		"a carried item was still being flown around by the animator").is_false()


# --- Locked ------------------------------------------------------------------

func test_locked_the_shout_moves_nothing() -> void:
	GameSession.submit(Commands.pick_up(pid, _members()[0]))
	# Snapshot AFTER the pick-up: picking an item up takes it off the ground, so
	# a baseline from before would differ for a reason that has nothing to do
	# with the shout.
	var before := _ground_positions()
	assert_dict(before).is_not_empty()
	ability.shout()
	assert_dict(_ground_positions()).override_failure_message(
		"the ability is not bought and the island moved anyway").is_equal(before)
	assert_bool(GameSession.progression.can_summon(SERIES)).override_failure_message(
		"a locked shout spent the series").is_true()
	assert_bool(hud.said(tr("ui.error.ability_locked"))).override_failure_message("the player was never told: %s" % [tr("ui.error.ability_locked")]).is_true()


# --- Unlocked ----------------------------------------------------------------

func test_every_loose_member_comes_and_the_packed_ones_stay_put() -> void:
	_unlock_call_mate()
	var members := _members()
	# One in hand (it is not on the ground, so it must not be moved either) and
	# one already packed away — the rest are what the shout is for.
	GameSession.submit(Commands.pick_up(pid, members[1]))
	GameSession.submit(Commands.place(pid, members[1], "tent_bag", 0))
	var packed := GameSession.state.location(members[1]).duplicate()
	GameSession.submit(Commands.pick_up(pid, members[0]))
	_stand_at(0.0, 0.0)

	var loose := _ground_positions().keys()
	assert_array(loose).override_failure_message(
		"nothing was left lying about to summon").is_not_empty()
	assert_bool(ability.shout()).is_true()

	assert_dict(GameSession.state.location(members[1])).override_failure_message(
		"an item that was already packed was dragged back out").is_equal(packed)
	assert_int(GameSession.state.kind_of(members[0])).override_failure_message(
		"the item in his hands was thrown on the floor").is_equal(WorldState.Kind.CARRIED)
	for id in loose:
		var pos: Vector3 = GameSession.state.location(id)["position"]
		assert_float(Vector2(pos.x, pos.z).distance_to(Vector2(0.0, 0.0))).override_failure_message(
			"%s landed %.1f m away — that is not 'at your feet'" % [id, pos.length()]
		).is_less_equal(CommandProcessor.SUMMON_RING_RADIUS + EPSILON)


func test_summoned_items_do_not_stack_on_one_point() -> void:
	_unlock_call_mate()
	GameSession.submit(Commands.pick_up(pid, _members()[0]))
	_stand_at(0.0, 0.0)
	var loose: Array = _ground_positions().keys()
	assert_int(loose.size()).is_greater(1) # otherwise this proves nothing
	ability.shout()
	for i in range(loose.size()):
		for j in range(i + 1, loose.size()):
			var a: Vector3 = GameSession.state.location(loose[i])["position"]
			var b: Vector3 = GameSession.state.location(loose[j])["position"]
			assert_float(a.distance_to(b)).override_failure_message(
				"%s and %s landed on top of each other" % [loose[i], loose[j]]).is_greater(0.1)


func test_a_second_shout_for_the_same_series_is_refused_and_moves_nothing() -> void:
	_unlock_call_mate()
	GameSession.submit(Commands.pick_up(pid, _members()[0]))
	_stand_at(0.0, 0.0)
	ability.shout()
	var after_first := _ground_positions()

	_stand_at(6.0, 6.0) # somewhere else entirely, so a second summon would show
	ability.shout()
	assert_dict(_ground_positions()).override_failure_message(
		"the series was summoned twice").is_equal(after_first)
	assert_bool(hud.said(tr("ui.error.series_already_summoned"))).override_failure_message(
		"the player was not told why nothing happened"
	).is_true()


func test_a_series_with_nothing_left_lying_about_costs_nothing() -> void:
	_unlock_call_mate()
	var members := _members()
	# Pack every member except the one he ends up holding: there is nothing left
	# to fetch. One at a time — a pole is size 2 against a capacity of 3, so
	# picking the next one up while still holding the last fails with hands_full
	# and leaves the series on the ground.
	for i in range(1, members.size()):
		GameSession.submit(Commands.pick_up(pid, members[i]))
		GameSession.submit(Commands.place(pid, members[i], "tent_bag", i))
	GameSession.submit(Commands.pick_up(pid, members[0]))
	assert_dict(_ground_positions()).override_failure_message(
		"the setup failed: something is still lying about").is_empty()
	ability.shout()
	assert_bool(hud.said(tr("ui.error.nothing_to_summon"))).override_failure_message("the player was never told: %s" % [tr("ui.error.nothing_to_summon")]).is_true()
	assert_bool(GameSession.progression.can_summon(SERIES)).override_failure_message(
		"a shout that fetched nothing still spent the series").is_true()


func test_an_item_that_belongs_to_no_series_says_so_instead_of_shouting() -> void:
	_unlock_call_mate()
	var loner := _loner()
	assert_str(loner).is_not_empty()
	GameSession.submit(Commands.pick_up(pid, loner))
	assert_bool(ability.shout()).is_false()
	assert_bool(hud.said(tr("ui.ability.no_series"))).override_failure_message("the player was never told: %s" % [tr("ui.ability.no_series")]).is_true()


func test_shouting_with_empty_hands_says_nothing_at_all() -> void:
	_unlock_call_mate()
	# Count around the shout rather than asserting an empty HUD: buying the
	# ability is itself toasted by the HUD (WP-3.1), and that message is not
	# what this test is about. What matters is that the keypress adds nothing.
	var before := hud.toast_count()
	assert_bool(ability.shout()).is_false()
	assert_int(hud.toast_count()).override_failure_message(
		"an empty-handed keypress nagged the player").is_equal(before)


# --- Where things land -------------------------------------------------------

func test_shouting_from_the_water_lands_everything_on_the_island() -> void:
	_unlock_call_mate()
	GameSession.submit(Commands.pick_up(pid, _members()[0]))
	# Far out in the lake: a client may ask for anything, so the answer has to
	# hold even then (WorldState.clamp_to_island).
	_stand_at(40.0, -25.0)
	ability.shout()
	for id in _ground_positions():
		var pos: Vector3 = GameSession.state.location(id)["position"]
		assert_float(Vector2(pos.x, pos.z).length()).override_failure_message(
			"%s was summoned into the lake" % id).is_less_equal(GameSession.island_radius() + EPSILON)


func test_nothing_is_summoned_into_a_container_or_under_the_terrain() -> void:
	_unlock_call_mate()
	GameSession.submit(Commands.pick_up(pid, _members()[0]))
	# Right up against a container — the case that makes summoned items
	# unreachable if the shout's centre is taken literally.
	var bag := GameSession.container_position("tent_bag")
	_stand_at(bag.x + 0.6, bag.z + 0.2)
	ability.shout()

	for id in _ground_positions():
		var pos: Vector3 = GameSession.state.location(id)["position"]
		for cid in GameSession.catalog.container_ids():
			var origin := GameSession.container_position(cid)
			var radius := GameSession.catalog.get_container(cid).footprint_radius()
			assert_float(Vector2(pos.x - origin.x, pos.z - origin.z).length()).override_failure_message(
				"%s landed inside %s's footprint, where you cannot pick it up" % [id, cid]
			).is_greater(radius)
		# And the visual has to end up on the grass, not inside the dome: the
		# core only knows a flat ground_y.
		ability.animator.advance(SummonArc.FLIGHT_SECONDS)
		var node := _item_node(id)
		assert_float(node.global_position.y).override_failure_message(
			"%s came to rest %.2f m under the terrain" % [id, island.height_at(pos.x, pos.z) - node.global_position.y]
		).is_greater_equal(island.height_at(pos.x, pos.z))


func test_the_visual_ends_exactly_where_the_world_state_says() -> void:
	_unlock_call_mate()
	GameSession.submit(Commands.pick_up(pid, _members()[0]))
	_stand_at(3.0, -2.0)
	ability.shout()
	ability.animator.advance(SummonArc.FLIGHT_SECONDS)
	for id in _ground_positions():
		var pos: Vector3 = GameSession.state.location(id)["position"]
		var node := _item_node(id)
		assert_float(node.global_position.x).is_equal_approx(pos.x, EPSILON)
		assert_float(node.global_position.z).is_equal_approx(pos.z, EPSILON)
		assert_float(node.rotation.y).override_failure_message(
			"the item was left spinning").is_equal_approx(0.0, 0.01)


# --- The cue -----------------------------------------------------------------

func test_the_shout_is_heard_once_per_command_not_once_per_item() -> void:
	_unlock_call_mate()
	GameSession.submit(Commands.pick_up(pid, _members()[0]))
	ability.shout()
	assert_int(GameSession.progression.summoned_series().size()).is_equal(1)
	assert_int(ability.shout_count()).override_failure_message(
		"he shouted once per paddle").is_equal(1)


func test_the_cue_is_a_one_shot_on_the_sfx_bus() -> void:
	var stream := ability.shout_player().stream as AudioStreamWAV
	assert_object(stream).is_not_null()
	assert_str(ability.shout_player().bus).is_equal("SFX")
	assert_int(stream.loop_mode).override_failure_message(
		"a looping shout is a man who never stops").is_equal(AudioStreamWAV.LOOP_DISABLED)
	# Deliberately no loop-seam test here (the snore has one): this cue is a
	# one-shot, so there is no seam, and a seam assertion that cannot fail would
	# be worse than none.
	assert_float(stream.get_length()).is_between(0.4, 2.0)


func test_the_cue_is_a_man_shouting_and_not_a_chime() -> void:
	# Read the SOURCE wav, not the imported stream: Godot compresses to QOA and
	# decoding that as PCM reads plausible-looking noise (see WavPcm).
	var pcm := WavPcm.samples(CallMateAbility.SHOUT_SFX)
	assert_int(pcm.size()).is_greater(10000)
	assert_float(absf(pcm[0])).override_failure_message("the cue starts with a click").is_less(0.02)
	assert_float(absf(pcm[pcm.size() - 1])).override_failure_message(
		"the cue ends with a click").is_less(0.02)

	# A voice has a fundamental a man can produce; the other cues in this file
	# are sine stacks at 523–1568 Hz. Measured by autocorrelation over a window
	# in the sustained middle of the shout.
	var f0 := _fundamental(pcm, int(pcm.size() * 0.25))
	assert_float(f0).override_failure_message(
		"fundamental is %.0f Hz — that is a bell, not a hungover man" % f0).is_between(90.0, 280.0)
	# And he runs out of air: the end is lower and quieter than the start.
	assert_float(_fundamental(pcm, int(pcm.size() * 0.75))).override_failure_message(
		"the pitch rose towards the end, which is a chime's shape, not a shout's").is_less(f0)
	assert_float(_rms(pcm, 0, int(pcm.size() * 0.3))).override_failure_message(
		"the shout gets louder as it goes on").is_greater(_rms(pcm, int(pcm.size() * 0.7), pcm.size()))


# --- Wording -----------------------------------------------------------------

func test_only_the_errors_this_ability_owns_get_its_wording() -> void:
	assert_str(CallMateAbility.rejection_key(CommandProcessor.E_SERIES_SPENT)) \
		.is_equal("ui.error.series_already_summoned")
	assert_str(CallMateAbility.rejection_key(CommandProcessor.E_ABILITY_LOCKED)) \
		.is_equal("ui.error.ability_locked")
	# Not ours: the HUD already words these, and inventing a key here would put
	# an untranslated id on screen.
	assert_str(CallMateAbility.rejection_key(CommandProcessor.E_HANDS_FULL)).is_empty()
	assert_str(CallMateAbility.rejection_key("")).is_empty()


func test_every_string_this_feature_shows_is_translated() -> void:
	for key in ["ui.ability.called", "ui.ability.no_series", "ui.error.ability_locked",
			"ui.error.unknown_series", "ui.error.series_already_summoned", "ui.error.nothing_to_summon"]:
		assert_str(tr(key)).override_failure_message(
			"%s has no row in strings.csv" % key).is_not_equal(key)


# --- Signal analysis helpers -------------------------------------------------

## Crude autocorrelation pitch estimate (Hz) over a window starting at
## [param from]. Only the lags a human voice can occupy are searched, which
## keeps it fast and keeps a bright harmonic from winning.
func _fundamental(pcm: PackedFloat32Array, from: int, window: int = 2048) -> float:
	var rate := 44100.0
	var min_lag := int(rate / 400.0)
	var max_lag := int(rate / 70.0)
	var last := mini(from + window, pcm.size() - max_lag)
	if last <= from:
		return 0.0
	var best_lag := min_lag
	var best := -1.0e30
	for lag in range(min_lag, max_lag):
		var sum := 0.0
		for i in range(from, last):
			sum += pcm[i] * pcm[i + lag]
		if sum > best:
			best = sum
			best_lag = lag
	return rate / float(best_lag)


func _rms(pcm: PackedFloat32Array, from: int, to: int) -> float:
	var sum := 0.0
	for i in range(from, to):
		sum += pcm[i] * pcm[i]
	return sqrt(sum / maxf(1.0, float(to - from)))
