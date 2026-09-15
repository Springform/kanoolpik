# WP-4.3 — Simulated multi-peer harness

**Phase:** 4 · **Lane:** net/test · **Size:** M · **Status:** **done** (2026-09-15) — 509 tests green

> **Build this first.** It is how every other phase-4 WP is tested, and it needs no network at all.

## Goal
Six players in one process, one of them the authority, all running the real `CommandProcessor` against their own `WorldState`, wired together by an in-memory transport that can be told to delay, drop, reorder and disconnect. A desync becomes a failing test instead of an argument in a chat thread.

## Owns
- `src/net/sim_transport.gd`
- `tests/net/` (new folder)

## Must not touch
- `src/core/**` — the core is already deterministic and does not learn about peers
- `src/game/**`, `src/autoload/**`

## Interfaces
**Consumes:** `Transport` (the existing seam), `CommandProcessor`, `WorldState`.

**Provides:** `SimTransport` — a `Transport` that, instead of a socket, hands commands to a shared in-process bus:
- `SimNetwork.new(peer_count)` builds one authority and N-1 clients, each with its own state and processor.
- `latency_ticks`, `drop_next(n)`, `reorder_window`, `disconnect(peer)`, `reconnect(peer)` — the knobs a test turns.
- `states_agree() -> bool` and `divergence() -> String` — the assertion every test ends with.

## The point
**Determinism is the whole bet of this architecture** (ADR 0003, ADR 0010). The core has been written for a year on the promise that the same command list produces the same state everywhere. Nothing has ever checked that across *peers* — only that two `WorldState`s in the same process agree. This is where that promise gets tested, before a single byte goes over a wire.

## Acceptance criteria
- [ ] Six peers, a few hundred mixed commands (pick up, place, take out, unlock, summon, collect, tick), authority applies and broadcasts, clients apply the broadcast: every `to_dict()` identical.
- [ ] The same run with 200 ms of simulated latency ends identical.
- [ ] The same run with reordered delivery ends identical, or fails loudly — if ordering matters, the transport contract must say so and enforce it.
- [ ] A client whose command is rejected by the authority does not mutate its own state.
- [ ] A peer disconnected mid-run and handed a snapshot on reconnect converges to the authority's state exactly.
- [ ] Two peers issuing conflicting commands in the same tick (both grab the same can) resolve the same way on every peer.
- [ ] `tools/run_tests.sh` green; boot check green.

## Notes / decisions

**The authority broadcasts the command, not the resulting events.** `Transport`'s docstring sketches it the other way round ("broadcasts the resulting events"), and this WP deliberately departs from it. Applying events on a client needs a second piece of code that knows the rules, and two implementations of one rule set is how desyncs are born. Broadcasting the command means every peer runs the same `CommandProcessor` over the same state; the authority only ever decides *whether* and *in what order*.

The risk that trade makes is a client whose state has already drifted drifting further in silence — so **the authority stamps each broadcast with its own state hash**, and a peer that lands on a different number says so immediately. WP-4.2 should keep that stamp.

### Three findings, in order of how much they matter

**1. Out-of-order delivery breaks the world — so the transport must be an ordered one.** A pick-up and the place that depends on it, delivered the wrong way round, leave that peer behind. `Transport`'s contract already demanded ordering; this is the proof the demand was real and not defensive. WebSocket is ordered per connection and gives it away free (ADR 0011). An unreliable WebRTC data channel would not, and would have needed a resequencing layer nobody had budgeted for — an argument for ADR 0011 arriving from a direction nobody was looking.

**2. Even unrelated commands are order-sensitive, because `WorldState._carry_counter` is global.** Six people picking up six *different* things in a different order produce different states: the counter stamps a `carry_seq` on each item as it is taken, so the numbers differ even though every item ends up in the right hands. Reproduced in isolation — two players, two items, two orders, `carry_seq` 1 vs 2. Nothing a player can see, and harmless while the transport is ordered, but it means **no two commands commute**, so "apply independent commands as they arrive" is off the table. Making the counter per-player would fix it; that is a core change on a replicated field and is KA's call. Pinned by `test_even_unrelated_pick_ups_are_order_sensitive`, which will fail the day somebody changes it.

**3. The first version of the reordering test could not fail.** It flushed after every command, so there was never more than one message in flight per peer and the shuffle had nothing to shuffle — and the shuffle itself worked on the whole due-list rather than per link, so it mostly swapped messages headed for *different* peers, which nobody can notice. Both are fixed: reordering is now per destination, and `test_the_reorder_knob_actually_reorders_something` guards the guard. This is the third time this session that a green test turned out to be measuring nothing.

**Mutation-checked.** Making `divergence()` blind, making the authority keep accepted commands to itself, and reconnecting a peer without a snapshot each turned the suite red on the test written for it.
