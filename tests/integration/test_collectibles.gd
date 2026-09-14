extends GdUnitTestSuite
## WP-3.7 — the four hidden things: where they are, how you find one, and the
## two promises the rest of the game depends on.
##
## The promises, in order of how expensive they would be to get wrong:
##   1. A collectible is **not an item**. It never counts toward completion,
##      accuracy or the island-clean check. If it ever does, the island stops
##      being cleanable and the score becomes a lie.
##   2. The trolley's +3 composes with Rolige hænder's +2 rather than replacing
##      it, and the sum is computed in exactly one place.
##
## The placement assertions are the other half of the WP: hand-authored hiding
## places are only good hiding places if they are on walkable ground, out of the
## containers, out of the trees and out of each other's way. A position typed
## into the level JSON that fails any of those is caught here rather than by a
## player who walks to the shore and finds a trolley standing in the lake.

const SLOT := "collectibles_integration_test"
const LEVEL_PATH := "res://data/levels/island_01.json"
## Sorted, because everything the core hands back is sorted.
const IDS: Array[String] = ["headlamp", "sunglasses", "trolley", "whistle"]
## How near two hiding places may be before finding one gives the other away.
const MIN_SEPARATION := 4.0
## How close a hiding place may be to a tree trunk or a bush before the thing
## is inside the scenery rather than behind it.
const MIN_SCENERY_CLEARANCE := 1.0
## Nothing may be findable from where a player stands up.
const MIN_SPAWN_CLEARANCE := 3.0

var island: Island
var spawner: CollectibleSpawner
var player: Player
var pid: int

var _found_events: Array[String] = []
var _rejections: Array[String] = []
var _capacities: Array[int] = []
var _clean_seen := 0


func before_test() -> void:
	SaveGame.erase(SLOT)
	GameSession.start_level("island_01", 4242)
	GameSession.autosave_enabled = false
	pid = GameSession.local_player_id()
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)
	spawner = auto_free(CollectibleSpawner.install(self))
	_found_events.clear()
	_rejections.clear()
	_capacities.clear()
	_clean_seen = 0
	GameEvents.collectible_found.connect(_on_found)
	GameEvents.command_rejected.connect(_on_rejected)
	GameEvents.capacity_changed.connect(_on_capacity)
	GameEvents.island_clean.connect(_on_clean)


func after_test() -> void:
	GameEvents.collectible_found.disconnect(_on_found)
	GameEvents.command_rejected.disconnect(_on_rejected)
	GameEvents.capacity_changed.disconnect(_on_capacity)
	GameEvents.island_clean.disconnect(_on_clean)
	GameSession.autosave_enabled = true
	SaveGame.erase(SLOT)
	GameSession.stop_level()


# --- Helpers ---------------------------------------------------------------------

func _on_found(collectible_id: String, _player_id: int) -> void:
	_found_events.append(collectible_id)


func _on_rejected(_command: Dictionary, error: String) -> void:
	_rejections.append(error)


func _on_capacity(_player_id: int, capacity: int) -> void:
	_capacities.append(capacity)


func _on_clean() -> void:
	_clean_seen += 1


func _level() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LEVEL_PATH))


## A player standing somewhere, without the mouse capture and input handling a
## local one turns on. The group is the real mechanism [Player] uses to announce
## itself, so joining it by hand is the same thing happening, quietly.
func _add_player(at: Vector3) -> Player:
	var p: Player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	p.is_local = false
	p.player_id = pid
	p.spawn_position = at
	p.position = at
	add_child(p)
	p.add_to_group(Player.LOCAL_GROUP)
	return p


## Stand on top of a hiding place and look.
func _walk_to(collectible_id: String) -> void:
	var node := spawner.node_for(collectible_id)
	assert_object(node).override_failure_message(
		"the level does not place '%s'" % collectible_id).is_not_null()
	if player == null:
		player = _add_player(node.global_position)
	player.global_position = node.global_position
	spawner.check_for_finds()


func _find_all() -> void:
	for id in IDS:
		_walk_to(id)


func _add_hud() -> HUD:
	var hud: HUD = auto_free(load("res://src/game/hud/hud.tscn").instantiate())
	add_child(hud)
	return hud


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Every tree and bush standing on the island. Trees carry a collider and bushes
## do not, so both lists are gathered by node rather than by class — a thing you
## cannot walk through and a thing you cannot see through hide a collectible
## equally well.
func _scenery_pieces() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for group_name in ["Scenery/Trees", "Scenery/Bushes"]:
		var group := island.get_node_or_null(group_name)
		assert_object(group).override_failure_message(
			"the island has no %s" % group_name).is_not_null()
		if group == null:
			continue
		for piece: Node3D in group.get_children():
			out.append(piece)
	return out


