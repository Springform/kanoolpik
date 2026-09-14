# WP-3.3 — Stedsans: an arrow toward the right container

**Phase:** 3 · **Lane:** abilities · **Size:** S · **Status:** unclaimed · **Depends on:** WP-3.0, WP-3.1 (`Hud.ability_layer()`)

## Goal
With Stedsans unlocked, a small arrow at the edge of the screen points at the container the held item belongs in, and fades when you are looking at it. Knowing *where* stops being the puzzle; deciding *what* still is.

## Owns (may edit)
- `src/game/abilities/map_sense/`
- `tests/integration/test_map_sense.gd`

## Must not touch
- `src/core/`, `src/autoload/`, `src/game/hud/hud.gd` (attach to `Hud.ability_layer()` instead), other abilities' folders

## Interfaces
**Consumes:** `GameSession.progression.has("map_sense")`, `GameSession.state.active_item()`, `Catalog.get_item(id).category`, `ContainerDef.accepts`, `GameSession.container_position(id)`, the local player's camera transform, input action `ability_map_sense` (toggle), `Hud.ability_layer()`.

## Design notes
- The *correct* container is the one whose `accepts` covers the category **and** where the series already lives if any sibling is placed — ask `PlacementRules` rather than reimplementing layer 2. If two containers qualify and neither holds a sibling, point at the nearer one.
- A toggle, not a hold: it is navigation, and a player carrying three things wants it on.
- Project the container to screen space; when it is on screen and near the crosshair, fade the arrow out rather than drawing a marker on top of the thing the player is already looking at.
- Carrying several items points at the *active* one (last picked up), consistent with what `place` will act on.

## Acceptance criteria
- [ ] Locked: the toggle does nothing.
- [ ] Unlocked and carrying, the arrow points at the container `PlacementRules` would call correct — verified by angle, not by eye, in the test.
- [ ] Empty-handed: no arrow.
- [ ] A sibling already placed in one of two eligible containers makes the arrow pick that one.
- [ ] The arrow fades when the container is centred on screen.
- [ ] Tests: target selection (including the two-eligible case), angle correctness from a known camera transform, hidden when idle.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Walk a full lap with it on — does it ever point at something wrong, or jitter when two containers are close together?
