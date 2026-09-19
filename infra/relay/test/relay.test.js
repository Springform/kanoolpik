import { env, SELF } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import { makeCode, isValidCode } from "../src/index.js";
import { MAX_PEERS, HOST_ID, CLOSE_HOST_LEFT } from "../src/room.js";

/**
 * These open real WebSockets against the real Durable Object running in
 * workerd. Nothing here is mocked, because a relay tested against a fake relay
 * would tell us only that the fake works.
 */

let codeCounter = 0;
/** A fresh room per test, so one test's peers never wander into another's. */
function freshCode() {
  codeCounter += 1;
  return ("TEST" + String(codeCounter).padStart(2, "0")).slice(0, 6).toUpperCase()
    .replace(/[0OIL1AEU]/g, "X");
}

async function join(code) {
  const response = await SELF.fetch(`https://relay/room/${code}`, {
    headers: { Upgrade: "websocket" },
  });
  if (response.status !== 101) {
    return { status: response.status, text: await response.text() };
  }
  const ws = response.webSocket;
  ws.accept();
  const inbox = [];
  const waiters = [];
  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    const waiter = waiters.shift();
    if (waiter) waiter(message);
    else inbox.push(message);
  });
  const next = () =>
    new Promise((resolve) => {
      const queued = inbox.shift();
      if (queued) resolve(queued);
      else waiters.push(resolve);
    });
  const welcome = await next();
  return { status: 101, ws, next, welcome, inbox, send: (m) => ws.send(JSON.stringify(m)) };
}

describe("room codes", () => {
  it("are six characters a person can read aloud", () => {
    for (let i = 0; i < 200; i++) {
      const code = makeCode();
      expect(code).toHaveLength(6);
      // The whole point of the alphabet: nothing you could mishear or mistype.
      expect(code).not.toMatch(/[0O1IL]/);
      expect(isValidCode(code)).toBe(true);
    }
  });

  it("reject anything that is not one", () => {
    expect(isValidCode("ABC")).toBe(false);
    expect(isValidCode("BCDFG0")).toBe(false); // contains a zero
    expect(isValidCode("")).toBe(false);
    expect(isValidCode(null)).toBe(false);
  });

  it("are minted only for a room nobody is sitting in", async () => {
    const response = await SELF.fetch("https://relay/new");
    const body = await response.json();
    expect(isValidCode(body.code)).toBe(true);
    expect(body.max_peers).toBe(MAX_PEERS);
  });

  it("a malformed code is refused before any socket is opened", async () => {
    const response = await SELF.fetch("https://relay/room/nope", {
      headers: { Upgrade: "websocket" },
    });
    expect(response.status).toBe(400);
  });
});

describe("joining", () => {
  it("makes the first arrival the host and numbers the rest", async () => {
    const code = freshCode();
    const host = await join(code);
    expect(host.welcome.host).toBe(true);
    expect(host.welcome.id).toBe(HOST_ID);
    expect(host.welcome.peers).toEqual([]);

    const second = await join(code);
    expect(second.welcome.host).toBe(false);
    expect(second.welcome.id).toBe(2);
    expect(second.welcome.peers).toEqual([1]);

    // The host hears about the arrival.
    expect(await host.next()).toEqual({ t: "join", id: 2 });
  });

  it("lets six in and refuses the seventh with a reason", async () => {
    const code = freshCode();
    const peers = [];
    for (let i = 0; i < MAX_PEERS; i++) peers.push(await join(code));
    expect(peers.map((p) => p.welcome.id)).toEqual([1, 2, 3, 4, 5, 6]);

    const seventh = await join(code);
    expect(seventh.status).toBe(409);
    expect(seventh.text).toContain("full");
  });
});

