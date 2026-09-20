# WP-5.3 — Cues you can read

**Phase:** 5 · **Lane:** a11y · **Size:** S · **Status:** done (2026-09-20) · **Depends on:** —

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
- [x] Every audio cue that carries information has a visible counterpart. Two did not: the chime's rising pitch and somebody else's shout.
- [x] Your own error and somebody else's news are distinguishable with colour removed — rendered in greyscale and looked at, not reasoned about.
- [x] The six avatar colours are chosen values in a constant, and the note on how they were checked is a test that measures them.
- [x] `VerdictStyle`'s existing guarantees are intact and its tests still pass — the toast mark is `VerdictStyle.MARK_WRONG`, so the slot and the toast say the same thing.
- [x] Looked at on screen: `tools/shots.gd --only=multihud`, in colour and in greyscale.
- [x] `tools/run_tests.sh` green (691); boot check green.

## Playtest checklist (human, 5 min)
- [ ] Mute the tab and play for two minutes. What did you stop knowing?
- [ ] Ask somebody who is colour-blind, if the crew has one. This is the whole point.

## Notes / decisions

## Decisions

### 1. The chime was carrying a number nobody could see

`ContainerNode._play_chime` raised the pitch a semitone per consecutive correct
placement, capped at seven. That is a real reward with a real number behind it,
and **the pitch was the only place in the entire game that knew a run was
happening.** Mute the tab and it is gone; and it was gone anyway for anybody who
cannot hear it.

The count moved to `src/game/hud/placement_streak.gd`, the HUD shows it
(`4 i træk`), and `ContainerNode` asks the HUD what pitch to play. One number,
two channels — and a test asserts the number on screen is the number being
played, which was not previously a thing that could be true.

**It also moved the run from the container to the player, which is where it
belonged.** The old counter was per `ContainerNode`, so a bottle in the crate
followed by a peg in the tent bag was two runs of one, and sounded like it.
Nobody plays that way on purpose — you work through what is in your arms — so
the old behaviour punished the normal thing. Nothing in the WP asked for this;
it fell out of asking where the number lives.

A container with no HUD in the tree (the shots harness, most tests) chimes at
the base pitch. That is the honest answer rather than a second counter kept
locally in case.

### 2. Somebody else's shout was audible and invisible

`CallMateAbility` plays the shout positionally for everyone within sixty metres
and toasted only for the shouter. A mate hauling a whole series across the camp
happened in silence and in secret for anybody not listening. Now it toasts for
everybody, as somebody else's news.

The toast is emitted from the ability and not from the HUD **because the dedupe
lives there**: one summon publishes an `item_summoned` per item, all in one
frame, and `_last_burst_frame` is what turns that into one shout. Putting the
toast in the HUD would have meant writing that rule a second time.

### 3. Marks, so a toast survives greyscale

Every toast that is not your own plain good news now carries a prefix: `×` for
an error — the same mark the wrong slot already draws, so it is learned once —
and `»` for somebody else's news. Both Latin-1, because Godot's default font
draws `✕` as nothing at all while every string assertion stays green.

Checked the way the WP demanded: the multiplayer HUD rendered and then converted
to greyscale. `» Spiller 3 pakkede Padle` and `× Det hører ikke til her` are two
different things with the hue removed; they were not before.

The caller still passes a colour, because a colour is how a caller says what it
means. `HUD.MARKS` is where that meaning becomes a second channel instead of
staying a hue, so the six call sites in other WPs did not have to change.

### 4. Six colours, measured rather than picked by eye

`Color.from_hsv(id * 0.16, ...)` walks the wheel in even steps, and the wheel is
not perceptually even — least of all when two of the three cone types are doing
one job. **Simulated and measured: peers 1 and 2 came out at ΔE 1.9 under
protanopia, which is to say the same colour.** Nobody would have found that by
looking at the palette, and no assertion about hue would have caught it.

The six that ship are six of the eight in the Okabe–Ito colour-universal
palette (orange, sky blue, bluish green, yellow, blue, vermillion; the reddish
purple and the black are left out). Their closest pair across normal vision and
all three dichromacies is **ΔE 13.8**.

`tests/helpers/colour_vision.gd` implements the Viénot–Brettel–Mollon
simulation so this is a number the suite checks rather than a paragraph anybody
has to believe. **`test_the_palette_this_replaced_would_fail_that` keeps the old
formula alive as a test** — the point of an assertion is that it can fail, and
this is the thing it fails on.

## Scope widening, as declared

Five files outside `src/game/hud/`:

1. **`src/game/player/remote/remote_avatar.gd`** — the palette. The WP's own
   third criterion asks for it; the file belongs to WP-4.5.
2. **`src/game/containers/container_node.gd`** — the chime asks the HUD for its
   pitch instead of counting. Deletes more than it adds.
3. **`src/game/abilities/call_mate/call_mate_ability.gd`** — four lines, for the
   reason in decision 2.
4. **`src/game/ui/panel_fit.gd`** — a new `grow_upwards()`, for the reason
   below.
5. **`tools/shots.gd`** — the multiplayer shot sets a run up so the screenshot
   is of the real counter rather than of a label with a number typed into it.

`assets/i18n/strings.csv` gained `ui.cue.streak` and `ui.multi.called`. The
first is under this WP's own `ui.cue.` prefix; the second is not, and is named
for the family it belongs to rather than for the WP that added it.

## The bug the screenshot caught, again

The streak label is a fourth row in the HUD's bottom-left panel, and that
panel's height is typed into `hud.tscn` as `offset_top = -120`. So `4 i træk`
drew **on the grass below the panel art**, with every test green. That is
WP-4.4's bug in a different corner, and `PanelFit` exists because of it — it
just had no function for a panel anchored to the bottom. It does now, and it is
built from `get_combined_minimum_size()` like the other one, which is the part
that makes it idempotent.

Third time this project has shipped a control outside its own background. The
rule is worth stating plainly: **any panel whose size is a number in a `.tscn`
is a bug waiting for its next row.**

## One thing tidied on the way past

`assert_array(hud.toast_texts()).contains([tr("...")])` appeared eighteen times
across seven suites, and every one of them broke when toasts grew marks — even
though not one of them cares about the mark. They now ask `HUD.said(text)`,
which is "was the player told this, however it was flagged". `toast_texts()`
still returns what is actually on screen, marks and all, because that is what
the two tests that *are* about marks need to see.

`HUD` also joined a group (`HUD.GROUP`) so the container could find it in one
call. The four ability WPs each carry their own recursive `_find_hud`; nothing
here changes them, but whoever next opens one of those files should delete it.

## Left undone, deliberately

The WP's playtest checklist is the part that matters and no test replaces it:
**mute the tab and play for two minutes, then say what you stopped knowing.**
Everything above is an answer to that question asked from the outside.
