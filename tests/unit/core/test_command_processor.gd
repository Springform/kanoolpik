extends GdUnitTestSuite

const V := PlacementRules.Verdict

var cat: Catalog
var state: WorldState
var proc: CommandProcessor


func before_test() -> void:
	cat = TestFixtures.catalog()
	state = TestFixtures.ground_state(cat, 4)
	proc = CommandProcessor.new(cat)


func test_unknown_command_type_fails() -> void:
	var r := proc.apply(state, {"type": "dance", "player_id": 1})
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_UNKNOWN_TYPE)


func test_pick_up_moves_item_to_hands_and_emits_event() -> void:
	var r := proc.apply(state, Commands.pick_up(1, "can_a1"))
	assert_bool(r["ok"]).is_true()
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.CARRIED)
	assert_array(state.carried_by(1)).contains_exactly(["can_a1"])
	assert_int(r["events"].size()).is_equal(1)
	assert_str(r["events"][0]["type"]).is_equal("item_picked_up")
	assert_int(state.stats["pickups"]).is_equal(1)


func test_pick_up_rejects_unknown_player_or_item() -> void:
	assert_str(proc.apply(state, Commands.pick_up(99, "can_a1"))["error"]).is_equal(CommandProcessor.E_UNKNOWN_PLAYER)
	assert_str(proc.apply(state, Commands.pick_up(1, "ghost"))["error"]).is_equal(CommandProcessor.E_UNKNOWN_ITEM)


func test_pick_up_rejects_item_not_on_ground() -> void:
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.pick_up(1, "can_a1"))
	assert_str(r["error"]).is_equal(CommandProcessor.E_NOT_ON_GROUND)


func test_capacity_counts_item_size() -> void:
	# capacity 4: two poles (size 2 each) fill the hands.
	assert_bool(proc.apply(state, Commands.pick_up(1, "pole_1"))["ok"]).is_true()
	assert_bool(proc.apply(state, Commands.pick_up(1, "pole_2"))["ok"]).is_true()
	var r := proc.apply(state, Commands.pick_up(1, "can_a1"))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_HANDS_FULL)
	assert_int(proc.carried_load(state, 1)).is_equal(4)


func test_drop_puts_item_back_on_ground_at_position() -> void:
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.drop(1, "can_a1", Vector3(1, 0, 2)))
	assert_bool(r["ok"]).is_true()
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.GROUND)
	assert_vector(state.location("can_a1")["position"]).is_equal(Vector3(1, 0, 2))


func test_drop_requires_carrying() -> void:
	var r := proc.apply(state, Commands.drop(1, "can_a1", Vector3.ZERO))
	assert_str(r["error"]).is_equal(CommandProcessor.E_NOT_CARRIED)


func test_place_correct_emits_verdict() -> void:
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.place(1, "can_a1", "pant_bag", 0))
	assert_bool(r["ok"]).is_true()
	assert_int(r["verdict"]).is_equal(V.CORRECT)
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.PLACED)
	assert_int(state.stats["placements"]).is_equal(1)
	assert_int(state.stats["wrong_placements"]).is_equal(0)


func test_wrong_placement_is_allowed_but_counted() -> void:
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.place(1, "can_a1", "cooler", 0))
	assert_bool(r["ok"]).is_true()
	assert_int(r["verdict"]).is_equal(V.WRONG_CATEGORY)
	assert_int(state.stats["wrong_placements"]).is_equal(1)
	assert_str(state.container_of("can_a1")).is_equal("cooler")


func test_place_into_occupied_slot_is_rejected() -> void:
	state.set_placed("can_b1", "pant_bag", 0)
	proc.apply(state, Commands.pick_up(1, "can_a1"))
	var r := proc.apply(state, Commands.place(1, "can_a1", "pant_bag", 0))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_BAD_SLOT)
	assert_int(r["verdict"]).is_equal(V.SLOT_OCCUPIED)
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.CARRIED)


func test_place_emits_container_completed() -> void:
	proc.apply(state, Commands.pick_up(1, "food_bread"))
	var r := proc.apply(state, Commands.place(1, "food_bread", "cooler", 0))
	var types: Array = r["events"].map(func(e): return e["type"])
	# The skill point is credited in the same transaction since ADR 0010.
	assert_array(types).contains_exactly(["item_placed", "container_completed", "points_awarded"])


