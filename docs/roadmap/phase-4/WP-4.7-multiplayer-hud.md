# WP-4.7 — Seeing what the others are doing

**Phase:** 4 · **Lane:** hud · **Size:** S · **Status:** done · **Depends on:** WP-4.2, WP-4.5

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
- [x] Placements, completions and purchases name the player who did them.
- [x] A ping or connection indicator, unobtrusive — `4 i kanoen · 38 ms` under the clock, hidden when there is no party.
- [x] Six players' worth of events do not bury the player's own feedback — somebody else's toast is evicted first; yours only when all three are yours.
- [x] Single player reads exactly as it does today — four tests exist for that one sentence.
- [x] Looked at on screen with a full toast queue: `tools/shots.gd --only=multihud`.

## Notes / decisions

## Decisions

**`PlayerNames.others_present()`, not "are we in a room".** A host alone in a
lobby is in a room, and telling them "Spiller 1 pakkede flaskekassen" about
themselves is worse than saying nothing. The question the HUD actually has is
whether there is somebody whose name is worth printing, so that is the question
the helper answers — and it is the single switch that keeps single player
reading exactly as it did.

**A mate's mistake says nothing at all.** Their correct placements are news;
their wrong ones are not. A verdict is feedback, feedback is for whoever can act
on it, and six people making mistakes would be a stream of red nobody can do
anything about laid over the one thing you are trying to read.

**Completions are credited to the last placer.** `container_completed` carries a
container and no actor — the core has no opinion about who deserves the credit,
and it is right not to have one. But the placement that completed it comes from
the same command and arrives first, so the HUD knows. Remembered in
`_last_placer` rather than inferred later.

**Eviction has a rule now.** The queue is three deep and a busy room fills it in
a second; plain oldest-first meant your own "wrong box" landed and was gone
before you looked up. Somebody else's oldest goes first; your own is dropped
only when all three are yours.

**The ping rides the relay's auto-response.** `room.js` already registers
`setWebSocketAutoResponse("ping" -> "pong")`, so Cloudflare answers at the edge
and the Durable Object is never woken — the measurement is close to free, and it
doubles as the keepalive that stops a proxy closing an idle socket. Three
seconds rather than one, because a number that jitters every second reads as a
problem when it is not.

## Scope note — this WP touched two files it does not own

`src/net/transport.gd` and `src/net/websocket_transport.gd`, for
`latency_ms()` and the ping. There is no way to display a round trip without
measuring one, and the measurement belongs next to the socket. Additive only:
the seam gained a method that answers -1, and nothing existing changed
behaviour.

`tests/net/fake_relay.gd` also gained the ping auto-response, because the Worker
has it. Read first, copied second — the last time that order was reversed, a red
test went green while the deployed relay stayed broken.
