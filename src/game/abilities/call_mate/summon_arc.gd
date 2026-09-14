class_name SummonArc
extends RefCounted
## The shape of the toss a summoned item makes — pure geometry, no nodes.
##
## The item's logical position changed the instant the `summon` command applied
## (see [CommandProcessor]); everything here is the half second of presentation
## that stops it from teleporting. Keeping the curve in a [RefCounted] with
## static functions means it can be asserted against directly, with no scene,
## no frames and no waiting — the flight itself ([SummonAnimator]) then only has
## to prove it samples this at the right times.

## How long the arc lasts. Long enough to read as "thrown", short enough that
## you are not standing still waiting for your own tent poles.
const FLIGHT_SECONDS := 0.6

## Apex of the toss, as a fraction of how far the item has to travel.
const HEIGHT_PER_METRE := 0.22
## Even a mate standing next to you lobs it rather than sliding it over.
const MIN_HEIGHT := 0.6
## Past this the arc stops growing: a throw from the far shore should not
## disappear into the sky (and out of the frustum) on the way.
const MAX_HEIGHT := 3.2


## Apex height in metres for a throw from [param from] to [param to].
static func height(from: Vector3, to: Vector3) -> float:
	return clampf(from.distance_to(to) * HEIGHT_PER_METRE, MIN_HEIGHT, MAX_HEIGHT)


## Where the item is at [param t] (0 = thrown, 1 = landed). Straight line in
## the horizontal, a half sine over the top — the endpoints are exact, which is
## what matters: t = 1 must be the position the core already decided on.
static func point(from: Vector3, to: Vector3, t: float) -> Vector3:
	var k := clampf(t, 0.0, 1.0)
	var p := from.lerp(to, k)
	p.y += height(from, to) * sin(PI * k)
	return p


## Yaw offset at [param t]. A whole turn, so the item lands facing exactly the
## way it started and the animation leaves nothing behind.
static func spin(t: float) -> float:
	return TAU * clampf(t, 0.0, 1.0)
