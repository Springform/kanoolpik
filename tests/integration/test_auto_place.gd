extends GdUnitTestSuite
## WP-3.6 — Autopilot: E with nothing to aim at puts the held item in the first
## correct slot of the nearest container within 2 m.
##
## The suite is built around the one thing that can go wrong in a helpful way:
## an assist that *takes over*. So the aim-wins cases are asserted both on the
## container and on the slot, and the "nothing is correct" case asserts the
## accuracy counter as well — placing wrongly on the player's behalf would still
## look like the ability working.
##
## Presses are driven through [method Player.interact_with] rather than a
## synthesised raycast: headless Godot transports no InputEvents, and the seam
## is the same one [method Player._interact] uses.

## Two identical can coolers 2.83 m apart, so both can be in range at once —
## the only pair on Island 01 that can produce the tiebreak.
const COOLER_A := "can_cooler_1"
const COOLER_B := "can_cooler_2"
## A sealed can: correct in either cooler while its series is still untouched.
const SEALED_CAN := "sealed_tuborg_1"
## An empty can: belongs in the pant bag, nowhere else.
const EMPTY_CAN := "can_tuborg_1"
## Bread belongs in the cooler, which is nowhere near the pant bag.
const LOOSE_FOOD := "food_bread"

var island: Island
var player: Player
var ability: AutoPlaceAbility
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	GameSession.autosave_enabled = false
	pid = GameSession.local_player_id()
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = false # no input, no mouse capture, no physics walking off
	player.player_id = pid
	add_child(player)
	ability = auto_free(AutoPlaceAbility.new())
	add_child(ability)


func after_test() -> void:
	GameSession.stop_level()
	GameSession.autosave_enabled = true


# --- Helpers -----------------------------------------------------------------------

## Buy Autopilot the real way, through a command. Points are poked in because
## earning three of them would mean packing three containers first.
func _unlock() -> void:
	GameSession.state.progression.points = int(Progression.ABILITIES[AutoPlaceAbility.ABILITY_ID]["cost"])
	GameSession.submit(Commands.unlock(pid, AutoPlaceAbility.ABILITY_ID))


func _hold(item_id: String) -> void:
	GameSession.submit(Commands.pick_up(pid, item_id))


## Stand [param offset] metres from the container's own position.
func _stand_at(container_id: String, offset := Vector3.ZERO) -> void:
	player.global_position = GameSession.container_position(container_id) + offset


func _stand(x: float, z: float) -> void:
	player.global_position = Vector3(x, 0.0, z)


## One press of E with the crosshair on nothing at all.
func _press_e_at_nothing() -> void:
	player.interact_with(null, -1)


func _container(id: String) -> ContainerNode:
	return island.get_node("Containers/Container_" + id)


func _where(item_id: String) -> String:
	return GameSession.state.container_of(item_id)


func _slot_of(item_id: String) -> int:
	var loc := GameSession.state.location(item_id)
	return int(loc.get("slot", -1)) if loc.get("kind", -1) == WorldState.Kind.PLACED else -1


func _wrong_placements() -> int:
	return int(GameSession.state.stats.get("wrong_placements", 0))


func _add_hud() -> HUD:
	var hud: HUD = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)
	return hud


func _toast_texts(hud: HUD) -> Array[String]:
	var out: Array[String] = []
	for node: Node in hud.toasts_box.get_children():
		out.append((node as Label).text)
	return out


# --- Locked: E must behave exactly as it does today --------------------------------

func test_locked_a_press_at_nothing_places_nothing() -> void:
	_hold(EMPTY_CAN)
	_stand_at("pant_bag") # as close as it is possible to be
	_press_e_at_nothing()
	assert_int(GameSession.state.kind_of(EMPTY_CAN)).is_equal(WorldState.Kind.CARRIED)
	assert_str(GameSession.state.item_in_slot("pant_bag", 0)).is_equal("")


