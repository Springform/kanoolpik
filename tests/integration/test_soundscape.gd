extends GdUnitTestSuite
## WP-2.6 — ambience and layered music that thickens with progress.
##
## Drives the mix purely by emitting GameEvents.progress_changed and by
## calling Soundscape's own API, then asserts on Soundscape.target_gain() /
## ambience_target_gain() (pure, instant) plus bus/stream state. Nothing here
## waits on real playback timing, per the WP.

const AUDIO_BUDGET_BYTES := 6 * 1024 * 1024


func before_test() -> void:
	# Leave any mute/layer-mute a previous test set from bleeding into this one.
	Soundscape.mute(false)
	for i in range(Soundscape.layer_count()):
		Soundscape.set_layer_muted(i, false)
	Soundscape.set_intensity(0.0)


func after_test() -> void:
	if GameSession.is_running():
		GameSession.stop_level()
	Soundscape.mute(false)
	for i in range(Soundscape.layer_count()):
		Soundscape.set_layer_muted(i, false)


# --- Buses -------------------------------------------------------------------

func test_music_and_ambience_buses_are_registered() -> void:
	assert_int(AudioServer.get_bus_index("Music")).is_greater_equal(0)
	assert_int(AudioServer.get_bus_index("Ambience")).is_greater_equal(0)
	assert_int(AudioServer.get_bus_index("SFX")).is_greater_equal(0)


func test_layers_route_to_the_right_bus() -> void:
	assert_int(Soundscape.layer_count()).is_equal(MusicMix.stem_count())
	for i in range(Soundscape.layer_count()):
		assert_str(String(Soundscape.stem_player(i).bus)).is_equal("Music")
	assert_str(String(Soundscape.ambience_player().bus)).is_equal("Ambience")


