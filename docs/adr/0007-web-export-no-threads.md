# ADR 0007 — Web export with threads disabled, GL Compatibility renderer

**Status:** Accepted · 2026-09-13

## Context
Godot's threaded web build needs `SharedArrayBuffer`, which browsers only allow with COOP/COEP headers. GitHub Pages cannot set custom headers. Since Godot 4.3 a single-threaded web export exists.

## Decision
Web preset: `variant/thread_support=false`, `variant/extensions_support=false`, renderer `gl_compatibility`, `ensure_cross_origin_isolation_headers=false`.

## Consequences
- Works on GitHub Pages, itch.io and any static host with zero configuration.
- Gameplay code must not use `Thread`, `WorkerThreadPool`, or threaded resource loading. Audio latency is slightly higher; acceptable.
- Forward+/Mobile-only rendering features (volumetric fog, SDFGI, some compositor effects) are off the table. Stylised low-poly art fits the budget anyway.
- If we ever want threads, a `coi-serviceworker` shim can be added to the HTML shell without changing the game.
