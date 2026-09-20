# WP-5.6 — The front page

**Phase:** 5 · **Lane:** docs · **Size:** S · **Status:** unclaimed · **Depends on:** —

## Goal
Somebody who has never seen the repo can look at `README.md` and know what the game is, what it looks like, and how to get five friends onto an island — without opening a single other file.

## The README is wrong right now
> *"**Multiplayer:** up to 6, host-authoritative over WebRTC (phase 4)"*

**ADR 0011 replaced WebRTC with a Cloudflare WebSocket relay**, and that is what shipped. The front page states the architecture that was rejected. Fix that line first; then read the rest of the file with the same suspicion, because it was written in phase 0 and phases 1–4 have all landed since.

Known stale, at least:
- Multiplayer is described as "phase 4" future tense. It works.
- Nothing says how to host or join a room, which is now the main way the game is played.
- "you spawn on a gray-box island full of junk" — it has been a real island since WP-2.1.
- The key list is missing every phase-3 ability (Tab, F, R, C, E) and F1.

## Owns (may edit)
- `README.md`
- `docs/screenshots/`
- `CONTRIBUTING.md` if the quick start moved

## Must not touch
`docs/adr/` (a decision record is not edited to match the code; the code matches it, or a new ADR supersedes it) · `docs/roadmap/` · `src/`.

## Design notes
- **The screenshots already exist, or can.** `docs/screenshots/` holds two terrain shots from phase 2. `tools/shots.gd` now renders the lobby, the skill menu, the abilities, remote avatars and the multiplayer HUD at 1920×1080 under xvfb — pick four or five that tell the story and replace the pair. The command is in the harness's own docstring.
- **Screenshots go in the repo, so they count against nothing but the clone.** They are not in the web export. Still: keep them reasonable, and let `.gitattributes` treat them as binary (it already does).
- **Write the multiplayer section as instructions to a person**, not as architecture: one of you presses "Lav et hold", reads six letters aloud, the others type them. Two sentences.
- The doc table further down (`Read this first`) is good and mostly still true — check every row still points at a file that exists and still says what the row claims.

## Acceptance criteria
- [ ] No sentence in `README.md` describes an architecture the project does not use.
- [ ] Multiplayer is described in the present tense, with how to start a room.
- [ ] Every key the game responds to is listed, including the phase-3 abilities and F1.
- [ ] Four or five current screenshots, none of them the gray-box island.
- [ ] Every link and every row of the doc table resolves.
- [ ] `tools/run_tests.sh` green (nothing here should be able to break it — say so if it does).

## Playtest checklist (human, 5 min)
- [ ] Hand the README to one of the crew who has not seen the repo. Can they get into a room?

## Notes / decisions