## Everything correctly packed, the long way round, exactly as a player would.
func _clean_the_island() -> void:
	for item_id in GameSession.catalog.item_ids():
		var item := GameSession.catalog.get_item(item_id)
		for container in GameSession.catalog.containers_accepting(item.category):
			var slot := PlacementRules.find_correct_slot(
				GameSession.catalog, GameSession.state, item_id, container.id)
			if slot < 0:
				continue
			GameSession.submit(Commands.pick_up(pid, item_id))
			GameSession.submit(Commands.place(pid, item_id, container.id, slot))
			break


# --- The level data: four hand-chosen places ----------------------------------------

func test_the_level_hides_exactly_the_four_the_core_knows_about() -> void:
	var placed: Array[String] = []
	for entry: Dictionary in CollectibleSpawner.placements(_level()):
		placed.append(String(entry.get("id", "")))
	placed.sort()
	assert_array(placed).contains_exactly(IDS)
	var known: Array[String] = []
	for key: Variant in Progression.COLLECTIBLES.keys():
		known.append(String(key))
	known.sort()
	# Something in the table with nowhere to be found is unfindable, and a
	# position for something the table does not know is unfound-able.
	assert_array(placed).contains_exactly(known)


func test_every_placement_is_hand_written_rather_than_a_bare_position() -> void:
	# Each entry carries the sentence that says which hiding place it is. It is
	# the only record of *why* the position is that position.
	for entry: Dictionary in CollectibleSpawner.placements(_level()):
		assert_str(String(entry.get("note", ""))).override_failure_message(
			"placement '%s' has no note saying where it hides" % entry.get("id", "")).is_not_empty()
		var p: Array = entry["position"]
		assert_int(p.size()).is_equal(3)


func test_the_spawner_puts_one_of_each_on_the_island() -> void:
	var built: Array[String] = []
	for node in spawner.nodes():
		built.append(node.collectible_id)
	built.sort()
	assert_array(built).contains_exactly(IDS)
	assert_array(spawner.remaining_ids()).contains_exactly(IDS)


func test_every_hiding_place_is_on_walkable_ground() -> void:
	for node in spawner.nodes():
		var at := node.global_position
		var where := "%s at %s" % [node.collectible_id, at]
		assert_bool(island.is_on_land(at.x, at.z)).override_failure_message(
			"%s is in the lake" % where).is_true()
		assert_float(Vector2(at.x, at.z).length()).override_failure_message(
			"%s is outside the island" % where).is_less(GameSession.island_radius())
		assert_float(island.slope_degrees_at(at.x, at.z)).override_failure_message(
			"%s is on a cliff" % where).is_less(Island.MAX_WALKABLE_SLOPE_DEG)


func test_nothing_sits_in_the_terrain_or_floats_over_it() -> void:
	for node in spawner.nodes():
		var at := node.global_position
		var ground := island.height_at(at.x, at.z)
		assert_float(at.y).override_failure_message(
			"%s is sunk into the hillside" % node.collectible_id).is_greater_equal(ground - 0.01)
		assert_float(at.y).override_failure_message(
			"%s hovers above the ground" % node.collectible_id).is_less_equal(
				ground + Collectible.LIFT + Collectible.BOB_HEIGHT + 0.01)


func test_nothing_is_hidden_inside_a_container() -> void:
	for node in spawner.nodes():
		for cid in GameSession.catalog.container_ids():
			var footprint := GameSession.catalog.get_container(cid).footprint_radius()
			var distance := _flat(node.global_position, GameSession.container_position(cid))
			assert_float(distance).override_failure_message(
				"%s is %.2f m from '%s' (footprint %.2f m) — inside it" % [
					node.collectible_id, distance, cid, footprint]).is_greater(footprint)


