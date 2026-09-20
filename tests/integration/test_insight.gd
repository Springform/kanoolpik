extends GdUnitTestSuite
## WP-3.2 — Klarsyn: the rest of the series glows, through the hill, for five seconds.
##
## The assertions are deliberately exact-set rather than "at least one glowed":
## the failure this suite exists to catch is an ability that lights up the whole
## island, and a count-only check would sail straight past it.

## Four tent poles, all on the ground at the start of island_01.
const POLES := ["tent_pole_1", "tent_pole_2", "tent_pole_3", "tent_pole_4"]
## An item with no series at all — the common case.
const LONER := "napkins"

var island: Island
var ability: InsightAbility
var pid: int


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	pid = GameSession.local_player_id()
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	ability = auto_free(InsightAbility.new())
	add_child(ability)


func after_test() -> void:
	GameSession.stop_level()


# --- Helpers -----------------------------------------------------------------------

## Buy Klarsyn. A tent pole costs 2 of the 3 base carry slots, so any test that
## needs a second pole in hand buys the capacity upgrade too — the real way,
## through a command, rather than poking a number into the state.
func _unlock(big_hands: bool = false) -> void:
	GameSession.state.progression.points = 3
	if big_hands:
		GameSession.submit(Commands.unlock(pid, "steady_hands"))
	GameSession.submit(Commands.unlock(pid, InsightAbility.ABILITY_ID))


func _hold(item_id: String) -> void:
	GameSession.submit(Commands.pick_up(pid, item_id))


func _pack(item_id: String, container_id: String) -> void:
	_hold(item_id)
	var slot := PlacementRules.find_correct_slot(
		GameSession.catalog, GameSession.state, item_id, container_id)
	GameSession.submit(Commands.place(pid, item_id, container_id, slot))


func _item(item_id: String) -> PickupItem:
	return island.get_node("Items/Item_" + item_id)


func _shells(item_id: String) -> Array[Node]:
	return _item(item_id).find_children("*", "InsightHighlight", true, false)


func _add_hud() -> HUD:
	var hud: HUD = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)
	return hud


# --- Locked ------------------------------------------------------------------------

func test_a_locked_ability_does_nothing_at_all() -> void:
	var hud := _add_hud()
	_hold("tent_pole_1")
	assert_bool(GameSession.progression.has(InsightAbility.ABILITY_ID)).is_false()
	ability.activate()
	assert_array(ability.highlighted_ids()).is_empty()
	assert_array(_shells("tent_pole_2")).is_empty()
	# "Nothing at all" includes saying nothing: no toast, not even a locked one.
	assert_array(hud.toast_texts()).is_empty()


func test_a_locked_ability_does_nothing_even_when_the_key_is_pressed() -> void:
	var hud := _add_hud()
	_hold("tent_pole_1")
	assert_bool(_press_f()).is_true() # the key is consumed…
	assert_array(ability.highlighted_ids()).is_empty() # …and still nothing happens
	assert_array(hud.toast_texts()).is_empty()


# --- Unlocked: the right set --------------------------------------------------------

func test_holding_a_series_item_highlights_exactly_its_ground_siblings() -> void:
	_unlock()
	_hold("tent_pole_1")
	ability.activate()
	# Exactly the other three poles: not the one in hand, and nothing else on the
	# island. This is the assertion that fails when the ability lights everything.
	assert_array(ability.highlighted_ids()).contains_exactly(
		["tent_pole_2", "tent_pole_3", "tent_pole_4"])
	for pole in ["tent_pole_2", "tent_pole_3", "tent_pole_4"]:
		assert_int(_shells(pole).size()).override_failure_message(
			"%s should carry exactly one highlight" % pole).is_equal(1)
	assert_array(_shells("tent_pole_1")).is_empty()
	# Nothing outside the series, and nothing from a *different* series either.
	assert_array(_shells(LONER)).is_empty()
	assert_array(_shells("paddle_1")).is_empty()
	assert_array(_shells("can_tuborg_1")).is_empty()


func test_the_whole_island_is_not_lit_up() -> void:
	_unlock()
	_hold("tent_pole_1")
	ability.activate()
	var lit := island.find_children("*", "InsightHighlight", true, false)
	assert_int(lit.size()).override_failure_message(
		"Klarsyn should glow 3 siblings, not %d nodes" % lit.size()).is_equal(3)
	assert_int(GameSession.catalog.item_count()).is_greater(100) # there was plenty to get wrong


func test_a_sibling_already_in_its_container_is_left_alone() -> void:
	_unlock()
	_pack("tent_pole_4", "tent_bag")
	assert_int(GameSession.state.kind_of("tent_pole_4")).is_equal(WorldState.Kind.PLACED)
	_hold("tent_pole_1")
	ability.activate()
	assert_array(ability.highlighted_ids()).contains_exactly(["tent_pole_2", "tent_pole_3"])
	assert_array(_shells("tent_pole_4")).is_empty()


