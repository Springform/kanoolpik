# WP-4.6 — Joining, leaving, reconnecting, and the host walking off

**Phase:** 4 · **Lane:** net · **Size:** M · **Status:** unclaimed · **Depends on:** WP-4.2, WP-4.4

## Goal
The session survives real life: someone's wifi drops, someone closes a tab, someone's laptop sleeps. And when the host leaves, everyone is told plainly instead of watching a frozen island.

## Owns
- `src/net/` reconnection handling
- `src/autoload/game_session.gd` — only the peer add/remove path
- `tests/net/test_join_leave.gd`

## What has to be decided here
- **A leaver's carried items.** `WorldState.remove_player` currently drops them at the origin, which in a 60-metre island means a pile in the middle of nowhere. Drop them where the player stood.
- **Rejoining.** Same room, same person: do they get their old peer id and capacity back, or a fresh one? Whichever, the party's shared points and abilities are in the replicated state already and must survive either way.
- **Host gone.** v1 ends the session with a clear message (ADR 0002). Host migration stays a stretch goal — but say in the notes how close the snapshot gets us, since that is the whole reason the state is serialisable.

## Acceptance criteria
- [ ] A client disconnecting drops its carried items where it stood, on every peer.
- [ ] Reconnecting into a running room converges to the host's state exactly.
- [ ] The host leaving tells everyone, in Danish, and returns them to the title screen rather than a frozen world.
- [ ] A dropped socket is distinguished from a deliberate quit.
- [ ] Every case above is a test in the WP-4.3 harness first, then over a real socket.

## Notes / decisions
