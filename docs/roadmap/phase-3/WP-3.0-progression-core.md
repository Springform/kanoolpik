# WP-3.0 — Progression as replicated state; `unlock` and `summon` commands

**Phase:** 3 · **Lane:** core/infra · **Size:** M · **Status:** **done** (2026-09-14, session 3) — 305 tests green

> **Blocks every other phase-3 WP.** Nothing else in this phase starts until this is merged.
> Implements [ADR 0010](../../adr/0010-progression-is-replicated-state.md) — read it first.

## Goal
The party's skill points and unlocked abilities live inside the simulation. Buying an ability is a command like any other: validated once, applied once, broadcast as an event. A mate summoning a series of paddles moves them through the same path that dropping one does. When phase 4 arrives, none of this needs revisiting.

## Owns (may edit)
- `src/core/progression.gd`, `world_state.gd`, `command_processor.gd`, `commands.gd`, `save_game.gd`
- `src/autoload/game_session.gd`, `src/autoload/game_events.gd`
- `project.godot` — **input actions for the whole phase, added here so no later WP touches this file**
- `tests/unit/core/`

## Must not touch
- `src/game/` — the presentation layer is other WPs' territory
- `data/` — WP-3.7 and WP-3.8 own content

## Interfaces
**Consumes:** existing `PlacementRules`, `Catalog`, `WorldState`.

**Provides:**
- `WorldState.progression: Progression` — serialised in `to_dict()` / `from_dict()`.
- `GameSession.progression` keeps working as a read-only accessor returning `state.progression`.
- `Commands.unlock(player_id, ability_id)` and `Commands.summon(player_id, series, position)`.
- New events on the bus, fanned out in `GameEvents.publish()` exactly like the existing ones:
  - `points_awarded { container_id, points, total_available }`
  - `ability_unlocked { ability_id, player_id, points_left }`
  - `capacity_changed { player_id, capacity }`
  - `item_summoned { item_id, player_id, position }`
- Input actions, so the ability WPs only bind — never edit `project.godot`:
  | Action | Default key | Used by |
  |---|---|---|
  | `ui_skills` | Tab | WP-3.1 |
  | `ability_insight` | F | WP-3.2 |
  | `ability_call_mate` | R | WP-3.4 (R for *Råb*) |
  | `ability_map_sense` | C | WP-3.3 (toggle) |

## Design notes
- **Crediting moves into `_place()`.** Where `CommandProcessor` appends `container_completed`, it also credits the point and appends `points_awarded`. `GameSession._on_command_applied()` loses its `progression.credit_container()` call and keeps only the autosave trigger. `_credited_containers` already makes this idempotent.
- **`unlock` validation** is `Progression.can_unlock()` — unchanged. Errors: `E_UNKNOWN_ABILITY`, `E_ALREADY_UNLOCKED`, `E_NOT_ENOUGH_POINTS`. A rejected unlock changes nothing.
- **`steady_hands` is a party upgrade.** On unlock, set every player in the state to `3 + progression.capacity_bonus()` and emit one `capacity_changed` each. Do not recompute capacity anywhere else: `GameSession.base_capacity()` stays the value a *joining* player starts at.
- **`summon` rules.** Only items of that series whose kind is `GROUND` move — never one already placed, never one in someone else's hands. Once per series: record it in the progression (`summoned_series`), so it survives a save and cannot be farmed. Reject with `E_ABILITY_LOCKED` when `call_mate` is not unlocked, `E_SERIES_SPENT` on a repeat, `E_UNKNOWN_SERIES` when no such series exists. The caller supplies `position`; clamp it to `island_radius` and the level's `ground_y` — a client must not be able to teleport items into the lake or off the map.
- **Save schema.** Bump the version; `SaveGame.unpack()` already returns `{}` for an unknown schema and `GameSession.load_save()` already handles that by returning false. Keep `unpacked["progression"]` working for the caller, reading it out of the state.
- **Determinism.** No RNG, no time, no Node access. Two peers applying the same command sequence must land on identical `to_dict()` output — the existing determinism test should be extended to cover a run that includes an unlock and a summon.

## Acceptance criteria
- [ ] A container completing awards exactly one point, through the processor, and a second completion of the same container awards none.
- [ ] `unlock` succeeds only with enough points; the rejected case leaves points, `unlocked` and capacity untouched.
- [ ] Unlocking `steady_hands` raises capacity for every player in the state, and a player can then pick up an item that was `hands_full` a moment earlier.
- [ ] `summon` moves only ground items of the series, to the clamped position, and the second summon of that series is rejected.
- [ ] A save written after an unlock and a summon, reloaded, has the same points, the same unlocked list, the same spent series and the same capacities.
- [ ] Round-trip determinism: two `WorldState`s fed the same command list (including unlock and summon) produce equal `to_dict()`.
- [ ] Tests: `tests/unit/core/test_progression.gd` extended; new cases in `test_command_processor.gd`, `test_world_state.gd`, `test_save_game.gd`.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Pack a container, confirm the point lands (HUD still shows the old counter — that is WP-3.1's job).
- [ ] Load a save from before this WP: the game starts a fresh run instead of crashing.

## Notes / decisions

**Q was already `drop`.** The first draft of this WP gave Klarsyn the Q key, which has bound `drop` since phase 1. Abilities are F (Klarsyn), R (Råb — the Danish initial, and the one people will remember), C (Stedsans). Tab is `ui_skills`. The table above is corrected; nothing else needs to change.

**Where the island bounds live.** Clamping a summon needs to know where the walkable ground ends, and the core holds no level data. Rather than passing bounds in the command (client-supplied, so worth nothing as a check) or into the processor's constructor (invisible to a replicated snapshot), `WorldState` gained `island_radius` / `ground_y`, set by `GameSession._begin()` from the level and serialised with everything else. `radius <= 0` means unbounded, so every existing unit test that builds a bare `WorldState` behaves exactly as before.

**`drop` is still unclamped.** It has accepted an arbitrary client position since phase 1, and `WorldState.clamp_to_island()` now exists to fix it. Left alone deliberately: it is a behaviour change outside this WP's goal, and it belongs with WP-1.7 or the phase-4 host-validation pass. Worth doing then — the hole is real, it is just not new.

**A shout with nothing to fetch costs nothing.** `summon` on a series that is already fully packed fails with `nothing_to_summon` and does **not** mark the series spent. Marking it would punish a player for a keypress that changed nothing.

**`SaveGame.pack()` lost its progression argument.** It is `pack(state, level_id)` now — the progression is inside the state. `unpack()` still returns a `progression` key, pointing at the state's own object rather than a copy, so callers did not have to change.

**`steady_hands` sets capacity, it does not add to it.** Unlocking sets every player to `Progression.capacity()` (base + bonus) rather than incrementing what they have. That makes the value idempotent and re-derivable from the progression alone — important when a late joiner arrives mid-run — but it does mean a player whose capacity was raised by something else would have it overwritten. Nothing does that today; WP-3.7's trolley must go through `capacity_bonus()` for the same reason, and its WP says so.

**The new tests were mutation-checked.** Four deliberate breaks — dropping the ground-only filter in `summon`, disabling the clamp, skipping the capacity fan-out, skipping the credit — each turned the suite red on the specific guard written for it. Per the WP-2.6 lesson, a green suite is only evidence once you have watched it go red.
