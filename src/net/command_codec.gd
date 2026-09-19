class_name CommandCodec
extends RefCounted
## Commands on and off the wire (WP-4.2).
##
## [b]This is a trust boundary.[/b] The relay (ADR 0011) never looks inside a
## payload, so nothing between a client's keyboard and the host's
## [CommandProcessor] has checked these bytes. Whatever arrives here was chosen
## by whoever is on the other end of the socket, and a room code is six
## characters somebody read aloud in a canoe. Treat every frame as hostile and
## the worst case is a refused command; treat one as trusted and the worst case
## is the host's world poisoned with a NaN nobody can get back out.
##
## [b]Decoding is a whitelist, not a filter.[/b] [method decode] builds the
## command from [constant SCHEMA] alone — it copies the fields the schema names
## and never touches the rest. So a frame carrying extra keys does not produce a
## command carrying extra keys: there is no "unknown field" to reject because
## there is no path by which one could arrive. That is deliberately stronger
## than validating what came in, and it is the reason this is a table rather
## than nine hand-written parsers that each remember to be careful.
##
## [b]What it does NOT decide.[/b] Whether the sender may issue this command at
## all. [code]player_id[/code] is decoded but must be [i]overwritten[/i] by the
## host with the peer id the relay reported, because a client is perfectly free
## to claim it is peer 1. See [WebSocketTransport]; the rule is stated here too
## because this is where someone will come looking for it.
##
## [codeblock]
##   var text := CommandCodec.encode(Commands.pick_up(3, "can_tuborg_1"))
##   var r := CommandCodec.decode(text)
##   if r["ok"]: processor.apply(state, r["command"])
## [/codeblock]

## Field kinds. Deliberately terse: the table below is meant to be read as a
## table, and a column of INT/FLOAT/VECTOR3 turns it into an essay.
const S := "s" ## String
const I := "i" ## int
const V := "v" ## Vector3, on the wire as [x, y, z]

## Every command type the wire accepts, and exactly which fields each carries.
## A type that is not in here cannot be decoded at all — which is what stops a
## peer reaching a command the game does not mean to expose over a socket.
##
## [code]player_id[/code] is implicit on every one of them; see [method decode].
const SCHEMA := {
	Commands.PICK_UP: {"item_id": S},
	Commands.DROP: {"item_id": S, "position": V},
	Commands.PLACE: {"item_id": S, "container_id": S, "slot": I},
	Commands.TAKE_OUT: {"item_id": S},
	Commands.UNLOCK: {"ability_id": S},
	Commands.SUMMON: {"series": S, "position": V},
	Commands.COLLECT: {"collectible_id": S},
	Commands.TICK: {"ticks": I},
	# Debug commands travel like anything else, and are refused by
	# CommandProcessor.allow_debug_commands on the HOST — so the host decides
	# once whether the party may cheat, and a client asking nicely does not
	# change that. Leaving it out of the schema instead would mean test mode
	# stopped working the moment a second player joined.
	Commands.GRANT_POINTS: {"points": I},
	# WP-4.6. On the wire because the HOST has to broadcast them — every peer
	# must add and remove the same players in the same order, and the host's own
	# frames go through this codec like everyone else's.
	#
	# A client can send them and it does not matter, which is not luck: the host
	# overwrites `player_id` with the sender's peer id, so `join` from a client
	# asks to add somebody already there (refused) and `leave` removes only the
	# sender — which they can do by closing the tab. Capacity is not a field, so
	# nobody can negotiate their own pockets.
	Commands.JOIN: {},
	Commands.LEAVE: {"position": V},
}

## An id longer than this is not an id, it is someone probing. Real ones look
## like "can_tuborg_1". Bounded because a megabyte of item_id costs the host a
## megabyte of comparison per frame, and nothing legitimate needs it.
const MAX_STRING := 64
## Nothing in this game happens a kilometre from the island, and a crafted
## 1e30 in a position would be a number the world never recovers from.
const MAX_COORD := 10000.0

