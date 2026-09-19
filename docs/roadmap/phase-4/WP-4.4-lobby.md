# WP-4.4 — Lobby: create, join, ready up

**Phase:** 4 · **Lane:** flow/hud · **Size:** M · **Status:** done (session 5) · **Depends on:** WP-4.2

## Goal
From the title screen: "Start oprydningen" (alone), "Lav et hold" which shows a room code to read aloud, or a code field and "Join". A player list fills as friends arrive. The host presses "Afgang" and everybody lands on the same island.

**There is no ready-up.** It was in this sentence and in none of the acceptance criteria, and every mechanism for it needs a lobby message the transport does not carry (see Decisions). The host looking at the roster and pressing the button is the same decision with nothing to build.

## Owns
- `src/game/lobby/`
- `src/game/title/title_screen.gd` + scene — the two new buttons
- `assets/i18n/` lobby rows (**ask for these to be pre-placed before the wave starts**)
- `tests/integration/test_lobby.gd`

## Must not touch
- `src/core/**`, `src/net/**` — the transport is done; use it

## The thing that must not go wrong
**Everyone must generate the same mess.** `MessGenerator` is seeded, and **the seed is the room code**: `RoomCode.seed_for()` turns the six characters into it, so every peer derives the island from something it already has and nothing about the level travels. `test_two_peers_given_the_same_code_build_identical_worlds` proves two peers from one code have identical `to_dict()` before a single command is issued, and `test_the_seed_a_code_names_never_moves` pins two codes to two numbers so the hash cannot be changed by accident.

## Acceptance criteria
- [x] Room code is displayed large enough to read to someone across a table, and copyable. 64 px, grouped "BCD-FGH", `DisplayServer.clipboard_set`.
- [x] Joining with a bad code fails with a reason, not a hang. Three ways it can be wrong and three sentences: not a code at all (refused before a socket is opened), no round with that code, and the relay unreachable.
- [x] The player list updates as people join and leave — **on the host.** See Decisions.
- [x] The host's seed reaches every client; all peers' initial states are identical. It reaches them without being sent.
- [x] Single player still starts with no network anywhere near it. `test_single_player_goes_nowhere_near_a_socket`.
- [x] A player who closes the tab in the lobby disappears from the others' list.

## Decisions

**The seed is the room code.** The lobby has to agree on an island before a
`WorldState` exists, and `WebSocketTransport` carries commands and nothing else.
The three options were a new envelope kind in the transport (against this WP's
"must not touch `src/net`"), shipping the host's whole world as a snapshot
(against `docs/NETWORKING.md` point 6), or deriving the seed from something
everyone already has. The third costs nothing on the wire, and it buys a
property worth having on its own: **the same code is always the same island**, so
a crew that liked a particular mess can ask for that room again. The price is
that a host cannot type a custom seed in multiplayer — a new room is how you roll
a new island. KA's call, session 5.

**The hash is written out rather than borrowed from `String.hash()`**, because
the engine's is an implementation detail that may change between Godot versions,
and this one decides which island six people are standing on. A 4.7 player and a
4.8 player in different worlds would produce no error anywhere.

**A client's roster is incomplete, and says so instead of guessing.** The relay's
`welcome` frame carries the ids already in the room; `WebSocketTransport` reads
it and does not pass it on. So a client arriving fourth does not learn about
peers two and three. The host's screen is the one being read aloud from, so that
is where the roster is drawn; a client's says "venter på at værten går i gang".
Completing it is **one accessor in the transport** and belongs to WP-4.6 with the
rest of join/leave.

**Nobody can pick anything up yet in a multiplayer game.** Peers are in the room
and on the same island, but nothing puts them into the replicated `WorldState` as
players, so `capacity()` is 0 for everyone but the host. Doing it locally on each
client would diverge the state hash immediately; doing it properly is an
`add_player` command from the host, which is `src/core` and is **WP-4.6**. This
WP gets six people into one room on one island and stops there, deliberately.

**A client that lands in an empty room is told the code was wrong.** The relay
makes the first socket in a room the host, so a typo in a well-formed code opens
a room nobody will ever join — the one failure that looks exactly like success.
`LobbyController` catches it by noticing the relay made it host when it asked not
to be. It costs one expected `ERROR: asked to be host=false…` line in the test
log, from `WebSocketTransport._welcome`; turning that push_error into something
the lobby reports is a line for WP-4.6.

**The panels size themselves now.** Both the title and the lobby panel had their
height typed into the `.tscn`. Adding two buttons pushed three controls past the
background, onto the island, with every string assertion still green — the
screenshot pass caught it. `PRESET_MODE_MINSIZE` replaced the number.

## Notes
