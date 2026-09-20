extends GdUnitTestSuite
## WP-5.2 — how it feels to walk.
##
## The claim worth testing is not "walking feels nice", which no test can check.
## It is that **the numbers are per second**. The version before this one stopped
## the player with `move_toward(velocity, 0, speed)` and no delta, so how far it
## took to stop depended on the frame rate — and the web export's frame rate
## depends on whether the tab is in front. That is a correctness bug wearing a
## feel bug's clothes, and it is the thing these tests pin.
##
## Everything here drives [method Player.step_motion] or the pure helpers by
## hand. Nothing waits for a physics frame: a test that steps the real server
## measures the server.

const RATES := [30.0, 60.0, 144.0, 240.0]


func _player() -> Player:
	var player: Player = auto_free(load("res://src/game/player/player.tscn").instantiate())
	# No input, no mouse capture, no camera fight — the same switch the shots
	# harness and the remote-player tests use.
	player.is_local = false
	add_child(player)
	return player


## Integrate the horizontal step for [param seconds] at [param fps], starting
## from rest and holding one direction. Returns metres covered.
func _distance_at(fps: float, seconds: float, wish: Vector3, speed: float) -> float:
	var delta := 1.0 / fps
	var velocity := Vector3.ZERO
	var travelled := 0.0
	for _i in int(round(seconds * fps)):
		velocity = Player.next_horizontal_velocity(velocity, wish, speed, true, delta)
		travelled += Vector2(velocity.x, velocity.z).length() * delta
	return travelled


# --- Frame-rate independence ---------------------------------------------------------

func test_a_second_of_walking_is_the_same_second_at_any_frame_rate() -> void:
	var forward := Vector3(0, 0, -1)
	var reference := _distance_at(60.0, 1.0, forward, 4.5)
	for fps: float in RATES:
		var travelled := _distance_at(fps, 1.0, forward, 4.5)
		assert_float(absf(travelled - reference) / reference).override_failure_message(
			"a second at %d fps covered %.3f m, a second at 60 fps covered %.3f m"
			% [int(fps), travelled, reference]
		).is_less(0.02)


func test_stopping_takes_the_same_time_at_any_frame_rate() -> void:
	# The half that was actually broken: the old expression stopped a walking
	# player inside a single frame at every rate the game runs at.
	#
	# **Time, not distance, and the first version of this test got it wrong.**
	# Summing `speed * delta` over a ramp is explicit Euler, and its answer
	# depends on the step: the same deceleration measured 0.150 m at 30 fps and
	# 0.216 m at 240 fps, converging on the true 0.225 m. That is the
	# integrator, not the rule. What the rule guarantees exactly is the time —
	# v over a, whatever the step — so that is what is asserted, and the
	# distance is pinned separately at the rate physics actually runs at.
	var reference := -1.0
	for fps: float in RATES:
		var delta := 1.0 / fps
		var velocity := Vector3(0, 0, -4.5)
		var elapsed := 0.0
		while Vector2(velocity.x, velocity.z).length() > 0.0001:
			velocity = Player.next_horizontal_velocity(velocity, Vector3.ZERO, 4.5, true, delta)
			elapsed += delta
		if reference < 0.0:
			reference = elapsed
		assert_float(absf(elapsed - reference)).override_failure_message(
			"stopping took %.4f s at %d fps and %.4f s at %d fps"
			% [elapsed, int(fps), reference, int(RATES[0])]
		).is_less(delta + 0.0001)


func test_stopping_is_neither_instant_nor_ice() -> void:
	# A number, so it can be wrong in a way somebody can argue with: from walking
	# speed, between a hand's width and a stride. At 60, because that is what
	# `_physics_process` runs at — a physics tick is a fixed rate in Godot and
	# does not follow the render frame rate.
	var velocity := Vector3(0, 0, -4.5)
	var travelled := 0.0
	while Vector2(velocity.x, velocity.z).length() > 0.01:
		velocity = Player.next_horizontal_velocity(velocity, Vector3.ZERO, 4.5, true, 1.0 / 60.0)
		travelled += Vector2(velocity.x, velocity.z).length() * 1.0 / 60.0
	assert_float(travelled).override_failure_message(
		"a walking stop took %.3f m" % travelled).is_between(0.1, 0.9)


func test_the_air_gives_you_less_say_than_the_ground() -> void:
	var wish := Vector3(0, 0, -1)
	var on_ground := Player.next_horizontal_velocity(Vector3.ZERO, wish, 4.5, true, 1.0 / 60.0)
	var in_air := Player.next_horizontal_velocity(Vector3.ZERO, wish, 4.5, false, 1.0 / 60.0)
	assert_float(in_air.length()).is_less(on_ground.length())


