extends GdUnitTestSuite
## WP-3.1 — the Tab skill panel: open/close, affordability, and the rule that
## the panel changes only because of an event off the bus, never because of the
## click that caused it.

## Packing the fire pit takes these five, and credits the party one skill point.
const FIRE_PIT_ITEMS := ["firewood_1", "firewood_2", "firewood_3", "firewood_4", "firewood_5"]
const SAVE_SLOT := "test_skill_menu"
## Narrower and shorter than the project's 1280x720 window, so the panel has to
## fit somewhere smaller than it will ever really be asked to.
const NARROW_WINDOW := Vector2(800, 700)

var hud: HUD
var menu: SkillMenu
var pid: int
var _core_events: Array[Dictionary] = []
var _refusals: Array[String] = []
var _locale: String


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	GameSession.start_level("island_01", 4242)
	GameSession.autosave_enabled = false
	pid = GameSession.local_player_id()
	hud = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)
	menu = hud.skill_menu
	_core_events = []
	_refusals = []
	GameEvents.core_event.connect(_record_event)
	menu.purchase_refused.connect(_record_refusal)


func after_test() -> void:
	GameEvents.core_event.disconnect(_record_event)
	if menu != null and menu.is_open():
		menu.close()
	GameSession.stop_level()
	GameSession.autosave_enabled = true
	TranslationServer.set_locale(_locale)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveGame.erase(SAVE_SLOT)


# --- Helpers ------------------------------------------------------------------------

func _record_event(event: Dictionary) -> void:
	_core_events.append(event)


func _record_refusal(_ability_id: String, error_id: String) -> void:
	_refusals.append(error_id)


func _events_of_type(type: String) -> Array:
	return _core_events.filter(func(e: Dictionary) -> bool: return String(e["type"]) == type)


## Pack the fire pit through the normal command path, which credits one point.
func _earn_a_point() -> void:
	for i in range(FIRE_PIT_ITEMS.size()):
		GameSession.submit(Commands.pick_up(pid, FIRE_PIT_ITEMS[i]))
		GameSession.submit(Commands.place(pid, FIRE_PIT_ITEMS[i], "fire_pit", i))


func _tab() -> void:
	var event := InputEventAction.new()
	event.action = "ui_skills"
	event.pressed = true
	menu._unhandled_input(event)


# --- Open / close -------------------------------------------------------------------

func test_panel_starts_closed_and_tab_opens_and_closes_it() -> void:
	assert_bool(menu.is_open()).is_false()
	_tab()
	assert_bool(menu.is_open()).is_true()
	_tab()
	assert_bool(menu.is_open()).is_false()


func test_open_frees_the_pointer_and_close_recaptures_it() -> void:
	# Headless has no pointer to capture and always reports VISIBLE, so the
	# recapture is checked through what the panel asked for.
	menu.open()
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	assert_int(menu.requested_mouse_mode()).is_equal(Input.MOUSE_MODE_VISIBLE)
	menu.close()
	assert_int(menu.requested_mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)


func test_closing_after_the_level_is_over_leaves_the_pointer_free() -> void:
	menu.open()
	GameSession.stop_level() # the evaluation screen owns the pointer now
	menu.close()
	assert_int(menu.requested_mouse_mode()).is_equal(Input.MOUSE_MODE_VISIBLE)


func test_the_player_cannot_walk_while_the_panel_is_open() -> void:
	var player: Player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	player.is_local = true
	player.player_id = pid
	add_child(player)
	assert_bool(player.is_physics_processing()).is_true()
	menu.open()
	assert_bool(player.is_physics_processing()).is_false()
	assert_bool(player.is_processing_input()).is_false()
	menu.close()
	assert_bool(player.is_physics_processing()).is_true()
	assert_bool(player.is_processing_input()).is_true()


func test_tab_does_nothing_once_the_level_is_over() -> void:
	GameSession.stop_level()
	_tab()
	assert_bool(menu.is_open()).is_false()


func test_the_crosshair_and_prompt_step_aside_while_the_panel_is_up() -> void:
	assert_bool(hud.crosshair_label.visible).is_true()
	menu.open()
	hud._process(0.0)
	assert_bool(hud.crosshair_label.visible).is_false()
	assert_str(hud.prompt_label.text).is_equal("")
	menu.close()
	hud._process(0.0)
	assert_bool(hud.crosshair_label.visible).is_true()


func test_the_panel_pauses_nothing() -> void:
	menu.open()
	assert_bool(get_tree().paused).is_false()
	assert_bool(GameSession.is_running()).is_true()


