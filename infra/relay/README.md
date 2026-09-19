# Kanoølpik relay

The one live piece of infrastructure (ADR 0011). One Cloudflare Worker, one
Durable Object per room. It moves opaque payloads between at most six sockets
and understands nothing about the game.

The protocol is in [`docs/NETWORKING.md`](../../docs/NETWORKING.md).

## Running the tests

```
cd infra/relay
npm install
npm test
```

These open real WebSockets against the real Durable Object inside `workerd`
(`@cloudflare/vitest-pool-workers`). Nothing is mocked — a relay tested against
a fake relay would only tell us the fake works.

## Locally

```
npx wrangler dev
# → http://localhost:8787
#   GET /new             mint a room code
#   GET /room/<code>     websocket upgrade
```

## Deploying, on a free account

```
npx wrangler login
npx wrangler deploy
```

Durable Objects are on the Workers Free plan, and `wrangler.toml` declares the
class as `new_sqlite_classes` because the SQLite-backed ones are the free ones.
Deploying prints a `https://kanoolpik-relay.<subdomain>.workers.dev` host.

**Point the client at it** by setting the relay host in the game's lobby
configuration (WP-4.4). Until then, `wrangler dev` and `localhost:8787` are
enough to develop against.

## Keeping it free

The billing shape is in `docs/NETWORKING.md`. Two rules keep it there:

1. **Do not add anything periodic to this Worker.** No acks, no server-side
   heartbeat. The keepalive is a hibernation auto-response, which answers a ping
   without waking the object, so an idle room costs nothing at all.
2. **The transform rate in the game decides the bill** — see WP-4.5. Six players
   at 20 Hz is about 4.6 hours of play a day on the free allowance; only sending
   a transform when it changed roughly doubles that.

## What it deliberately does not do

- Parse a game payload. If you are reading a field inside `d`, stop: the relay
  would then need redeploying whenever the game's messages change.
- Keep state beyond who is in the room. No authority, no game logic, no storage.
- Let clients talk to each other. Only the host is reachable from a client,
  which is what stops a peer from impersonating the authority.
