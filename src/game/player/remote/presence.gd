class_name Presence
extends RefCounted
## The wire shape of "where somebody is standing", and nothing else (WP-4.5).
##
## [b]A transform is presentation.[/b] It never becomes a [Commands] entry and
## never reaches [WorldState]: the core is deterministic because every peer
## applies the same commands in the same order, and a position that arrives
## twenty times a second — late, dropped, or out of order, as positions do —
## would put that guarantee at the mercy of the network. So presence travels on
## its own channel ([method Transport.send_presence]), is applied straight to a
## node, and is forgotten a tenth of a second later.
##
## [b]What is deliberately NOT in here:[/b] what the player is carrying. That is
## world state, so every peer already knows it — `pick_up` is a command and has
## been applied everywhere. [RemoteAvatar] reads it from
## [method WorldState.carried_by]. Sending it would be paying, twenty times a
## second, for a fact the receiver could look up for free.
##
## [b]The shape[/b] is a four-float array under one short key, because this is
## the field that travels twenty times a second:
## [codeblock]
##   {"t": [x, y, z, yaw]}
## [/codeblock]

## The key inside the frame. One letter for the same reason the envelope kinds are.
const KEY := "t"

## Centimetres, and hundredths of a radian. A player is 1.8 m tall and half a
## degree of facing is invisible at any distance you can see an avatar from, so
## the digits below this are pure cost: they make the number longer on the wire
## and change nothing on the screen.
const STEP := 0.01

## How far something must move before it counts as having moved, in metres.
## Just above the rounding: anything smaller would survive the comparison and
## then serialise to the exact same frame, which is traffic that carries no news.
const MOVED_EPSILON := 0.02
## The same, for facing, in radians — about one degree.
const TURNED_EPSILON := 0.02


## A position and a facing, ready to hand to [method Transport.send_presence].
static func to_wire(position: Vector3, yaw: float) -> Dictionary:
	return {KEY: [
		snappedf(position.x, STEP),
		snappedf(position.y, STEP),
		snappedf(position.z, STEP),
		snappedf(wrapf(yaw, -PI, PI), STEP),
	]}


## The inverse, as a whitelist: the result is built out of the four numbers we
## expect and nothing else, so a peer that adds fields to the frame cannot get
## them into a caller's dictionary. Same discipline as [CommandCodec], and for
## the same reason — the other end of this is the open internet.
##
## Returns [code]{}[/code] for anything that is not four numbers, which callers
## treat as "no news" rather than as an error: a malformed transform is one
## frame of one avatar not moving.
static func from_wire(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var frame: Dictionary = raw
	if not frame.has(KEY) or not frame[KEY] is Array:
		return {}
	var values: Array = frame[KEY]
	if values.size() != 4:
		return {}
	for value: Variant in values:
		if not (value is float or value is int):
			return {}
		if not is_finite(float(value)):
			# NaN teleports an avatar to nowhere and stays there, because every
			# later comparison against it is false.
			return {}
	return {
		"position": Vector3(float(values[0]), float(values[1]), float(values[2])),
		"yaw": float(values[3]),
	}


## Has this moved enough to be worth a frame?
##
## This is the acceptance criterion in one function: a player standing still
## reading a label must cost nothing. The comparison is against what was last
## [i]sent[/i], not against the last frame, so drifting one millimetre per frame
## across a minute still eventually sends — it does not accumulate silently.
static func differs(position: Vector3, yaw: float, last: Dictionary) -> bool:
	if last.is_empty():
		return true
	var was: Vector3 = last["position"]
	if position.distance_to(was) >= MOVED_EPSILON:
		return true
	return absf(angle_difference(yaw, float(last["yaw"]))) >= TURNED_EPSILON