func test_locked_a_press_at_nothing_says_nothing() -> void:
	var hud := _add_hud()
	_hold(EMPTY_CAN)
	_stand_at("pant_bag")
	var before := hud.toast_count()
	_press_e_at_nothing()
	assert_int(hud.toast_count()).is_equal(before)


func test_locked_aiming_at_a_container_body_still_finds_the_correct_slot() -> void:
	# The regression that matters: interact_with() is the old _interact() body.
	_hold(EMPTY_CAN)
	player.interact_with(_container("pant_bag"), -1)
	assert_str(GameSession.state.item_in_slot("pant_bag", 0)).is_equal(EMPTY_CAN)


func test_locked_aiming_at_a_container_body_still_falls_back_to_the_first_free_slot() -> void:
	_hold(LOOSE_FOOD)
	player.interact_with(_container("canoe"), -1) # bread does not belong in a canoe
	assert_str(GameSession.state.item_in_slot("canoe", 0)).is_equal(LOOSE_FOOD)


func test_locked_aiming_at_a_pickup_still_picks_it_up() -> void:
	var item: PickupItem = island.get_node("Items/Item_" + EMPTY_CAN)
	player.interact_with(item, -1)
	assert_int(GameSession.state.kind_of(EMPTY_CAN)).is_equal(WorldState.Kind.CARRIED)


# --- Unlocked: the press that had nothing to aim at --------------------------------

func test_in_range_a_press_at_nothing_places_into_the_first_correct_slot() -> void:
	_unlock()
	_hold(EMPTY_CAN)
	_stand_at("pant_bag")
	_press_e_at_nothing()
	assert_str(_where(EMPTY_CAN)).is_equal("pant_bag")
	assert_int(_slot_of(EMPTY_CAN)).is_equal(0)
	assert_int(_container("pant_bag").slot_verdict(0)).is_equal(PlacementRules.Verdict.CORRECT)


func test_a_successful_press_names_what_it_put_away() -> void:
	_unlock()
	var hud := _add_hud() # after the purchase: buying an ability toasts too
	_hold(EMPTY_CAN)
	_stand_at("pant_bag")
	_press_e_at_nothing()
	assert_array(_toast_texts(hud)).contains(
		[tr("ui.ability.auto_placed") % tr(GameSession.catalog.get_item(EMPTY_CAN).name_key)])


func test_an_armful_empties_one_press_at_a_time() -> void:
	_unlock()
	_stand_at("pant_bag")
	for i in [1, 2, 3]:
		_hold("can_tuborg_%d" % i)
	assert_int(GameSession.state.carried_by(pid).size()).is_equal(3)
	for i in [3, 2, 1]: # active item is the last picked up
		_press_e_at_nothing()
		assert_str(_where("can_tuborg_%d" % i)).is_equal("pant_bag")
	assert_array(GameSession.state.carried_by(pid)).is_empty()


# --- Precedence: an aim is never overridden ----------------------------------------

func test_aiming_at_a_slot_beats_the_slot_autopilot_would_have_chosen() -> void:
	_unlock()
	_hold(EMPTY_CAN)
	_stand_at("pant_bag") # autopilot's answer here is slot 0
	assert_int(int(ability.choose_target(EMPTY_CAN, player.global_position)[AutoPlaceAbility.KEY_SLOT])).is_equal(0)
	player.interact_with(_container("pant_bag"), 7)
	assert_int(_slot_of(EMPTY_CAN)).is_equal(7)
	assert_str(GameSession.state.item_in_slot("pant_bag", 0)).is_equal("")


func test_aiming_at_another_container_beats_the_nearer_one() -> void:
	_unlock()
	_hold(SEALED_CAN)
	_stand_at(COOLER_A) # autopilot would take cooler A, it is 0 m away
	assert_str(String(ability.choose_target(SEALED_CAN, player.global_position)[AutoPlaceAbility.KEY_CONTAINER])).is_equal(COOLER_A)
	player.interact_with(_container(COOLER_B), 3)
	assert_str(_where(SEALED_CAN)).is_equal(COOLER_B)
	assert_int(_slot_of(SEALED_CAN)).is_equal(3)


