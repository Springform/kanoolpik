# ADR 0003 — Pure GDScript core with command pattern and event list

**Status:** Accepted · 2026-09-13

## Context
Game logic sprinkled through scene scripts is untestable, non-deterministic and impossible to replicate. We need multiplayer-readiness from day one without building networking now, and we need many agents to work without stepping on each other.

## Decision
- All rules and state live in `src/core/` as `RefCounted` classes with **no Node, Input, tr(), scene or autoload dependencies**.
- The world is a single `WorldState` value object; **only `CommandProcessor.apply(state, cmd)` mutates it**.
- Commands and events are plain `Dictionary` values. `apply` returns `{ok, error, verdict, events[]}`.
- Presentation subscribes to events via the `GameEvents` autoload bus and reads state read-only via `GameSession`.
- A `Transport` interface sits between `GameSession.submit()` and the processor; `LocalTransport` today, `WebRtcTransport` later.

## Consequences
- Every rule is a pure function with unit tests; the suite runs in under a second.
- Multiplayer becomes "replace the transport": host applies, clients replay events. `test_same_commands_produce_identical_states` guards this.
- Save/load and replays are `WorldState.to_dict()` plus a command log.
- Discipline cost: agents must resist calling `state.set_*` from a scene. CI can grep for it (`tools/`, future WP).
- Slight verbosity: a new action needs a `Commands` builder, a processor handler, an event shape, and a bus signal. That is the price of a clean seam and it is documented in `CLAUDE.md`.
