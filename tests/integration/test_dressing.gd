extends GdUnitTestSuite
## WP-2.7 — the props that explain the mess, and the promises they have to keep.
##
## Dressing is the one part of the island the player must never have to think
## about. The tests are therefore mostly about what it does NOT do: no colliders,
## no standing on a container, no drifting between runs of the same seed.

var island: Island


func _build(level_seed: int = 4242) -> Island:
	GameSession.start_level("island_01", level_seed)
	var node: Island = auto_free(load("res://src/game/island/island.tscn").instantiate())
	add_child(node)
	return node


func before_test() -> void:
	island = _build()


func after_test() -> void:
	GameSession.stop_level()


func _dressing() -> Dressing:
	return island.get_node("Dressing")


func _props() -> Array[Node]:
	return _dressing().get_children()


# --- It is there --------------------------------------------------------------------

func test_the_camp_is_dressed() -> void:
	assert_object(_dressing()).is_not_null()
	assert_array(_props()).override_failure_message(
		"a tidy island is not a story").is_not_empty()
	assert_object(_dressing().get_node_or_null("SleepingMate")).is_not_null()
	assert_object(_dressing().get_node_or_null("TrampledGround")).is_not_null()


func test_every_prop_stands_on_the_terrain() -> void:
	for prop in _props():
		if not (prop is Node3D) or prop.name == "TrampledGround":
			continue # the patch is built in world space, vertex by vertex
		var p: Vector3 = (prop as Node3D).position
		assert_float(p.y).override_failure_message(
			"'%s' is at y=%.2f but the ground there is %.2f" % [prop.name, p.y, island.height_at(p.x, p.z)]
		).is_equal_approx(island.height_at(p.x, p.z), 0.01)


func test_the_trampled_patch_follows_the_ground() -> void:
	var patch: MeshInstance3D = _dressing().get_node("TrampledGround")
	var aabb := patch.mesh.get_aabb()
	# It is a patch, not a dome: a few centimetres of relief over three metres.
	assert_float(aabb.size.y).is_less(1.5)
	assert_float(aabb.size.x).is_greater(3.0)


# --- It gets out of the way ----------------------------------------------------------

func test_no_prop_has_a_collider_anywhere_under_it() -> void:
	# The rule that matters: a prop with collision can pin the player against a
	# container, or hide an item behind something that cannot be moved — and the
	# player has no way to tell dressing from a real object.
	for prop in _props():
		var bodies := prop.find_children("*", "CollisionObject3D", true, false)
		assert_array(bodies).override_failure_message(
			"'%s' has %d collider(s); dressing is drawn and nothing else" % [prop.name, bodies.size()]
		).is_empty()
		assert_array(prop.find_children("*", "CollisionShape3D", true, false)).is_empty()


func test_no_prop_stands_on_a_container_or_a_player_spawn() -> void:
	for prop in _props():
		if not (prop is Node3D) or prop.name == "TrampledGround":
			continue
		var p: Vector3 = (prop as Node3D).position
		for cid in GameSession.catalog.container_ids():
			var c := GameSession.container_position(cid)
			var keep_out := GameSession.catalog.get_container(cid).footprint_radius()
			assert_float(Vector2(p.x - c.x, p.z - c.z).length()).override_failure_message(
				"'%s' is standing on '%s'" % [prop.name, cid]).is_greater(keep_out)
		for spawn: Array in GameSession.level["player_spawns"]:
			assert_float(Vector2(p.x - float(spawn[0]), p.z - float(spawn[2])).length()
				).override_failure_message("'%s' is in a player spawn" % prop.name).is_greater(1.0)


func test_dressing_stays_on_the_island() -> void:
	for prop in _props():
		if not (prop is Node3D) or prop.name == "TrampledGround":
			continue
		var p: Vector3 = (prop as Node3D).position
		assert_bool(island.is_on_land(p.x, p.z)).override_failure_message(
			"'%s' is in the lake" % prop.name).is_true()


# --- It is the same island twice ------------------------------------------------------

func test_the_same_seed_dresses_the_camp_the_same_way() -> void:
	var first := _positions_of(_dressing())
	GameSession.stop_level()
	island.free()
	island = _build(4242)
	assert_dict(_positions_of(_dressing())).is_equal(first)


func test_a_different_seed_moves_things() -> void:
	var first := _positions_of(_dressing())
	GameSession.stop_level()
	island.free()
	island = _build(1337)
	assert_dict(_positions_of(_dressing())).is_not_equal(first)


func _positions_of(dressing: Dressing) -> Dictionary:
	var out := {}
	for prop in dressing.get_children():
		if prop is Node3D:
			out[prop.name] = (prop as Node3D).position.snapped(Vector3.ONE * 0.001)
	return out


# --- The snore ------------------------------------------------------------------------

func test_the_snore_loops_and_is_a_local_sound() -> void:
	var snore: AudioStreamPlayer3D = _dressing().get_node("SleepingMate/Snore")
	assert_object(snore.stream).is_not_null()
	assert_int((snore.stream as AudioStreamWAV).loop_mode).override_failure_message(
		"a snore that plays once is a cough").is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_str(snore.bus).is_equal("SFX")
	assert_float(snore.max_distance).override_failure_message(
		"you should not hear him from the far shore").is_less_equal(20.0)


func test_the_snore_loop_has_no_seam() -> void:
	# Generated to be exactly periodic (tools/gen_sfx.py). Check it rather than
	# trusting it: a click every six seconds is the kind of thing you stop
	# hearing after an hour of work and a player hears immediately.
	#
	# Read the SOURCE .wav, not the imported AudioStreamWAV: the import
	# compresses to QOA (compress/mode=2), so `stream.data` is codec bytes and
	# decoding them as PCM measures nothing at all.
	var bytes := FileAccess.get_file_as_bytes("res://assets/audio/sfx/snore.wav")
	assert_int(bytes.size()).is_greater(44)
	var samples := (bytes.size() - 44) / 2 # 44-byte canonical WAV header
	var first := bytes.decode_s16(44)
	var last := bytes.decode_s16(44 + (samples - 1) * 2)
	assert_int(absi(last - first)).override_failure_message(
		"loop seam jumps by %d of 32767 — that is a click" % absi(last - first)).is_less(1200)