func test_aiming_at_a_pickup_beats_autopilot() -> void:
	# Standing on the pant bag holding a can, looking at another can: the look wins.
	_unlock()
	_hold(EMPTY_CAN)
	_stand_at("pant_bag")
	player.interact_with(island.get_node("Items/Item_can_tuborg_2"), -1)
	assert_int(GameSession.state.kind_of("can_tuborg_2")).is_equal(WorldState.Kind.CARRIED)
	assert_int(GameSession.state.kind_of(EMPTY_CAN)).is_equal(WorldState.Kind.CARRIED)
	assert_str(GameSession.state.item_in_slot("pant_bag", 0)).is_equal("")


# --- Never places wrongly ----------------------------------------------------------

func test_in_range_but_nothing_correct_does_nothing_and_costs_no_accuracy() -> void:
	_unlock()
	_hold(LOOSE_FOOD)
	_stand_at("pant_bag") # in range of a container that does not take food
	var wrong_before := _wrong_placements()
	var placements_before := int(GameSession.state.stats.get("placements", 0))
	_press_e_at_nothing()
	assert_int(GameSession.state.kind_of(LOOSE_FOOD)).is_equal(WorldState.Kind.CARRIED)
	assert_str(GameSession.state.item_in_slot("pant_bag", 0)).is_equal("")
	assert_int(_wrong_placements()).is_equal(wrong_before)
	assert_int(int(GameSession.state.stats.get("placements", 0))).is_equal(placements_before)


func test_out_of_range_of_everything_does_nothing() -> void:
	_unlock()
	_hold(EMPTY_CAN)
	_stand(0.0, 0.0) # the middle of the island: no container within 2 m
	var wrong_before := _wrong_placements()
	_press_e_at_nothing()
	assert_int(GameSession.state.kind_of(EMPTY_CAN)).is_equal(WorldState.Kind.CARRIED)
	assert_int(_wrong_placements()).is_equal(wrong_before)


func test_a_press_that_could_not_act_explains_itself() -> void:
	_unlock()
	var hud := _add_hud()
	_hold(LOOSE_FOOD)
	_stand_at("pant_bag")
	_press_e_at_nothing()
	assert_array(_toast_texts(hud)).contains([tr("ui.ability.nothing_nearby")])


func test_empty_hands_stay_silent() -> void:
	_unlock()
	var hud := _add_hud()
	_stand_at("pant_bag")
	var before := hud.toast_count()
	_press_e_at_nothing()
	assert_int(hud.toast_count()).is_equal(before)


# --- Range -------------------------------------------------------------------------

func test_the_range_is_the_two_metres_game_design_promised() -> void:
	assert_float(AutoPlaceAbility.RANGE_METRES).is_equal(2.0)


func test_just_inside_the_range_places_and_just_outside_does_not() -> void:
	_unlock()
	_hold(EMPTY_CAN)
	_stand_at("pant_bag", Vector3(2.1, 0, 0))
	_press_e_at_nothing()
	assert_int(GameSession.state.kind_of(EMPTY_CAN)).is_equal(WorldState.Kind.CARRIED)
	_stand_at("pant_bag", Vector3(1.9, 0, 0))
	_press_e_at_nothing()
	assert_str(_where(EMPTY_CAN)).is_equal("pant_bag")


func test_range_is_measured_flat_so_standing_height_does_not_count() -> void:
	# Container positions are flat level data; the player's eye height must not
	# eat into the budget.
	_unlock()
	_hold(EMPTY_CAN)
	_stand_at("pant_bag", Vector3(1.9, 1.8, 0))
	_press_e_at_nothing()
	assert_str(_where(EMPTY_CAN)).is_equal("pant_bag")