# --- Contents -----------------------------------------------------------------------

func test_every_ability_in_the_dictionary_gets_a_row_cheapest_first() -> void:
	assert_int(menu.ability_ids().size()).is_equal(Progression.ABILITIES.size())
	assert_array(menu.ability_ids()).contains(Progression.ABILITIES.keys())
	var last_cost := 0
	for id in menu.ability_ids():
		var cost := int(Progression.ABILITIES[id]["cost"])
		assert_int(cost).is_greater_equal(last_cost)
		last_cost = cost


func test_rows_show_name_cost_and_description_from_the_csv() -> void:
	for id in menu.ability_ids():
		var name_key: String = Progression.ABILITIES[id]["name_key"]
		assert_str(menu.row_name(id)).is_equal(tr(name_key))
		assert_str(menu.row_description(id)).is_equal(tr(name_key + ".desc"))
		assert_str(menu.row_cost(id)).is_equal(tr("ui.skills.cost") % int(Progression.ABILITIES[id]["cost"]))
		# A missing CSV row would leave the bare key on screen.
		assert_str(menu.row_name(id)).is_not_equal(name_key)
		assert_str(menu.row_description(id)).is_not_equal(name_key + ".desc")


func test_texts_are_danish_by_default_and_english_after_the_toggle() -> void:
	TranslationServer.set_locale("da")
	menu._notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(menu.title_label.text).is_equal("Evner")
	assert_str(menu.row_name("call_mate")).is_equal("Råb på en kammerat")
	assert_str(menu.hint_label.text).contains("luk")
	TranslationServer.set_locale("en")
	menu._notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_str(menu.title_label.text).is_equal("Skills")
	assert_str(menu.row_name("call_mate")).is_equal("Call a mate")
	assert_str(menu.hint_label.text).contains("close")


func test_with_no_points_nothing_is_buyable_and_the_panel_says_how_to_earn_one() -> void:
	menu.open()
	assert_str(menu.points_label.text).is_equal(tr("ui.skills.points") % 0)
	assert_bool(menu.empty_label.visible).is_true()
	for id in menu.ability_ids():
		assert_bool(menu.can_buy(id)).is_false()
		assert_str(menu.row_status(id)).is_equal(tr("ui.skills.cannot_afford"))


func test_one_point_buys_the_cheap_abilities_and_not_the_dear_ones() -> void:
	_earn_a_point()
	menu.open()
	assert_str(menu.points_label.text).is_equal(tr("ui.skills.points") % 1)
	assert_bool(menu.empty_label.visible).is_false()
	assert_bool(menu.can_buy("insight")).is_true()      # costs 1
	assert_bool(menu.can_buy("map_sense")).is_true()    # costs 1
	assert_bool(menu.can_buy("call_mate")).is_false()   # costs 2
	assert_bool(menu.can_buy("auto_place")).is_false()  # costs 3
	# Out of reach is still legible, not hidden — that is what makes it a goal.
	assert_bool(menu.buy_button("auto_place").visible).is_true()
	assert_str(menu.row_name("auto_place")).is_equal(tr("ability.auto_place"))
	assert_str(menu.row_cost("auto_place")).is_equal(tr("ui.skills.cost") % 3)
	assert_str(menu.row_status("auto_place")).is_equal(tr("ui.skills.cannot_afford"))


func test_the_panel_fits_a_narrow_window_with_every_line_of_every_row_visible() -> void:
	menu.open()
	# Pretend the HUD lives in a small window: the panel is anchored to its
	# parent, so resizing it is the same thing as resizing the window.
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu.size = Vector2(NARROW_WINDOW.x, NARROW_WINDOW.y)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: PanelContainer = menu.get_node("Center/Panel")
	assert_float(panel.size.x).is_less_equal(NARROW_WINDOW.x)
	assert_float(panel.size.y).is_less_equal(NARROW_WINDOW.y)
	var labels := _labels_under(panel)
	assert_int(labels.size()).is_greater(Progression.ABILITIES.size()) # rows really are there
	for label in labels:
		if label.text.is_empty() or not label.visible:
			continue
		# Every line the label holds is a line the player can read.
		assert_int(label.get_visible_line_count()).is_equal(label.get_line_count())


