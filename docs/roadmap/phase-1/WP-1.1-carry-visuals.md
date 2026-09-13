# WP-1.1 — Carried items visible in hand

**Phase:** 1 · **Lane:** items · **Size:** M · **Status:** unclaimed

## Goal
When the player picks something up it appears in the lower-right of the view, stacked/fanned when carrying several, with the most recently picked item on top (that is the one `place`/`drop` act on). Dropping or placing removes it with a short animation. Remote players (phase 4) will reuse the same "held items" node attached to their avatar.

## Owns (may edit)
- `src/game/items/` (add `held_items.tscn` + `held_items.gd`; `PickupItem` may gain a `make_view_copy()` helper)
- `tests/integration/test_held_items.gd`

## Must not touch
- `src/core/`, `src/autoload/`, `src/game/player/` (the player scene will *instantiate* `held_items.tscn` under its camera — request that one-line change in the PR; it is allowed as the only edit outside the folder)

## Interfaces
**Consumes:** `GameEvents.item_picked_up/item_dropped/item_placed/item_taken_out`, `GameSession.state.carried_by(pid)`, `GameSession.catalog.get_item(id)`.
**Provides:** `HeldItems` node with `func set_player(pid: int)` and `func top_item_id() -> String`.

## Acceptance criteria
- [ ] Carrying 0..capacity items renders the correct count, ordered by pick-up order (use `state.carried_by()` order — sorted by id today; if order matters, request a core change to track pick-up order rather than hacking presentation).
- [ ] Items use the same colour/size scheme as `PickupItem` (extract the palette into `items/item_palette.gd` so both use one source).
- [ ] Held items don't collide with the world and don't cast shadows onto the camera.
- [ ] Integration test: pick up two items → `HeldItems` has two children; place one → one child.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Items never clip through walls when walking into them (render on a separate layer or scale them small).
- [ ] The top item is obviously the "active" one.