func test_a_sibling_already_in_someones_hands_is_left_alone() -> void:
	_unlock(true)
	_hold("tent_pole_2")
	_hold("tent_pole_1") # tent_pole_1 is now the active item; both are carried
	assert_array(GameSession.state.carried_by(pid)).contains_exactly(["tent_pole_2", "tent_pole_1"])
	ability.activate()
	assert_array(ability.highlighted_ids()).contains_exactly(["tent_pole_3", "tent_pole_4"])


func test_the_selection_rule_is_ground_only_and_excludes_the_held_item() -> void:
	# The set-picking logic on its own, with no nodes involved.
	var chosen := InsightAbility.siblings_on_ground(
		GameSession.catalog, GameSession.state, "tent_poles", "tent_pole_1")
	assert_array(chosen).contains_exactly(["tent_pole_2", "tent_pole_3", "tent_pole_4"])
	assert_array(InsightAbility.siblings_on_ground(
		GameSession.catalog, GameSession.state, "", "tent_pole_1")).is_empty()


# --- Unlocked: the series-less case --------------------------------------------------

func test_a_series_less_item_says_so_and_glows_nothing() -> void:
	var hud := _add_hud()
	_unlock()
	assert_str(GameSession.catalog.get_item(LONER).series).is_empty()
	_hold(LONER)
	ability.activate()
	assert_array(ability.highlighted_ids()).is_empty()
	assert_int(island.find_children("*", "InsightHighlight", true, false).size()).is_equal(0)
	assert_bool(hud.said(tr("ui.ability.no_series"))).override_failure_message("the player was never told: %s" % [tr("ui.ability.no_series")]).is_true()


func test_empty_hands_glow_nothing_and_say_nothing() -> void:
	# Attach the HUD after the unlock: WP-3.1 made the HUD toast every
	# ability_unlocked, and that toast is not this test's business.
	_unlock()
	var hud := _add_hud()
	ability.activate()
	assert_array(ability.highlighted_ids()).is_empty()
	assert_array(hud.toast_texts()).is_empty()


# --- The five seconds ----------------------------------------------------------------

func test_the_activation_lasts_five_seconds() -> void:
	assert_float(InsightAbility.DURATION_SECONDS).is_equal(5.0)


func test_highlights_expire_and_take_their_nodes_with_them() -> void:
	_unlock()
	ability.duration = 0.2
	_hold("tent_pole_1")
	ability.activate()
	assert_bool(ability.is_active()).is_true()
	await await_millis(500)
	assert_array(ability.highlighted_ids()).is_empty()
	assert_bool(ability.is_active()).is_false()
	for pole in ["tent_pole_2", "tent_pole_3", "tent_pole_4"]:
		assert_array(_shells(pole)).is_empty()


func test_pressing_again_restarts_the_timer_instead_of_stacking() -> void:
	_unlock()
	ability.duration = 1.0
	_hold("tent_pole_1")
	ability.activate()
	await await_millis(400)
	ability.activate()
	# One shell per item, not two, and the clock started over.
	assert_int(island.find_children("*", "InsightHighlight", true, false).size()).is_equal(3)
	assert_float(ability.seconds_remaining()).is_greater(0.7)


# --- Through the hill -----------------------------------------------------------------

