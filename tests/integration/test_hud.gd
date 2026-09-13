extends GdUnitTestSuite
## WP-1.4 — HUD reacts to bus events and reads state; no player needed.

var hud: HUD
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	pid = GameSession.local_player_id()
	hud = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)


func after_test() -> void:
	GameSession.stop_level()


func _place(item_id: String, cid: String, slot: int) -> void:
	GameSession.submit(Commands.pick_up(pid, item_id))
	GameSession.submit(Commands.place(pid, item_id, cid, slot))


func test_initial_progress_is_shown_without_waiting_for_an_event() -> void:
	var total := GameSession.catalog.item_count()
	assert_str(hud.progress_label.text).is_equal(tr("ui.hud.progress") % [0, total])
	assert_float(hud.progress_bar.value).is_equal(0.0)
	assert_str(hud.containers_label.text).is_equal(tr("ui.hud.containers") % [0, 8])


func test_progress_updates_after_placement() -> void:
	_place("firewood_1", "fire_pit", 0)
	assert_str(hud.progress_label.text).is_equal(tr("ui.hud.progress") % [1, GameSession.catalog.item_count()])
	assert_float(hud.progress_bar.value).is_greater(0.0)


func test_carrying_panel_shows_load_and_active_item() -> void:
	GameSession.submit(Commands.pick_up(pid, "can_tuborg_1"))
	GameSession.submit(Commands.pick_up(pid, "food_bread"))
	hud._refresh_carrying()
	assert_str(hud.carrying_label.text).is_equal(tr("ui.hud.carrying") % [2, 3])
	assert_int(hud.slots_box.get_child_count()).is_equal(3)
	assert_object((hud.slots_box.get_child(1) as ColorRect).color).is_equal(HUD.COLOR_SLOT_FULL)
	assert_object((hud.slots_box.get_child(2) as ColorRect).color).is_equal(HUD.COLOR_SLOT_EMPTY)
	# carried_by() is in pick-up order → food_bread (picked second) is the active one.
	assert_str(hud.held_label.text).ends_with("» " + tr("item.food_bread"))


func test_empty_hands_text() -> void:
	hud._refresh_carrying()
	assert_str(hud.held_label.text).is_equal(tr("ui.hud.hands_empty"))


func test_wrong_placement_toasts_the_verdict_in_verdict_colour() -> void:
	_place("food_bread", "canoe", 0)
	assert_array(hud.toast_texts()).contains([tr("ui.verdict.wrong_category")])
	var toast: Label = hud.toasts_box.get_child(hud.toast_count() - 1)
	assert_object(toast.modulate).is_equal(VerdictStyle.COLOR_WRONG)


func test_rejected_command_toasts_a_translated_message_not_the_error_id() -> void:
	GameSession.submit(Commands.drop(pid, "can_tuborg_1", Vector3.ZERO))
	var texts := hud.toast_texts()
	assert_array(texts).contains([tr("ui.error.item_not_carried_by_player")])
	assert_array(texts).not_contains([CommandProcessor.E_NOT_CARRIED])


func test_hands_full_has_its_own_message() -> void:
	assert_str(HUD.error_key(CommandProcessor.E_HANDS_FULL)).is_equal("ui.error.hands_full")
	assert_str(HUD.error_key("something_new")).is_equal("ui.error.generic")
	assert_str(tr("ui.error.hands_full")).is_not_equal("ui.error.hands_full") # key exists in CSV


func test_toast_queue_is_capped() -> void:
	for i in range(6):
		hud.show_toast("t%d" % i)
	assert_int(hud.toast_count()).is_equal(HUD.MAX_TOASTS)
	assert_array(hud.toast_texts()).is_equal(["t3", "t4", "t5"])


func test_toast_disappears_after_its_lifetime() -> void:
	hud.show_toast("bye", 0.3)
	assert_int(hud.toast_count()).is_equal(1)
	await await_millis(600)
	assert_int(hud.toast_count()).is_equal(0)


func test_container_completed_toast_names_the_container() -> void:
	for i in range(1, 6):
		_place("firewood_%d" % i, "fire_pit", i - 1)
	assert_array(hud.toast_texts()).contains([tr("ui.container_complete") % tr("container.fire_pit")])


func test_format_time() -> void:
	assert_str(HUD.format_time(0)).is_equal("00:00")
	assert_str(HUD.format_time(125)).is_equal("02:05")
	assert_str(HUD.format_time(3600)).is_equal("60:00")


func test_prompt_texts() -> void:
	var held: Array[String] = []
	assert_str(hud._prompt_for(null, held)).is_equal("")
	held.append("can_tuborg_1")
	assert_str(hud._prompt_for(null, held)).is_equal(tr("ui.hud.drop") % tr("item.can_tuborg_1"))
	var island: Island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	var bag: ContainerNode = island.get_node("Containers/Container_pant_bag")
	assert_str(hud._prompt_for(bag, held)).is_equal(tr("ui.hud.place") % [tr("item.can_tuborg_1"), tr("container.pant_bag")])
	var item: PickupItem = island.get_node("Items/Item_food_bread")
	assert_str(hud._prompt_for(item, held)).is_equal(tr("ui.hud.pickup") % tr("item.food_bread"))


func test_danish_glyphs_survive_translation() -> void:
	assert_str(tr("ui.hud.progress") % [1, 2]).contains("på")
	assert_str(tr("ui.hud.carrying") % [0, 3]).contains("Bærer")
	assert_str(tr("ui.hud.clean")).contains("Øen")


func test_hud_finds_a_player_that_spawned_before_it() -> void:
	var player: Player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = true
	player.player_id = pid
	add_child(player)
	var late_hud: HUD = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(late_hud)
	assert_object(late_hud._player).is_same(player)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
