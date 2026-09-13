# ADR 0002 — Static hosting; multiplayer via WebRTC with a player as host

**Status:** Accepted · 2026-09-13

## Context
The owner does not want to operate a server. The game must be shareable as a URL. Multiplayer (≤ 6) is essential eventually.

## Decision
- Host the web build on GitHub Pages (CI deploys `main`).
- Multiplayer is **host-authoritative peer-to-peer over WebRTC**: one player's browser runs the authoritative `WorldState`; others send commands and receive events.
- Connection brokering uses a minimal signalling endpoint (Cloudflare Worker free tier, or a hosted free alternative) that only relays SDP/ICE — no game logic, no state.

## Alternatives considered
- Authoritative Node/WebSocket server: more robust (reconnect, host migration trivial) but somebody has to run it.
- Godot ENet: does not work in browsers.
- Full lockstep P2P: unnecessary complexity for a co-op tidy-up game.

## Consequences
- The core must be deterministic and serialisable (ADR 0003) so any peer can become host or be resynced from a snapshot.
- Host leaving ends the session in v1; host migration is a stretch goal (snapshot makes it feasible).
- NAT traversal: WebRTC needs STUN (free public servers) and occasionally TURN (not free). Accept that a small fraction of network setups won't connect in v1.
- A tiny piece of infrastructure (signalling) still exists, but it is stateless, free-tier, and replaceable.
