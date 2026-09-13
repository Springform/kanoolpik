# WP-1.1 — Carried items visible in hand

**Phase:** 1 · **Lane:** items · **Size:** M · **Status:** done (Claude, 2026-09-13)

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
- [x] Carrying 0..capacity items renders the correct count, ordered by pick-up order (use `state.carried_by()` order — sorted by id today; if order matters, request a core change to track pick-up order rather than hacking presentation).
- [x] Items use the same colour/size scheme as `PickupItem` (extract the palette into `items/item_palette.gd` so both use one source).
- [x] Held items don't collide with the world and don't cast shadows onto the camera.
- [x] Integration test: pick up two items → `HeldItems` has two children; place one → one child.
- [x] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Items never clip through walls when walking into them (render on a separate layer or scale them small).
- [ ] The top item is obviously the "active" one.

## Notes / decisions
- **Core change (small, tested):** `WorldState.set_carried` now stamps a monotonic `carry_seq`; `carried_by()` returns pick-up order and `active_item(pid)` returns the last one. Serialised (`carry_counter`), so snapshots keep the order. Player, HUD and HeldItems all rely on "last = active".
- `ItemPalette` (items/item_palette.gd) is the single source for placeholder colours/sizes; `PickupItem` and `HeldItems` both use it.
- `HeldItems` is a Node3D under the player's `Camera3D` (`player.tscn` gained that one child node). First-person meshes use `no_depth_test` + render priority so they never clip into walls, and cast no shadows. `is_first_person = false` is reserved for remote avatars (phase 4).
- Stack offset tuned by screenshot at FOV 90 / 16:9: `Vector3(1.05, -0.62, -0.9)`.
- **Bug found & fixed while verifying:** the HUD subscribed to `local_player_spawned` after the player had already emitted it, so prompts/carrying never updated. Player now joins group `local_player`; HUD looks it up on `_ready`. Regression test in `test_hud.gd`.
- Godot's default font lacks ▶; the active-item marker is `»`.
