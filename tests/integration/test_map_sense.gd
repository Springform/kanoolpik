extends GdUnitTestSuite
## WP-3.3 — Stedsans: an arrow toward the container the held item belongs in.
##
## Two things are being proved here, and they are proved separately on purpose.
##
## *Which* container is [PlacementRules]' answer, so the interesting cases are the
## ones where a naive "first container that accepts the category" would be wrong:
## two beer coolers both take sealed cans, and a sibling already in one of them
## settles it. `island_01` ships exactly that pair — `can_cooler_1` at (6.5, 0,
## -1.5) and `can_cooler_2` at (4.5, 0, -3.5) — which is why the cans, and not the
## tent poles, do most of the work below.
##
## *Which way* is geometry, and it is checked as an angle in radians computed by
## hand from a camera transform written down in the test. "It looked right" is not
## available to a headless suite and would not be worth much if it were.

## Both of these accept `can_sealed`, and nothing else does.
const COOLER_A := "can_cooler_1" # (6.5, 0, -1.5)
const COOLER_B := "can_cooler_2" # (4.5, 0, -3.5)
## Head height, east of both coolers and unambiguously nearer COOLER_A: 2.7 m
## against 5.2 m, so "the nearer one" is not a coin toss this test could win by
## accident.
const EYE_BY_A := Vector3(8.0, 1.6, 0.0)
## Six sealed Tuborg, one series, all on the ground at the start of island_01.
const CAN := "sealed_tuborg_1"
const CAN_SIBLING := "sealed_tuborg_2"
## A can of a *different* series, so the series rule can be told apart from the
## category rule.
const OTHER_CAN := "sealed_carlsberg_1"
## No series, one possible home (trash_bag) — the boring case, for contrast.
const LONER := "napkins"

var ability: MapSenseAbility
var camera: Camera3D
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	GameSession.autosave_enabled = false
	pid = GameSession.local_player_id()
	ability = auto_free(MapSenseAbility.new())
	add_child(ability)
	# The ability reads the local player's camera; there is no player in this
	# suite, so it gets one whose transform the test wrote down itself.
	camera = auto_free(Camera3D.new())
	add_child(camera)
	ability.camera_override = camera


func after_test() -> void:
	GameSession.stop_level()
	GameSession.autosave_enabled = true


# --- Helpers -----------------------------------------------------------------------

## Buy Stedsans. Nothing else buys anything, so no test below has to reason about
## the HUD's purchase toast — except by attaching the HUD afterwards.
func _unlock() -> void:
	GameSession.state.progression.points = 3
	GameSession.submit(Commands.unlock(pid, MapSenseAbility.ABILITY_ID))


func _hold(item_id: String) -> void:
	GameSession.submit(Commands.pick_up(pid, item_id))


func _pack(item_id: String, container_id: String) -> void:
	_hold(item_id)
	var slot := PlacementRules.find_correct_slot(
		GameSession.catalog, GameSession.state, item_id, container_id)
	assert_int(slot).override_failure_message(
		"%s should have a correct slot in %s for this test to mean anything"
			% [item_id, container_id]).is_greater_equal(0)
	GameSession.submit(Commands.place(pid, item_id, container_id, slot))


func _add_hud() -> HUD:
	var hud: HUD = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)
	return hud


func _positions() -> Dictionary:
	var out: Dictionary = {}
	for cid: String in GameSession.catalog.container_ids():
		out[cid] = GameSession.container_position(cid)
	return out


## Ask the selection rule directly, from a given standing position.
func _target_from(item_id: String, from: Vector3, current: String = "") -> String:
	return MapSenseAbility.correct_container(
		GameSession.catalog, GameSession.state, item_id, _positions(), from, current)


## Put the camera at [param where] looking down -Z (Godot's default facing), and
## let the ability answer for it.
func _look_from(where: Vector3) -> void:
	camera.global_transform = Transform3D(Basis.IDENTITY, where)
	ability.refresh()


## Stand at [param where] and look at [param at].
func _look_at_from(where: Vector3, at: Vector3) -> void:
	camera.global_transform = Transform3D(Basis.IDENTITY, where).looking_at(at, Vector3.UP)
	ability.refresh()


# --- Locked ------------------------------------------------------------------------

func test_a_locked_toggle_does_nothing_at_all() -> void:
	var hud := _add_hud()
	_hold(CAN)
	assert_bool(GameSession.progression.has(MapSenseAbility.ABILITY_ID)).is_false()
	ability.toggle()
	assert_bool(ability.is_enabled()).is_false()
	assert_str(ability.target_container()).is_empty()
	assert_object(ability.arrow).is_null()
	# "Nothing at all" includes saying nothing — not even that it is locked.
	assert_array(hud.toast_texts()).is_empty()