func test_place_emits_island_clean_on_last_item() -> void:
	var placements := [
		["can_a1", "pant_bag", 0], ["can_a2", "pant_bag", 1], ["can_b1", "pant_bag", 2],
		["pole_1", "tent_bag", 0], ["pole_2", "tent_bag", 1], ["pole_3", "tent_bag", 2],
		["peg_1", "tent_bag", 3], ["peg_2", "tent_bag", 4], ["food_bread", "cooler", 0],
	]
	var last: Dictionary = {}
	for p in placements:
		assert_bool(proc.apply(state, Commands.pick_up(1, p[0]))["ok"]).is_true()
		last = proc.apply(state, Commands.place(1, p[0], p[1], p[2]))
		assert_bool(last["ok"]).is_true()
	var types: Array = last["events"].map(func(e): return e["type"])
	assert_array(types).contains("island_clean")


func test_take_out_returns_item_to_hands() -> void:
	state.set_placed("can_a1", "cooler", 0)
	var r := proc.apply(state, Commands.take_out(1, "can_a1"))
	assert_bool(r["ok"]).is_true()
	assert_str(r["events"][0]["container_id"]).is_equal("cooler")
	assert_int(state.kind_of("can_a1")).is_equal(WorldState.Kind.CARRIED)


func test_take_out_requires_placed_item_and_capacity() -> void:
	assert_str(proc.apply(state, Commands.take_out(1, "can_a1"))["error"]).is_equal(CommandProcessor.E_NOT_PLACED)
	state.set_placed("pole_1", "tent_bag", 0)
	state.set_player_capacity(1, 1)
	assert_str(proc.apply(state, Commands.take_out(1, "pole_1"))["error"]).is_equal(CommandProcessor.E_HANDS_FULL)


func test_tick_advances_clock() -> void:
	proc.apply(state, Commands.tick(60))
	proc.apply(state, Commands.tick())
	assert_int(state.elapsed_ticks).is_equal(61)


func test_same_commands_produce_identical_states() -> void:
	# Determinism is the foundation of host/client agreement in multiplayer.
	var cmds := [
		Commands.pick_up(1, "can_a1"), Commands.place(1, "can_a1", "pant_bag", 3),
		Commands.pick_up(1, "pole_2"), Commands.place(1, "pole_2", "tent_bag", 2),
		Commands.pick_up(1, "pole_1"), Commands.place(1, "pole_1", "tent_bag", 4), # wrong order
		Commands.tick(120),
	]
	var a := TestFixtures.ground_state(cat)
	var b := TestFixtures.ground_state(cat)
	for c in cmds:
		proc.apply(a, c)
		proc.apply(b, c)
	assert_dict(a.to_dict()).is_equal(b.to_dict())
	assert_int(a.stats["wrong_placements"]).is_equal(1)


# --- Progression through the processor (WP-3.0 / ADR 0010) -------------------

## Fill the cooler so the container completes and the point is credited.
func _complete_the_cooler() -> Dictionary:
	state.set_carried("food_bread", 1)
	return proc.apply(state, Commands.place(1, "food_bread", "cooler", 0))


func _event_types(result: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for e in result["events"]:
		out.append(String(e["type"]))
	return out


func test_completing_a_container_awards_a_point_in_the_same_transaction() -> void:
	var r := _complete_the_cooler()
	assert_array(_event_types(r)).contains(["container_completed", "points_awarded"])
	assert_int(state.progression.available_points()).is_equal(1)
	for e in r["events"]:
		if e["type"] == "points_awarded":
			assert_int(e["total_available"]).is_equal(1)
			assert_str(e["container_id"]).is_equal("cooler")


func test_re_completing_a_container_awards_nothing() -> void:
	_complete_the_cooler()
	# Take it out and put it straight back: complete again, already credited.
	proc.apply(state, Commands.take_out(1, "food_bread"))
	var r := proc.apply(state, Commands.place(1, "food_bread", "cooler", 0))
	assert_array(_event_types(r)).contains(["container_completed"])
	assert_array(_event_types(r)).not_contains(["points_awarded"])
	assert_int(state.progression.available_points()).is_equal(1)


func test_unlock_requires_points_and_changes_nothing_when_refused() -> void:
	var r := proc.apply(state, Commands.unlock(1, "insight"))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_NOT_ENOUGH_POINTS)
	assert_bool(state.progression.has("insight")).is_false()
	assert_int(state.progression.spent).is_equal(0)


