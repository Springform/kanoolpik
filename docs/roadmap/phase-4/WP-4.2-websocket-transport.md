# WP-4.2 — `WebSocketTransport`

**Phase:** 4 · **Lane:** net · **Size:** L · **Status:** unclaimed · **Depends on:** WP-4.3 (harness), WP-4.1 (protocol)

## Goal
The `Transport` seam, implemented over a real socket. Gameplay code does not change a line.

## Owns
- `src/net/websocket_transport.gd`
- `tests/net/test_websocket_transport.gd`

## Must not touch
- `src/core/**` · `src/game/**` · `src/autoload/game_session.gd` beyond the one line that chooses a transport (quote it in your report; the integrator adds it)

## Interfaces
**Consumes:** `Transport`, `Commands`, `WorldState.to_dict()` / `from_dict()`, the protocol in `docs/NETWORKING.md`.

**Provides:** `WebSocketTransport.new(url, room_code, as_host: bool)`.

## The contract it has to keep
`Transport`'s docstring already states it: *every command is applied at most once, in the same order on every peer, against the same `WorldState`*. On the host that is easy. On a client it means:

- A client **never applies its own command locally first.** It sends, and applies what the host broadcasts back. Snappier local prediction is a phase-5 conversation and a rollback problem; this game is about walking to a bin, not twitch aim.
- **A late joiner gets `WorldState.to_dict()` and nothing else.** That is the same snapshot `SaveGame` already writes, which is why ADR 0010 put progression inside the state — so a joiner arrives with the party's points and abilities and not just item positions.
- The clock keeps advancing on the host only; `Commands.tick` is broadcast like anything else.

## Acceptance criteria
- [ ] Against a loopback WebSocket server in the test itself (no Cloudflare, no network): host and two clients converge on identical `to_dict()` after a mixed command run.
- [ ] A joiner arriving mid-run receives the snapshot and matches the host exactly, including progression and found collectibles.
- [ ] A rejected command reaches the submitting client as `command_rejected` and mutates nothing anywhere.
- [ ] Messages are applied in send order even when they arrive together.
- [ ] The socket dying is reported, not swallowed; nothing in gameplay crashes.
- [ ] The same suites that pass with `SimTransport` pass with this one — the harness is the oracle.
- [ ] `tools/run_tests.sh` green; boot check green.

## Notes / decisions