func test_a_locked_toggle_does_nothing_even_when_the_key_is_pressed() -> void:
	var hud := _add_hud()
	_hold(CAN)
	assert_bool(_press_c()).is_true() # the key is consumed…
	assert_bool(ability.is_enabled()).is_false() # …and still nothing happens
	assert_array(hud.toast_texts()).is_empty()


func test_nothing_happens_once_the_level_has_stopped() -> void:
	_unlock()
	_hold(CAN)
	GameSession.stop_level()
	ability.toggle()
	assert_bool(ability.is_enabled()).is_false()


# --- The toggle ----------------------------------------------------------------------

func test_the_toggle_turns_the_sense_on_and_then_off_again() -> void:
	_unlock()
	# The HUD is attached *after* the purchase: WP-3.1 makes it toast every
	# ability_unlocked, and that toast is not this test's business.
	var hud := _add_hud()
	_hold(CAN)

	ability.toggle()
	assert_bool(ability.is_enabled()).is_true()
	assert_array(hud.toast_texts()).contains([tr("ui.ability.map_sense_on")])

	ability.toggle()
	assert_bool(ability.is_enabled()).is_false()
	assert_array(hud.toast_texts()).contains([tr("ui.ability.map_sense_off")])


func test_it_is_a_toggle_and_not_a_hold() -> void:
	# Stated as a test because the alternative — a hold — is the obvious way to
	# build it, and WP-3.3 argues at length for the other one.
	_unlock()
	_hold(CAN)
	assert_bool(_press_c()).is_true()
	assert_bool(ability.is_enabled()).is_true()
	# The key going up is not the ability's business; it stays on.
	var released := InputEventAction.new()
	released.action = MapSenseAbility.INPUT_ACTION
	released.pressed = false
	assert_bool(ability.handle_input(released)).is_false()
	assert_bool(ability.is_enabled()).is_true()


func test_the_ability_is_bound_to_its_own_input_action() -> void:
	assert_str(MapSenseAbility.INPUT_ACTION).is_equal("ability_map_sense")
	assert_bool(InputMap.has_action(MapSenseAbility.INPUT_ACTION)).is_true()
	_unlock()
	# Any other key is none of this node's business.
	var other := InputEventAction.new()
	other.action = "jump"
	other.pressed = true
	assert_bool(ability.handle_input(other)).is_false()
	assert_bool(ability.is_enabled()).is_false()


# --- Which container: the easy case ----------------------------------------------------

func test_it_points_at_the_one_container_that_takes_the_item() -> void:
	# A tent pole has exactly one home, so there is nothing to choose between.
	assert_int(GameSession.catalog.containers_accepting("tent_pole").size()).is_equal(1)
	assert_str(_target_from("tent_pole_1", Vector3.ZERO)).is_equal("tent_bag")


func test_empty_hands_have_no_container_to_point_at() -> void:
	assert_str(_target_from("", Vector3.ZERO)).is_empty()


# --- Which container: two eligible ------------------------------------------------------

func test_two_eligible_containers_and_the_nearer_one_wins() -> void:
	# The premise: both coolers really are correct homes for this can right now.
	assert_int(PlacementRules.find_correct_slot(
		GameSession.catalog, GameSession.state, CAN, COOLER_A)).is_greater_equal(0)
	assert_int(PlacementRules.find_correct_slot(
		GameSession.catalog, GameSession.state, CAN, COOLER_B)).is_greater_equal(0)

	# Standing on top of cooler 1 …
	assert_str(_target_from(CAN, GameSession.container_position(COOLER_A) + Vector3(0.5, 1.6, 0.0))
		).is_equal(COOLER_A)
	# … and on top of cooler 2. Same can, same world, different answer.
	assert_str(_target_from(CAN, GameSession.container_position(COOLER_B) + Vector3(0.5, 1.6, 0.0))
		).is_equal(COOLER_B)


