# WP-4.2 — `WebSocketTransport`

**Phase:** 4 · **Lane:** net · **Size:** L · **Status:** done (2026-09-15) · **Depends on:** WP-4.3 (harness), WP-4.1 (protocol)

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
- [x] Against a loopback WebSocket server in the test itself (no Cloudflare, no network): host and two clients converge on identical `to_dict()` after a mixed command run.
- [x] A joiner arriving mid-run receives the snapshot and matches the host exactly, including progression and found collectibles.
- [x] A rejected command reaches the submitting client as `command_rejected` and mutates nothing anywhere.
- [x] Messages are applied in send order even when they arrive together.
- [x] The socket dying is reported, not swallowed; nothing in gameplay crashes.
- [x] The same suites that pass with `SimTransport` pass with this one — the harness is the oracle.
- [x] `tools/run_tests.sh` green; boot check green.

## Notes / decisions

**Done 2026-09-15.** 28 new tests (13 codec, 15 transport), full suite 537, 0 failures, 0 orphans.

### Three files, not one
`WebSocketTransport` alone would have been a class that both parses hostile
bytes and decides game outcomes, and those deserve separate blame.

- **`src/net/command_codec.gd`** — the trust boundary. The relay never inspects
  a payload, so this is the first code to see bytes a stranger chose. Decoding
  is a **whitelist**: the command is built from `SCHEMA` outward, so a frame
  carrying extra keys cannot produce a command carrying extra keys. There is no
  "unknown field" to reject because no path exists by which one could arrive.
  Refuses NaN/inf (`1e999` parses to `inf` in Godot), fractional ints (a `slot`
  of 2.5 silently becoming 2 would place an item nobody asked for), coordinates
  past ±10 000, and ids over 64 characters.
- **`tests/net/fake_relay.gd`** — the protocol, in-process, deliberately stupid.
  Under `tests/` so the export preset cannot ship it.
- **`src/net/websocket_transport.gd`** — the seam itself.

### The escape hatch that makes the fake trustworthy
A test double of a thing that exists is the dangerous kind. `KANOOLPIK_RELAY_URL`
points the *same* suite at a real relay:

```
cd infra/relay && npx wrangler dev &
KANOOLPIK_RELAY_URL=ws://localhost:8787 tools/run_tests.sh res://tests/net/
```

Nothing else can catch `FakeRelay` drifting from the Worker. Run it whenever
either side of the protocol changes.

### Three rules, each with a test that fails without it
1. **A client never applies its own command first.** It sends and waits.
2. **The host stamps the sender's peer id over `player_id`.** A frame is
   whatever the other end chose to type; the codec decodes a lie perfectly and
   refuses to judge it, on purpose. This is the only place the stamp happens.
3. **Every broadcast carries the host's state hash**, checked after applying.

### Found by mutation, after fourteen green tests
Removing the host's own encode/decode round trip changed nothing — the guard was
unfalsifiable. It turned out to protect a real case nobody had named: **the host
is subject to the same wire rules as everyone else.** A command the host can
apply but cannot transmit is a silent divergence, and the host's own frames are
the one path where no hash is ever compared, because the host has nothing to
compare itself against. `test_the_host_refuses_its_own_command_when_it_could_not_be_transmitted`
now pins it, and the mutation dies.

### The one line outside this work package
`src/autoload/game_session.gd` ticked only the authority's transport. Draining a
client's socket happens in `tick()`, so a `WebSocketTransport` client connected
and then never heard another word. Now every transport is ticked and each
decides what that means; `LocalTransport` is always authority and `SimTransport`
already checked for itself, so neither notices.

### Left for later, deliberately
No reconnection or resync-after-divergence — `diverged` is a signal and WP-4.6
owns what to do about it. No lobby: the relay URL and room code are constructor
arguments until WP-4.4 exists. No transform traffic; WP-4.5 owns that, and with
it the only number that decides whether this stays free.