func test_unlock_spends_the_point_and_reports_what_is_left() -> void:
	_complete_the_cooler()
	var r := proc.apply(state, Commands.unlock(1, "insight"))
	assert_bool(r["ok"]).is_true()
	assert_bool(state.progression.has("insight")).is_true()
	assert_int(r["events"][0]["points_left"]).is_equal(0)
	assert_str(r["events"][0]["ability_id"]).is_equal("insight")


func test_unlocking_the_same_ability_twice_is_refused() -> void:
	state.progression.points = 9
	proc.apply(state, Commands.unlock(1, "insight"))
	var r := proc.apply(state, Commands.unlock(1, "insight"))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_ALREADY_UNLOCKED)


func test_an_ability_nobody_has_heard_of_is_refused() -> void:
	state.progression.points = 9
	var r := proc.apply(state, Commands.unlock(1, "teleport"))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_UNKNOWN_ABILITY)


func test_steady_hands_raises_capacity_for_every_player() -> void:
	state.add_player(2, Progression.BASE_CAPACITY)
	state.set_player_capacity(1, Progression.BASE_CAPACITY)
	state.progression.points = 2
	var r := proc.apply(state, Commands.unlock(1, "steady_hands"))
	assert_bool(r["ok"]).is_true()
	assert_int(state.player_capacity(1)).is_equal(Progression.BASE_CAPACITY + 2)
	assert_int(state.player_capacity(2)).is_equal(Progression.BASE_CAPACITY + 2)
	assert_array(_event_types(r)).contains(["capacity_changed", "capacity_changed"])


func test_steady_hands_lets_a_player_lift_what_was_too_heavy_a_moment_ago() -> void:
	# Start where a real run starts. Base capacity 3, poles are size 2: one fits,
	# a second does not — until the party buys the extra pair of hands.
	state.set_player_capacity(1, Progression.BASE_CAPACITY)
	proc.apply(state, Commands.pick_up(1, "pole_1"))
	var refused := proc.apply(state, Commands.pick_up(1, "pole_2"))
	assert_str(refused["error"]).is_equal(CommandProcessor.E_HANDS_FULL)
	state.progression.points = 2
	proc.apply(state, Commands.unlock(1, "steady_hands"))
	assert_bool(proc.apply(state, Commands.pick_up(1, "pole_2"))["ok"]).is_true()


func test_unlocking_a_non_capacity_ability_leaves_capacity_alone() -> void:
	state.set_player_capacity(1, Progression.BASE_CAPACITY)
	state.progression.points = 1
	var r := proc.apply(state, Commands.unlock(1, "insight"))
	assert_array(_event_types(r)).contains_exactly(["ability_unlocked"])
	assert_int(state.player_capacity(1)).is_equal(Progression.BASE_CAPACITY)


# --- Summon ------------------------------------------------------------------

func _with_call_mate() -> void:
	state.progression.points = 2
	proc.apply(state, Commands.unlock(1, "call_mate"))


func test_summoning_without_the_ability_is_refused() -> void:
	var r := proc.apply(state, Commands.summon(1, "poles", Vector3(3, 0, 0)))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_ABILITY_LOCKED)


func test_summon_moves_only_the_loose_members_of_the_series() -> void:
	_with_call_mate()
	state.set_carried("pole_1", 1)                    # in hand
	state.set_placed("pole_2", "tent_bag", 0)         # already packed
	var r := proc.apply(state, Commands.summon(1, "poles", Vector3(3, 0, -2)))
	assert_bool(r["ok"]).is_true()
	assert_int(r["events"].size()).is_equal(1)
	assert_str(r["events"][0]["item_id"]).is_equal("pole_3")
	assert_int(state.kind_of("pole_1")).is_equal(WorldState.Kind.CARRIED)
	assert_int(state.kind_of("pole_2")).is_equal(WorldState.Kind.PLACED)
	assert_int(state.kind_of("pole_3")).is_equal(WorldState.Kind.GROUND)
	# It landed within the ring radius of where it was called to.
	var landed: Vector3 = state.location("pole_3")["position"]
	assert_float(landed.distance_to(Vector3(3, 0, -2))).is_less_equal(
		CommandProcessor.SUMMON_RING_RADIUS + 0.001)


