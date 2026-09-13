# WP-1.6 — Title screen, seed entry, pause, restart

**Phase:** 1 · **Lane:** flow · **Size:** M · **Status:** done (Claude, 2026-09-13)

## Goal
The game opens on a title screen (`ui.title`, background = a slow camera drift over the island) with "Start oprydningen", an optional seed field, language toggle (da/en via `TranslationServer.set_locale`) and a settings stub. Esc in game opens a pause menu (resume / restart / title). `main.tscn` becomes a tiny state machine: TITLE → PLAYING → EVALUATION.

## Owns (may edit)
- `src/game/title/` (new), `src/game/main/` (state machine; keep it small)
- `assets/i18n/strings.csv` — append `ui.title.*`, `ui.pause.*`
- `tests/integration/test_flow.gd`

## Must not touch
- `src/core/`, `src/autoload/`, `src/game/player/` (the pause menu just toggles `get_tree().paused` and mouse mode)

## Interfaces
**Consumes:** `GameSession.start_level/stop_level`, `GameEvents.level_loaded`.
**Provides:** `Main.to_title()`, `Main.start_game(seed)`; `Main.state` enum for tests.

## Acceptance criteria
- [x] Boot → title; Start → island; Esc → pause; restart from pause reproduces the same seed.
- [x] Player scene is not instantiated on the title screen (no captured mouse).
- [x] `process_mode` set so the pause menu works while the tree is paused.
- [x] Language toggle swaps UI strings live.
- [x] Integration test drives TITLE → PLAYING → TITLE through `Main` methods.
- [x] `tools/run_tests.sh` green; boot check green (`--quit-after` on the title screen must still exit 0).

## Playtest checklist
- [ ] Mouse capture/release never gets stuck.
- [ ] Title reads well in both languages.

## Notes / decisions
- `Main` is now a three-state machine (TITLE / PLAYING / EVALUATION) and the only builder of a level. `@export skip_title` drops straight into a game while developing (and for the evaluation tests).
- The title backdrop starts the level and immediately `stop_level()`s it: the island is there to look at, the clock never runs and no command can be submitted. `BackdropCamera` orbits it slowly with `PROCESS_MODE_ALWAYS`.
- **The pause menu really does use `get_tree().paused`** — unlike the evaluation screen. A pause is a genuine suspension, the player is pausable (so it stops receiving input the instant the tree pauses) and the menu is `PROCESS_MODE_ALWAYS` so it can unpause itself. Tests must never `await` while paused: the awaited timer would never fire and the suite would hang. There is a comment saying so at the top of `test_flow.gd`.
- Esc uses the built-in `ui_cancel` action, so `project.godot` needed no change. `Player`'s own `ui_toggle_mouse` (also Escape) still fires when unpaused and also releases the mouse — same end state, so it is harmless; once paused the player no longer receives input at all.
- **Screen changes are connected `CONNECT_DEFERRED`.** Acting on "start" or "back to title" frees the node that is still emitting the signal, which Godot refuses with "Attempted to free a locked object". Every flow test therefore waits a frame before asserting.
- `pause_menu.can_open` is switched off when the evaluation appears: Esc has nothing to pause once the level is over.
- Mouse capture is **not** asserted in tests — headless has no window, so `Input.mouse_mode` never leaves VISIBLE. It is on the playtest checklist instead.
- Both the title screen and the pause menu re-apply their text on `NOTIFICATION_TRANSLATION_CHANGED`, so the language toggle is live. The HUD and evaluation screen set their text in `_ready()` only; if we ever offer a language toggle mid-game they need the same treatment.
- The seed field's English placeholder was cut off at 180 px (spotted on screen, not in tests) — field widened and the hint shortened.

## Playtest checklist
- [ ] Esc captures/releases the mouse cleanly, every time, with no stuck state.
- [ ] Typing an island code and pressing Enter starts that exact mess.
- [ ] The backdrop drift is slow enough to be calming, not distracting.
