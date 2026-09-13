class_name MusicMix
extends RefCounted
## Pure mixing rules for the soundscape's music stems (WP-2.6).
##
## Kept separate from [Soundscape] so "how loud should stem N be at this
## completion" is a plain function of a float, testable without any audio
## node, bus or stream in play. [Soundscape] is the only thing that turns
## these numbers into sound.

## One row per stem: the completion span over which it fades in (start may be
## negative so the stem is already partly in at completion 0 — "sparse", not
## silent), and the gain ceiling it fades toward.
const STEMS := [
	{"start": -0.05, "end": 0.15, "max_gain": 0.55}, # pad: present from the very start
	{"start": 0.30, "end": 0.55, "max_gain": 0.70}, # melody: joins once it stops looking hopeless
	{"start": 0.60, "end": 0.85, "max_gain": 0.65}, # shimmer: a little sparkle for the last containers
]


static func stem_count() -> int:
	return STEMS.size()


## Target linear gain (0..1) for one stem at a given completion (0..1).
static func stem_gain(index: int, completion: float) -> float:
	var row: Dictionary = STEMS[index]
	var start: float = row["start"]
	var end: float = row["end"]
	var t: float
	if end > start:
		t = clampf((completion - start) / (end - start), 0.0, 1.0)
	else:
		t = 1.0 if completion >= start else 0.0
	return t * float(row["max_gain"])