func test_streams_loop_forward() -> void:
	assert_object(Soundscape.ambience_player().stream).is_not_null()
	assert_int(Soundscape.ambience_player().stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	for i in range(Soundscape.layer_count()):
		assert_int(Soundscape.stem_player(i).stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)


# --- Silence when nothing is running ------------------------------------------

func test_no_level_running_means_no_music() -> void:
	assert_bool(GameSession.is_running()).is_false()
	for i in range(Soundscape.layer_count()):
		assert_float(Soundscape.target_gain(i)).is_equal(0.0)


func test_title_screen_keeps_ambience_but_silences_music() -> void:
	# Mirrors Main.to_title(): a level is built (for the backdrop) then
	# immediately stopped, so nothing can act on the world and no music plays.
	GameSession.start_level("island_01", 1)
	GameSession.stop_level()
	assert_bool(GameSession.is_running()).is_false()
	assert_float(Soundscape.ambience_target_gain()).is_greater(0.0)
	for i in range(Soundscape.layer_count()):
		assert_float(Soundscape.target_gain(i)).is_equal(0.0)


# --- Intensity shapes the mix --------------------------------------------------

func test_progress_zero_is_sparse() -> void:
	GameSession.start_level("island_01", 1)
	GameEvents.progress_changed.emit({"completion": 0.0})
	assert_float(Soundscape.target_gain(0)).is_greater(0.0) # pad: present but quiet
	assert_float(Soundscape.target_gain(1)).is_equal(0.0) # melody: not yet
	assert_float(Soundscape.target_gain(2)).is_equal(0.0) # shimmer: not yet


func test_progress_rising_thickens_the_mix() -> void:
	GameSession.start_level("island_01", 1)
	GameEvents.progress_changed.emit({"completion": 0.45})
	assert_float(Soundscape.target_gain(0)).is_equal(MusicMix.stem_gain(0, 0.45))
	assert_float(Soundscape.target_gain(1)).is_greater(0.0)
	assert_float(Soundscape.target_gain(2)).is_equal(0.0)


func test_progress_full_brings_in_every_stem() -> void:
	GameSession.start_level("island_01", 1)
	GameEvents.progress_changed.emit({"completion": 1.0})
	for i in range(Soundscape.layer_count()):
		assert_float(Soundscape.target_gain(i)).is_greater(0.0)


func test_set_intensity_can_be_driven_directly() -> void:
	GameSession.start_level("island_01", 1)
	Soundscape.set_intensity(0.7)
	assert_float(Soundscape.intensity()).is_equal_approx(0.7, 0.001)
	assert_float(Soundscape.target_gain(2)).is_greater(0.0)


func test_set_intensity_clamps() -> void:
	Soundscape.set_intensity(3.0)
	assert_float(Soundscape.intensity()).is_equal(1.0)
	Soundscape.set_intensity(-2.0)
	assert_float(Soundscape.intensity()).is_equal(0.0)


# --- Mute / per-layer control (Provides, for the phase 5 settings screen) -----

func test_mute_silences_both_buses_but_not_sfx() -> void:
	Soundscape.mute(true)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music"))).is_true()
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience"))).is_true()
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX"))).is_false()
	assert_float(Soundscape.ambience_target_gain()).is_equal(0.0)
	Soundscape.mute(false)
	assert_bool(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music"))).is_false()


func test_layer_can_be_muted_independently() -> void:
	GameSession.start_level("island_01", 1)
	GameEvents.progress_changed.emit({"completion": 1.0})
	assert_float(Soundscape.target_gain(1)).is_greater(0.0)
	Soundscape.set_layer_muted(1, true)
	assert_float(Soundscape.target_gain(1)).is_equal(0.0)
	# Untouched stems keep playing at their own target.
	assert_float(Soundscape.target_gain(0)).is_greater(0.0)


# --- Seamless loops (assert the seam, don't trust ears) ------------------------

func _decode_range(stream: AudioStreamWAV, start_frame: int, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	for i in range(count):
		out[i] = float(stream.data.decode_s16((start_frame + i) * 2)) / 32768.0
	return out


func _max_seam_jump(stream: AudioStreamWAV, edge := 4000) -> Dictionary:
	var total_frames := stream.data.size() / 2
	var head := _decode_range(stream, 0, edge)
	var tail := _decode_range(stream, total_frames - edge, edge)
	var wrap_delta := absf(head[0] - tail[tail.size() - 1])
	var internal: Array[float] = []
	for i in range(1, edge):
		internal.append(absf(head[i] - head[i - 1]))
		internal.append(absf(tail[i] - tail[i - 1]))
	internal.sort()
	var p95: float = internal[int(internal.size() * 0.95)]
	return {"wrap": wrap_delta, "typical": p95}


func test_ambience_loops_without_an_audible_seam() -> void:
	var stream: AudioStreamWAV = load("res://assets/audio/ambience/lake_morning.wav")
	var seam := _max_seam_jump(stream)
	assert_float(seam["wrap"]).override_failure_message(
		"ambience seam jump %.5f is much larger than a typical sample delta %.5f — it will click" %
		[seam["wrap"], seam["typical"]]
	).is_less_equal(float(seam["typical"]) * 2.0 + 0.001)


func test_music_stems_loop_without_an_audible_seam() -> void:
	for path in ["res://assets/audio/music/stem_pad.wav", "res://assets/audio/music/stem_melody.wav",
			"res://assets/audio/music/stem_shimmer.wav"]:
		var stream: AudioStreamWAV = load(path)
		var seam := _max_seam_jump(stream)
		assert_float(seam["wrap"]).override_failure_message(
			"%s seam jump %.5f exceeds typical sample delta %.5f" % [path, seam["wrap"], seam["typical"]]
		).is_less_equal(float(seam["typical"]) * 2.0 + 0.001)


# --- Budget --------------------------------------------------------------------

func test_added_audio_stays_under_budget() -> void:
	var total := 0
	for dir_path in ["res://assets/audio/ambience", "res://assets/audio/music"]:
		var dir := DirAccess.open(dir_path)
		assert_object(dir).override_failure_message("missing dir: %s" % dir_path).is_not_null()
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir() and not f.ends_with(".import"):
				total += FileAccess.get_file_as_bytes(dir_path + "/" + f).size()
			f = dir.get_next()
	assert_int(total).override_failure_message(
		"added assets/audio (ambience+music) is %.2f MB, over the 6 MB WP-2.6 budget" % (total / 1048576.0)
	).is_less(AUDIO_BUDGET_BYTES)
