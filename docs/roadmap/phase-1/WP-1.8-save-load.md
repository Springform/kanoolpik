# WP-1.8 — Save/load via WorldState snapshot

**Phase:** 1 · **Lane:** core / infra · **Size:** S · **Status:** done (Claude, 2026-09-13)

## Goal
A run can be saved and resumed: `WorldState.to_dict()` + `Progression.to_dict()` + level id + seed → JSON in `user://saves/<slot>.json` (web export maps `user://` to IndexedDB). Autosave on every `container_completed`. Loading restores an identical state (verified by dict equality). This also proves the snapshot path multiplayer will use for late joiners.

## Owns (may edit)
- `src/core/save_game.gd` (pure: `SaveGame.pack(state, progression, level_id) -> Dictionary`, `unpack(dict) -> {state, progression, level_id}`, `SCHEMA_VERSION`)
- `src/autoload/game_session.gd` — add `save(slot)`, `load(slot)`, autosave hook (≤ 40 lines; nothing else)
- `tests/unit/core/test_save_game.gd`, `tests/integration/test_save_load.gd`

## Interfaces
**Consumes:** `WorldState.to_dict/from_dict`, `Progression.to_dict/from_dict`.
**Provides:** `GameSession.save(slot: String) -> bool`, `GameSession.load_save(slot: String) -> bool`, `SaveGame` for the net WPs.

## Acceptance criteria
- [x] Round trip equality: pack → JSON string → parse → unpack → `to_dict()` identical (note JSON turns ints into floats — normalise in `from_dict`, add a test for it).
- [x] Schema version checked; older/unknown version fails gracefully (returns false, no crash).
- [x] Autosave writes at most once per completed container and never during `tick`.
- [x] Load replaces `GameSession.state` and emits `Transport.state_replaced` semantics (progress refresh) — presentation re-syncs (island rebuild is fine for v1).
- [x] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Reload the browser tab mid-run, click "Fortsæt" (add the string), everything is where it was.

## Notes / decisions
- `SaveGame` owns both the pure pack/unpack **and** the file I/O (`read`/`write`/`erase`/`has_save`). Keeping the I/O there rather than in `GameSession` kept the autoload to a handful of lines, and `Catalog` already reads files from core, so there was precedent.
- **`unpack()` returns `{}` rather than a half-built game.** Wrong schema, missing state, missing level id, corrupt JSON — all read as "there is no save". `Main.continue_game()` then falls back to a fresh game, so the button can never strand the player on the title screen.
- A corrupt file is parsed with `JSON.new().parse()` instead of `JSON.parse_string()`, which logs an engine error on bad input. An unreadable save is an ordinary outcome, not an error worth printing.
- The JSON round-trip test is the important one: JSON has a single number type, so every integer returns as a float. `WorldState.from_dict` and `Progression.from_dict` already cast everything; the test pins that so a future field cannot quietly skip the cast. **This is the same snapshot multiplayer will hand a late joiner** (ADR 0002/0003), so it is load-bearing well beyond save files.
- Autosave fires on `container_completed` only — never on a tick, never mid-placement. `GameSession.autosave_enabled` lets tests turn it off.
- `_begin()` is the shared tail of `start_level` and `load_save`, so a loaded game is wired exactly like a generated one. A loaded state already knows its players, so the local player is only added when missing (which preserves an earned carry capacity).
- **Outside the WP's owned folders, deliberately:** `PickupItem` now sets its visibility from the state on `_ready` (a resumed run must not leave packed and carried items lying on the ground), `Main` gained `continue_game()` and a shared `_build_playing_scene()`, and the title screen gained the "Fortsæt hvor I slap" button, shown only when a save exists. All four were needed for the feature to actually work end to end.
- **Not saved: where the player is standing.** A resumed run puts you back at the spawn point. Position is presentation, not world state, and remembering it buys little; revisit if phase 2's terrain makes walking back annoying.
- On the web export `user://` is IndexedDB, so a save survives a tab reload but lives in that one browser on that one machine. Sharing a run means sharing the island code, not the save.

## Playtest checklist
- [ ] Pack a container, reload the browser tab, click "Fortsæt hvor I slap" — everything is where it was.
- [ ] Start a new game from the title after a save exists; the old save is left alone until the next container is packed.