func test_nothing_is_hidden_inside_a_tree_or_a_bush() -> void:
	var scenery := _scenery_pieces()
	# Without this the suite would pass just as happily on an island with no
	# trees on it, which is the one case where the check means nothing.
	assert_int(scenery.size()).override_failure_message(
		"no trees or bushes found — this test would pass on an empty island"
	).is_greater(Scenery.TREE_COUNT)
	for node in spawner.nodes():
		for piece: Node3D in scenery:
			var distance := _flat(node.global_position, piece.global_position)
			assert_float(distance).override_failure_message(
				"%s is %.2f m from a %s — it is inside the scenery" % [
					node.collectible_id, distance, piece.name]).is_greater(MIN_SCENERY_CLEARANCE)


func test_the_four_are_hidden_in_four_different_places() -> void:
	var all := spawner.nodes()
	for i in range(all.size()):
		for j in range(i + 1, all.size()):
			var distance := _flat(all[i].global_position, all[j].global_position)
			assert_float(distance).override_failure_message(
				"%s and %s are %.2f m apart — finding one gives away the other" % [
					all[i].collectible_id, all[j].collectible_id, distance]
			).is_greater(MIN_SEPARATION)


func test_nothing_is_found_by_standing_up_at_the_spawn() -> void:
	var spawns: Array = GameSession.level["player_spawns"]
	for index in range(spawns.size()):
		var spawn := GameSession.player_spawn(index)
		for node in spawner.nodes():
			assert_float(_flat(spawn, node.global_position)).override_failure_message(
				"%s is within reach of spawn %d" % [node.collectible_id, index]
			).is_greater(MIN_SPAWN_CLEARANCE)


