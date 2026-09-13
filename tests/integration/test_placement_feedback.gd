extends GdUnitTestSuite
## WP-1.2 — containers react to verdicts with style, markers and sound players.

var island: Island
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	pid = GameSession.local_player_id()
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)


func after_test() -> void:
	GameSession.stop_level()


func _container(id: String) -> ContainerNode:
	return island.get_node("Containers/Container_" + id)


func _slot_mesh(c: ContainerNode, slot: int) -> MeshInstance3D:
	return c.slot_mesh(slot)


func _place(item_id: String, cid: String, slot: int) -> void:
	GameSession.submit(Commands.pick_up(pid, item_id))
	GameSession.submit(Commands.place(pid, item_id, cid, slot))


func test_every_container_has_sound_players_on_sfx_bus() -> void:
	for cid in GameSession.catalog.container_ids():
		var c := _container(cid)
		for name in ["SfxCorrect", "SfxWrong", "SfxComplete", "SfxClean"]:
			var p: AudioStreamPlayer3D = c.get_node(name)
			assert_object(p.stream).override_failure_message("%s/%s has no stream" % [cid, name]).is_not_null()
			assert_str(String(p.bus)).is_equal("SFX")


func test_correct_placement_uses_correct_style_and_no_marker() -> void:
	var bag := _container("pant_bag")
	_place("can_tuborg_1", "pant_bag", 2)
	# Flash material is temporary; the resting material is restored by a tween. Check verdict + marker now.
	assert_int(bag.slot_verdict(2)).is_equal(PlacementRules.Verdict.CORRECT)
	assert_bool(bag.slot_mark(2).visible).is_false()
	await await_millis(int(ContainerNode.FLASH_SECONDS * 1000) + 100)
	assert_object(_slot_mesh(bag, 2).material_override).is_equal(VerdictStyle.material("correct"))


func test_wrong_placement_shows_marker_and_wrong_style() -> void:
	var canoe := _container("canoe")
	_place("food_bread", "canoe", 0)
	assert_int(canoe.slot_verdict(0)).is_equal(PlacementRules.Verdict.WRONG_CATEGORY)
	assert_bool(canoe.slot_mark(0).visible).is_true()
	assert_str(canoe.slot_mark(0).text).is_equal(VerdictStyle.MARK_WRONG)
	# Guard against glyphs the default font cannot draw (Dingbats etc. render as nothing).
	assert_int(VerdictStyle.MARK_WRONG.unicode_at(0)).is_less(0x0250)
	await await_millis(int(ContainerNode.FLASH_SECONDS * 1000) + 100)
	assert_object(_slot_mesh(canoe, 0).material_override).is_equal(VerdictStyle.material("wrong"))


func test_taking_out_clears_marker() -> void:
	var canoe := _container("canoe")
	_place("food_bread", "canoe", 0)
	GameSession.submit(Commands.take_out(pid, "food_bread"))
	assert_bool(canoe.slot_mark(0).visible).is_false()
	assert_int(canoe.slot_verdict(0)).is_equal(-1)


func test_completed_container_goes_gold_and_marks_label() -> void:
	var pit := _container("fire_pit")
	for i in range(1, 6):
		_place("firewood_%d" % i, "fire_pit", i - 1)
	assert_bool(pit.is_complete).is_true()
	assert_str(pit.label.text).is_equal(tr("ui.container_packed") % tr("container.fire_pit"))
	await await_millis(int(ContainerNode.COMPLETE_PULSE_SECONDS * 1000) + 100)
	for i in range(5):
		assert_object(_slot_mesh(pit, i).material_override).is_equal(VerdictStyle.material("complete"))
	assert_object(_slot_mesh(pit, 5).material_override).is_equal(VerdictStyle.material("empty"))


func test_taking_out_of_completed_container_reverts_gold() -> void:
	var pit := _container("fire_pit")
	for i in range(1, 6):
		_place("firewood_%d" % i, "fire_pit", i - 1)
	GameSession.submit(Commands.take_out(pid, "firewood_3"))
	assert_bool(pit.is_complete).is_false()
	assert_str(pit.label.text).is_equal(tr("container.fire_pit"))
	assert_object(_slot_mesh(pit, 0).material_override).is_equal(VerdictStyle.material("correct"))


func test_chime_pitch_steps_up_on_combo_and_caps() -> void:
	var bag := _container("pant_bag")
	for i in range(1, 7):
		_place("can_tuborg_%d" % i, "pant_bag", i - 1)
	for i in range(1, 5):
		_place("can_carlsberg_%d" % i, "pant_bag", 5 + i)
	# 10 correct placements within the window → capped at CHIME_MAX_STEPS semitones.
	assert_float(bag.sfx_correct.pitch_scale).is_equal_approx(pow(2.0, ContainerNode.CHIME_MAX_STEPS / 12.0), 0.001)


func test_other_containers_ignore_events() -> void:
	var cooler := _container("cooler")
	_place("can_tuborg_1", "pant_bag", 0)
	assert_int(cooler.slot_verdict(0)).is_equal(-1)
	assert_object(_slot_mesh(cooler, 0).material_override).is_equal(VerdictStyle.material("empty"))


func test_verdict_style_helpers() -> void:
	assert_bool(VerdictStyle.is_good(PlacementRules.Verdict.CORRECT)).is_true()
	assert_bool(VerdictStyle.is_good(PlacementRules.Verdict.WRONG_ORDER)).is_false()
	assert_str(VerdictStyle.toast_key(PlacementRules.Verdict.SPLIT_SERIES)).is_equal("ui.verdict.split_series")
	assert_object(VerdictStyle.material("correct")).is_same(VerdictStyle.material("correct"))
