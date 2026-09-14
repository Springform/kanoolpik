# WP-3.4 — Råb på en kammerat: the series comes to you

**Phase:** 3 · **Lane:** abilities · **Size:** M · **Status:** **done** (2026-09-14, wave 1) · **Depends on:** WP-3.0 (`summon` command)

## Goal
Holding an item and pressing F shouts for a mate. Every remaining member of that series, wherever it is lying on the island, arcs over and lands at your feet. Once per series, for two skill points — the ability that turns the last twenty minutes of hunting into a decision about which series to spend it on.

## Owns (may edit)
- `src/game/abilities/call_mate/`
- `assets/audio/sfx/` — one new shout cue, generated (`tools/gen_sfx.py`), plus its CREDITS-free procedural provenance
- `tests/integration/test_call_mate.gd`

## Must not touch
- `src/core/` — the command exists; call it
- `src/game/items/pickup_item.gd` beyond reading its transform

## Interfaces
**Consumes:** `GameSession.progression.has("call_mate")`, `GameSession.state.active_item()`, `Catalog.get_item(id).series`, input action `ability_call_mate`. Submits `Commands.summon(local_player_id(), series, player_feet_position)`.

**Reacts to:** `GameEvents.item_summoned { item_id, player_id, position }` — the event is what moves the visual, not the keypress. In multiplayer the same event arrives for someone else's shout and the animation plays for free.

## Design notes
- **The arc is presentation only.** The item's logical position changes the instant the command applies; the visual interpolates over ~0.6 s from wherever it was. This is the same answer GAME_DESIGN §9 proposes for throwing, and the reason the core stays deterministic — see [ADR 0010](../../adr/0010-progression-is-replicated-state.md).
- Land items *around* the player's feet, not on one point: a ring with a small deterministic offset per item index, so six paddles do not z-fight in a stack.
- The audio cue is a shout, and it is the ability's whole personality. It should sound like a hungover man at 09:00, not a magic chime.
- The rejection cases (locked, series already spent, item has no series) all come back as `command_rejected` — show a toast, do not fail silently.
- If the series is already fully packed there is nothing to summon; the command rejects and the point is not spent.

## Acceptance criteria
- [ ] Locked: F does nothing.
- [ ] Unlocked, holding a series item: every *ground* member of the series ends up near the player, and items already placed in containers stay put.
- [ ] A second F on the same series is rejected with a visible reason and moves nothing.
- [ ] Items land inside the island radius even when the player stands at the water's edge.
- [ ] The visual is driven by `item_summoned`, proven by a test that emits the event without pressing anything.
- [ ] No item ends up inside a container's footprint or under the terrain.
- [ ] Tests: locked/unlocked, ground-only selection, repeat rejection, event-driven animation, landing positions valid.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Shout for the tent poles from the far shore. Do they arrive somewhere you can actually pick them up from?
- [ ] Does spending two points on this feel worth it, or does it trivialise the level? Note the answer for WP-3.8.

## Notes / decisions
Built by an agent in an isolated tree; integrated by hand afterwards.

- **The arc and the shout cue both hang off `GameEvents.item_summoned`, not off the keypress** — which is the whole point, and is tested by emitting the event with no input at all. A mate's shout in phase 4 will animate and sound correct for free.
- **One shout per command, not per item.** The processor publishes an `item_summoned` for every member of the series in the same frame, so the cue is de-duplicated by frame number.
- **The cue is generated, not sourced** (ADR 0008): a glottal pulse train with a shouted pitch contour that sags as he runs out of air, gliding formants, breath, and a slap-back off the far shore. One-shot by design, so there is no loop seam and deliberately no seam test — a seam test on a one-shot is a test that cannot fail.
- **`summon_centre()` pushes the landing ring clear of containers.** The core clamps to the island but holds no level geometry, so keeping a summoned paddle out of a cooler is the caller's job — the same exclusion `MessGenerator` respects when it scatters the mess.
- **The agent flagged the double-toast collision with WP-3.1 before it happened** and left `own_rejection_toasts` as an explicit switch with instructions. Integration turned it off. That is the cheapest kind of cross-WP handoff there is: name the conflict in code where the other side will be read.

### The wave-1 lesson: nothing tested the wiring
All three agents' tests built their own ability node, so all three passed while `Main` created none of them. The entire wave could have shipped as code no player could reach. `tests/integration/test_flow.gd` now asserts that starting a game installs exactly one of each, that a restart does not leave a second set, and that the summon rejection message belongs to the HUD. The restart check found a real leak on its first run: `CallMateAbility` stayed subscribed to `GameEvents` across a restart, which would have animated the next shout twice.
