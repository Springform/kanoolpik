class_name PlacementStreak
extends RefCounted
## How many things in a row you have put in the right place (WP-5.3).
##
## [b]This existed already, and only your ears knew about it.[/b]
## [ContainerNode] raised the chime a semitone per consecutive correct
## placement and reset after a pause — a real reward, with a real number behind
## it, carried by exactly one channel. Mute the tab and it was gone; and it was
## gone for anybody who cannot hear it whether the tab is muted or not.
##
## So the count moved here, where the HUD can show it and the chime can ask for
## it. One number, two channels.
##
## [b]It also moves the streak from the container to the player, which is where
## it belonged.[/b] It used to be per [ContainerNode], so putting a bottle in
## the crate and then a peg in the tent bag was two streaks of one, and sounded
## like it. Nobody plays that way on purpose — you work through what is in your
## arms — so the old behaviour punished the normal thing.

## Longest gap between two placements that still counts as a run. Two seconds
## is about as long as walking from one container to the next one beside it,
## and short enough that putting something away after a think starts over.
const WINDOW_SECONDS := 2.0
## Semitones the chime climbs. Seven, so a run tops out at a fifth rather than
## somewhere shrill.
const MAX_STEPS := 7
## A run is only worth saying out loud from here up. One is not a run and two
## is barely one; the HUD stays quiet until it means something.
const SHOW_FROM := 3

var steps := 0
var _last_time := -1000.0


## Count a correct placement at [param now] (seconds) and return the new step.
func advance(now: float) -> int:
	steps = mini(steps + 1, MAX_STEPS) if now - _last_time <= WINDOW_SECONDS else 0
	_last_time = now
	return steps


## A wrong placement ends a run, and so does time. Kept separate because the
## caller knows which of the two happened and this class should not guess.
func broken() -> void:
	steps = 0
	_last_time = -1000.0


## Has the run gone quiet without anybody telling us? Asked by the HUD every
## frame, because a run that ends by the player standing still has no event.
func expired(now: float) -> bool:
	return steps > 0 and now - _last_time > WINDOW_SECONDS


## What the chime should be multiplied by: one semitone per step.
func pitch_scale() -> float:
	return pow(2.0, float(steps) / 12.0)


## How many in a row, as a person would count them.
##
## [member steps] is the number of semitones the chime has climbed, so it is
## one behind: the first correct placement of a run is step 0. That offset is
## the chime's business and nobody should have to know it twice, which is why
## the HUD asks this and not [member steps].
func run_length() -> int:
	return steps + 1 if steps > 0 or _last_time > -999.0 else 0


## Is this run worth putting on screen?
func worth_showing() -> bool:
	return run_length() >= SHOW_FROM
