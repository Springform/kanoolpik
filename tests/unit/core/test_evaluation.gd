extends GdUnitTestSuite

var cat: Catalog
var state: WorldState


func before_test() -> void:
	cat = TestFixtures.catalog()
	state = TestFixtures.ground_state(cat)


func test_progress_on_fresh_level() -> void:
	var p := Evaluation.progress(cat, state)
	assert_int(p["total"]).is_equal(9)
	assert_int(p["on_ground"]).is_equal(9)
	assert_int(p["correct"]).is_equal(0)
	assert_float(p["completion"]).is_equal(0.0)
	assert_bool(p["is_clean"]).is_false()
	assert_int(p["containers_completed"]).is_equal(0)


func test_progress_counts_correct_and_wrong() -> void:
	state.set_placed("can_a1", "pant_bag", 0)
	state.set_placed("food_bread", "pant_bag", 1)
	state.set_carried("peg_1", 1)
	var p := Evaluation.progress(cat, state)
	assert_int(p["correct"]).is_equal(1)
	assert_int(p["wrong"]).is_equal(1)
	assert_int(p["carried"]).is_equal(1)
	assert_int(p["on_ground"]).is_equal(6)
	assert_float(p["completion"]).is_equal_approx(1.0 / 9.0, 0.0001)


func test_time_factor_curve() -> void:
	assert_float(Evaluation.time_factor(0, 600, 1800)).is_equal(1.0)
	assert_float(Evaluation.time_factor(600, 600, 1800)).is_equal(1.0)
	assert_float(Evaluation.time_factor(1200, 600, 1800)).is_equal_approx(0.5, 0.0001)
	assert_float(Evaluation.time_factor(1800, 600, 1800)).is_equal(0.0)
	assert_float(Evaluation.time_factor(9999, 600, 1800)).is_equal(0.0)


func test_perfect_run_scores_s() -> void:
	_place_all_correctly()
	state.stats["placements"] = 9
	state.stats["wrong_placements"] = 0
	state.elapsed_ticks = 60 * 120 # 2 minutes
	var s := Evaluation.score(cat, state)
	assert_int(s["points"]).is_equal(100)
	assert_str(s["grade"]).is_equal("S")


func test_sloppy_slow_run_scores_lower() -> void:
	_place_all_correctly()
	state.stats["placements"] = 18
	state.stats["wrong_placements"] = 9 # fixed every mistake, eventually
	state.elapsed_ticks = 60 * 1800
	var s := Evaluation.score(cat, state)
	# completion 1.0*60 + accuracy 0.5*25 + speed 0*15 = 72.5 → 73 (B)
	assert_int(s["points"]).is_between(72, 73)
	assert_str(s["grade"]).is_equal("B")


func test_grade_thresholds() -> void:
	assert_str(Evaluation.grade_for(100)).is_equal("S")
	assert_str(Evaluation.grade_for(95)).is_equal("S")
	assert_str(Evaluation.grade_for(94)).is_equal("A")
	assert_str(Evaluation.grade_for(70)).is_equal("B")
	assert_str(Evaluation.grade_for(69)).is_equal("C")
	assert_str(Evaluation.grade_for(0)).is_equal("D")


func _place_all_correctly() -> void:
	state.set_placed("can_a1", "pant_bag", 0)
	state.set_placed("can_a2", "pant_bag", 1)
	state.set_placed("can_b1", "pant_bag", 2)
	state.set_placed("pole_1", "tent_bag", 0)
	state.set_placed("pole_2", "tent_bag", 1)
	state.set_placed("pole_3", "tent_bag", 2)
	state.set_placed("peg_1", "tent_bag", 3)
	state.set_placed("peg_2", "tent_bag", 4)
	state.set_placed("food_bread", "cooler", 0)


func test_grade_key_maps_every_grade_to_its_string() -> void:
	assert_str(Evaluation.grade_key("S")).is_equal("grade.s")
	assert_str(Evaluation.grade_key("D")).is_equal("grade.d")
	assert_str(Evaluation.grade_key("nonsense")).is_equal("grade.d")
	for g in Evaluation.GRADES:
		assert_str(Evaluation.grade_key(g["grade"])).is_equal(g["key"])