func test_the_glow_is_drawn_through_terrain_and_not_on_the_item() -> void:
	_unlock()
	_hold("tent_pole_1")
	ability.activate()
	var shell := _shells("tent_pole_2")[0] as InsightHighlight
	var mat := shell.material_override as StandardMaterial3D
	assert_object(mat).is_not_null()
	# Seeing the fourth pole through a hill is the entire ability.
	assert_bool(mat.no_depth_test).is_true()
	assert_int(mat.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_int(mat.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	# It wraps the item; it is not the item.
	assert_object(shell.get_parent()).is_same(_item("tent_pole_2"))
	# The shell wraps the item, so it has to be bigger than it on every axis.
	var item_box := (_item("tent_pole_2").get_node("Collision").shape as BoxShape3D).size
	var shell_box := (shell.mesh as BoxMesh).size
	assert_float(shell_box.x).is_greater(item_box.x)
	assert_float(shell_box.y).is_greater(item_box.y)
	assert_float(shell_box.z).is_greater(item_box.z)


func test_every_highlight_owns_its_material_rather_than_sharing_one() -> void:
	_unlock()
	_hold("tent_pole_1")
	ability.activate()
	var a := (_shells("tent_pole_2")[0] as InsightHighlight).material_override
	var b := (_shells("tent_pole_3")[0] as InsightHighlight).material_override
	assert_object(a).is_not_same(b)


func test_the_item_itself_is_never_repainted() -> void:
	_unlock()
	var pole := _item("tent_pole_2")
	var before: Array[Color] = _albedos(pole.visual)
	_hold("tent_pole_1")
	ability.activate()
	assert_array(_albedos(pole.visual)).contains_exactly(before)


# --- Picking a glowing item up ----------------------------------------------------------

func test_picking_up_a_glowing_sibling_puts_its_glow_out() -> void:
	_unlock(true)
	_hold("tent_pole_1")
	ability.activate()
	GameSession.submit(Commands.pick_up(pid, "tent_pole_2"))
	assert_array(ability.highlighted_ids()).contains_exactly(["tent_pole_3", "tent_pole_4"])
	assert_array(_shells("tent_pole_2")).is_empty()
	assert_int(island.find_children("*", "InsightHighlight", true, false).size()).is_equal(2)


func test_packing_a_glowing_sibling_puts_its_glow_out() -> void:
	_unlock(true)
	_hold("tent_pole_1")
	ability.activate()
	_pack("tent_pole_3", "tent_bag")
	assert_array(ability.highlighted_ids()).contains_exactly(["tent_pole_2", "tent_pole_4"])
	assert_array(_shells("tent_pole_3")).is_empty()


# --- Teardown -----------------------------------------------------------------------------

func test_clearing_frees_the_nodes_rather_than_queueing_them() -> void:
	_unlock()
	_hold("tent_pole_1")
	ability.activate()
	var shell := _shells("tent_pole_2")[0]
	ability.clear()
	# free(), not queue_free(): valid immediately after, and the item is clean.
	assert_bool(is_instance_valid(shell)).is_false()
	assert_int(island.find_children("*", "InsightHighlight", true, false).size()).is_equal(0)
	assert_array(ability.highlighted_ids()).is_empty()


func test_no_highlight_survives_the_level_ending() -> void:
	_unlock()
	_hold("tent_pole_1")
	ability.activate()
	# The level goes away the way Main tears it down: freed, not queued.
	remove_child(island)
	island.free()
	island = null
	# Whatever the ability was pointing at is gone; clearing must not resurrect
	# or leak it, and must not crash on the dangling references.
	ability.clear()
	assert_array(ability.highlighted_ids()).is_empty()
	remove_child(ability)
	ability.free()
	ability = null
	# gdUnit4 counts orphans for this test; anything left over fails it here.


func test_a_new_level_clears_what_the_old_one_lit() -> void:
	_unlock()
	_hold("tent_pole_1")
	ability.activate()
	assert_bool(ability.is_active()).is_true()
	GameEvents.level_loaded.emit("island_01")
	assert_array(ability.highlighted_ids()).is_empty()


# --- Wiring ---------------------------------------------------------------------------------

func test_the_ability_is_bound_to_its_own_input_action() -> void:
	assert_str(InsightAbility.INPUT_ACTION).is_equal("ability_insight")
	assert_bool(InputMap.has_action(InsightAbility.INPUT_ACTION)).is_true()


func test_the_key_press_is_what_activates_it() -> void:
	_unlock()
	_hold("tent_pole_1")
	assert_bool(_press_f()).is_true()
	assert_array(ability.highlighted_ids()).contains_exactly(
		["tent_pole_2", "tent_pole_3", "tent_pole_4"])
	# Any other key is none of this node's business.
	var other := InputEventAction.new()
	other.action = "jump"
	other.pressed = true
	assert_bool(ability.handle_input(other)).is_false()


func test_installing_twice_leaves_exactly_one_ability_node() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var first := InsightAbility.install(host)
	assert_bool(is_instance_valid(first)).is_true()
	InsightAbility.install(host)
	assert_int(host.find_children("*", "InsightAbility", true, false).size()).is_equal(1)
	assert_bool(is_instance_valid(first)).is_false()


func test_nothing_happens_once_the_level_has_stopped() -> void:
	_unlock()
	_hold("tent_pole_1")
	GameSession.stop_level()
	ability.activate()
	assert_array(ability.highlighted_ids()).is_empty()


# --- Private ---------------------------------------------------------------------------------

## Hand the ability the event the F key produces. Godot does not transport
## InputEvents in headless mode, so pushing one into the viewport would prove
## nothing — this goes through the same entry point _unhandled_input uses.
func _press_f() -> bool:
	var event := InputEventAction.new()
	event.action = InsightAbility.INPUT_ACTION
	event.pressed = true
	return ability.handle_input(event)


func _albedos(node: Node3D) -> Array[Color]:
	var out: Array[Color] = []
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for surface in range(maxi(1, mesh.get_surface_override_material_count())):
			var mat: Material = mesh.get_active_material(surface)
			out.append((mat as StandardMaterial3D).albedo_color if mat is StandardMaterial3D else Color.BLACK)
	return out
