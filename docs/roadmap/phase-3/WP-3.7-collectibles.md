# WP-3.7 — Hidden collectibles

**Phase:** 3 · **Lane:** content/abilities · **Size:** M · **Status:** unclaimed · **Depends on:** WP-3.0

## Goal
Four things are hidden on the island that nobody needs to find. Finding one is a small permanent gift: sunglasses, a headlamp, a trolley that carries three more, a whistle. They reward looking at the place rather than sorting it, and they give a second playthrough a reason to exist.

## Owns (may edit)
- `src/game/collectibles/`
- `data/catalog/collectibles.json` (new), `data/levels/island_01.json` — the placement block only
- `assets/i18n/` rows for `collectible.*`
- `tests/unit/core/test_collectibles.gd`, `tests/integration/test_collectibles.gd`

## Must not touch
- `src/core/command_processor.gd` beyond the agreed `collect` handling — coordinate in the WP thread before touching core at all
- The item catalog: a collectible is not an item and must never count toward completion

## Interfaces
**Consumes:** `WorldState`, `Progression`, `GameSession.container_position()` for placement sanity.

**Provides:** `collectible_found { collectible_id, player_id }` on the bus; effects declared as data, not code branches.

## Design notes
- **Placement is hand-authored, not generated.** A hiding place only reads as a hiding place if a person chose it — behind the collapsed tent, under the canoe, in the reeds. Put the four positions in the level JSON.
- Effects reuse what exists: the trolley is `capacity_bonus`, and must compose with `steady_hands` rather than replace it (3 + 2 + 3 = 8, and the arithmetic belongs in one function). Sunglasses and the headlamp are phase-5 hooks — declare them as found and let the shader read the flag later. The whistle is a phase-4 hook; store it, do nothing yet.
- Found state lives with progression, so it saves and replicates with everything else.
- They must be findable without being frustrating: visible from *somewhere* a player would stand, never inside geometry, never requiring a jump the controller cannot make.

## Acceptance criteria
- [ ] Four collectibles exist in the level data, each at a hand-chosen position on walkable ground.
- [ ] Finding one emits the event once; re-entering the area does nothing.
- [ ] The trolley composes with `steady_hands` — capacity is computed in one place and both bonuses apply.
- [ ] Found state survives save and resume.
- [ ] Collectibles never affect completion, accuracy or the island-clean check.
- [ ] Tests: the composition arithmetic, one-shot finding, save round-trip, and that `is_island_clean` ignores them.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Find all four without knowing where they are. Time it. If one takes more than three minutes it is hidden badly, not cleverly.
