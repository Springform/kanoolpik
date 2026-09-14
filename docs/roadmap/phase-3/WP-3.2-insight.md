# WP-3.2 — Klarsyn: series siblings glow

**Phase:** 3 · **Lane:** abilities · **Size:** S · **Status:** **done** (2026-09-14, wave 1) · **Depends on:** WP-3.0

## Goal
Holding an item and pressing Q makes every other member of its series glow through walls and terrain for 5 seconds. The fourth tent pole stops being a hunt across the island and becomes a glance.

## Owns (may edit)
- `src/game/abilities/insight/`
- `tests/integration/test_insight.gd`

## Must not touch
- `src/core/`, `src/autoload/`, `src/game/hud/`, `src/game/items/item_visual.gd` (add an overlay; do not change how items render)

## Interfaces
**Consumes:** `GameSession.progression.has("insight")`, `GameSession.state.active_item()` and `.items_of_kind(WorldState.Kind.GROUND)`, `Catalog.get_item(id).series`, input action `ability_insight`.

**Provides:** nothing other WPs depend on.

## Design notes
- Draw the highlight as a separate node parented to the item's visual, on a material with `no_depth_test` and unshaded — do not tint the item's own material. Tinting an imported glTF multiplies its albedo (CLAUDE.md), so a "glow" would read as a smudge.
- Items with no `series` are the common case. Q while holding one should say so once, briefly, rather than silently doing nothing.
- 5 seconds from GAME_DESIGN §6. A timer per activation, not per item; re-pressing restarts it rather than stacking.
- Items already placed in a container are not siblings worth glowing — the player has dealt with those.

## Acceptance criteria
- [ ] With the ability locked, Q does nothing at all.
- [ ] Unlocked and holding a series item, exactly the ground members of that series are highlighted, for 5 s, then not.
- [ ] Holding a series-less item gives feedback and highlights nothing.
- [ ] Highlights are visible through terrain (the point of the ability) and disappear when an item is picked up.
- [ ] No highlight node survives the level ending — check for orphans; gdUnit4 reports them.
- [ ] Tests: activation with/without the unlock, correct set selected, expiry, orphan-free teardown.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Stand among 150 items with a pole in hand and press Q — can you pick the three siblings out of the mess at a glance?
- [ ] Look at it from 20 m and through a hill.

## Notes / decisions
Built by an agent in an isolated tree; integrated by hand afterwards.

- **Highlights are separate overlay nodes**, parented to the `PickupItem` they wrap, never a tint on the item's own material — an imported glTF multiplies its albedo, so a tint would have darkened the thing it was meant to pick out.
- **`InsightAbility.install(parent)` is idempotent**: it frees any existing ability under the same parent first. That is what keeps a restart from leaving two sets of highlights behind.
- The ability node is created by `Main._build_playing_scene()`; the WP itself does not own that file, so the hook was added at integration. Nothing in the ability's own tests would have caught its absence — see the wave-1 note in WP-3.4.
