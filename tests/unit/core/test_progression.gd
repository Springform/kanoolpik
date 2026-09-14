extends GdUnitTestSuite


func test_credit_container_only_once() -> void:
	var p := Progression.new()
	assert_bool(p.credit_container("pant_bag")).is_true()
	assert_bool(p.credit_container("pant_bag")).is_false()
	assert_int(p.points).is_equal(Progression.POINTS_PER_CONTAINER)


func test_unlock_spends_points() -> void:
	var p := Progression.new()
	p.credit_container("a")
	p.credit_container("b")
	assert_bool(p.can_unlock("call_mate")).is_true()
	assert_bool(p.unlock("call_mate")).is_true()
	assert_int(p.available_points()).is_equal(0)
	assert_bool(p.unlock("insight")).is_false()
	assert_bool(p.has("call_mate")).is_true()


func test_cannot_unlock_twice_or_unknown() -> void:
	var p := Progression.new()
	p.points = 10
	assert_bool(p.unlock("insight")).is_true()
	assert_bool(p.unlock("insight")).is_false()
	assert_bool(p.unlock("teleport")).is_false()


func test_capacity_bonus() -> void:
	var p := Progression.new()
	assert_int(p.capacity_bonus()).is_equal(0)
	p.points = 5
	p.unlock("steady_hands")
	assert_int(p.capacity_bonus()).is_equal(2)


func test_round_trip() -> void:
	var p := Progression.new()
	p.credit_container("x")
	p.credit_container("y")
	p.unlock("insight")
	var copy := Progression.from_dict(p.to_dict())
	assert_dict(copy.to_dict()).is_equal(p.to_dict())
	assert_bool(copy.credit_container("x")).is_false()


# --- Summons: once per series, party-wide (WP-3.0) ---------------------------

func test_a_series_can_only_be_summoned_once() -> void:
	var p := Progression.new()
	assert_bool(p.can_summon("poles")).is_true()
	assert_bool(p.mark_summoned("poles")).is_true()
	assert_bool(p.can_summon("poles")).is_false()
	assert_bool(p.mark_summoned("poles")).is_false()
	# A different series is untouched.
	assert_bool(p.can_summon("pegs")).is_true()


func test_an_empty_series_can_never_be_summoned() -> void:
	var p := Progression.new()
	assert_bool(p.can_summon("")).is_false()
	assert_bool(p.mark_summoned("")).is_false()


func test_capacity_is_the_base_plus_what_the_party_owns() -> void:
	var p := Progression.new()
	assert_int(p.capacity()).is_equal(Progression.BASE_CAPACITY)
	p.points = 2
	assert_bool(p.unlock("steady_hands")).is_true()
	assert_int(p.capacity()).is_equal(Progression.BASE_CAPACITY + 2)


func test_spent_summons_survive_serialisation() -> void:
	var p := Progression.new()
	p.points = 2
	p.unlock("call_mate")
	p.mark_summoned("poles")
	p.mark_summoned("pegs")
	var back := Progression.from_dict(p.to_dict())
	assert_array(back.summoned_series()).contains_exactly(["pegs", "poles"])
	assert_bool(back.can_summon("poles")).is_false()
	assert_dict(back.to_dict()).is_equal(p.to_dict())
