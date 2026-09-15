# WP-4.5 — Remote players you can see

**Phase:** 4 · **Lane:** player · **Size:** M · **Status:** unclaimed · **Depends on:** WP-4.2
> **Owns the number that decides whether multiplayer stays free** — see below.

## Goal
Five other people walking around the island, carrying things, with their names over them.

## Owns
- `src/game/player/remote/`
- `tests/integration/test_remote_players.gd`

## Must not touch
- `src/core/**` — a transform is presentation, not world state, and must never become a command
- `src/net/**` beyond using it

## The free-tier constraint is yours
[ADR 0011](../../adr/0011-websocket-relay.md) does the arithmetic: transforms are the only traffic that matters, and at 20 Hz × 6 players the free plan covers about 4.6 hours of play a day. At 10 Hz, or by sending only when something changed, that roughly doubles.

So: **one named constant for the rate, and do not send an unchanged transform.** A player standing still reading a label should cost nothing. This is an acceptance criterion, not an optimisation to do later.

## Acceptance criteria
- [ ] Five remote avatars appear, move, and carry visibly.
- [ ] Name tags read at the distances people actually stand at — **look at it on screen** with `tools/shots.gd`.
- [ ] A standing-still player generates no transform traffic; a test asserts the send count stops rising.
- [ ] The rate is one constant with ADR 0011's arithmetic quoted next to it.
- [ ] A remote player leaving takes their avatar with them, with nothing left subscribed to `GameEvents` (the wave-1 lesson).
- [ ] Transforms never travel as commands and never touch `WorldState`.

## Notes / decisions