func test_summoned_items_do_not_land_on_top_of_each_other() -> void:
	_with_call_mate()
	var r := proc.apply(state, Commands.summon(1, "poles", Vector3.ZERO))
	assert_int(r["events"].size()).is_equal(3)
	var seen: Array[Vector3] = []
	for e in r["events"]:
		assert_array(seen).not_contains([e["position"]])
		seen.append(e["position"])


func test_a_series_can_only_be_called_once() -> void:
	_with_call_mate()
	assert_bool(proc.apply(state, Commands.summon(1, "poles", Vector3.ZERO))["ok"]).is_true()
	# Scatter them again; the shout is still spent.
	state.set_on_ground("pole_1", Vector3(9, 0, 9))
	var r := proc.apply(state, Commands.summon(1, "poles", Vector3.ZERO))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_SERIES_SPENT)
	assert_vector(state.location("pole_1")["position"]).is_equal(Vector3(9, 0, 9))


func test_calling_for_a_series_that_does_not_exist_is_refused() -> void:
	_with_call_mate()
	var r := proc.apply(state, Commands.summon(1, "kayaks", Vector3.ZERO))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_UNKNOWN_SERIES)


func test_calling_for_a_series_that_is_fully_packed_spends_nothing() -> void:
	_with_call_mate()
	for id in ["pole_1", "pole_2", "pole_3"]:
		state.set_placed(id, "tent_bag", 0)
	var r := proc.apply(state, Commands.summon(1, "poles", Vector3.ZERO))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_NOTHING_TO_SUMMON)
	assert_bool(state.progression.can_summon("poles")).is_true()


func test_items_are_never_summoned_into_the_lake() -> void:
	_with_call_mate()
	state.island_radius = 5.0
	state.ground_y = 0.5
	# Called from well outside the island — a client must not be able to do this.
	var r := proc.apply(state, Commands.summon(1, "poles", Vector3(400, 0, 0)))
	assert_bool(r["ok"]).is_true()
	for e in r["events"]:
		var p: Vector3 = e["position"]
		assert_float(Vector2(p.x, p.z).length()).is_less_equal(5.001)
		assert_float(p.y).is_equal_approx(0.5, 0.001)


func test_two_peers_agree_on_a_run_that_includes_an_unlock_and_a_shout() -> void:
	# The determinism guarantee has to cover abilities too, or host and client
	# diverge the first time somebody buys something (ADR 0010). The run below
	# deliberately mixes commands that apply with ones that are refused.
	var cmds := [
		Commands.pick_up(1, "food_bread"), Commands.place(1, "food_bread", "cooler", 0),
		Commands.unlock(1, "call_mate"),
		Commands.summon(1, "poles", Vector3(2, 0, 1)),
		Commands.summon(1, "poles", Vector3(4, 0, 4)), # refused: already spent
		Commands.unlock(1, "auto_place"),              # refused: costs 3, one left
		Commands.tick(60),
	]
	var a := TestFixtures.ground_state(cat)
	var b := TestFixtures.ground_state(cat)
	for s in [a, b]:
		s.island_radius = 12.0
		s.progression.points = 2
	for c in cmds:
		proc.apply(a, c)
		proc.apply(b, c)
	assert_dict(a.to_dict()).is_equal(b.to_dict())
	assert_bool(a.progression.has("call_mate")).is_true()
	assert_bool(a.progression.has("auto_place")).is_false()
	assert_bool(a.progression.can_summon("poles")).is_false()


# --- Test-mode commands (WP-3.10) --------------------------------------------

func test_granting_points_is_refused_unless_debug_is_on() -> void:
	# The default matters more than the feature: a build must not be able to
	# cheat by accident.
	assert_bool(proc.allow_debug_commands).is_false()
	var r := proc.apply(state, Commands.grant_points(1, 5))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_DEBUG_DISABLED)
	assert_int(state.progression.available_points()).is_equal(0)


