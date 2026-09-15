# WP-4.4 — Lobby: create, join, ready up

**Phase:** 4 · **Lane:** flow/hud · **Size:** M · **Status:** unclaimed · **Depends on:** WP-4.2

## Goal
From the title screen: "Start alene", or "Lav et hold" which shows a room code to read aloud, or "Join" which takes one. A player list fills as friends arrive. Everyone ready → the host starts, and all six land on the same island.

## Owns
- `src/game/lobby/`
- `src/game/title/title_screen.gd` + scene — the two new buttons
- `assets/i18n/` lobby rows (**ask for these to be pre-placed before the wave starts**)
- `tests/integration/test_lobby.gd`

## Must not touch
- `src/core/**`, `src/net/**` — the transport is done; use it

## The thing that must not go wrong
**Everyone must generate the same mess.** `MessGenerator` is seeded, so the host's seed goes to every client in the lobby and `start_level` runs with it locally on each. Nobody ships item positions over the wire at level start — that is what the determinism is for. A test must prove two peers starting from the same seed have identical `to_dict()` before a single command is issued.

## Acceptance criteria
- [ ] Room code is displayed large enough to read to someone across a table, and copyable.
- [ ] Joining with a bad code fails with a reason, not a hang.
- [ ] The player list updates as people join and leave.
- [ ] The host's seed reaches every client; all peers' initial states are identical.
- [ ] Single player still starts with no network anywhere near it.
- [ ] A player who closes the tab in the lobby disappears from the others' list.

## Notes / decisions
