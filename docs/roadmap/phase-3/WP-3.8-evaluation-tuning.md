# WP-3.8 — Evaluation tuning from real playthroughs

**Phase:** 3 · **Lane:** content · **Size:** S · **Status:** **blocked — needs human playtest data** · **Depends on:** 3.1–3.7 merged

## Goal
Par time, grade thresholds and the point economy stop being estimates. The camp leader's verdict reflects what a real round of this game actually takes.

## Owns (may edit)
- `data/levels/*.json` — `par_seconds`, `max_seconds`
- `src/core/evaluation.gd` thresholds only, if the data says so
- `assets/i18n/` grade copy
- `tests/unit/core/test_evaluation.gd`

## Why it is blocked
Every number in GAME_DESIGN §5 is a guess: par 20 min / max 40 min, five grade bands, 12 points per island. Nothing here can be decided by an agent, because the input is how long a person takes and how they feel about the score they got. Tuning against a guess just relocates the guess.

## What unblocks it
Three logged playthroughs with abilities available, recording per run:
1. Wall-clock to island-clean, and time to *each* container completing.
2. Placements and wrong placements.
3. Which abilities were bought, in what order, and at what point in the run.
4. The score awarded, and whether the player thought it was fair.

`WorldState.stats` and `elapsed_ticks` already carry 1 and 2 — a small run log dumped at the evaluation screen would capture all four with no guesswork afterwards. Write that first if it is not there.

## Acceptance criteria
- [ ] Par and max come from measured runs, with the measurements recorded in the WP notes.
- [ ] A competent unhurried run scores B or better; a fast accurate run can reach S; a sloppy one lands below 50.
- [ ] Abilities do not make an S trivial — check what a run that buys Autopilot early actually scores.
- [ ] Grade copy reads as a Danish camp leader, not as a spreadsheet.
- [ ] Tests updated to the new constants, including the boundaries.

## Playtest checklist (human)
- [ ] Three runs, at least two different people, at least one who has never played.
