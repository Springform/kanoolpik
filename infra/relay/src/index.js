/**
 * Kanoølpik relay — the whole server side of multiplayer (ADR 0011).
 *
 *   GET /new            → { code } for a room nobody is in
 *   GET /room/<code>    → WebSocket upgrade into that room
 *
 * The game is served as static files from GitHub Pages; this is the one live
 * thing, and it is deliberately tiny. It moves opaque payloads between six
 * sockets and knows nothing about islands, items or who is winning.
 */

import { Room, MAX_PEERS } from "./room.js";

export { Room };

/**
 * Codes people read aloud across a table, so the alphabet has no 0/O, no 1/I/L,
 * and no vowels — which also means no room is ever accidentally a word.
 * 26 symbols, 6 characters: about 3×10^8 rooms.
 */
const ALPHABET = "BCDFGHJKMNPQRSTVWXYZ23456789";
const CODE_LENGTH = 6;
const NEW_CODE_ATTEMPTS = 5;

export function makeCode(random = crypto.getRandomValues.bind(crypto)) {
  const bytes = random(new Uint8Array(CODE_LENGTH));
  let code = "";
  for (const byte of bytes) code += ALPHABET[byte % ALPHABET.length];
  return code;
}

export function isValidCode(code) {
  if (typeof code !== "string" || code.length !== CODE_LENGTH) return false;
  return [...code].every((ch) => ALPHABET.includes(ch));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/new") {
      // Minting server-side and checking the room is empty is one extra request
      // per game, and it is what stops two groups of friends walking into each
      // other's island because they happened to roll the same code.
      for (let attempt = 0; attempt < NEW_CODE_ATTEMPTS; attempt++) {
        const code = makeCode();
        const room = env.ROOMS.get(env.ROOMS.idFromName(code));
        if (await room.isEmpty()) {
          return json({ code, max_peers: MAX_PEERS });
        }
      }
      return json({ error: "could not find a free room code" }, 503);
    }

    const match = url.pathname.match(/^\/room\/([^/]+)$/);
    if (match) {
      const code = match[1].toUpperCase();
      if (!isValidCode(code)) {
        return new Response("that is not a room code", { status: 400 });
      }
      const room = env.ROOMS.get(env.ROOMS.idFromName(code));
      return room.fetch(request);
    }

    return new Response("kanoolpik relay", { status: 404 });
  },
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "access-control-allow-origin": "*" },
  });
}
