# WP-1.2 — Placement feedback: flash, chime, completion glow

**Phase:** 1 · **Lane:** containers + audio · **Size:** M · **Status:** unclaimed

## Goal
Placing an item gives immediate, legible feedback: a gold flash and a bright chime for `CORRECT`; a dull red pulse and a low "thud/shrug" for any wrong verdict; when a container completes, all its slots glow, a short fanfare plays and the label gets its ✓. When the island is clean, a longer fanfare. This is the heart of the game's feel.

## Owns (may edit)
- `src/game/containers/` (feedback nodes, tweens, `AudioStreamPlayer3D` per container)
- `assets/audio/sfx/` (CC0 sounds; list sources in `assets/audio/CREDITS.md`)
- `tests/integration/test_placement_feedback.gd`

## Must not touch
- `src/core/`, `src/autoload/`, `src/game/hud/` (HUD toasts are WP-1.4's job)

## Interfaces
**Consumes:** `GameEvents.item_placed(..., verdict)`, `GameEvents.container_completed`, `GameEvents.island_clean`, `PlacementRules.Verdict`.
**Provides:** nothing new. Colours: define `Verdict → Color` in `containers/verdict_style.gd` so HUD (1.4) can import it.

## Acceptance criteria
- [ ] Correct / wrong / complete / clean each have distinct visual and audio feedback.
- [ ] Feedback is driven only by events (no polling `state` in `_process`).
- [ ] Sounds are 3D-positioned at the container; volume via an `SFX` audio bus (add bus in `default_bus_layout.tres` — that file is yours).
- [ ] Colour-blind safe: gold vs red also differ in brightness/shape (e.g. wrong slots show an ✕ decal).
- [ ] Integration test: place wrong → slot material is the wrong style; place correct → correct style; complete → all slots "complete" style.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Rapid-fire placing five items doesn't produce a cacophony (limit overlapping chimes or pitch-step them).
- [ ] Completing a container feels like a small celebration.
