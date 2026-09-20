# WP-5.7 — What the crew found

**Phase:** 5 · **Lane:** — · **Size:** unknown by design · **Status:** blocked — waiting on a playtest

## This is not a work package yet
It is the place the playtest's findings become work packages. It stays empty until people have played, and it is written down now so the bug-fix week has somewhere to land instead of turning into an afternoon of unattributed patches.

## What it is waiting for
A session with the actual canoe crew, against the **QA checklist** written on 2026-09-20. Everything in passes 03–05 of that list — remote avatars, the multiplayer HUD, dropping out and coming back — was written and shipped in a single day and **has never been seen by a human**. Two people have played together, once.

The checklist also collects the numbers [WP-3.8](../phase-3/WP-3.8-evaluation-tuning.md) has been blocked on since spring: how long a full clean actually takes, whether the S band is reachable, and whether Autopilot makes the rest of the game pointless. Par is *guessed* at 20 minutes and max at 40. Nobody has measured either.

## How to fill this in
1. Collect the copied reports from everyone who tested.
2. Sort every finding into one of three piles, and be strict about the middle one:
   - **A bug** — the game does something other than what it says it does. Fix it, with a test that fails first.
   - **A design question** — the game does what it was built to do and that turns out to be wrong. This becomes a decision, not a patch; write it up the way [WP-3.9](../phase-3/WP-3.9-hvalen-design-questions.md) is written and get an answer before touching code.
   - **A number** — par time, the S band, the transform rate, the carry capacity. Goes to WP-3.8 with the measurement attached.
3. Split anything left into WPs under this phase, numbered 5.7.1 onwards, each under a page.

## The one finding that outranks everything
**If two screens ever show different numbers in "X af 162 ting på plads", stop.** That is a desync: two peers applied the same commands and landed in different worlds, and every other finding from that session is suspect because the players were not in the same game. `WebSocketTransport` emits `diverged` with both hashes and the command that caused it — get that log before anything else, and fix it before fixing anything cosmetic.

## Acceptance criteria
- [ ] Every report collected and read.
- [ ] Every finding sorted into bug / design question / number, with nothing left in "misc".
- [ ] The numbers handed to WP-3.8.
- [ ] Bugs fixed, each with a test that fails without the fix.
- [ ] Design questions written up, not silently decided by whoever was editing.

## Notes / decisions