const E_BAD_JSON := "bad_json"
const E_NOT_A_COMMAND := "not_a_command"
const E_UNKNOWN_TYPE := "unknown_command_type"
const E_MISSING_FIELD := "missing_field"
const E_BAD_FIELD := "bad_field"


## A command as JSON text, ready for the relay's opaque [code]d[/code].
static func encode(command: Dictionary) -> String:
	return JSON.stringify(to_wire(command))


## The JSON-safe form, for when the caller is building a bigger frame and does
## not want a string inside a string.
static func to_wire(command: Dictionary) -> Dictionary:
	var type := String(command.get("type", ""))
	var out := {"type": type, "player_id": int(command.get("player_id", -1))}
	var fields: Dictionary = SCHEMA.get(type, {})
	for name in fields:
		var value: Variant = command.get(name)
		match String(fields[name]):
			V:
				var v: Vector3 = value if value is Vector3 else Vector3.ZERO
				out[name] = [v.x, v.y, v.z]
			I:
				out[name] = int(value)
			_:
				out[name] = String(value)
	return out


## [code]{ ok, command, error }[/code]. Never pushes an error and never throws:
## a bad frame is an answer, not an incident. The caller decides whether to tell
## the sender (the host does) or to log loudly (a client receiving rubbish from
## the host has bigger problems).
static func decode(text: String) -> Dictionary:
	var json := JSON.new()
	# JSON.parse_string() logs an engine error on bad input, and an engine error
	# fails tools/run_tests.sh. A hostile peer must not be able to turn the
	# suite red from across the internet, so parse the quiet way.
	if json.parse(text) != OK:
		return _no(E_BAD_JSON)
	return from_wire(json.data)


static func from_wire(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _no(E_NOT_A_COMMAND)
	var wire: Dictionary = raw
	var type := String(wire.get("type", ""))
	if not SCHEMA.has(type):
		return _no(E_UNKNOWN_TYPE)

	var player_id: Variant = _as_int(wire.get("player_id"))
	if player_id == null:
		return _no("%s: player_id" % E_BAD_FIELD)

	# Built from the schema outward, never from the frame inward: `command` can
	# only ever hold keys this table names.
	var command := {"type": type, "player_id": player_id}
	var fields: Dictionary = SCHEMA[type]
	for name in fields:
		if not wire.has(name):
			return _no("%s: %s" % [E_MISSING_FIELD, name])
		var value: Variant = wire[name]
		match String(fields[name]):
			S:
				if not value is String or (value as String).length() > MAX_STRING:
					return _no("%s: %s" % [E_BAD_FIELD, name])
				command[name] = value
			I:
				var n: Variant = _as_int(value)
				if n == null:
					return _no("%s: %s" % [E_BAD_FIELD, name])
				command[name] = n
			V:
				var v: Variant = _as_vector3(value)
				if v == null:
					return _no("%s: %s" % [E_BAD_FIELD, name])
				command[name] = v
	return {"ok": true, "command": command, "error": ""}


# --- Internals -----------------------------------------------------------------

## JSON has one number type, so an int arrives as a float. Accept a whole
## number, refuse 2.5 — a slot of 2.5 would become 2 silently and place an item
## somewhere nobody asked for. Refuse NaN and inf, which `int()` turns into
## rubbish rather than failing.
static func _as_int(value: Variant):
	if value is int:
		return value
	if value is float:
		var f: float = value
		if not is_finite(f) or f != floorf(f):
			return null
		return int(f)
	return null


static func _as_vector3(value: Variant):
	if not value is Array or (value as Array).size() != 3:
		return null
	var out := Vector3.ZERO
	for i in range(3):
		var c: Variant = (value as Array)[i]
		if not (c is float or c is int):
			return null
		var f := float(c)
		# is_finite catches the NaN and the inf that "1e999" parses to; the
		# bound catches the merely absurd, which is just as effective at
		# launching a canoe into the next county.
		if not is_finite(f) or absf(f) > MAX_COORD:
			return null
		out[i] = f
	return out


static func _no(error: String) -> Dictionary:
	return {"ok": false, "command": {}, "error": error}