func test_a_sibling_already_placed_beats_the_nearer_container() -> void:
	# One Tuborg goes into the *far* cooler …
	_pack(CAN_SIBLING, COOLER_B)
	assert_str(GameSession.state.container_of(CAN_SIBLING)).is_equal(COOLER_B)
	# … which is precisely what makes the near one wrong: the series may not split.
	assert_int(PlacementRules.evaluate(GameSession.catalog, GameSession.state,
		CAN, COOLER_A, 0)).is_equal(PlacementRules.Verdict.SPLIT_SERIES)

	# Standing right on the near cooler, the arrow still sends you to the far one.
	var beside_the_near_one := GameSession.container_position(COOLER_A) + Vector3(0.5, 1.6, 0.0)
	assert_str(_target_from(CAN, beside_the_near_one)).override_failure_message(
		"a placed sibling decides the container, however near the other one is"
		).is_equal(COOLER_B)

	# And a can of a different series is not dragged along with it: nothing of
	# *its* series is placed, so proximity decides again.
	assert_str(GameSession.catalog.get_item(OTHER_CAN).series).is_not_equal(
		GameSession.catalog.get_item(CAN).series)
	assert_str(_target_from(OTHER_CAN, beside_the_near_one)).is_equal(COOLER_A)


func test_the_arrow_sticks_to_its_container_rather_than_twitching_between_two() -> void:
	# Halfway between the coolers, a hair nearer cooler 2. Already pointing at
	# cooler 1, that is not enough of a difference to justify swapping.
	var a := GameSession.container_position(COOLER_A)
	var b := GameSession.container_position(COOLER_B)
	var middle := a.lerp(b, 0.51)
	assert_str(_target_from(CAN, middle, COOLER_A)).is_equal(COOLER_A)
	# Walk properly over to cooler 2 and it does swap.
	assert_str(_target_from(CAN, b + Vector3(0.2, 0, 0), COOLER_A)).is_equal(COOLER_B)


func test_a_full_container_still_gets_pointed_at_when_the_series_lives_there() -> void:
	# Fill cooler 2 with the six Tuborg but one, so the last can has nowhere
	# CORRECT left to go — and the answer is still "over there, with the others".
	for i in range(2, 7):
		_pack("sealed_tuborg_%d" % i, COOLER_B)
	_pack(OTHER_CAN, COOLER_B) # the sixth and last slot
	assert_int(PlacementRules.find_correct_slot(
		GameSession.catalog, GameSession.state, CAN, COOLER_B)).is_equal(-1)
	assert_str(_target_from(CAN, Vector3.ZERO)).is_equal(COOLER_B)


# --- Which item ---------------------------------------------------------------------------

func test_carrying_several_things_points_at_the_active_one() -> void:
	_unlock()
	_hold(LONER) # trash → trash_bag, the other side of the island
	_hold(CAN)   # last picked up, so this is what `place` would act on
	assert_array(GameSession.state.carried_by(pid)).contains_exactly([LONER, CAN])
	ability.set_enabled(true)
	_look_from(EYE_BY_A)
	assert_str(ability.target_container()).override_failure_message(
		"the arrow follows the active item, not the first thing picked up").is_equal(COOLER_A)
	# Put the can down and the napkins become the active item again.
	GameSession.submit(Commands.drop(pid, CAN, EYE_BY_A))
	ability.refresh()
	assert_str(ability.target_container()).is_equal("trash_bag")


# --- Which way: the angle ------------------------------------------------------------------

func test_the_screen_direction_is_the_offset_from_the_centre_of_the_view() -> void:
	# Camera at the origin looking down -Z, Godot's default facing.
	var view := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	# 45° to the right and level: straight right on screen, which is angle 0.
	assert_float(MapSenseAbility.screen_direction(view, Vector3(5, 0, -5)).angle()
		).is_equal_approx(0.0, 0.0001)
	# 45° to the left: straight left, angle PI (atan2 gives -PI or PI; compare the
	# vector, not the number, so the sign of a half-turn cannot make it flake).
	assert_vector(MapSenseAbility.screen_direction(view, Vector3(-5, 0, -5))
		).is_equal_approx(Vector2.LEFT, Vector2.ONE * 0.0001)
	# Screen space has y pointing *down*, so a container below eye level is "down".
	assert_vector(MapSenseAbility.screen_direction(
		Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), Vector3(0, 0, -4))
		).is_equal_approx(Vector2.DOWN, Vector2.ONE * 0.0001)
	# Something behind you reads as "turn around", not as "dead ahead".
	assert_vector(MapSenseAbility.screen_direction(
		Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)), Vector3(0, 0, 6))
		).is_equal_approx(Vector2.DOWN, Vector2.ONE * 0.0001)


func test_the_screen_direction_turns_with_the_camera() -> void:
	# Yawed a quarter turn: the camera now faces -X, so its right hand points at
	# -Z, and a container sitting at -Z is straight out to the right.
	var yawed := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	assert_vector(MapSenseAbility.screen_direction(yawed, Vector3(0, 0, -5))
		).is_equal_approx(Vector2.RIGHT, Vector2.ONE * 0.0001)
	assert_vector(MapSenseAbility.screen_direction(yawed, Vector3(0, 0, 5))
		).is_equal_approx(Vector2.LEFT, Vector2.ONE * 0.0001)


