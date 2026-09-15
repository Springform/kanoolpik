# WP-4.1 — The relay: Cloudflare Worker, room codes, protocol doc

**Phase:** 4 · **Lane:** infra · **Size:** M · **Status:** unclaimed · **Depends on:** —
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
- [ ] Six sockets can join one room and exchange messages; a seventh is refused with a clear reason.
- [ ] Room codes are short, unambiguous to read aloud (no `0`/`O`, no `1`/`l`), and random enough not to collide in practice.
- [ ] Host leaves → every client is told, and the room is torn down.
- [ ] A client that drops is announced to the host within seconds.
- [ ] An empty room's Durable Object goes away rather than idling forever — the free tier's GB-s is spent on rooms nobody is in otherwise.
- [ ] `docs/NETWORKING.md` states every message type, its direction, its fields, and what happens on a malformed one.
- [ ] Deployable with `wrangler deploy` on a free account, and the README says exactly how, including how to point the client at it.

## Notes / decisions
