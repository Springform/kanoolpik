# WP-4.7 — Seeing what the others are doing

**Phase:** 4 · **Lane:** hud · **Size:** S · **Status:** unclaimed · **Depends on:** WP-4.2, WP-4.5

## Goal
The HUD stops speaking as if you are alone: who packed what, who bought which ability, how many of you there are, and whether the connection is healthy.

## Owns
- `src/game/hud/` multiplayer additions
- `assets/i18n/` rows (**pre-place before the wave**)
- `tests/integration/test_multiplayer_hud.gd`

## Interfaces
Everything needed is already on the bus and already carries a `player_id`: `item_placed`, `container_completed`, `ability_unlocked`, `points_awarded`, `item_summoned`, `collectible_found`. That was not an accident — it is why the events were shaped that way in WP-3.0.

## Design notes
- **Name the actor, not the event.** "Mikkel pakkede flaskekassen" is worth reading; "flaskekassen blev pakket" is not, and you already have that in the progress bar.
- A mate's purchase already updates the skill panel (WP-3.1 made it event-driven for exactly this). It should also say who bought it — shared points mean the party can spend them without agreeing, and the toast is what starts that conversation.
- Keep the toast queue at three. Six people generate a lot of events; the HUD is not a chat log.

## Acceptance criteria
- [ ] Placements, completions and purchases name the player who did them.
- [ ] A ping or connection indicator, unobtrusive.
- [ ] Six players' worth of events do not bury the player's own feedback.
- [ ] Single player reads exactly as it does today — no "du" turning into "Spiller 1".
- [ ] Looked at on screen with a full toast queue.

## Notes / decisions
