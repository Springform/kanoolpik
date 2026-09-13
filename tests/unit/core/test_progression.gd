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