func test_nothing_slows_you_down_in_mid_air() -> void:
	# Letting go of the keys mid-jump must not stop you dead in the air — that
	# is the one place friction would be visible as a bug rather than as feel.
	var velocity := Vector3(0, 0, -4.5)
	var after := Player.next_horizontal_velocity(velocity, Vector3.ZERO, 4.5, false, 1.0 / 60.0)
	assert_float(after.z).is_equal_approx(-4.5, 0.0001)


# --- Coyote time ---------------------------------------------------------------------

func test_the_coyote_window_is_short_enough_to_be_a_lie_nobody_notices() -> void:
	# It is a lie the game tells: for this long the player is airborne and the
	# game pretends otherwise. Three or four frames at 60 fps — long enough to
	# cover the frame somebody was a pixel past the rock, too short to cross a
	# gap with.
	assert_float(Player.COYOTE_TIME).is_between(0.05, 0.2)
	var reachable := 7.5 * Player.COYOTE_TIME
	assert_float(reachable).override_failure_message(
		"a sprinting player gets %.2f m of free air out of the coyote window" % reachable
	).is_less(1.5)


## A player standing on something, which is the only way `is_on_floor()` ever
## becomes true — it is set by `move_and_slide`, so a player floating in an empty
## test scene has never been on a floor and has no coyote window to spend. The
## first version of these two tests did exactly that and one of them passed
## anyway, which is the more interesting half.
func _player_on_a_floor() -> Player:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(auto_free(floor_body))
	var player := _player()
	player.global_position = Vector3(0, 1.2, 0)
	for _i in 30:
		player.step_motion(1.0 / 60.0, Vector3.ZERO, false, false)
	assert_bool(player.is_on_floor()).override_failure_message(
		"the test player never landed, so it has no coyote window to test").is_true()
	return player


func test_a_jump_at_the_edge_still_fires() -> void:
	var player := _player_on_a_floor()
	# Off the edge, without touching the floor again — exactly the frame the
	# window exists for.
	player.global_position += Vector3(0, 4.0, 0)
	player.velocity = Vector3.ZERO
	player.step_motion(1.0 / 60.0, Vector3.ZERO, false, true)
	assert_float(player.velocity.y).override_failure_message(
		"a jump one frame after leaving the ground did nothing").is_greater(0.0)


func test_the_window_runs_out() -> void:
	var player := _player_on_a_floor()
	player.global_position += Vector3(0, 4.0, 0)
	player.velocity = Vector3.ZERO
	# Past the window, in steps small enough that the player does not fall back
	# onto the floor while it runs out.
	for _i in 20:
		player.step_motion(Player.COYOTE_TIME / 8.0, Vector3.ZERO, false, false)
	var falling := player.velocity.y
	player.step_motion(1.0 / 60.0, Vector3.ZERO, false, true)
	assert_float(player.velocity.y).override_failure_message(
		"a jump long after leaving the ground fired anyway").is_less(falling)


# --- Jumping -------------------------------------------------------------------------

func test_you_can_get_onto_a_rock_and_not_onto_a_roof() -> void:
	# The acceptance criterion as arithmetic rather than as a level to walk
	# around: apex is v squared over 2g, and the island's rocks are half a metre.
	var player := _player()
	var apex := Player.jump_apex_height(player.jump_velocity, player.gravity())
	assert_float(apex).override_failure_message(
		"a jump reaches %.2f m; a 0.5 m rock has to work and a 1.2 m one must not" % apex
	).is_between(0.6, 1.15)


# --- Footsteps -----------------------------------------------------------------------

func test_a_stride_is_the_length_of_a_human_one() -> void:
	# In metres, not in units of itself. A test phrased as
	# "walking STRIDE_LENGTH * 3 makes 3 footsteps" is true for any value of
	# STRIDE_LENGTH, including half a stride — which is what a mutation run
	# pointed out, and it was right.
	assert_float(Player.STRIDE_LENGTH).override_failure_message(
		"a stride of %.2f m is not a person walking" % Player.STRIDE_LENGTH
	).is_between(0.6, 1.2)


func test_walking_ten_metres_is_about_eleven_footsteps() -> void:
	var player := _player()
	await get_tree().physics_frame
	var heard: Array[Vector3] = []
	player.footstep.connect(func(at: Vector3) -> void: heard.append(at))
	# Driven through the same private path physics uses, so the number being
	# tested is the one the game counts. Ten metres is a walk across the camp.
	for _i in 100:
		player._advance_stride(Vector3(0, 0, -0.1))
	assert_int(heard.size()).override_failure_message(
		"ten metres of walking made %d footsteps" % heard.size()).is_between(9, 14)


