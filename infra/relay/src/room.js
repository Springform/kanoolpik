/**
 * One room, as a Durable Object. Six sockets, one of them the host, and a pipe
 * between them.
 *
 * What this deliberately does NOT do: understand the game. Payloads travel in
 * `d` and are never parsed, so the relay never needs redeploying when the
 * game's messages change. If you find yourself reading a field inside `d`, stop.
 *
 * Hibernation matters here. `ctx.acceptWebSocket()` lets the object be evicted
 * from memory between messages while the sockets stay open, which is the
 * difference between a room costing GB-s while six friends stand around
 * arguing and costing nothing. Because the object can be evicted, per-socket
 * state lives in `serializeAttachment` rather than in a field — a field would
 * be gone when it wakes.
 */

import { DurableObject } from "cloudflare:workers";

export const MAX_PEERS = 6;
export const HOST_ID = 1;

// Extends DurableObject so the Worker can call `isEmpty()` on it directly as
// an RPC method — a plain class only answers fetch().
export class Room extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    // A socket sitting idle behind a proxy gets closed unless something keeps
    // it warm. Answering the ping here, inside the hibernation API, means the
    // object is NOT woken to do it: an idle room of six friends arguing about
    // where the paddles go costs zero requests and zero GB-s. Doing this in
    // `webSocketMessage` instead would have made idling the single largest
    // line in the bill.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("expected a websocket upgrade", { status: 426 });
    }

    const sockets = this.ctx.getWebSockets();
    if (sockets.length >= MAX_PEERS) {
      // Refuse with a reason rather than a silent close: the client shows this.
      return new Response("room is full", { status: 409 });
    }

    const peerId = this.#nextFreeId(sockets);
    const isHost = peerId === HOST_ID;

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ peerId, isHost });

    const existing = sockets.map((s) => s.deserializeAttachment().peerId).sort((a, b) => a - b);
    this.#send(server, { t: "welcome", id: peerId, host: isHost, peers: existing });
    for (const other of sockets) {
      this.#send(other, { t: "join", id: peerId });
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  /**
   * A frame from a peer. Clients may only reach the host; the host may reach
   * one client or all of them. Nothing else is routable, which is what stops a
   * client from impersonating the authority.
   */
  async webSocketMessage(ws, raw) {
    const me = ws.deserializeAttachment();
    let message;
    try {
      message = JSON.parse(raw);
    } catch {
      // A bad frame is the sender's problem, not the room's.
      this.#send(ws, { t: "err", code: "bad_json", msg: "frame was not JSON" });
      return;
    }
    if (!message || message.t !== "m") {
      this.#send(ws, { t: "err", code: "bad_type", msg: "expected {t:'m'}" });
      return;
    }

    if (!me.isHost) {
      const host = this.#socketFor(HOST_ID);
      if (!host) {
        this.#send(ws, { t: "err", code: "no_host", msg: "the host has gone" });
        return;
      }
      this.#send(host, { t: "m", from: me.peerId, d: message.d });
      return;
    }

    // From the host: `to` 0 (or missing) means everyone, otherwise one peer.
    const to = message.to ?? 0;
    if (to === 0) {
      for (const socket of this.ctx.getWebSockets()) {
        const them = socket.deserializeAttachment();
        if (them.peerId !== HOST_ID) this.#send(socket, { t: "m", from: HOST_ID, d: message.d });
      }
      return;
    }
    const target = this.#socketFor(to);
    if (!target) {
      this.#send(ws, { t: "err", code: "no_such_peer", msg: `peer ${to} is not here` });
      return;
    }
    this.#send(target, { t: "m", from: HOST_ID, d: message.d });
  }

  async webSocketClose(ws) {
    this.#announceDeparture(ws);
  }

  async webSocketError(ws) {
    this.#announceDeparture(ws);
  }

  /**
   * The host leaving ends the session (ADR 0002): everyone is told, and the
   * room empties rather than sitting there with five clients and no authority.
   * A client leaving is just news for the host.
   */
  #announceDeparture(ws) {
    let me;
    try {
      me = ws.deserializeAttachment();
    } catch {
      return; // never finished joining
    }
    const others = this.ctx.getWebSockets().filter((s) => s !== ws);
    if (me.isHost) {
      for (const socket of others) {
        this.#send(socket, { t: "hostgone" });
        try { socket.close(1000, "host left"); } catch { /* already gone */ }
      }
      return;
    }
    for (const socket of others) {
      this.#send(socket, { t: "leave", id: me.peerId });
    }
  }

  /** Lowest free id, so a rejoining sixth player does not become peer 9. */
  #nextFreeId(sockets) {
    const taken = new Set(sockets.map((s) => s.deserializeAttachment().peerId));
    for (let id = HOST_ID; id < HOST_ID + MAX_PEERS; id++) {
      if (!taken.has(id)) return id;
    }
    return HOST_ID + MAX_PEERS; // unreachable: fetch() refuses a full room first
  }

  #socketFor(peerId) {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket.deserializeAttachment().peerId === peerId) return socket;
    }
    return null;
  }

  #send(ws, payload) {
    try {
      ws.send(JSON.stringify(payload));
    } catch {
      // A socket that died between our check and this send is not an error
      // worth taking the room down for.
    }
  }

  /** Used by `GET /new` to find a code nobody is sitting in. */
  async isEmpty() {
    return this.ctx.getWebSockets().length === 0;
  }
}
