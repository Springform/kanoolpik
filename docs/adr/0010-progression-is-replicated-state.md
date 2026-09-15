# ADR 0010 — Progression is replicated state, and unlocking is a command

**Status:** Accepted · 2026-09-14 (implemented by WP-3.0) · **Extends [ADR 0003](0003-pure-core-command-pattern.md)**

## Context
[`Progression`](../../src/core/progression.gd) exists and is tested, but it sits outside the simulation. `GameSession._on_command_applied()` watches the event stream and calls `progression.credit_container()` as a side effect; `SaveGame.pack()` stores it next to the `WorldState` rather than inside it. That was the right shape while abilities were a phase-3 promise: nothing read progression back into the world.

Phase 3 ends that. Three of the five abilities write to the world or move items:

- **Rolige hænder** changes `WorldState.player_capacity` — a field only [`CommandProcessor`](../../src/core/command_processor.gd) is allowed to touch.
- **Råb på en kammerat** relocates every remaining ground item of a series — the same class of mutation as `drop`.
- **Autopilot** picks the slot a `place` lands in, so what the player pressed and what the world did stop being the same thing.

And unlocking is itself a decision the party makes together: GAME_DESIGN §8 already says skill points are shared, and that the buying is meant to provoke conversation. Two clients that each unlock locally, from their own copy of a shared point pool, diverge on the first double-spend.

## Decision
**`Progression` moves inside `WorldState`, and every change to it goes through a command.**

1. `WorldState` owns a `Progression` and serialises it in `to_dict()` / `from_dict()`. `SaveGame` schema bumps; older saves are rejected by the existing version check rather than migrated — the only saves in existence are KA's own test runs.
2. `CommandProcessor` credits the point when it emits `container_completed`, in the same `apply()` that placed the item. It stops being a `GameSession` side effect.
3. Two new commands:
   - `unlock(player_id, ability_id)` — validates against the shared pool, emits `ability_unlocked`. `steady_hands` additionally raises capacity for **every** player in the state and emits `capacity_changed` per player.
   - `summon(player_id, series, position)` — moves every ground item of that series to `position`, once per series, emitting `item_summoned` per item. The position comes from the client; the host clamps it to the island radius.
4. `GameSession.progression` stays as a read-only accessor (`state.progression`) so the HUD and the ability scenes do not learn a new path.

## Alternatives considered
**Leave progression local and replicate it separately in phase 4.** Cheaper today, and wrong in the same way that replicating item positions separately from item ownership would be wrong: two authorities over one game means two versions of who can carry what. The seam would open exactly where it is hardest to debug — six browsers, one point, two buyers.

**Make abilities purely presentational and never touch state.** Works for Klarsyn and Stedsans, which only draw things. It cannot work for capacity or for summoning, and a rule that holds for three of five abilities is not a rule.

## Consequences
- Phase 4 inherits progression replication for free: it rides in the snapshot a late joiner already receives.
- The determinism guarantee now covers abilities. A recorded command log replays a run including what the party bought and when.
- Ability *effects* still live in the presentation layer. The core knows `auto_place` is unlocked; it does not know what "within 2 m" means. The scene reads the flag and submits an ordinary `place` — the core stays free of geometry.
- `steady_hands` raising everyone's capacity is a design choice this ADR fixes: it is a party upgrade, consistent with the shared pool. Single-player notices no difference.
- One save-format break, taken now while the only saves are throwaway.