func test_the_arrow_on_screen_points_at_the_container_by_angle() -> void:
	_unlock()
	var hud := _add_hud()
	_hold(CAN)
	ability.set_enabled(true)
	# A camera at head height on the island, looking down -Z.
	var eye := EYE_BY_A
	_look_from(eye)
	assert_str(ability.target_container()).is_equal(COOLER_A)

	# Worked out here rather than asked of the code under test: the camera's basis
	# is the identity, so the container's offset in camera space is simply
	# target - eye, and screen y runs downwards.
	var offset := GameSession.container_position(COOLER_A) - eye
	var expected := atan2(-offset.y, offset.x)
	assert_float(ability.arrow.rotation).override_failure_message(
		"the arrow should point at %s, %.4f rad, not %.4f rad"
			% [COOLER_A, expected, ability.arrow.rotation]).is_equal_approx(expected, 0.001)
	assert_bool(ability.arrow.is_showing()).is_true()
	assert_object(ability.arrow.get_parent()).is_same(hud.ability_layer())

	# The arrow sits on a ring around the crosshair, on the same bearing.
	var area := ability.arrow.screen_area()
	var from_centre := ability.arrow.centre() - area * 0.5
	assert_float(from_centre.angle()).is_equal_approx(expected, 0.001)
	assert_float(from_centre.length()).is_equal_approx(
		minf(area.x, area.y) * MapSenseArrow.RING_FRACTION, 0.5)


func test_the_arrow_turns_the_other_way_for_the_other_cooler() -> void:
	# The same scene, one sibling placed, and the arrow must swing across the
	# screen. This is the case that catches an arrow hard-wired to the first
	# container in the catalog.
	_unlock()
	_add_hud()
	_pack(CAN_SIBLING, COOLER_B)
	_hold(CAN)
	ability.set_enabled(true)
	# Due south of cooler 1 and looking north (-Z), so cooler 1 is dead ahead and
	# cooler 2 is off to the left. An arrow that quietly settled on the wrong one
	# would point up the middle of the screen instead.
	var eye := Vector3(6.5, 1.6, 4.0)
	_look_from(eye)
	assert_str(ability.target_container()).is_equal(COOLER_B)
	var offset := GameSession.container_position(COOLER_B) - eye
	assert_float(ability.arrow.rotation).is_equal_approx(atan2(-offset.y, offset.x), 0.001)
	assert_float(ability.arrow.direction.x).is_less(0.0)


# --- Which way: the fade -------------------------------------------------------------------

func test_the_arrow_fades_out_as_the_container_comes_into_view() -> void:
	var inner := deg_to_rad(MapSenseAbility.FADE_INNER_DEGREES)
	var outer := deg_to_rad(MapSenseAbility.FADE_OUTER_DEGREES)
	assert_float(MapSenseAbility.fade_alpha(0.0)).is_equal(0.0)
	assert_float(MapSenseAbility.fade_alpha(inner)).is_equal(0.0)
	assert_float(MapSenseAbility.fade_alpha((inner + outer) * 0.5)).is_equal_approx(0.5, 0.0001)
	assert_float(MapSenseAbility.fade_alpha(outer)).is_equal(1.0)
	assert_float(MapSenseAbility.fade_alpha(PI)).is_equal(1.0) # dead behind you


func test_the_off_axis_angle_is_measured_from_where_the_camera_looks() -> void:
	var view := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	assert_float(MapSenseAbility.off_axis_angle(view, Vector3(0, 0, -5))).is_equal_approx(0.0, 0.0001)
	assert_float(MapSenseAbility.off_axis_angle(view, Vector3(5, 0, -5))
		).is_equal_approx(PI * 0.25, 0.0001)
	assert_float(MapSenseAbility.off_axis_angle(view, Vector3(0, 0, 5))).is_equal_approx(PI, 0.0001)


func test_looking_straight_at_the_container_puts_the_arrow_away() -> void:
	_unlock()
	_add_hud()
	_hold(CAN)
	ability.set_enabled(true)
	var eye := EYE_BY_A
	var cooler := GameSession.container_position(COOLER_A)

	_look_from(eye)
	assert_bool(ability.arrow.is_showing()).is_true() # well off to the side

	_look_at_from(eye, cooler)
	assert_str(ability.target_container()).is_equal(COOLER_A) # still knows where
	assert_bool(ability.arrow.is_showing()).override_failure_message(
		"the container is in the crosshair; there is nothing left to point out"
		).is_false()

	# Turn a little off it and the arrow comes back rather than blinking on.
	var away := Transform3D(Basis.IDENTITY, eye).looking_at(cooler, Vector3.UP)
	camera.global_transform = away.rotated_local(Vector3.UP, deg_to_rad(12.0))
	ability.refresh()
	assert_float(ability.arrow.modulate.a).is_between(0.05, 0.95)


