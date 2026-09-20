# WP-5.4 — The morning after

**Phase:** 5 · **Lane:** fx · **Size:** S · **Status:** unclaimed · **Depends on:** [5.1](WP-5.1-settings.md)

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
- [ ] Plays once per round start, never on a resume from the pause menu.
- [ ] Any key or click ends it immediately, and ending it early leaves nothing behind.
- [ ] `fx.intro = false` skips it entirely — no frame of blur.
- [ ] It renders in the **web export**, not only in the editor. Say which renderer you verified on.
- [ ] Does not delay the first command a player can submit.
- [ ] In multiplayer, a player still in the intro does not stop the host's clock and does not desync.
- [ ] Looked at on screen, with a frame from about a second in.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Watch it once. Then restart four times and see whether it is still charming.
- [ ] Does anybody feel queasy?

## Notes / decisions
