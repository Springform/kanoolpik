# WP-4.1 — The relay: Cloudflare Worker, room codes, protocol doc

**Phase:** 4 · **Lane:** infra · **Size:** M · **Status:** done (2026-09-15) · **Depends on:** —
> Implements [ADR 0011](../../adr/0011-websocket-relay.md). Can run in parallel with WP-4.3.

## Goal
A room code gets six browsers talking. One Worker, one Durable Object per room, no game logic anywhere in it.

## Owns
- `infra/relay/` — the Worker source, `wrangler.toml`, and a README saying how to deploy it
- `docs/NETWORKING.md` — the protocol, written down once so the client and the relay cannot drift

## Must not touch
- Anything under `src/` — the Godot client is WP-4.2's

## What the relay does, and nothing more
- `GET /room/<code>` upgrades to a WebSocket and joins that room's Durable Object.
- The **first** socket in a room is the host. Everyone else is a client.
- Every message from a client goes to the host. Every message from the host goes to all clients (or to one, addressed).
- It assigns peer ids, tells the host when someone joins or leaves, and tells clients when the host is gone.
- **It never parses a game message.** Payloads are opaque. This is what keeps it free of the game's versioning.

## Acceptance criteria
- [x] Six sockets can join one room and exchange messages; a seventh is refused with a clear reason.
- [x] Room codes are short, unambiguous to read aloud (no `0`/`O`, no `1`/`l`), and random enough not to collide in practice.
- [x] Host leaves → every client is told, and the room is torn down.
- [x] A client that drops is announced to the host within seconds.
- [x] An empty room's Durable Object goes away rather than idling forever — the free tier's GB-s is spent on rooms nobody is in otherwise.
- [x] `docs/NETWORKING.md` states every message type, its direction, its fields, and what happens on a malformed one.
- [x] Deployable with `wrangler deploy` on a free account, and the README says exactly how, including how to point the client at it.

## Notes / decisions

**Done 2026-09-15.** 17 tests, green, opening real WebSockets against the real
Durable Object in `workerd` — nothing mocked.

- **`setWebSocketAutoResponse` for the keepalive.** The acceptance criterion
  said an empty room must not idle expensively. Durable Objects with hibernating
  sockets are already evicted from memory between messages, so the real risk was
  the *keepalive*: a ping handled in `webSocketMessage` wakes the object every
  time and would have been the single largest line in the bill. Answering it
  inside the hibernation API means an idle room of six people costs **zero**
  requests and zero GB-s.
- **Per-socket state lives in `serializeAttachment`, not in a field.** A field is
  gone when the object wakes. This is the one thing about hibernation that will
  bite whoever edits `room.js` next.
- **`Room extends DurableObject`** so `GET /new` can call `isEmpty()` on it as a
  plain RPC method; a bare class only answers `fetch()`.
- **Mutation-tested**, per the house rule. Three mutations introduced and killed:
  "a client may address another client" (3 tests red), "no limit on room size"
  (1 red), "the host leaves in silence" (2 red). All restored; suite green.
- **`infra/.gdignore`** added — without it Godot scans 431 MB of `node_modules`
  on every import. Import is back to 14.6 s.

**Left for WP-4.2, deliberately:** everything about *what* travels in `d`. The
relay never parses it, so the game's message versioning is entirely the client's
business. `docs/NETWORKING.md` is written so WP-4.2 can be implemented from that
document alone, without reading the Worker.
