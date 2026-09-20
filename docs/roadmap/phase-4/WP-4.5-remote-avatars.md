# WP-4.5 — Remote players you can see

**Phase:** 4 · **Lane:** player · **Size:** M · **Status:** done · **Depends on:** WP-4.2
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
- [x] Five remote avatars appear, move, and carry visibly.
- [x] Name tags read at the distances people actually stand at — `tools/shots.gd --only=remote`, and the first attempt failed it.
- [x] A standing-still player generates no transform traffic; `test_a_room_where_nobody_moves_sends_nothing` asserts `presence_sent` does not rise over thirty ticks.
- [x] The rate is one constant with ADR 0011's arithmetic quoted next to it (`PresenceSender.RATE_HZ`).
- [x] A remote player leaving takes their avatar with them, freed rather than queued, with nothing left subscribed to `GameEvents`.
- [x] Transforms never travel as commands and never touch `WorldState` — `test_presence_never_touches_the_world` pins the hash.

## Notes / decisions

## Decisions

**A presence channel on the seam, not a command.** `Transport.send_presence` /
`Transport.presence_received`, default no-op. A transform needs no judging, no
ordering and no hash; putting twenty a second through `CommandProcessor` would
put the one thing that must stay deterministic at the mercy of the one thing
that cannot be. Single player gets the no-op and never notices.

**The host merges, it does not forward.** A client may only reach the host
(`room.js`), so every client transform comes back down through it. Forwarding
each one costs eleven incoming messages a tick for six players; merging them
into one fan-out costs six — which is the number ADR 0011 costed. The ADR has
been corrected to say so.

**10 Hz, not 20.** `RemoteAvatar` interpolates towards the last known position,
so the gap between frames is hidden. The second ten cost half the daily free
allowance and buy a smoothness nobody can see.

**No prediction.** Nothing extrapolates past the last known position. A guess
that turns out wrong has to be taken back, and an avatar sliding backwards out
of a wall reads worse than one that is a tenth of a second behind.

**What is carried is not sent.** `pick_up` is a command, so every peer has
already applied it: the armful is read out of `WorldState.carried_by`. Paying
for it twenty times a second would be paying for a fact the receiver has.

**Not the player scene.** `Player` is a `CharacterBody3D` that simulates itself
from input; a remote player's position is a fact that arrives on the wire, and
re-simulating it would give two answers to where somebody is standing. The
docstring on `Player` that promised scene reuse is now out of date — this
replaces it.

**Avatars appear on first transform, not on join.** The join arrives first, and
an avatar built at that moment stands at the origin until the first frame and
then walks across the island to its owner.

## Found by looking at it

1. **Name tags were unreadable at eight metres.** Scaled like the item labels
   do; at the distance where you actually cannot tell who somebody is, the name
   was a smudge. Now `fixed_size` — constant on screen, whatever the distance.
2. **The capsule was built standing on the origin**, which floats every avatar
   a metre in the air: the position on the wire is `Player`'s node origin, and
   that node's collision capsule is *centred* on it. Measured rather than
   eyeballed in the end — a 90° FOV over a domed island makes pixel-reading a
   liar in both directions.

## Left for WP-4.7
`GameSession._on_peer_left` still drops a leaver's armful at the level spawn
point. It now *could* use their last known position — `RemotePlayers` has it —
but that is a rule about where items land, which makes it the core's business
and not a transform's.
