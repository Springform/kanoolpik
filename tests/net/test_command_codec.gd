extends GdUnitTestSuite
## WP-4.2 — commands on and off the wire.
##
## Two separate things are on trial here, and they fail in different ways.
##
## [b]Fidelity.[/b] A command that survives the round trip must be the command
## that went in. If it is not, the host and its clients apply subtly different
## things and the party desyncs — the failure mode WP-4.3 spent its whole
## existence learning to detect.
##
## [b]Hostility.[/b] The relay never inspects a payload, so [CommandCodec] is
## the first code to look at bytes a stranger chose. Every test below the
## fidelity ones asks the same question: can a frame make the host do something
## worse than refuse it?

const ALL_TYPES := [
	Commands.PICK_UP, Commands.DROP, Commands.PLACE, Commands.TAKE_OUT,
	Commands.UNLOCK, Commands.SUMMON, Commands.COLLECT, Commands.TICK,
	Commands.GRANT_POINTS,
	# WP-4.6. Host-issued, but they travel like everything else — see the note
	# in CommandCodec.SCHEMA for why a client sending one is harmless.
	Commands.JOIN, Commands.LEAVE,
]


func _every_command() -> Array[Dictionary]:
	return [
		Commands.pick_up(2, "can_tuborg_1"),
		Commands.drop(3, "paddle_a", Vector3(1.5, 0.25, -7.125)),
		Commands.place(4, "food_bread", "cooler", 2),
		Commands.take_out(5, "food_bread"),
		Commands.unlock(1, "call_mate"),
		Commands.summon(6, "paddle", Vector3(-3.0, 0.0, 12.5)),
		Commands.collect(2, "sunglasses"),
		Commands.tick(1),
		Commands.grant_points(3, 5),
		Commands.join(4),
		Commands.leave(4, Vector3(2.5, 0.0, -1.25)),
	]


# --- Fidelity ------------------------------------------------------------------

func test_every_command_survives_the_round_trip_unchanged() -> void:
	for command in _every_command():
		var result := CommandCodec.decode(CommandCodec.encode(command))
		assert_bool(result["ok"]).override_failure_message(
			"%s did not decode: %s" % [command["type"], result["error"]]).is_true()
		assert_dict(result["command"]).override_failure_message(
			"%s changed on the wire" % command["type"]).is_equal(command)


## The schema is the list of what may travel. A command builder that is not in
## it cannot be sent at all, which is a bug nobody notices until multiplayer —
## the single-player transport never encodes anything.
func test_the_schema_covers_every_command_the_game_can_build() -> void:
	for type in ALL_TYPES:
		assert_bool(CommandCodec.SCHEMA.has(type)).override_failure_message(
			"Commands.%s exists but cannot travel over a socket" % type).is_true()
	assert_int(CommandCodec.SCHEMA.size()).is_equal(ALL_TYPES.size())


## Vector3 is 32-bit in a standard Godot build, and JSON.stringify prints ~15
## significant digits — comfortably more than a float32 carries. That is WHY
## positions survive exactly, and it stops being true in a double-precision
## build, so the day somebody switches this test is the one that says so.
func test_positions_survive_exactly_not_approximately() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in range(500):
		var position := Vector3(
			rng.randf_range(-50.0, 50.0), rng.randf_range(-5.0, 5.0), rng.randf_range(-50.0, 50.0))
		var command := Commands.drop(2, "paddle_a", position)
		var back: Dictionary = CommandCodec.decode(CommandCodec.encode(command))["command"]
		assert_vector(back["position"]).override_failure_message(
			"%s came back as %s" % [position, back["position"]]).is_equal(position)


func test_a_whole_number_arriving_as_a_float_is_still_an_int() -> void:
	# JSON has one number type: 2 goes out and 2.0 comes back. A slot that is a
	# float reaches PlacementRules as a float and compares unequal to every int
	# slot there is.
	var decoded: Dictionary = CommandCodec.decode('{"type":"place","player_id":2.0,"item_id":"x","container_id":"c","slot":3.0}')["command"]
	assert_that(typeof(decoded["slot"])).is_equal(TYPE_INT)
	assert_that(typeof(decoded["player_id"])).is_equal(TYPE_INT)


