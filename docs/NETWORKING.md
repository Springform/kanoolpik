# Networking — the relay protocol

Everything the Godot client and the relay have to agree on. WP-4.2 is written
from this document alone, by someone who has not read the Worker.

See [ADR 0011](adr/0011-websocket-relay.md) for why it is a WebSocket relay and
not WebRTC, and `infra/relay/` for the implementation.

## Shape of the thing

The game is static files on GitHub Pages. The relay is one Cloudflare Worker
with one Durable Object per room. One player's browser is the **authority** and
owns the `WorldState`; the relay moves opaque payloads between sockets and
understands none of them.

```
  client ──┐                        ┌── client
  client ──┼── relay (room XYZ) ────┼── client
  client ──┘        │               └── client
                    └── host (the authority)
```

**Clients may only reach the host. The host may reach one client or all of
them.** There is no client-to-client path, which is what stops a peer from
impersonating the authority by talking straight to its neighbours.

## Endpoints

| | |
|---|---|
| `GET /new` | `{"code": "BCDFGH", "max_peers": 6}` — a code for a room nobody is sitting in |
| `GET /room/<code>` | WebSocket upgrade into that room |

`400` for a code that is not a code, `409` when the room already holds six.
Both come back before any socket is opened, so the client can show a reason.

**Room codes** are six characters from `BCDFGHJKMNPQRSTVWXYZ23456789`: no `0`/`O`,
no `1`/`I`/`L`, and no vowels, so nothing can be misheard across a table and no
room is accidentally a word. Codes are case-insensitive on the way in.

## Messages

JSON, one object per frame. `t` is the type. **`d` is opaque** — the relay never
looks inside it, which is why adding a game message never means redeploying the
relay.

### Relay → peer

| `t` | Fields | When |
|---|---|---|
| `welcome` | `id`, `host` (bool), `peers` (ids already here) | immediately on connect |
| `join` | `id` | somebody arrived |
| `leave` | `id` | a client went away |
| `hostgone` | — | the host went away; the relay then closes your socket |
| `m` | `from`, `d` | a payload, from the host or from a client |
| `err` | `code`, `msg` | your last frame was refused (see below) |

### Peer → relay

| From | Frame | Goes to |
|---|---|---|
| client | `{"t":"m","d":…}` | the host |
| host | `{"t":"m","d":…}` | every client |
| host | `{"t":"m","to":<id>,"d":…}` | that one client |

A client that sets `to` is ignored on that field and still reaches only the
host. `to: 0` or omitted, from the host, means everyone.

### Errors

| `code` | Meaning |
|---|---|
| `bad_json` | the frame was not JSON |
| `bad_type` | not a `{"t":"m"}` frame |
| `no_such_peer` | the host addressed somebody who is not here |
| `no_host` | a client sent something with no host in the room |

**A bad frame is the sender's problem, not the room's.** Nobody else is
disturbed and the room keeps working — there is a test for exactly that.

## Peer ids

The **first socket in a room is the host and is always peer 1.** Clients get the
lowest free id, 2 to 6, so somebody rejoining takes the seat that was freed
rather than becoming peer 9.

Peer ids are the relay's, and they are what the game uses as `player_id` in
commands. Single player uses 1, which is the same number the host gets — so a
single-player run and a host's run are indistinguishable to the core.

## What the client has to get right

1. **Order matters.** WP-4.3 proved it: a pick-up and the place that depends on
   it, applied the wrong way round, desync that peer permanently. A WebSocket is
   ordered per connection, so this is free — but do not add anything that could
   reorder, such as handling a snapshot on a second connection.
2. **A client never applies its own command locally first.** It sends, and
   applies what the host broadcasts back. Optimistic prediction is a rollback
   problem and this game is about walking to a bin.
3. **The host broadcasts the command it accepted, not the resulting events**
   (WP-4.3). Every peer then runs the same `CommandProcessor`. Sending events
   instead would mean a second implementation of the rules on the client, which
   is how desyncs are born.
4. **Stamp broadcasts with the authority's state hash** and check it after
   applying. A peer that lands on a different number has diverged and should ask
   for a snapshot rather than carry on. `SimNetwork` does this already.
5. **A late joiner gets `WorldState.to_dict()`** and nothing else — the same
   snapshot a save writes, which is why ADR 0010 put progression inside the
   state.
6. **Nobody ships item positions at level start.** Since WP-4.4 the seed does
   not even travel: `RoomCode.seed_for()` derives it from the six characters
   every peer already has, so a client that connects before the host has
   generated anything is already on the right island. The late-join snapshot in
   rule 5 remains the mechanism for somebody arriving mid-game.

## What it costs

Cloudflare's free plan: 100,000 requests/day, and **incoming** WebSocket
messages are billed **20:1** (outgoing are free).

| | |
|---|---|
| Idle room, six people standing still | **0 requests.** The keepalive ping is answered by the hibernation API without waking the object, and WP-4.5 must not send an unchanged transform. |
| Playing, transforms at 20 Hz | 5 client frames + 1 host broadcast per tick = 120 incoming/s → 7,200/min → **360 billable requests/min** |
| | ≈ 21,600/hour → **~4.6 hours of six-player play per day** |
| At 10 Hz, or only while moving | roughly double that |
| Compute duration | 13,000 GB-s/day ≈ 29 h of an awake room — not the binding limit |

**The transform rate is the only number that decides whether this stays free.**
Commands are negligible beside it: a busy player issues a few per second, not
twenty. The relay itself adds nothing periodic — no acks, no heartbeat it has to
wake up for.

## Deploying

See `infra/relay/README.md`. Short version: `npx wrangler deploy` on a free
account, then point the client at the resulting `https://…workers.dev` host.

**It is deployed.** Since 2026-09-19:

```
wss://kanoolpik-relay.kennet-hoejmark.workers.dev
```

Verified at the HTTP layer — `/new` returns a room code with
`Access-Control-Allow-Origin: *` (the game is served from a different origin, so
that header is not decoration), and `/room/aaaaaa` is refused with `400` because
`A` is not in the alphabet.

**The host is stated once**, in `src/game/lobby/relay_endpoint.gd`:

```gdscript
const HOST := "kanoolpik-relay.kennet-hoejmark.workers.dev"
```

WP-4.4 baked it into the build, `net-live.yml` greps that line rather than
carrying a copy, and the repository variable `KANOOLPIK_RELAY_URL` is gone.
`test_lobby.gd` runs the workflow's own pattern against the file, so reformatting
the constant fails CI instead of leaving the workflow probing an empty string.
The address above is a copy for humans and is not read by anything.

Moving the relay is therefore one edit and one rebuild.

## The only test that can catch the fake drifting

`tests/net/` runs against `FakeRelay` by default. The **environment** variable
`KANOOLPIK_RELAY_URL` points it at a real relay instead (`KANOOLPIK_RELAY_HTTP`
does the same for `GET /new`, and is derived from the first when only that is
set — so a test cannot redirect the socket and go on minting live room codes), and the suite then scales its patience ×12 and waits
on conditions rather than turn counts, so it survives real latency.

Nothing on a developer machine runs it that way — it needs Godot and real
network access at once. `.github/workflows/net-live.yml` is where it actually
happens: on changes to `src/net/`, `tests/net/` or `infra/relay/`, weekly, and
on demand. A red run there means the client and the live relay disagree, which
is a different claim from "the code is broken" — hence its own workflow rather
than a job in `ci.yml`.
