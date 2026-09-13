# WP-X.Y — Title

**Phase:** X · **Lane:** <feature> · **Size:** S / M / L · **Status:** unclaimed | in progress (@who) | done

## Goal
One paragraph: what exists when this is done, from the player's point of view.

## Owns (may edit)
- `src/game/<feature>/`
- `tests/integration/test_<feature>.gd`

## Must not touch
- `src/core/` (open a core WP instead) · `src/autoload/` · other features' folders · `project.godot`

## Interfaces
**Consumes:** signals/APIs this WP reads (e.g. `GameEvents.item_placed`, `GameSession.state`).
**Provides:** anything new other WPs will rely on (new signals → request in an infra PR first).

## Acceptance criteria
- [ ] …
- [ ] Tests: …
- [ ] `tools/run_tests.sh` green; boot check green

## Playtest checklist (human, 5 min)
- [ ] …

## Notes / decisions
Record anything you decided that the WP didn't specify.
