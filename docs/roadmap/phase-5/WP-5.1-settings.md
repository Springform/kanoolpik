# WP-5.1 — Settings that stick

**Phase:** 5 · **Lane:** settings · **Size:** M · **Status:** unclaimed · **Depends on:** —
> **Supersedes the settings half of [WP-1.7](../phase-1/WP-1.7-controller-feel.md).** The motion half is [WP-5.2](WP-5.2-feel.md).

## Goal
A panel, reachable from the title screen and from Esc mid-round, where a player sets mouse sensitivity, FOV, head bob, the three volume sliders and the language — and finds them the same way next time. **Nothing is remembered today.** `user://` holds saved games and nothing else, so the language toggle on the title screen resets on every reload, and there is no way at all to change sensitivity without editing the scene.

## Owns (may edit)
- `src/game/settings/` (new: `settings.gd`, `settings_panel.gd`)
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
- [ ] Every value survives a reload.
- [ ] Sensitivity and FOV change what the camera does **while the slider moves**.
- [ ] Volume sliders move the three buses independently, and 0 is silent rather than quiet.
- [ ] A deleted, empty or garbage `settings.cfg` loads the defaults without an error in the log.
- [ ] Nothing in `src/core/` changed.
- [ ] Tests: defaults on a missing file; a round trip through save/load; `changed` fires once per actual change and not on a write of the same value.
- [ ] `tools/run_tests.sh` green; boot check green.
- [ ] Looked at on screen at 1920×1080 **and** at a narrow window — `PanelFit.centre()`, not a height typed into a scene.

## Playtest checklist (human, 5 min)
- [ ] Set sensitivity, close the game, reopen it: still there.
- [ ] Open settings mid-round from Esc; the round is paused and resumes cleanly.
- [ ] Switch to English and back while standing on the island.

## Notes / decisions