# --- Two containers in range: the nearer one wins ----------------------------------

func test_two_containers_in_range_takes_the_nearer_one() -> void:
	_unlock()
	_hold(SEALED_CAN)
	_stand(5.3, -2.7) # nearer cooler 2, but cooler 1 is in range too
	assert_float(ability.distance_to(COOLER_A, player.global_position)).is_less(AutoPlaceAbility.RANGE_METRES)
	assert_float(ability.distance_to(COOLER_B, player.global_position)).is_less(
		ability.distance_to(COOLER_A, player.global_position))
	_press_e_at_nothing()
	assert_str(_where(SEALED_CAN)).is_equal(COOLER_B)


func test_the_tiebreak_is_distance_and_not_the_container_order() -> void:
	# Mirror of the test above from the other side. Sorted-first would answer
	# can_cooler_1 both times; nearest answers each side correctly.
	_unlock()
	_hold(SEALED_CAN)
	_stand(5.7, -2.3) # nearer cooler 1 now
	assert_float(ability.distance_to(COOLER_B, player.global_position)).is_less(AutoPlaceAbility.RANGE_METRES)
	assert_float(ability.distance_to(COOLER_A, player.global_position)).is_less(
		ability.distance_to(COOLER_B, player.global_position))
	_press_e_at_nothing()
	assert_str(_where(SEALED_CAN)).is_equal(COOLER_A)


# --- Ordered containers fall out of the rules --------------------------------------

func test_an_ordered_container_fills_in_sequence_across_presses() -> void:
	_unlock()
	_stand_at("tent_bag")
	for i in [1, 2, 3, 4]:
		_hold("tent_pole_%d" % i) # poles are size 2 of capacity 3: one at a time
		_press_e_at_nothing()
		GameSession.submit(Commands.tick(1))
	var bag := _container("tent_bag")
	for i in [1, 2, 3, 4]:
		assert_str(GameSession.state.item_in_slot("tent_bag", i - 1)).is_equal("tent_pole_%d" % i)
		assert_int(bag.slot_verdict(i - 1)).is_equal(PlacementRules.Verdict.CORRECT)


func test_a_pole_that_has_no_correct_slot_left_is_left_in_hand() -> void:
	# Pole 3 first, so pole 1 has nowhere correct to go: before slot 0 does not
	# exist and after it is out of order. Autopilot must refuse, not guess.
	_unlock()
	_stand_at("tent_bag")
	_hold("tent_pole_3")
	_press_e_at_nothing()
	assert_int(_slot_of("tent_pole_3")).is_equal(0)
	var wrong_before := _wrong_placements()
	_hold("tent_pole_1")
	_press_e_at_nothing()
	assert_int(GameSession.state.kind_of("tent_pole_1")).is_equal(WorldState.Kind.CARRIED)
	assert_int(_wrong_placements()).is_equal(wrong_before)


# --- Installation -------------------------------------------------------------------

func test_install_leaves_exactly_one_ability_however_often_it_runs() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var first := AutoPlaceAbility.install(host)
	assert_object(first).is_not_null()
	AutoPlaceAbility.install(host)
	assert_int(host.find_children("*", "AutoPlaceAbility", true, false).size()).is_equal(1)


func test_the_player_finds_an_installed_ability_through_the_group() -> void:
	assert_object(AutoPlaceAbility.find_in_tree(player)).is_same(ability)


func test_a_player_with_no_ability_installed_is_unharmed() -> void:
	remove_child(ability)
	_hold(EMPTY_CAN)
	_stand_at("pant_bag")
	_press_e_at_nothing() # must not crash, must not place
	assert_int(GameSession.state.kind_of(EMPTY_CAN)).is_equal(WorldState.Kind.CARRIED)
	add_child(ability) # back in the tree so auto_free can take it
