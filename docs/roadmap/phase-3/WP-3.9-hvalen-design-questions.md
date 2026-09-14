# WP-3.9 — "Hvalen": open design questions, not a work package yet

**Phase:** 3 · **Lane:** design · **Size:** — · **Status:** **needs a decision session with KA**

Captured from GAME_DESIGN §9. Written down here so it stops living in one person's head, but it is deliberately not a buildable WP: an agent handed this would invent the answers, and the answers are the design.

## The idea as captured
A horn sounds. The crew has around 30 seconds to find a beer bong that has spawned somewhere at random, plus an unopened beer. Holding both drinks a bong. Success rewards something — possibly a skill unlock. Failure punishes something — possibly a container emptying back onto the island.

## What has to be decided first
1. **How hard does the penalty bite?** Emptying a packed container undoes real work and is the kind of mechanic that makes a player quit rather than laugh. A softer failure — a time penalty, a scattering of a few loose items, nothing at all beyond missing the reward — keeps the tone without the sting. This is the decision everything else hangs off.
2. **Where does the beer come from once the coolers are packed?** Late in a run every unopened beer is inside a completed container. Either the event can take one back out (and un-completes a container, which is the penalty question again), or it spawns its own, or the event stops firing once the beer is gone. The third is the cheapest and arguably the most honest: the party is over.
3. **What happens to a beer that gets drunk?** It leaves the world, so completion arithmetic changes mid-run — `is_island_clean` counts what the catalog says exists. Either the drunk beer is replaced by an empty can that still needs sorting (nice: the mess regenerates itself, exactly like a real morning), or the item is removed from the completion set, which means the core needs a concept it does not have.
4. **Single-player or multiplayer?** "The crew has 30 seconds" reads as a co-op event. In single-player it is a timed fetch quest, which is a different and much weaker thing.
5. **How often?** Once per run, on a timer, or triggered by progress?

## Recommendation
Option 3a — drinking a beer turns it into an empty can that still has to be sorted — answers question 3 and most of question 2 in one move, costs the core nothing (it is a `remove_item` plus a spawn, both of which exist), and is funnier than either alternative. Decide question 1 first, though; if the penalty is soft, this becomes a light phase-6 event rather than a phase-3 mechanic, and it should move.

## Not blocking anything
Phase 3 completes without it.
