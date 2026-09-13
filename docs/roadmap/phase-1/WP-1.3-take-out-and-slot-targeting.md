# WP-1.3 — Take items back out; aim at a specific slot

**Phase:** 1 · **Lane:** containers / player · **Size:** M · **Status:** unclaimed · **Depends on:** 1.2

## Goal
Mistakes are fixable: aiming at an occupied slot and pressing E (with empty-enough hands) takes the item out (`Commands.take_out`). Aiming at a specific empty slot places into *that* slot, so ordered containers (tent bag) become a real puzzle instead of auto-slotting. If the crosshair is on the container body rather than a slot, keep today's behaviour (first correct slot, else first free).

## Owns (may edit)
- `src/game/containers/` (each slot becomes its own `Area3D`/`StaticBody3D` child with `slot_index`)
- `src/game/player/player.gd` `_interact()` only (coordinate with 1.7 owner: rebase on their branch; touch nothing else in the file)
- `tests/integration/test_slot_targeting.gd`

## Interfaces
**Consumes:** `Commands.take_out`, `Commands.place`, `PlacementRules.evaluate/find_correct_slot`, `ContainerNode.first_free_slot()`.
**Provides:** `ContainerNode.slot_at(collider: Node) -> int` (−1 if body), `class_name SlotNode` with `container_id`, `slot_index`.

## Acceptance criteria
- [ ] Aim at empty slot k + E → `place(..., k)`. Aim at occupied slot + E → `take_out`. Aim at body + E → previous behaviour.
- [ ] HUD-facing: expose `Player.aimed_slot() -> int` so 1.4 can show "Slot 3" / "Tag ud".
- [ ] Rejected commands (`hands_full`) are visible via `GameEvents.command_rejected` (already wired).
- [ ] Integration test covers all three aim cases by calling the functions directly (no input simulation needed).
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Slot colliders are big enough to hit from 2–3 m without pixel hunting.
- [ ] Taking out the wrong item then placing it right feels like fixing, not fighting.
