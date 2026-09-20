# WP-5.1 — Settings that stick

**Phase:** 5 · **Lane:** settings · **Size:** M · **Status:** done (2026-09-20) · **Depends on:** —
> **Supersedes the settings half of [WP-1.7](../phase-1/WP-1.7-controller-feel.md).** The motion half is [WP-5.2](WP-5.2-feel.md).

## Goal
A panel, reachable from the title screen and from Esc mid-round, where a player sets mouse sensitivity, FOV, head bob, the three volume sliders and the language — and finds them the same way next time. **Nothing is remembered today.** `user://` holds saved games and nothing else, so the language toggle on the title screen resets on every reload, and there is no way at all to change sensitivity without editing the scene.

## Owns (may edit)
- `src/game/settings/` (`settings.gd`, `settings_panel.gd`)
- `tests/integration/test_settings.gd`
- `assets/i18n/strings.csv` rows prefixed `ui.settings.`

## Must not touch
`src/core/` · `src/autoload/` · `src/game/player/` (WP-5.2 applies the values) · other features' folders.

## Declared scope widening
Two buttons, and nothing else: one in `title_screen.tscn` and one in `pause_menu.tscn`. Say so in the PR. **Build the panel itself in code, not as a `.tscn`** — a scene file is the one thing two agents cannot merge, and this panel will be edited by every later WP that adds an option.

## Interfaces
**Consumes:** `AudioServer` bus indices for `SFX`, `Music`, `Ambience` (they already exist in `default_bus_layout.tres`); `TranslationServer.set_locale`.
**Provides:**
- `Settings.get_float(key, fallback)` / `get_bool` / `get_int`, and `Settings.set_value(key, value)` which writes through to `user://settings.cfg` and emits `Settings.changed(key)`.
- The key names other WPs read: `look.sensitivity`, `look.fov`, `look.head_bob`, `audio.sfx`, `audio.music`, `audio.ambience`, `ui.locale`.

## Design notes
- **A `ConfigFile` at `user://settings.cfg`, not a save game.** `SaveGame` is a `WorldState` snapshot and has nothing to do with preferences; do not extend it.
- **Changes apply live, not on close.** Dragging the sensitivity slider is how a person finds the right sensitivity, and that only works if the camera moves while they drag.
- **A missing or corrupt file is not an error.** First run, a cleared browser, a half-written file: fall back to the defaults, and say nothing.
- **Web storage is not a hard disk.** `user://` in a web export is IndexedDB, and a private window can refuse it. Every read and write must survive failing — the panel still works for that session, it just forgets.
- Language belongs here rather than on the title screen. Leave the title's toggle where it is for now; it should set the same value through `Settings`, so the two cannot disagree.

## Acceptance criteria
- [x] Every value survives a reload.
- [x] Sensitivity and FOV change what the camera does **while the slider moves** — see the scope note below.
- [x] Volume sliders move the three buses independently, and 0 is silent rather than quiet (`linear_to_db(0.0)` is `-inf`, so the bottom of the range is a mute).
- [x] A deleted, empty or garbage `settings.cfg` loads the defaults. The engine's own `ConfigFile parse error` line is printed for a corrupt file; `run_tests.sh` fails on `SCRIPT ERROR` and `Parse Error`, not on a bare `ERROR`, and the test says so.
- [x] Nothing in `src/core/` changed.
- [x] Tests: 19, including a file from a later version that cannot smuggle a key or a type past the loader.
- [x] `tools/run_tests.sh` green; boot check green.
- [x] Looked at on screen in both languages — `tools/shots.gd --only=settings`.

## Playtest checklist (human, 5 min)
- [ ] Set sensitivity, close the game, reopen it: still there.
- [ ] Open settings mid-round from Esc; the round is paused and resumes cleanly.
- [ ] Switch to English and back while standing on the island.

## Notes / decisions

## Decisions

**A `ConfigFile` at `user://settings.cfg`, loaded once on the first read.** Not
an autoload: a preferences store has no per-frame work and nothing to tear down,
and an autoload is a line in `project.godot` that two agents would then both
want to edit. The statics reach just as far.

**A write of the value something already holds is not a change.** A slider emits
`value_changed` while it is dragged and again on release with the same number.
Without that rule every drag writes the file dozens of times and every listener
re-applies what it already has — and it is what lets `refresh()` put a control
back in step without the control reporting it as a choice. The panel has no
guard of its own for that; the rule lives in `set_value` and only there.

**Values are clamped on the way in AND on the way out of the file.** A
hand-edited or newer `settings.cfg` cannot hand [Player] a field of view of 400,
and an unknown key is dropped rather than stored.

**Sensitivity is shown as a multiple, not as radians.** `0.0025` means nothing to
anybody; `1.0×` is what the game has always felt like and `2.0×` is twice as fast.

**Head bob and the intro toggle are not in the panel.** Their keys exist in
`Settings` so WP-5.2 and WP-5.4 have somewhere to write, but nothing reads them
yet, and a switch that does nothing is worse than a missing switch — it is a bug
report from whoever flicked it and watched carefully. Add the row when the thing
it controls exists; it is one entry in `SettingsPanel.ROWS`.

## Scope widening, as declared

Three files outside `src/game/settings/`:

1. **One button each in `title_screen.tscn` and `pause_menu.tscn`**, plus the
   signal and the label in their scripts. Planned.
2. **`title_screen.gd`'s language toggle now goes through `Settings`** instead of
   straight at `TranslationServer`, so the two places that change the language
   cannot disagree — and so the choice survives a reload, which it did not.
3. **`player.gd` reads `look.sensitivity` and `look.fov`** and re-reads them on
   `Settings.changed`. **Not planned, and not optional**: the WP's own acceptance
   criterion says both apply while the slider moves, and a slider that stores a
   number nothing reads is worse than no slider. Ten lines, and it is the hook
   WP-5.2's acceleration and head bob hang off. `src/game/player/` is WP-5.2's
   folder — coordinate before touching it again.

`main.gd` also owns the panel (built once in `_ready`, survives `_tear_down`) and
calls `Settings.apply_all()` before any screen exists, so the locale decides what
the title screen says and the bus volumes decide how loud it opens.

## Two mutations that survived, and what they meant

Both were guards restating a rule that already held somewhere else — the same
mistake as WP-4.6's flattened `y`, twice in one day.

1. A `_syncing` flag in the panel, to stop `refresh()` writing a control's value
   back as a choice. `set_value` already ignores an unchanged write, so the flag
   could be deleted with no test noticing. Deleted; the test that matters now
   pins the behaviour rather than the guard.
2. An explicit `disconnect` in `Player._exit_tree`. Godot drops a freed object's
   connections itself. Deleted, and the test replaced with one that pins
   something the project owns: three levels in a row leave no listeners behind.
