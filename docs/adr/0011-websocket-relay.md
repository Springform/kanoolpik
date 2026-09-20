# ADR 0011 — Multiplayer over a WebSocket relay, not WebRTC

**Status:** Accepted · 2026-09-14 · **Supersedes the transport clause of [ADR 0002](0002-static-hosting-webrtc.md)**

ADR 0002 still stands for everything else: the game ships as static files on GitHub Pages, one player's browser is the authority, and the core stays deterministic and serialisable so any peer can be resynced from a snapshot. Only *how the bytes move* changes.

## Context
ADR 0002 chose host-authoritative peer-to-peer over WebRTC, in phase 0, before there was a game. Three things have been learned since, and the constraint from KA is unchanged: **free, and still served from GitHub Pages.**

**1. WebRTC cannot be exercised where this project does its testing.** Stock Godot 4.7.1 reports `No default WebRTC extension configured` and refuses to create a peer connection: on desktop it needs the `webrtc-native` GDExtension as an extra binary dependency, and only the web export has it built in. So the transport could never run in CI, and never in two windows on KA's machine — it would only ever be exercised by six people in browsers, at the moment it matters most. This project has spent a whole session learning that a test which cannot fail is worthless and that code the game never runs is where bugs hide; adopting a transport nothing can test is the same mistake with a network stack attached.

**2. The signalling server does not disappear.** A browser cannot accept an incoming connection, so WebRTC still needs a live service holding both peers' connections while they exchange SDP and ICE. The infrastructure is the same shape either way; only the traffic through it differs.

**3. NAT traversal is a real failure mode with a price tag.** Some of the canoe crew will sit behind networks that need TURN. Cloudflare's TURN is $0.05 per GB outbound — pennies for this game's traffic, but it needs billing enabled, and without it those friends simply cannot join. "It works for four of you" is a worse outcome than a few milliseconds of latency.

## Decision
**One Cloudflare Worker with a Durable Object per room relays every message.** Clients connect to it over a WebSocket; the host's browser still owns the authoritative `WorldState` and the relay forwards bytes without understanding them.

- `WebSocketTransport` implements the existing [`Transport`](../../src/net/transport.gd) seam — the same one `LocalTransport` implements today. Gameplay code does not learn that a network exists.
- The relay has no game logic and no state beyond "who is in this room". It is not an authority; it is a pipe.
- Rooms are addressed by a short code. The Worker keeps one Durable Object per room, which is what lets six sockets talk to each other at all.

## Does it stay free?
Measured against Cloudflare's published free plan: 100,000 requests/day, 13,000 GB-s/day, and **incoming WebSocket messages billed at 20:1** (outgoing free).

| | |
|---|---|
| Six players, transforms at 20 Hz | 120 incoming messages/s → 432,000/hour → **21,600 billable requests/hour** |
| Free daily allowance | 100,000 requests → **~4.6 hours of six-player play per day** |
| At 10 Hz, or sending only while moving | **~9 hours/day** |
| Compute duration | 13,000 GB-s ÷ 0.125 GB ≈ 29 hours/day of an active room — not the binding limit |

Commands are negligible next to transforms: a busy player issues a few per second, not twenty. **The transform rate is the only thing that decides whether this stays free**, which is why WP-4.5 owns it as a named constant and why "only send when it changed" is in its acceptance criteria rather than left as an optimisation.

### The sum above assumes the host merges (added by WP-4.5)

"Six players → six incoming messages a tick" is only true if the host sends **one** frame carrying the whole room. A client may not reach another client — that restriction is what stops a peer impersonating the authority — so a transform has to come back down through the host, and forwarding each one separately makes it eleven incoming messages a tick rather than six. That is nearly double the bill for the same picture.

So `WebSocketTransport.send_presence` collects what arrived since the last tick and fans it out as one frame. The numbers in the table hold; they would not have. WP-4.5 also settled the rate at **10 Hz**, because `RemoteAvatar` interpolates between frames and the second ten cost half the daily budget to hide a gap nobody can see.

## Alternatives considered
**WebRTC as originally decided.** Cheaper in requests and lower latency once connected. Rejected for the testing story above, and because the NAT failure mode costs either money or a friend.

**Both, behind the seam.** The `Transport` abstraction genuinely allows it, and if latency ever becomes the complaint, a `WebRtcTransport` can be added later without touching gameplay — that is the point of the seam. Not now: two transports is twice the surface for a problem nobody has yet.

**No server at all**, with players pasting connection blobs to each other. Free and infrastructure-less. Unusable for six people who are being invited to click a link.

## Consequences
- **The real transport runs in CI.** WP-4.3's harness exercises N peers in one process, and a loopback WebSocket test can run the actual socket code headless. This is the main thing bought.
- **Everyone connects.** No STUN, no TURN, no NAT class that silently excludes a friend.
- **Latency is one extra hop** through Cloudflare's edge rather than direct peer-to-peer. For a game about picking up bottles, this is not the axis that matters.
- **Free has a shape now, and it is the transform rate.** If the room list ever shows sessions dying at the same time of day, this is the number to look at first.
- **The relay must stay up.** A dead Worker means no multiplayer, where a dead signalling server would only have meant no *new* connections. Single player is untouched either way — `LocalTransport` never talks to anything.
- ADR 0002's consequence "host leaving ends the session in v1" still holds, and host migration stays a stretch goal.
