# WP-2.6 — Soundscape: ambience and music that rises with progress

**Phase:** 2 · **Lane:** audio · **Size:** M · **Status:** unclaimed

## Goal
The island sounds like a Swedish lake in the morning, and the music thickens as the place gets cleaner — quiet and sparse at 0 % done, warm and full when the canoes are about to launch. The reference game does this with shelves; ours does it with containers packed. All audio is synthesised in-repo (ADR 0008: no downloaded assets), the same way `tools/gen_sfx.py` made the placement sounds.

## Owns (may edit)
- `src/game/audio/` (new)
- `assets/audio/` (ambience and music; leave `assets/audio/sfx/` alone — WP-1.2 owns those four files, but you may add new ones)
- `tools/gen_ambience.py`, `tools/gen_music.py` (new; follow the style of `tools/gen_sfx.py`)
- `project.godot` — **you are the only WP touching it this wave.** Add the soundscape autoload and any audio buses.
- `tests/integration/test_soundscape.gd` (new)

## Must not touch
- `src/core/`, `src/autoload/` (other than registering your autoload), `src/game/island/`, `src/game/containers/`, `data/`

## Interfaces
**Consumes:** `GameEvents.progress_changed(progress)` (has `completion`, `containers_completed`, `containers_total`), `GameEvents.container_completed`, `GameEvents.island_clean`, `GameEvents.level_loaded`, `GameSession.is_running()`.
**Provides:** a `Soundscape` autoload with `set_intensity(0..1)`, `mute(bool)` and layer control, so the settings WP in phase 5 has something to hook into.

## Acceptance criteria
- [ ] Layered music: at least three stems that fade in as completion rises; crossfades are smooth, not stepped.
- [ ] Ambience (water, wind, birds) loops without an audible seam — assert the loop points in a test, do not trust your ears alone.
- [ ] Everything runs on named audio buses (`Music`, `Ambience`, `SFX`) so volume can be controlled per category later.
- [ ] **No `Thread` or `WorkerThreadPool`** — the web export is single-threaded (ADR 0007). Audio files stay small: total added `assets/audio/` under 6 MB, asserted by a test or a tool.
- [ ] Silence when no level is running (title screen gets ambience only, no music).
- [ ] Tests drive intensity by emitting `progress_changed` and assert the mix responds; they must not depend on real playback timing.
- [ ] `bash tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Ten minutes of play without the ambience becoming irritating.
- [ ] The moment a container is packed still stands out over the music.