func test_a_collectible_has_nothing_to_bump_into() -> void:
	# The rule Dressing follows for the same reason: a prop with a collider can
	# pin the player against a container, and there is no way to tell it from a
	# 163rd object that refuses to be picked up.
	for node in spawner.nodes():
		assert_int(node.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
		assert_int(node.find_children("*", "CollisionShape3D", true, false).size()).is_equal(0)


func test_a_collectible_carries_no_name_label() -> void:
	# A label floating over a hiding place is a sign saying "here".
	for node in spawner.nodes():
		assert_int(node.find_children("*", "Label3D", true, false).size()).is_equal(0)


# --- Finding one -------------------------------------------------------------------

func test_walking_up_to_one_finds_it_and_says_so() -> void:
	var hud := _add_hud()
	_walk_to("trolley")
	assert_bool(GameSession.progression.has_found("trolley")).is_true()
	assert_array(_found_events).contains_exactly(["trolley"])
	assert_array(hud.toast_texts()).contains(
		[tr("ui.collectible.found") % tr("collectible.trolley")])
	# And it is off the island, not still bobbing in the reeds.
	assert_bool(spawner.node_for("trolley").visible).is_false()
	assert_array(spawner.remaining_ids()).contains_exactly(
		["headlamp", "sunglasses", "whistle"])


func test_standing_in_the_same_spot_again_does_nothing_at_all() -> void:
	_walk_to("trolley")
	_found_events.clear()
	_rejections.clear()
	for i in range(20):
		spawner.check_for_finds()
	assert_array(_found_events).is_empty()
	# Silence, not a refused command every frame: the spawner stops asking once
	# the thing is found rather than leaning on the core to say no 60 times a
	# second (which the HUD would turn into 60 error toasts).
	assert_array(_rejections).is_empty()


func test_walking_past_at_a_distance_finds_nothing() -> void:
	var node := spawner.node_for("whistle")
	player = _add_player(node.global_position + Vector3(0, 0, CollectibleSpawner.FIND_RADIUS + 1.5))
	spawner.check_for_finds()
	assert_array(_found_events).is_empty()
	assert_bool(GameSession.progression.has_found("whistle")).is_false()
	# …and one step closer does.
	player.global_position = node.global_position
	spawner.check_for_finds()
	assert_array(_found_events).contains_exactly(["whistle"])


func test_a_hiding_place_on_the_hill_above_you_is_not_within_reach() -> void:
	var node := spawner.node_for("headlamp")
	player = _add_player(node.global_position - Vector3(0, CollectibleSpawner.FIND_HEIGHT + 1.0, 0))
	spawner.check_for_finds()
	assert_array(_found_events).is_empty()


func test_finding_all_four_says_so_once_more() -> void:
	var hud := _add_hud()
	_find_all()
	assert_array(_found_events).contains_exactly(IDS)
	assert_array(GameSession.progression.found_collectibles()).contains_exactly(IDS)
	assert_array(hud.toast_texts()).contains([tr("ui.collectible.found_all")])
	assert_array(spawner.remaining_ids()).is_empty()
	for node in spawner.nodes():
		assert_bool(node.visible).is_false()


func test_a_toast_is_written_in_the_players_language() -> void:
	var hud := _add_hud()
	_walk_to("headlamp")
	var expected := tr("ui.collectible.found") % tr("collectible.headlamp")
	assert_str(expected).is_not_equal("ui.collectible.found") # the row really exists
	assert_str(expected).contains(tr("collectible.headlamp"))
	assert_array(hud.toast_texts()).contains([expected])


# --- The trolley, and the one place capacity is computed ------------------------------

func test_the_trolley_carries_three_more_and_composes_with_steady_hands() -> void:
	assert_int(GameSession.base_capacity()).is_equal(Progression.BASE_CAPACITY)
	_walk_to("trolley")
	assert_int(GameSession.progression.capacity_bonus()).is_equal(3)
	assert_int(GameSession.base_capacity()).is_equal(6)
	# Now buy Rolige hænder the real way, through a command.
	GameSession.state.progression.points = 2
	GameSession.submit(Commands.unlock(pid, "steady_hands"))
	# 3 + 2 + 3 = 8, and the +3 did not replace the +2.
	assert_int(GameSession.base_capacity()).is_equal(8)
	assert_int(GameSession.progression.capacity()).is_equal(8)
	assert_int(Progression.BASE_CAPACITY + GameSession.progression.capacity_bonus()).is_equal(8)


func test_the_order_the_two_arrive_in_does_not_change_the_sum() -> void:
	GameSession.state.progression.points = 2
	GameSession.submit(Commands.unlock(pid, "steady_hands"))
	assert_int(GameSession.base_capacity()).is_equal(5)
	_walk_to("trolley")
	assert_int(GameSession.base_capacity()).is_equal(8)


func test_finding_the_trolley_tells_everyone_their_hands_grew() -> void:
	_walk_to("trolley")
	assert_array(_capacities).contains([6])


func test_the_other_three_are_flags_and_grant_nothing_today() -> void:
	_walk_to("sunglasses")
	_walk_to("headlamp")
	_walk_to("whistle")
	assert_int(GameSession.base_capacity()).is_equal(Progression.BASE_CAPACITY)
	assert_array(GameSession.progression.found_collectibles()).contains_exactly(
		["headlamp", "sunglasses", "whistle"])


# --- Not an item: the promise the rest of the game rests on ----------------------------

func test_a_collectible_is_neither_an_item_nor_a_container() -> void:
	for id in IDS:
		assert_object(GameSession.catalog.get_item(id)).override_failure_message(
			"'%s' is in the item catalog — it would count toward completion" % id).is_null()
		assert_bool(GameSession.catalog.item_ids().has(id)).is_false()
		assert_bool(GameSession.catalog.container_ids().has(id)).is_false()
		# Nowhere in the world state either: not on the ground, not carried,
		# not placed. kind_of() returns -1 for something it has never heard of.
		assert_int(GameSession.state.kind_of(id)).is_equal(-1)


func test_finding_all_four_changes_no_number_on_the_scoreboard() -> void:
	var before := Evaluation.progress(GameSession.catalog, GameSession.state)
	var score_before := Evaluation.score(GameSession.catalog, GameSession.state)
	_find_all()
	assert_dict(Evaluation.progress(GameSession.catalog, GameSession.state)).is_equal(before)
	assert_dict(Evaluation.score(GameSession.catalog, GameSession.state)).is_equal(score_before)


func test_the_island_is_clean_with_all_four_still_hidden() -> void:
	_clean_the_island()
	assert_bool(PlacementRules.is_island_clean(
		GameSession.catalog, GameSession.state)).override_failure_message(
		"the island cannot be finished while the collectibles are still out there").is_true()
	assert_int(_clean_seen).is_equal(1)
	# Nothing was found on the way: the clean check ignored them entirely.
	assert_array(GameSession.progression.found_collectibles()).is_empty()
	assert_array(spawner.remaining_ids()).contains_exactly(IDS)
	assert_float(Evaluation.progress(GameSession.catalog, GameSession.state)["completion"]).is_equal(1.0)


func test_finding_one_first_does_not_stop_the_island_getting_clean() -> void:
	_walk_to("sunglasses")
	_clean_the_island()
	assert_bool(PlacementRules.is_island_clean(GameSession.catalog, GameSession.state)).is_true()
	assert_int(_clean_seen).is_equal(1)


# --- Save and resume ---------------------------------------------------------------------

func test_found_things_survive_a_save_and_a_resume() -> void:
	_walk_to("trolley")
	_walk_to("whistle")
	assert_bool(GameSession.save(SLOT)).is_true()
	GameSession.stop_level()

	assert_bool(GameSession.load_save(SLOT)).is_true()
	assert_array(GameSession.progression.found_collectibles()).contains_exactly(
		["trolley", "whistle"])
	# The trolley still carries three more after the resume.
	assert_int(GameSession.base_capacity()).is_equal(6)


func test_a_resumed_island_puts_back_only_what_is_still_hidden() -> void:
	_walk_to("trolley")
	_walk_to("whistle")
	assert_bool(GameSession.save(SLOT)).is_true()
	GameSession.stop_level()
	assert_bool(GameSession.load_save(SLOT)).is_true()

	var host: Node = auto_free(Node.new())
	add_child(host)
	var resumed := CollectibleSpawner.install(host)
	assert_array(resumed.remaining_ids()).contains_exactly(["headlamp", "sunglasses"])
	assert_bool(resumed.node_for("trolley").visible).is_false()
	assert_bool(resumed.node_for("whistle").visible).is_false()
	assert_bool(resumed.node_for("headlamp").visible).is_true()
	assert_bool(resumed.node_for("sunglasses").visible).is_true()
	# And walking back to where the trolley was finds nothing twice.
	_found_events.clear()
	_rejections.clear()
	player = _add_player(resumed.node_for("trolley").global_position)
	resumed.check_for_finds()
	assert_array(_found_events).is_empty()
	assert_array(_rejections).is_empty()


# --- Installing and tearing down -----------------------------------------------------------

func test_installing_twice_leaves_exactly_one_spawner_and_one_set() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var first := CollectibleSpawner.install(host)
	assert_bool(is_instance_valid(first)).is_true()
	CollectibleSpawner.install(host)
	assert_int(host.find_children("*", "CollectibleSpawner", true, false).size()).is_equal(1)
	assert_int(host.find_children("*", "Collectible", true, false).size()).is_equal(IDS.size())
	assert_bool(is_instance_valid(first)).is_false()


func test_clearing_frees_the_nodes_rather_than_queueing_them() -> void:
	var trolley := spawner.node_for("trolley")
	spawner.clear()
	assert_bool(is_instance_valid(trolley)).is_false()
	assert_int(spawner.find_children("*", "Collectible", true, false).size()).is_equal(0)
	assert_array(spawner.remaining_ids()).is_empty()


func test_nothing_survives_the_level_being_torn_down() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var doomed := CollectibleSpawner.install(host)
	var trolley := doomed.node_for("trolley")
	host.remove_child(doomed)
	doomed.free()
	assert_bool(is_instance_valid(trolley)).is_false()
	# gdUnit4 counts orphans for this test; anything left over fails it here.


func test_nothing_is_found_once_the_level_has_stopped() -> void:
	player = _add_player(spawner.node_for("trolley").global_position)
	GameSession.stop_level()
	spawner.check_for_finds()
	assert_array(_found_events).is_empty()


# --- The glint ---------------------------------------------------------------------------------

func test_a_hidden_thing_turns_slowly_so_it_catches_the_eye() -> void:
	var node := spawner.node_for("sunglasses")
	var turned := node.rotation.y
	var height := node.position.y
	node._process(0.4)
	assert_float(node.rotation.y).is_not_equal(turned)
	assert_float(node.position.y).is_not_equal(height)
	# It bobs around the ground it was placed on, never through it.
	for step in range(24):
		node._process(0.1)
		assert_float(node.position.y).is_greater_equal(
			island.height_at(node.global_position.x, node.global_position.z))


func test_a_found_thing_stops_costing_frames() -> void:
	var node := spawner.node_for("whistle")
	assert_bool(node.is_processing()).is_true()
	_walk_to("whistle")
	assert_bool(node.is_processing()).is_false()
	assert_bool(node.visible).is_false()


func test_every_collectible_owns_its_materials_rather_than_sharing_them() -> void:
	var seen: Array[Material] = []
	for node in spawner.nodes():
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var mat := mesh.material_override
			assert_object(mat).is_not_null()
			assert_bool(seen.has(mat)).override_failure_message(
				"%s shares a material with another node" % node.collectible_id).is_false()
			seen.append(mat)
	assert_int(seen.size()).is_greater(10)