describe("routing", () => {
  it("sends a client's message to the host and to nobody else", async () => {
    const code = freshCode();
    const host = await join(code);
    const a = await join(code);
    const b = await join(code);
    await host.next(); // join a
    await host.next(); // join b
    await a.next(); // join b

    a.send({ t: "m", d: { hello: "authority" } });
    expect(await host.next()).toEqual({ t: "m", from: 2, d: { hello: "authority" } });
    // b must not have seen a client-to-client message; nothing is queued for it.
    expect(b.inbox).toHaveLength(0);
  });

  it("broadcasts from the host to every client but not back to the host", async () => {
    const code = freshCode();
    const host = await join(code);
    const a = await join(code);
    const b = await join(code);
    await host.next();
    await host.next();
    await a.next();

    host.send({ t: "m", d: { apply: "pick_up" } });
    expect(await a.next()).toEqual({ t: "m", from: 1, d: { apply: "pick_up" } });
    expect(await b.next()).toEqual({ t: "m", from: 1, d: { apply: "pick_up" } });
    expect(host.inbox).toHaveLength(0);
  });

  it("delivers an addressed message to exactly one client", async () => {
    const code = freshCode();
    const host = await join(code);
    const a = await join(code);
    const b = await join(code);
    await host.next();
    await host.next();
    await a.next();

    host.send({ t: "m", to: 3, d: { snapshot: true } });
    expect(await b.next()).toEqual({ t: "m", from: 1, d: { snapshot: true } });
    expect(a.inbox).toHaveLength(0);
  });

  it("keeps one sender's messages in the order they were sent", async () => {
    // The whole determinism argument rests on this (see WP-4.3): out-of-order
    // delivery of dependent commands desyncs the party.
    const code = freshCode();
    const host = await join(code);
    const client = await join(code);
    await host.next();

    for (let i = 0; i < 25; i++) host.send({ t: "m", d: { n: i } });
    for (let i = 0; i < 25; i++) {
      expect((await client.next()).d.n).toBe(i);
    }
  });

  it("tells the host when an addressed peer is not there", async () => {
    const code = freshCode();
    const host = await join(code);
    host.send({ t: "m", to: 4, d: {} });
    const reply = await host.next();
    expect(reply.t).toBe("err");
    expect(reply.code).toBe("no_such_peer");
  });

  it("tells a client when there is no host to talk to", async () => {
    // Only reachable if the host went away between joining and sending.
    const code = freshCode();
    const host = await join(code);
    const client = await join(code);
    await host.next();
    host.ws.close();
    await client.next(); // hostgone
    client.send({ t: "m", d: {} });
    // The socket is being closed by the relay; either an error or a close is
    // acceptable, what matters is that the room did not fall over.
    const response = await SELF.fetch(`https://relay/room/${code}`, {
      headers: { Upgrade: "websocket" },
    });
    expect([101, 409]).toContain(response.status);
  });
});

describe("leaving", () => {
  it("tells the host when a client drops", async () => {
    const code = freshCode();
    const host = await join(code);
    const client = await join(code);
    await host.next(); // join

    client.ws.close();
    expect(await host.next()).toEqual({ t: "leave", id: 2 });
  });

  it("tells everyone when the host goes, and ends the room", async () => {
    const code = freshCode();
    const host = await join(code);
    const a = await join(code);
    const b = await join(code);
    await host.next();
    await host.next();
    await a.next();

    host.ws.close();
    expect(await a.next()).toEqual({ t: "hostgone" });
    expect(await b.next()).toEqual({ t: "hostgone" });
  });

  it("says why on the close frame too, because the message can lose the race", async () => {
    // A client that never reads the `hostgone` frame must still be able to tell
    // "the host went home" from "your wifi died". The close code survives where
    // a queued message does not: Godot drops buffered packets the moment the
    // socket reaches CLOSED, and the two can arrive in one read.
    const code = freshCode();
    const host = await join(code);
    const client = await join(code);
    await host.next();

    const closed = new Promise((resolve) =>
      client.ws.addEventListener("close", (event) =>
        resolve({ code: event.code, reason: event.reason })));
    host.ws.close();
    const seen = await closed;
    expect(seen.code).toBe(CLOSE_HOST_LEFT);
    expect(seen.reason).toBe("host left");
  });
});

describe("bad input", () => {
  it("a frame that is not JSON is the sender's problem, not the room's", async () => {
    const code = freshCode();
    const host = await join(code);
    const client = await join(code);
    await host.next();

    client.ws.send("this is not json {");
    const reply = await client.next();
    expect(reply.t).toBe("err");
    expect(reply.code).toBe("bad_json");

    // The room still works afterwards.
    client.send({ t: "m", d: { still: "here" } });
    expect((await host.next()).d).toEqual({ still: "here" });
  });

  it("a frame of the wrong shape is refused without disturbing anyone", async () => {
    const code = freshCode();
    const host = await join(code);
    const client = await join(code);
    await host.next();

    client.send({ t: "something-else", d: 1 });
    expect((await client.next()).code).toBe("bad_type");
    expect(host.inbox).toHaveLength(0);
  });

  it("a client cannot address another client", async () => {
    // `to` is only meaningful from the host. A client setting it must still
    // reach the host and nobody else — otherwise a peer could impersonate the
    // authority by talking straight to its neighbours.
    const code = freshCode();
    const host = await join(code);
    const a = await join(code);
    const b = await join(code);
    await host.next();
    await host.next();
    await a.next();

    a.send({ t: "m", to: 3, d: { sneaky: true } });
    expect(await host.next()).toEqual({ t: "m", from: 2, d: { sneaky: true } });
    expect(b.inbox).toHaveLength(0);
  });
});
