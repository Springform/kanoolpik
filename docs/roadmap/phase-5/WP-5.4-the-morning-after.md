# WP-5.4 — The morning after

**Phase:** 5 · **Lane:** fx · **Size:** S · **Status:** done (2026-09-20) · **Depends on:** [5.1](WP-5.1-settings.md)

## Goal
The round opens the way the morning does: you come round face-down in a sleeping bag, the world is a blur that resolves over a few seconds, the snoring is very close, and then you are standing on an island covered in last night. Ten seconds at most, skippable by any key, and off for anyone who does not want it.

## Owns (may edit)
- `src/game/fx/` (new)
- `tests/integration/test_intro.gd`

## Must not touch
`src/core/` · `src/game/main/main.gd` beyond **one call** to start the intro when a level begins — declare it in the PR · `src/game/player/`.

## Design notes
- **GL Compatibility, no threads.** ADR 0007. A full-screen post-process shader that only exists on Forward+ is not an option, and neither is anything that wants a compute pass. Check what actually renders in the web export before building on it — `CanvasLayer` + a `ColorRect` with a shader, or an animated blur on a `TextureRect` copy, are the safe shapes.
- **Skippable from the first frame.** Nobody wants this on the fifth run of the evening, and a playtest is mostly restarts.
- **Off is a real option, not a hidden one.** Screen blur and a lurching camera are motion-sickness triggers; `fx.intro` in `Settings` (WP-5.1), and the panel says what it does in plain Danish.
- **It must not be load-bearing.** The round starts when the round starts; the intro is drawn over a world that is already running, so skipping it cannot leave anything half-initialised. In multiplayer the clock is the host's and does not wait for anybody's animation.
- The mess dressing already put a mate asleep and snoring on the island (WP-2.7). Start the camera near him rather than inventing a second sleeper.

## Acceptance criteria
- [x] Plays once per round start, never on a resume from the pause menu — it is built in `_build_playing_scene`, which a resume does not run.
- [x] Any key or click ends it immediately, and ending it early leaves nothing behind. It frees itself; there is nothing else to leave.
- [x] `fx.intro = false` skips it entirely — the node is never built, so there is no frame to have.
- [x] It renders under **GL Compatibility** (`--rendering-driver opengl3`), which is what the web export uses. Rendered and looked at, not read about.
- [x] Does not delay the first command a player can submit — a test picks something up while the intro is on screen.
- [x] In multiplayer, a player still in the intro does not stop the host's clock and does not desync: the file cannot, because it never mentions `GameSession`, `GameEvents`, `Commands` or `WorldState`, and a test asserts that.
- [x] Looked at on screen, at 0.45 s, 1.4 s and 3.3 s.
- [x] `tools/run_tests.sh` green (707); boot check green.

## Playtest checklist (human, 5 min)
- [ ] Watch it once. Then restart four times and see whether it is still charming.
- [ ] Does anybody feel queasy?

## Notes / decisions

## Decisions

**It is an overlay and nothing else.** The world is already running underneath:
the clock has started, the items are where the seed put them, and in
multiplayer the host's round never waited for anybody. Skipping it therefore
cannot leave anything half-initialised, because it initialises nothing. That is
the whole design, and it is what makes every one of the hard acceptance criteria
true by construction rather than by care.

**So the test for the multiplayer criterion is a grep.** `wake_up.gd` never
mentions `GameSession`, `GameEvents`, `Commands` or `WorldState`, and a test
asserts that. A file that cannot reach the session cannot delay it, desync it or
stop its clock — which is a stronger statement than simulating six peers and
finding that it did not happen this time.

**One line in `main.gd`, as the WP allowed**, at the end of
`_build_playing_scene`, after everything a round needs exists. Plus the variable
it is held in and its entry in `_tear_down`'s free list, because a node that
outlives a restart is this project's oldest bug.

### The blur, and how it was arrived at

ADR 0007 rules out anything Forward+-only, so the question was whether a
`canvas_item` shader reading `hint_screen_texture` renders at all under GL
Compatibility. **It does** — verified by rendering the intro under
`--rendering-driver opengl3` and looking at the picture, which is the only way
that question has ever been answered honestly in this repo.

The first version was a nine-tap square at a 1.1 % radius, and it **turned the
grass into vertical stripes**. Nine samples spread over a field of thin bright
blades is not a blur, it is aliasing with extra steps, and it read as a broken
shader rather than as unfocused eyes. The fix was to stop sampling and start
asking for a mip: **a mipmap is a blur**, the back buffer has them the moment the
sampler asks (`filter_linear_mipmap`), and one `textureLod` at level 5 is both
cheaper and smoother than any number of taps. Four taps on top, because a mip
on its own is blocky at the level where it is doing real work.

**No camera movement at all.** The WP mentions a lurch; `src/game/player/` is
WP-5.2's and off limits, and more importantly a lurching camera is the single
most reliable way to make somebody feel sick. Eyelids and focus do the same job
and move nothing the player is standing on.

### The storyboard is data, so the shape can be tested

`FRAMES` is nine entries of `{at, open, blur}` and `state_at()` interpolates
between them with a smoothstep — an eyelid does not move at a constant speed,
and a linear one reads as a shutter. Because it is pure and static, the tests
assert the **shape**: it starts shut, it ends with nothing on the screen, and
the lids close again exactly twice on the way up. A person coming round does not
open their eyes once, and a storyboard is easy to flatten into a fade by
accident — so the blinks are counted rather than assumed.

Seven seconds, against the WP's ten. The fifth restart of an evening is not the
first one, and a playtest is mostly restarts.

### Off is off

`WakeUp.install()` checks `fx.intro` and returns null, so switching it off means
**the node is never built** — not that it is built and draws nothing. One frame
of blur is precisely what somebody who turned this off is complaining about.

The switch is now in the settings panel, which WP-5.1 left a note asking for.

## Scope widening, as declared

1. **`src/game/main/main.gd`** — the one call the WP permits, plus the variable
   and its line in `_tear_down`.
2. **`src/game/settings/settings_panel.gd`** — one row, `ui.settings.intro`.
3. **`tools/shots.gd`** — three frames of the storyboard, which is how the
   renderer question got answered.
4. **`tests/integration/test_settings.gd`** — see below.

## A test that had to stop being a list

`test_the_panel_only_shows_settings_something_reads` named `look.head_bob` and
`fx.intro` as the two keys that must **not** be on the panel. It has now gone
red twice for the right reason — WP-5.2 made one of them do something, WP-5.4
the other — and both times the fix was to edit the list.

A list that has to be edited every time the world changes is not the rule; it is
a snapshot of the rule. It now asserts the rule itself: **every key the panel
offers is read by somebody.** The reader is found by looking for the constant's
name in `src/`, with the constant names taken from the script rather than typed
out here, and with the two keys `Settings` applies itself — the audio buses and
the locale — counted as read, because `Settings.apply()` is what reading them
means.

The opposite direction is deliberately not asserted. "Every live key is on the
panel" is not a rule anybody wants: an internal setting with no switch is a
perfectly ordinary thing.