func _labels_under(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label:
			out.append(child as Label)
		out.append_array(_labels_under(child))
	return out


# --- Buying -------------------------------------------------------------------------

func test_clicking_buy_submits_an_unlock_command_for_the_local_player() -> void:
	_earn_a_point()
	menu.open()
	_core_events = []
	menu.buy_button("insight").pressed.emit()
	var unlocks := _events_of_type("ability_unlocked")
	assert_int(unlocks.size()).is_equal(1)
	assert_str(unlocks[0]["ability_id"]).is_equal("insight")
	assert_int(unlocks[0]["player_id"]).is_equal(pid)
	assert_bool(GameSession.progression.has("insight")).is_true()


func test_a_bought_ability_reads_as_owned_and_the_point_is_spent() -> void:
	_earn_a_point()
	menu.open()
	menu.buy_button("insight").pressed.emit()
	assert_str(menu.row_status("insight")).is_equal(tr("ui.skills.owned"))
	assert_bool(menu.buy_button("insight").visible).is_false()
	assert_str(menu.points_label.text).is_equal(tr("ui.skills.points") % 0)
	assert_str(hud.points_label.text).is_equal(tr("ui.skills.points") % 0)
	assert_array(hud.toast_texts()).contains([tr("ui.ability.unlocked") % tr("ability.insight")])


func test_an_unaffordable_ability_cannot_be_bought_and_says_why() -> void:
	_earn_a_point()
	menu.open()
	assert_bool(menu.buy_button("auto_place").disabled).is_true()
	_core_events = []
	menu.buy("auto_place") # the route past the disabled button: keyboard, or code
	assert_array(_refusals).is_equal([CommandProcessor.E_NOT_ENOUGH_POINTS])
	assert_int(_events_of_type("ability_unlocked").size()).is_equal(0)
	assert_bool(GameSession.progression.has("auto_place")).is_false()
	assert_str(menu.row_status("auto_place")).is_equal(tr("ui.skills.cannot_afford"))
	assert_array(hud.toast_texts()).contains([tr("ui.error.not_enough_points")])


func test_buying_the_same_ability_twice_is_refused() -> void:
	_earn_a_point()
	menu.open()
	menu.buy_button("insight").pressed.emit()
	menu.buy("insight")
	assert_array(_refusals).is_equal([CommandProcessor.E_ALREADY_UNLOCKED])
	assert_array(hud.toast_texts()).contains([tr("ui.error.already_unlocked")])


# --- The panel reacts to the bus, not to the click ----------------------------------

func test_the_panel_updates_from_a_received_unlock_for_another_player() -> void:
	# A mate on player 7 buys Klarsyn. Nothing was clicked here; the replicated
	# state arrives first and the event follows, exactly as CommandProcessor
	# does it locally. The row must flip all the same.
	_earn_a_point()
	menu.open()
	assert_bool(menu.can_buy("insight")).is_true()
	GameSession.state.progression.unlock("insight") # stands in for the remote apply
	GameEvents.publish({
		"type": "ability_unlocked", "ability_id": "insight",
		"player_id": 7, "points_left": GameSession.progression.available_points(),
	})
	assert_str(menu.row_status("insight")).is_equal(tr("ui.skills.owned"))
	assert_bool(menu.buy_button("insight").visible).is_false()
	assert_str(menu.points_label.text).is_equal(tr("ui.skills.points") % 0)
	assert_str(hud.points_label.text).is_equal(tr("ui.skills.points") % 0)
	assert_array(hud.toast_texts()).contains([tr("ui.ability.unlocked") % tr("ability.insight")])


func test_without_the_event_the_click_alone_changes_nothing_on_screen() -> void:
	# Cut the one wire the panel is allowed to listen on. The command still
	# applies — but an optimistic panel would flip the row anyway, and this is
	# the test that would catch it.
	_earn_a_point()
	menu.open()
	GameEvents.ability_unlocked.disconnect(menu._on_ability_unlocked)
	menu.buy_button("insight").pressed.emit()
	assert_bool(GameSession.progression.has("insight")).is_true() # the command went through
	assert_bool(menu.buy_button("insight").visible).is_true()     # the panel did not
	assert_str(menu.row_status("insight")).is_equal("")
	GameEvents.ability_unlocked.connect(menu._on_ability_unlocked)


func test_a_refused_unlock_leaves_the_panel_untouched() -> void:
	menu.open() # zero points
	GameSession.submit(Commands.unlock(pid, "insight"))
	assert_bool(GameSession.progression.has("insight")).is_false()
	assert_str(menu.row_status("insight")).is_equal(tr("ui.skills.cannot_afford"))
	assert_str(menu.points_label.text).is_equal(tr("ui.skills.points") % 0)
	assert_array(hud.toast_texts()).contains([tr("ui.error.not_enough_points")])


# --- HUD counter --------------------------------------------------------------------

func test_the_hud_counter_ticks_up_when_a_container_is_packed() -> void:
	assert_str(hud.points_label.text).is_equal(tr("ui.skills.points") % 0)
	_earn_a_point()
	assert_str(hud.points_label.text).is_equal(tr("ui.skills.points") % 1)
	assert_bool(menu.is_open()).is_false() # without opening anything


func test_the_hud_counter_survives_a_save_and_resume() -> void:
	_earn_a_point()
	assert_bool(GameSession.save(SAVE_SLOT)).is_true()
	GameSession.stop_level()
	assert_bool(GameSession.load_save(SAVE_SLOT)).is_true()
	var resumed: HUD = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(resumed)
	assert_str(resumed.points_label.text).is_equal(tr("ui.skills.points") % 1)
	assert_str(resumed.skill_menu.points_label.text).is_equal(tr("ui.skills.points") % 1)


# --- The extension point the other ability WPs depend on ----------------------------

func test_ability_layer_is_a_full_rect_mouse_ignoring_container_that_always_exists() -> void:
	var layer := hud.ability_layer()
	assert_object(layer).is_not_null()
	assert_bool(layer.is_inside_tree()).is_true()
	assert_bool(menu.is_open()).is_false() # present while the panel is closed
	assert_bool(layer.visible).is_true()
	assert_int(layer.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_float(layer.anchor_right).is_equal(1.0)
	assert_float(layer.anchor_bottom).is_equal(1.0)
	assert_int(layer.get_child_count()).is_equal(0) # the HUD puts nothing in it
	menu.open()
	assert_object(hud.ability_layer()).is_same(layer)
	var overlay := Control.new()
	layer.add_child(overlay)
	assert_int(hud.ability_layer().get_child_count()).is_equal(1)


# --- Error keys ---------------------------------------------------------------------

func test_every_progression_error_has_a_message_of_its_own() -> void:
	var ids: Array[String] = [
		CommandProcessor.E_ABILITY_LOCKED, CommandProcessor.E_UNKNOWN_ABILITY,
		CommandProcessor.E_ALREADY_UNLOCKED, CommandProcessor.E_NOT_ENOUGH_POINTS,
		CommandProcessor.E_UNKNOWN_SERIES, CommandProcessor.E_SERIES_SPENT,
		CommandProcessor.E_NOTHING_TO_SUMMON,
	]
	for id in ids:
		var key := HUD.error_key(id)
		assert_str(key).is_equal("ui.error." + id)
		assert_str(tr(key)).is_not_equal(key) # the row really is in the CSV
	assert_str(HUD.error_key("something_new")).is_equal("ui.error.generic")


# --- The key that actually fires it -------------------------------------------

func test_every_ability_says_which_key_uses_it() -> void:
	# The panel described what each ability does and never said how to use it,
	# which is the panel failing at its one job: a player who buys Klarsyn and
	# then has to ask which key it is on has been sold a mystery.
	assert_str(menu.key_hint("insight")).is_equal("[F]")
	assert_str(menu.key_hint("call_mate")).is_equal("[R]")
	assert_str(menu.key_hint("map_sense")).is_equal("[C]")
	# Autopilot has no key of its own — it changes what interact already does.
	assert_str(menu.key_hint("auto_place")).contains("E")
	# Rolige hænder has nothing to press at all.
	assert_str(menu.key_hint("steady_hands")).is_equal(tr("ui.skills.passive"))


func test_the_key_is_read_from_the_input_map_not_written_out() -> void:
	# A hard-coded "[F]" would quietly lie the day somebody rebinds the action.
	# Rebind it here and the label must follow.
	var original := InputMap.action_get_events("ability_insight")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_J
	InputMap.action_erase_events("ability_insight")
	InputMap.action_add_event("ability_insight", event)
	assert_str(menu.key_hint("insight")).override_failure_message(
		"the key label is hard-coded and would lie after a rebind").is_equal("[J]")
	InputMap.action_erase_events("ability_insight")
	for e in original:
		InputMap.action_add_event("ability_insight", e)
	assert_str(menu.key_hint("insight")).is_equal("[F]")


func test_an_ability_with_no_binding_at_all_says_nothing_rather_than_lying() -> void:
	var original := InputMap.action_get_events("ability_call_mate")
	InputMap.action_erase_events("ability_call_mate")
	assert_str(menu.key_hint("call_mate")).override_failure_message(
		"an unbound action should show no key, not a stale one").is_empty()
	for e in original:
		InputMap.action_add_event("ability_call_mate", e)
