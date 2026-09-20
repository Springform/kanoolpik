# WP-5.6 — The front page

**Phase:** 5 · **Lane:** docs · **Size:** S · **Status:** done (2026-09-20) · **Depends on:** —

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
- [x] No sentence in `README.md` describes an architecture the project does not use.
- [x] Multiplayer is described in the present tense, with how to start a room — and what the code actually *is*.
- [x] Every key the game responds to is listed, checked against `project.godot`'s own action list rather than from memory.
- [x] Five current screenshots, rendered by `tools/shots.gd`, none of them the gray-box island.
- [x] Every link resolves — checked by walking every relative link in every `.md` outside `node_modules` and `addons`.
- [x] Boot check green. Docs and images only; nothing here can reach the suite.

## Playtest checklist (human, 5 min)
- [ ] Hand the README to one of the crew who has not seen the repo. Can they get into a room?

## Notes / decisions

## Decisions

**Five screenshots, all from the harness.** `tools/shots.gd` renders them at
1920×1080 under xvfb; they are downscaled to 1280×720 and quantised, which puts
the set at about 850 KB. Regenerating them is one command, so they should never
go stale again the way the phase-0 one did:

```
xvfb-run -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
  --resolution 1920x1080 res://tools/shots.tscn -- --only=island,skills,lobby,remote,evaluation
```

**Shoot each one in its own run.** The harness boots the game once and walks
through every shot in order, so state from an earlier shot is still there: the
first attempt at the evaluation screen had five remote avatars standing behind
it, left over from the multiplayer shot. Obvious once seen, invisible until.

**The two phase-2 terrain screenshots are gone.** Nothing referenced them.
`docs/screenshot-phase0.png` is left alone — it is outside this WP's folder and
deleting a file that records where the project started is somebody else's call,
but nothing points at it any more.

**The controls table was checked against `project.godot`, not remembered.** Two
things that came out of that: jump is Space and was missing entirely, and
**Esc is bound to both `ui_cancel` and `ui_toggle_mouse`** — so one press both
pauses and releases the mouse. That is a real oddity in the input map, not a
documentation problem, and the table says so plainly rather than pretending it
is two keys. Worth a look in WP-5.2, which owns the player's input.

## Noticed while writing it, not fixed here

The evaluation screenshot shows **98 % cleanup, 100 % precision, 18 minutes →
99 points**. That is very nearly the top of the scale for a run that was not
perfect, which is the S-band headroom question [WP-3.8](../phase-3/WP-3.8-evaluation-tuning.md)
has been waiting on. It is a number, so it belongs to WP-3.8 and a playtest, not
to the README.

## One more thing the delivery turned up

**The device bridge re-encodes PNGs.** All five arrived with valid headers, the
right dimensions and the right pixels — and a different sha256 from the file
that left. Text round-trips byte for byte; an image does not. So an image
delivery is verified by hashing the decoded pixels on both sides, and every
previous "sha256 verified" on a binary was proving nothing. Written into
`CLAUDE.md`.
