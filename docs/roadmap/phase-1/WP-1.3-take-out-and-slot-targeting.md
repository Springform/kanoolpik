# WP-1.3 — Take items back out; aim at a specific slot

**Phase:** 1 · **Lane:** containers / player · **Size:** M · **Status:** done (Claude, 2026-09-13) · **Depends on:** 1.2

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
- [x] Aim at empty slot k + E → `place(..., k)`. Aim at occupied slot + E → `take_out`. Aim at body + E → previous behaviour.
- [x] HUD-facing: expose `Player.aimed_slot() -> int` so 1.4 can show "Slot 3" / "Tag ud".
- [x] Rejected commands (`hands_full`) are visible via `GameEvents.command_rejected` (already wired).
- [x] Integration test covers all three aim cases by calling the functions directly (no input simulation needed).
- [x] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Slot colliders are big enough to hit from 2–3 m without pixel hunting.
- [ ] Taking out the wrong item then placing it right feels like fixing, not fighting.

## Notes / decisions
- `SlotNode` is a **StaticBody3D**, not an Area3D, and sits **above the container lid** (`ContainerNode.SLOT_HEIGHT = 0.74`). Both were required: an Area3D with monitoring off is not a reliable ray target, and at the old height the slots sat *inside* the container's own collision box, so the ray always hit the body first. Verified in-engine (the ray reports `Slot_7` when aimed at a slot and the container when aimed at the body), not just in tests.
- `Player.interact_with_container(container, slot)` is split out from `_interact()` so tests drive the three cases without simulating a raycast. `aimed_slot()` returns -1 for body/no hit.
- Take-out wins over place when the targeted slot is occupied — even with a full hand; the command is then rejected and the HUD says "Hænderne er fulde" rather than nothing happening silently.
- Slot hitboxes (0.24 × 0.30 × 0.30) are deliberately larger than the 0.18 cubes so aiming from 2–3 m needs no precision.
- `ContainerNode` exposes `slot_node/slot_mesh/slot_mark/slot_count/slot_at`; the private `_slot_meshes`/`_slot_marks` arrays are gone.
- **Bug found while verifying (from WP-1.2):** the ✓ and ✕ markers never rendered at all — Godot's default font (Open Sans) has no Dingbats/Geometric Shapes glyphs, so they drew as nothing while string assertions still passed. Marker is now `×` (Latin-1) and the completed label uses a translated suffix (`ui.container_packed`, "Bålplads – pakket"). A test asserts the marker stays below U+0250. Same class of bug as `▶` in WP-1.4 — **when adding a glyph, look at it on screen.**
- Two tests I wrote were wrong before the code was: tent poles are size 2 against capacity 3, so you cannot hold two at once, and hands must be free before a take-out. Both are real rules worth remembering when tuning carry capacity.
