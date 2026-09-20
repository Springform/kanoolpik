# WP-4.6 — Joining, leaving, reconnecting, and the host walking off

**Phase:** 4 · **Lane:** net · **Size:** M · **Status:** done (session 6) · **Depends on:** WP-4.2, WP-4.4

## Goal
The session survives real life: someone's wifi drops, someone closes a tab, someone's laptop sleeps. And when the host leaves, everyone is told plainly instead of watching a frozen island.

## Owns
- `src/net/` reconnection handling
- `src/autoload/game_session.gd` — only the peer add/remove path
- `tests/net/test_join_leave.gd`

**Scope widened, declared rather than smuggled** (CLAUDE.md's one rule). The
*Owns* list was written before WP-4.4 existed and before anyone had noticed that
peers are not players. What this actually touched:

| Outside *Owns* | Why |
|---|---|
| `src/core/commands.gd`, `command_processor.gd`, `world_state.gd` | `join` and `leave` have to be commands. A peer that adds itself has a state the host does not. |
| `src/net/command_codec.gd`, `transport.gd` | the two commands must travel; `peer_joined`/`peer_left`/`disconnected` moved onto the seam so [GameSession] can listen without asking which transport it has |
| `src/game/lobby/` | the roster gap WP-4.4 left open closes with `known_peers()` |
| `src/game/main/`, `src/game/title/` | the host leaving has to say so somewhere |
| `src/game/ui/panel_fit.gd` (new) | see the panel note below |

## What was decided
- **A leaver's carried items** land in a ring at the position the `leave` command
  carries, clamped to the island, with an `item_dropped` event each — so a
  friend's wifi dying looks like them putting things down rather than items
  teleporting. A ring, not a point: six things at one coordinate are one
  unclickable pile.
- **The position is the command's, not the state's**, because the core does not
  know where anybody is standing — positions are presentation. Until WP-4.5
  replicates transforms the host passes the level's spawn point. Wrong, but
  wrong somewhere a person walks past, rather than at the origin.
- **Rejoining gets you the relay's lowest free id**, which is already what the
  protocol does, and a fresh `join` — so the same person rejoining is a new
  player as far as the world is concerned. The party's points and abilities are
  in the replicated state (ADR 0010) and are untouched by either command; there
  is a test for exactly that.
- **Host gone ends the round** (ADR 0002) with "Værten forlod runden." on the
  title screen, distinct from "Forbindelsen blev afbrudt." **Host migration is
  closer than it looks and still out of scope:** every client already holds a
  complete `WorldState`, so the missing pieces are electing a successor and
  getting the relay to re-seat them as peer 1 — neither of which the current
  protocol can express.

## Acceptance criteria
- [x] A client disconnecting drops its carried items where it stood, on every peer.
- [x] **Reconnecting into a running room converges to the host's state exactly** — it is a fresh `join` and a fresh snapshot, which is what joining mid-round already was. See below for why there is no grace period.
- [x] The host leaving tells everyone, in Danish, and returns them to the title screen rather than a frozen world.
- [x] A dropped socket is distinguished from a deliberate quit.
- [x] Every case above is a test in the core first, then over a real socket.

## Reconnect, and why it needed no number

The stop here was deliberate: automatic reconnection seemed to need a decision
nobody had earned the right to make — **how long a dropped player keeps their
place.** Remove them at once and a ten-second tunnel costs somebody their
armful; hold their seat and a room of six fills with ghosts.

**KA answered it by asking a different question.** Joining a round that is
already running works, and nothing personal is lost when you go: progression
lives in the replicated `WorldState` (ADR 0010), so a returning player comes back
with the party's points, abilities and capacity. There is no seat worth holding.
Drop them straight away and let them walk back in.

That left exactly two things, and neither is a number:

**1. The armful lands where they were standing.** `GameSession._on_peer_left`
used to pass `player_spawn(0)`, because the core has never carried positions and
had nothing better to offer. WP-4.5 replicates transforms, so `RemotePlayers`
writes the latest one to `GameSession.remember_peer_position()` and the `leave`
command carries it. Positions are still not world state: this is one dictionary,
presentation-fed, read by one command and cleared with the round.

The body centre is handed over unflattened on purpose —
`WorldState.clamp_to_island` already drops every position to `ground_y`, and
saying it twice is how two places start to differ. (A first attempt did say it
twice; the mutation that should have killed the test survived, which is what
pointed at the duplication.)

**2. The way back in is one click.** A connection that dies under a running
round now returns to the title with the room code already in the field and the
Join button focused, under a notice that says what to press. Only when it was
*our* connection that died: if the host left there is no room to go back to, and
the relay would make us the first socket in a new one — hosting an empty island
under a code nobody is coming to. WP-4.4 refuses that, but offering it is still
a lie.

What is still not there, deliberately: no automatic retry and no "reconnecting…"
state. A person pressing a focused button is a clearer contract than a client
that silently decides how many times to try.

## Three findings

**`net-live` earned its keep on its first real run.** The suite was green on
`FakeRelay` and red against Cloudflare, with
`asked to be host=true but the relay made us host=false` in the log. The tests
opened the host's socket and a guest's back to back, so the two were racing to
be the first socket in the room — and on loopback the host always won. The game
never has this race: the host mints a code and reads it aloud, so a person sits
between the two connections. The tests now join in order (`_open_room()`, then
`_add_guest()`), which is the protocol's own rule restated.

The same run killed a fixed `_pump(40)` — 80 ms, a comfortable round trip on
loopback and nothing over the internet. One of those two tests asserted only
that the bad thing had not happened, so against a dead relay it would have
passed while proving nothing. Both now wait on an observable effect.


**The reason a round ended had to move onto the close frame.** `FakeRelay` sent
`hostgone` and closed in the same breath, and the first diagnosis was that the
fake was being unfaithful — it was "fixed" by deferring the close a turn. That
was wrong twice over: `infra/relay/src/room.js` does exactly the same thing, so
the fix made the fake *stop* resembling production, and it turned the test green
while the deployed relay stayed broken. `net-live` said so on the next run.

The real problem is not whose fault the flush is. **Godot discards buffered
packets the moment a socket reaches `STATE_CLOSED`** — measured: OPEN with one
packet to CLOSED with none, in a single poll. A message that races a close can
always lose. So the Worker now closes a client with **code 4000**, the transport
reads `get_close_code()`, and `hostgone` stays as a fast path that may or may not
win. A close code cannot lose the race, because it is the close.

`infra/relay/` has an 18th test for it, in real `workerd`. **The Worker must be
redeployed for this to take effect** — the client change alone does nothing.

**Godot discards buffered packets when a WebSocket reaches `STATE_CLOSED`**, and
it goes there from `STATE_OPEN` in a single poll — measured, not assumed. So a
farewell that has not been read by the time the close lands is gone, and no care
on the client can recover it. Everything rests on the relay sending and closing
on separate turns. An attempted client-side fix (drain before reacting to the
close) turned out not to fix this at all; it is kept as a labelled guard with no
test rather than dressed up as a solution.

## The panel bug, twice

WP-4.4 replaced a hard-coded panel height with
`set_anchors_and_offsets_preset(PRESET_CENTER, PRESET_MODE_MINSIZE)`. That fix
was wrong: called before a layout pass it sizes from the panel's *current* size,
so two deferred calls in one frame compound — adding the host-left notice took a
545 px panel to 1039 px, centred, with the title off the top of the screen. The
screenshot pass caught it, as it caught the first one. `PanelFit.centre()` writes
the offsets from the minimum size every time and is idempotent; there is a test
that fits twice and compares.

## Notes