# --- Hostility -----------------------------------------------------------------

## The whitelist property, stated as a test: decoding cannot produce a key the
## schema does not name, so there is no "extra field" for later code to trip on.
func test_fields_the_schema_does_not_name_cannot_get_through() -> void:
	var result := CommandCodec.decode(
		'{"type":"pick_up","player_id":2,"item_id":"can_tuborg_1","allow_debug_commands":true,"capacity":999}')
	assert_bool(result["ok"]).is_true()
	assert_array(result["command"].keys()).contains_exactly_in_any_order(
		["type", "player_id", "item_id"])


func test_an_unknown_command_type_never_becomes_a_command() -> void:
	var result := CommandCodec.decode('{"type":"delete_everything","player_id":2}')
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).is_equal(CommandCodec.E_UNKNOWN_TYPE)


func test_a_missing_field_is_refused_rather_than_defaulted() -> void:
	# Defaulting item_id to "" would reach CommandProcessor as a real command
	# about a real player and be refused there — one layer later than it should
	# be, and one layer closer to the state.
	var result := CommandCodec.decode('{"type":"pick_up","player_id":2}')
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).contains(CommandCodec.E_MISSING_FIELD)


func test_infinity_and_nan_never_reach_the_world() -> void:
	# "1e999" parses to inf in Godot (with an engine warning). An infinite drop
	# position is a world you cannot clean: the item is nowhere, forever.
	for hostile in ['[1e999,0,0]', '[0,0,-1e999]', '[1e30,0,0]']:
		var result := CommandCodec.decode(
			'{"type":"drop","player_id":2,"item_id":"x","position":%s}' % hostile)
		assert_bool(result["ok"]).override_failure_message(
			"%s was accepted as a position" % hostile).is_false()


func test_a_fractional_slot_is_refused_rather_than_truncated() -> void:
	var result := CommandCodec.decode(
		'{"type":"place","player_id":2,"item_id":"x","container_id":"c","slot":2.5}')
	assert_bool(result["ok"]).is_false()


func test_an_absurdly_long_id_is_refused() -> void:
	var result := CommandCodec.decode(
		'{"type":"pick_up","player_id":2,"item_id":"%s"}' % "a".repeat(CommandCodec.MAX_STRING + 1))
	assert_bool(result["ok"]).is_false()


func test_a_position_of_the_wrong_shape_is_refused() -> void:
	for hostile in ['[1,2]', '[1,2,3,4]', '"1,2,3"', '{"x":1}', '[1,"two",3]', 'null']:
		var result := CommandCodec.decode(
			'{"type":"drop","player_id":2,"item_id":"x","position":%s}' % hostile)
		assert_bool(result["ok"]).override_failure_message(
			"%s was accepted as a position" % hostile).is_false()


## A hostile peer must not be able to turn the test suite red from across the
## internet. JSON.parse_string() logs an engine error on bad input, and
## tools/run_tests.sh fails the run on engine errors — so the codec parses the
## quiet way. If this ever regresses, the whole suite goes red on a garbage
## frame, which is a denial of service with extra steps.
func test_rubbish_is_an_answer_not_an_engine_error() -> void:
	for rubbish in ['', 'not json {', '[]', '"a string"', '42', 'null']:
		var result := CommandCodec.decode(rubbish)
		assert_bool(result["ok"]).override_failure_message(
			"%s was accepted" % rubbish).is_false()
		assert_str(result["error"]).is_not_empty()


## The host overwrites player_id with the peer id the relay reported — the codec
## does not, and must not pretend to. This test exists so that nobody reads
## "decoded safely" as "decoded trustworthily": a client claiming to be the
## host decodes perfectly, and it is WebSocketTransport's job to stamp over it.
func test_a_client_can_claim_any_player_id_and_the_codec_will_not_stop_it() -> void:
	var result := CommandCodec.decode('{"type":"pick_up","player_id":1,"item_id":"x"}')
	assert_bool(result["ok"]).is_true()
	assert_int(result["command"]["player_id"]).is_equal(1)
