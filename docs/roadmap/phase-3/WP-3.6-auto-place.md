# WP-3.6 — Autopilot: place without aiming

**Phase:** 3 · **Lane:** abilities/player · **Size:** M · **Status:** **done** (2026-09-14, wave 2) · **Depends on:** WP-3.0
> **Schedule against [WP-1.7](../phase-1/WP-1.7-controller-feel.md):** both own `src/game/player/player.gd`. They must not run in parallel.

## Goal
Three skill points buy the end of aiming. Within 2 m of the container an item belongs in, pressing E puts it in the first correct slot — no looking at the slot, no cycling. Carrying an armful to the right place becomes one press per item.

## Owns (may edit)
- `src/game/abilities/auto_place/`
- `src/game/player/player.gd` — the interact path, minimally
- `tests/integration/test_auto_place.gd`

## Must not touch
- `src/core/` — it still receives an ordinary `place` command
- `src/game/containers/` — slot geometry is WP-2.3's and works

## Interfaces
**Consumes:** `GameSession.progression.has("auto_place")`, the player's existing interact handling, `GameSession.container_position()`, `PlacementRules.evaluate()` to find the first slot with verdict `CORRECT`.

**Provides:** nothing; it submits the same `Commands.place()` a manual placement does.

## Design notes
- **Precedence is the whole design.** If the interaction ray is already on a slot, the manual placement wins — the ability assists, it never overrides an aim. Autopilot only fires when E would otherwise do nothing useful.
- "First correct slot" means asking `PlacementRules` per slot and taking the first `CORRECT`. In an *ordered* container that is the next sequence position, which falls out of the rules for free — do not special-case it.
- If no slot in range is correct, do nothing rather than placing wrongly. The ability must never spend the player's accuracy score for them.
- 2 m is from GAME_DESIGN §6; measure from the player to the container's position, and keep the constant in one named place for WP-3.8 to tune.
- Ambiguity: two containers within 2 m, both correct. Take the nearer. Note it in the WP if that feels wrong in play.

## Acceptance criteria
- [ ] Locked: E behaves exactly as it does today (a regression test on the existing placement path).
- [ ] Unlocked and in range with a correct slot free: E places into the first correct slot.
- [ ] Aiming at a specific slot still places there, even when autopilot would have chosen another.
- [ ] No correct slot in range: E does nothing, and no wrong placement is recorded in `stats`.
- [ ] An ordered container fills in sequence order across repeated presses.
- [ ] Tests: all five cases above, plus the two-containers-in-range tiebreak.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Carry three cans to the pant bag and press E three times without looking down. Does it feel like help or like losing control?
- [ ] Try to place something deliberately wrong while it is on — can you still?

## Notes / decisions
- **"E would otherwise do nothing useful" was defined as: the interaction ray found nothing at all.** Aiming at an item, a slot, *or a container body* all stay manual. That has a consequence worth playtesting: with Autopilot bought, looking straight at the wrong container still lets you place wrongly, while looking at nothing refuses to. It reads as "you asked for it", but it is a judgement call, not a rule the WP settled.
- **Distance is measured flat (XZ).** `container_positions` are flat data that presentation lifts onto the terrain; counting the player's ~1.8 m eye height against a container's y=0 would silently spend half the 2 m budget. Pinned by a test.
- **Nearest wins, ties by sorted container id** so it stays deterministic for phase 4. Flagged for playtest: the two canoes are 3.5 m apart and *are* different destinations (crew A vs crew B), so silently taking the nearer one for the first paddle of a series is the one case where "nearest" could pick wrong. It self-corrects after the first member, because the series rule then makes the other canoe `SPLIT_SERIES`.
- `player.gd` changed only in the interact path: the old `_interact()` body moved verbatim into a public `interact_with(target, slot)` with one added `else` branch. The `PickupItem` and `ContainerNode` branches are byte-for-byte unchanged.