func test_standing_still_makes_no_footsteps() -> void:
	var player := _player()
	await get_tree().physics_frame
	var heard := 0
	player.footstep.connect(func(_at: Vector3) -> void: heard += 1)
	for _i in 120:
		player._advance_stride(Vector3.ZERO)
	assert_int(heard).is_equal(0)


func test_a_footstep_is_not_on_the_event_bus() -> void:
	# It fires two or three times a second and is not a fact about the world.
	# GameEvents is what every peer's presentation listens on; a footstep on it
	# would be the loudest thing on the bus and the least worth hearing.
	assert_bool(GameEvents.has_signal("footstep")).override_failure_message(
		"a footstep ended up on GameEvents").is_false()


# --- Head bob ------------------------------------------------------------------------

func test_head_bob_is_off_until_somebody_asks_for_it() -> void:
	# The one option that makes some people ill. Opt-in, not opt-out.
	assert_bool(bool(Settings.DEFAULTS[Settings.LOOK_HEAD_BOB])).is_false()


func test_a_camera_does_not_move_when_the_bob_is_off() -> void:
	var player := _player()
	await get_tree().physics_frame
	var rest := player.camera.position.y
	player.velocity = Vector3(0, 0, -4.5)
	for _i in 60:
		player._step_camera(1.0 / 60.0, false)
	assert_float(player.camera.position.y).is_equal_approx(rest, 0.0001)


func test_the_bob_moves_the_camera_and_puts_it_back() -> void:
	var player := _player()
	await get_tree().physics_frame
	var rest := player.camera.position.y
	player._head_bob = true
	player.velocity = Vector3(0, 0, -4.5)
	var lowest := rest
	var highest := rest
	for _i in 120:
		player._bob_distance += 4.5 / 60.0
		player._step_camera(1.0 / 60.0, false)
		lowest = minf(lowest, player.camera.position.y)
		highest = maxf(highest, player.camera.position.y)
	# Centimetres, not multiples of BOB_AMPLITUDE: phrased in its own units this
	# passes with an amplitude of zero, which a mutation run demonstrated.
	# Enough to feel, not enough to aim through.
	assert_float(highest - lowest).override_failure_message(
		"the head bob moved the camera %.4f m" % (highest - lowest)
	).is_between(0.02, 0.15)

	# And standing still settles, rather than leaving the camera wherever the
	# sine happened to be when the player stopped walking.
	player.velocity = Vector3.ZERO
	for _i in 120:
		player._step_camera(1.0 / 60.0, false)
	assert_float(player.camera.position.y).is_equal_approx(rest, 0.001)


# --- The sprint kick -----------------------------------------------------------------

func test_sprinting_widens_the_view_and_letting_go_narrows_it() -> void:
	var player := _player()
	await get_tree().physics_frame
	var base := player.camera.fov
	player.velocity = Vector3(0, 0, -7.5)
	for _i in 60:
		player._step_camera(1.0 / 60.0, true)
	var sprinting := player.camera.fov
	# Degrees, not multiples of the constant being tested: written the other way
	# round, this passes just as happily with a kick of zero.
	assert_float(sprinting - base).override_failure_message(
		"sprinting changed the field of view by %.2f degrees" % (sprinting - base)
	).is_between(3.0, 10.0)

	for _i in 180:
		player._step_camera(1.0 / 60.0, false)
	assert_float(player.camera.fov).is_equal_approx(base, 0.3)


func test_the_kick_arrives_faster_than_it_leaves() -> void:
	# A speedometer needle, not a dial: the change is the signal, so it should
	# land with the sprint and fade after it.
	assert_float(Player.FOV_KICK_IN).is_greater(Player.FOV_KICK_OUT)


func test_standing_still_and_holding_sprint_does_nothing() -> void:
	var player := _player()
	await get_tree().physics_frame
	var base := player.camera.fov
	for _i in 60:
		player._step_camera(1.0 / 60.0, true)
	assert_float(player.camera.fov).is_equal_approx(base, 0.01)


# --- A remote player is not simulated ------------------------------------------------

func test_none_of_this_reaches_a_remote_player() -> void:
	# A remote player's position arrives on the wire (WP-4.5) and is never
	# simulated; RemoteAvatar is a different node entirely, with no camera to
	# bob and no velocity to accelerate.
	var avatar: RemoteAvatar = auto_free(RemoteAvatar.new(3))
	add_child(avatar)
	await get_tree().process_frame
	assert_bool(avatar.has_method("step_motion")).override_failure_message(
		"a remote avatar grew a movement simulation").is_false()
	assert_bool(avatar.has_signal("footstep")).is_false()