# --- Nothing to point at -------------------------------------------------------------------

func test_empty_hands_get_no_arrow() -> void:
	_unlock()
	_add_hud()
	ability.set_enabled(true)
	_look_from(EYE_BY_A)
	assert_str(ability.target_container()).is_empty()
	assert_bool(ability.arrow.is_showing()).is_false()


func test_turning_it_off_takes_the_arrow_off_the_screen() -> void:
	_unlock()
	_add_hud()
	_hold(CAN)
	ability.set_enabled(true)
	_look_from(EYE_BY_A)
	assert_bool(ability.arrow.is_showing()).is_true()
	ability.set_enabled(false)
	assert_bool(ability.arrow.is_showing()).is_false()
	assert_str(ability.target_container()).is_empty()


func test_placing_the_held_item_stops_the_arrow_pointing_at_it() -> void:
	_unlock()
	_add_hud()
	_hold(CAN)
	ability.set_enabled(true)
	_look_from(EYE_BY_A)
	assert_str(ability.target_container()).is_equal(COOLER_A)
	var slot := PlacementRules.find_correct_slot(
		GameSession.catalog, GameSession.state, CAN, COOLER_A)
	GameSession.submit(Commands.place(pid, CAN, COOLER_A, slot))
	ability.refresh()
	assert_str(ability.target_container()).is_empty()
	assert_bool(ability.arrow.is_showing()).is_false()


func test_a_new_level_puts_the_arrow_away() -> void:
	_unlock()
	_add_hud()
	_hold(CAN)
	ability.set_enabled(true)
	_look_from(EYE_BY_A)
	assert_bool(ability.arrow.is_showing()).is_true()
	GameEvents.level_loaded.emit("island_01")
	assert_str(ability.target_container()).is_empty()
	assert_bool(ability.arrow.is_showing()).is_false()


# --- Wiring and teardown ---------------------------------------------------------------------

func test_installing_twice_leaves_exactly_one_ability_node() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var first := MapSenseAbility.install(host)
	assert_bool(is_instance_valid(first)).is_true()
	MapSenseAbility.install(host)
	assert_int(host.find_children("*", "MapSenseAbility", true, false).size()).is_equal(1)
	assert_bool(is_instance_valid(first)).is_false()


func test_the_arrow_does_not_survive_the_ability_being_freed() -> void:
	_unlock()
	var hud := _add_hud()
	_hold(CAN)
	ability.set_enabled(true)
	_look_from(EYE_BY_A)
	var overlay := ability.arrow
	assert_bool(is_instance_valid(overlay)).is_true()

	# Main frees its abilities before it frees the HUD, so the arrow has to be
	# taken off the layer by the ability itself — and freed, not queued: a queued
	# node is still an orphan when gdUnit4 counts them.
	remove_child(ability)
	ability.free()
	ability = null
	assert_bool(is_instance_valid(overlay)).is_false()
	assert_int(hud.ability_layer().get_child_count()).is_equal(0)


func test_it_survives_the_hud_being_torn_down_under_it() -> void:
	_unlock()
	var hud := _add_hud()
	_hold(CAN)
	ability.set_enabled(true)
	_look_from(EYE_BY_A)
	assert_bool(ability.arrow.is_showing()).is_true()
	remove_child(hud)
	hud.free()
	# The arrow went with the HUD; asking again must neither crash nor resurrect it.
	ability.refresh()
	assert_object(ability.arrow).is_null()
	# A new HUD gets a new arrow.
	var replacement := _add_hud()
	ability.refresh()
	assert_object(ability.arrow).is_not_null()
	assert_object(ability.arrow.get_parent()).is_same(replacement.ability_layer())


# --- Private -----------------------------------------------------------------------------------

## Hand the ability the event the C key produces. Godot does not transport
## InputEvents in headless mode, so pushing one into the viewport would prove
## nothing — this goes through the same entry point _unhandled_input uses.
func _press_c() -> bool:
	var event := InputEventAction.new()
	event.action = MapSenseAbility.INPUT_ACTION
	event.pressed = true
	return ability.handle_input(event)
