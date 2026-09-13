# ADR 0001 — Godot 4.7 with GDScript

**Status:** Accepted · 2026-09-13

## Context
We want a 3D first-person game that friends can play from a link, with multiplayer for up to six, built largely by AI agents working in parallel, by a developer with strong software-engineering habits but no game-dev experience. Candidates: Three.js (TypeScript), Godot 4, Unity.

## Decision
Godot 4.7, GDScript (standard build, not .NET).

## Why
- Batteries included for a game-dev novice: 3D scene editor, CharacterBody3D, physics (Jolt), glTF import, audio buses, input map, i18n — every one of these is a week of work in Three.js.
- First-class high-level multiplayer (`MultiplayerAPI`, `MultiplayerSynchronizer`, `WebRTCMultiplayerPeer`) that works in web export. Three.js has nothing; we'd write netcode from scratch.
- Web export to a static host is a supported target; since 4.3 no SharedArrayBuffer is required.
- Text-based scenes (`.tscn`) and scripts diff and merge in git; headless CLI runs tests and exports in CI.
- Open source, MIT, no licensing surprises for a hobby project. Unity's web story and licensing churn ruled it out.

## Consequences
- Agents must learn Godot idioms (see `docs/GAME_DEV_PRIMER.md`); GDScript typing is weaker than TypeScript, so we mandate static types and treat warnings as errors.
- Merge conflicts in `.tscn` are painful → thin scenes, one feature per folder, composition in code (ADR 0003 and `ARCHITECTURE.md §4`).
- Web build size (~30–40 MB engine wasm) means a longer first load than a JS game. Acceptable for a friends-only game.