func test_granting_points_works_when_debug_is_on() -> void:
	proc.allow_debug_commands = true
	var r := proc.apply(state, Commands.grant_points(1, 5))
	assert_bool(r["ok"]).is_true()
	assert_int(state.progression.available_points()).is_equal(5)
	assert_int(r["events"][0]["total_available"]).is_equal(5)
	# And the points are ordinary points: they buy an ability the ordinary way.
	assert_bool(proc.apply(state, Commands.unlock(1, "auto_place"))["ok"]).is_true()


func test_granted_points_cannot_be_negative() -> void:
	proc.allow_debug_commands = true
	proc.apply(state, Commands.grant_points(1, -10))
	assert_int(state.progression.available_points()).is_equal(0)


func test_a_granted_point_replays_the_same_on_two_peers() -> void:
	# A cheat still has to be deterministic, or test mode becomes useless in
	# exactly the place it would be most useful (ADR 0010).
	var a := TestFixtures.ground_state(cat)
	var b := TestFixtures.ground_state(cat)
	proc.allow_debug_commands = true
	for c in [Commands.grant_points(1, 3), Commands.unlock(1, "call_mate"), Commands.tick(10)]:
		proc.apply(a, c)
		proc.apply(b, c)
	assert_dict(a.to_dict()).is_equal(b.to_dict())
	assert_bool(a.progression.has("call_mate")).is_true()


# --- Collectibles (pre-placed for WP-3.7) ------------------------------------

func test_finding_a_collectible_is_recorded_once() -> void:
	var r := proc.apply(state, Commands.collect(1, "trolley"))
	assert_bool(r["ok"]).is_true()
	assert_bool(state.progression.has_found("trolley")).is_true()
	var again := proc.apply(state, Commands.collect(1, "trolley"))
	assert_bool(again["ok"]).is_false()
	assert_str(again["error"]).is_equal(CommandProcessor.E_ALREADY_FOUND)


func test_something_that_is_not_a_collectible_is_refused() -> void:
	var r := proc.apply(state, Commands.collect(1, "golden_paddle"))
	assert_bool(r["ok"]).is_false()
	assert_str(r["error"]).is_equal(CommandProcessor.E_UNKNOWN_COLLECTIBLE)


func test_the_trolley_and_steady_hands_add_up() -> void:
	# The whole point of computing capacity in one place: finding the trolley
	# after buying Rolige hænder must not throw the +2 away.
	state.set_player_capacity(1, Progression.BASE_CAPACITY)
	state.progression.points = 2
	proc.apply(state, Commands.unlock(1, "steady_hands"))
	assert_int(state.player_capacity(1)).is_equal(Progression.BASE_CAPACITY + 2)
	proc.apply(state, Commands.collect(1, "trolley"))
	assert_int(state.player_capacity(1)).override_failure_message(
		"the trolley replaced the steady hands instead of adding to them"
	).is_equal(Progression.BASE_CAPACITY + 5)
	# And the other way round, which is the order that actually breaks things.
	var other := TestFixtures.ground_state(cat, Progression.BASE_CAPACITY)
	other.progression.points = 2
	proc.apply(other, Commands.collect(1, "trolley"))
	proc.apply(other, Commands.unlock(1, "steady_hands"))
	assert_int(other.player_capacity(1)).is_equal(Progression.BASE_CAPACITY + 5)


func test_a_collectible_with_no_capacity_effect_changes_no_capacity() -> void:
	state.set_player_capacity(1, Progression.BASE_CAPACITY)
	var r := proc.apply(state, Commands.collect(1, "whistle"))
	assert_array(_event_types(r)).contains_exactly(["collectible_found"])
	assert_int(state.player_capacity(1)).is_equal(Progression.BASE_CAPACITY)


func test_what_the_party_found_survives_serialisation() -> void:
	proc.apply(state, Commands.collect(1, "trolley"))
	proc.apply(state, Commands.collect(1, "headlamp"))
	var back := WorldState.from_dict(state.to_dict())
	assert_array(back.progression.found_collectibles()).contains_exactly(["headlamp", "trolley"])
	assert_int(back.progression.capacity()).is_equal(Progression.BASE_CAPACITY + 3)
	assert_dict(back.to_dict()).is_equal(state.to_dict())
