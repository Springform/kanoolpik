# WP-5.3 — Cues you can read

**Phase:** 5 · **Lane:** a11y · **Size:** S · **Status:** unclaimed · **Depends on:** —

## Goal
Nothing the game tells you is told by one channel only. A chime, a glow or a colour is a nice way to say something and a bad way to say it *once*.

## What is already done — do not redo it
`VerdictStyle` was written with this in mind and says so: correct and wrong differ in **hue and brightness**, and a wrong slot additionally carries a `×` marker, so colour is never the only channel. **Read `src/game/containers/verdict_style.gd` before changing anything there.** The marker is Latin-1 (`×`, not `✕`) because Godot's default font has no Dingbats glyphs and drew the nicer character as nothing at all.

## What is actually missing
1. **Audio cues say things nothing else says.** `container_complete`, `island_clean`, `place_correct`, `place_wrong`, `shout_mate` all play a sound; a player with the tab muted, or who cannot hear it, gets the toast for some and nothing for others. Work out which sounds carry information that is not already on screen, and put that information on screen.
2. **WP-4.7's toast colours were never checked.** `HUD.COLOR_OTHER` (somebody else's news) and `COLOR_ERROR` are new, and "dimmed blue-grey" versus "warm orange" is exactly the pair that stops being a pair for some people. Somebody else's toast should be distinguishable from your own error **without** colour — a prefix, an indent, a marker.
3. **`RemoteAvatar.colour_for()` hands out six hues by peer id.** Six hues on one wheel will contain a pair that some people cannot tell apart. The name tag carries the name, so this is not fatal, but the colour is doing real work ("the green one keeps putting bottles in the kitchen box") and should be picked rather than computed.

## Owns (may edit)
- `src/game/hud/` (toast markers, a caption line)
- `assets/i18n/strings.csv` rows prefixed `ui.cue.`
- `tests/integration/test_cues.gd`

## Must not touch
`src/core/` · `src/game/audio/` (the sounds are right; this WP is about what is *also* said) · `src/game/settings/`.

## Interfaces
**Consumes:** `GameEvents.core_event` and the convenience signals; `Soundscape`'s cue names.
**Provides:** nothing new on the bus. If a caption needs a setting (on/off), read it from `Settings` (WP-5.1) rather than inventing a second store.

## Acceptance criteria
- [ ] Every audio cue that carries information has a visible counterpart.
- [ ] Your own error and somebody else's news are distinguishable with colour removed — check it by rendering the HUD in greyscale, not by reasoning about it.
- [ ] The six avatar colours are chosen values in a constant, with a note on how they were checked, not `Color.from_hsv(id * k)`.
- [ ] `VerdictStyle`'s existing guarantees are intact and its tests still pass.
- [ ] Looked at on screen: `tools/shots.gd --only=multihud`, plus a greyscale pass.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Mute the tab and play for two minutes. What did you stop knowing?
- [ ] Ask somebody who is colour-blind, if the crew has one. This is the whole point.

## Notes / decisions
