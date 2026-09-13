# WP-1.8 — Save/load via WorldState snapshot

**Phase:** 1 · **Lane:** core / infra · **Size:** S · **Status:** unclaimed

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
- [ ] Round trip equality: pack → JSON string → parse → unpack → `to_dict()` identical (note JSON turns ints into floats — normalise in `from_dict`, add a test for it).
- [ ] Schema version checked; older/unknown version fails gracefully (returns false, no crash).
- [ ] Autosave writes at most once per completed container and never during `tick`.
- [ ] Load replaces `GameSession.state` and emits `Transport.state_replaced` semantics (progress refresh) — presentation re-syncs (island rebuild is fine for v1).
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Reload the browser tab mid-run, click "Fortsæt" (add the string), everything is where it was.
