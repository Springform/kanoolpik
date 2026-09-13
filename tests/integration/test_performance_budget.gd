extends GdUnitTestSuite
## WP-2.8 — the budgets that keep the island loading and running in a browser.
##
## Frame rate cannot be measured here: headless has no GPU, and the CI runner's
## software renderer would give a number that means nothing about a real
## machine. What *can* be pinned down is the shape of the scene — how many nodes
## exist, how much is asked of the renderer, how much there is to download — and
## that is what actually regresses. Somebody adds a `Label3D` to every slot and
## nobody notices until a laptop chokes on it.
##
## Real frame rates are a playtest job (see the WP). These are the guard rails.

## Generous against today's numbers, tight enough to catch a per-item mistake.
## Today a built island is ~2260 nodes: 162 items and 178 slots, each of which is
## a body, a mesh and a label. That is the shape of the scene, and a change that
## adds one more node per item would add another 160.
const MAX_ISLAND_NODES := 2800
## Roughly the draw-call count, and the number to watch on a real machine.
## Today: ~805 — 178 slot cubes, 162 items, and the trees, bushes and rocks.
## Grass and reeds are MultiMeshes and cost one call each however many tufts
## they hold; that is why they are not in this number, and why they must stay
## MultiMeshes. If a low-end laptop struggles, the obvious lever is hiding slot
## cubes on distant containers — but a container's slot colours are how you see
## from across the island that it is finished, so that trade is a playtest call,
## not a free win.
const MAX_MESH_INSTANCES := 1000

var island: Island


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(island)


func after_test() -> void:
	GameSession.stop_level()


func _count_class(node: Node, cls: String) -> int:
	return node.find_children("*", cls, true, false).size()


# --- Scene shape ----------------------------------------------------------------

func test_the_island_stays_within_its_node_budget() -> void:
	var total := island.find_children("*", "", true, false).size() + 1
	assert_int(total).override_failure_message(
		"the island is %d nodes; budget is %d. Something is being created per item or per slot."
		% [total, MAX_ISLAND_NODES]).is_less_equal(MAX_ISLAND_NODES)


func test_grass_stays_one_multimesh_rather_than_thousands_of_nodes() -> void:
	var grass: MultiMeshInstance3D = island.get_node("Scenery/Grass")
	assert_int(grass.multimesh.instance_count).override_failure_message(
		"no grass at all is a regression too").is_greater(500)
	assert_int(_count_class(island, "MeshInstance3D")).override_failure_message(
		"%d MeshInstance3D nodes — is something that should be a MultiMesh not one?"
		% _count_class(island, "MeshInstance3D")).is_less_equal(MAX_MESH_INSTANCES)


func test_the_cheap_shadow_settings_are_still_off_where_they_were_turned_off() -> void:
	# Grass and the trampled patch are flat and ankle-high; shadowing thousands
	# of tufts costs a lot and shows nothing.
	var grass: MultiMeshInstance3D = island.get_node("Scenery/Grass")
	assert_int(grass.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var patch: MeshInstance3D = island.get_node("Dressing/TrampledGround")
	assert_int(patch.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


# --- Per-frame work --------------------------------------------------------------

func test_item_labels_are_not_recomputed_every_frame_for_every_item() -> void:
	# 162 items each doing a camera lookup and a distance test every frame is
	# work that buys nothing: a label cannot become visible and invisible again
	# within a sixth of a second of walking.
	assert_int(PickupItem.LABEL_CHECK_FRAMES).is_greater(1)
	var items := island.get_node("Items").get_children()
	var buckets := {}
	for item: PickupItem in items:
		buckets[item.get_instance_id() % PickupItem.LABEL_CHECK_FRAMES] = true
	assert_int(buckets.size()).override_failure_message(
		"every item checks on the same frame — the cost is spread over none of them"
	).is_greater(1)


# --- Download --------------------------------------------------------------------

func test_the_content_we_control_stays_small() -> void:
	# The engine wasm is ~9.7 MB gzipped and not ours to shrink. Everything else
	# is, and it is the half that grows one model at a time.
	# tools/measure_build.py checks the exported build; this checks the sources,
	# so the number is visible before anyone exports anything.
	var total := 0
	for dir in ["res://assets/models", "res://assets/audio"]:
		total += _bytes_under(dir)
	assert_int(total).override_failure_message(
		"models + audio are %.1f MB of source" % (total / 1048576.0)).is_less_equal(12 * 1024 * 1024)


func _bytes_under(path: String) -> int:
	var total := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := path + "/" + entry
		if dir.current_is_dir():
			total += _bytes_under(full)
		elif not entry.ends_with(".import"):
			total += FileAccess.get_file_as_bytes(full).size()
		entry = dir.get_next()
	dir.list_dir_end()
	return total
