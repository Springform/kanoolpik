# Game design

This document is the source of truth for rules. Code in `src/core/` implements it; when they disagree, fix one and say which.

## 1. Reference-game mapping

| Librarian | Kanoølpik | Implemented in |
|---|---|---|
| Book | **Item** (can, sock, tent pole…) | `ItemDef`, `data/catalog/items.json` |
| Shelf section (1A–2Q) | **Container** (pant bag, cooler, tent bag, canoe…) | `ContainerDef`, `data/catalog/containers.json` |
| Section code on the book | `ItemDef.category` must be in `ContainerDef.accepts` | `PlacementRules` layer 1 |
| Series (same title) | `ItemDef.series` — all members must share one container | `PlacementRules` layer 2 |
| Volume order | `ItemDef.sequence` in an `ordered` container (tent poles 1→4) | `PlacementRules` layer 3 |
| Gold / red feedback | `Verdict.CORRECT` vs any other verdict | `PlacementRules.Verdict` |
| Completed row chime | `container_completed` event | `CommandProcessor` |
| Exit barrier | `island_clean` event; canoes launch | `PlacementRules.is_island_clean` |
| Principal's Evaluation | **Camp leader's evaluation** — completion, accuracy, speed | `Evaluation` |
| Skill points per row | 1 point per completed container | `Progression` |
| Insight | **Klarsyn** — highlight same-series items | Phase 3 |
| Assemble | **Råb på en kammerat** — a mate throws you the remaining series members | Phase 3 |
| Auto-Shelving | **Autopilot** — held item snaps to its correct slot near its container | Phase 3 |
| Shelf Guide | **Stedsans** — arrow towards the container for the held item | Phase 3 |
| Carry-capacity keys | **Rolige hænder** (+2 capacity) and hidden collectibles | Phase 3 |
| Two floors, 31 sections | One island, 8 containers (Island 01), ~57 items → grow to ~150 | `data/levels/island_01.json` |

## 2. Core loop

```
look around → spot item → walk → pick up (E) → carry (up to capacity, items have size)
→ find container → place (E) → feedback → repeat
→ container complete → skill point → maybe unlock ability
→ island clean → evaluation → canoes launch
```

Wrong placements are **allowed** (that's the puzzle); they count against accuracy and the item can be taken back out.

## 3. Placement rules (exact)

Given item *I*, container *C*, slot *s*:

1. `s` must exist (`0 ≤ s < C.slot_count`) and be empty → else `INVALID_SLOT` / `SLOT_OCCUPIED` (physically impossible; the command is rejected, nothing happens).
2. `I.category ∈ C.accepts` → else `WRONG_CATEGORY`.
3. If `I.series ≠ ""`: no other member of the series may already sit in a *different* container → else `SPLIT_SERIES`.
4. If `C.ordered` and `I.sequence > 0`: for every other member *J* of the same series already in *C*, `slot(J) < s ⇔ J.sequence < I.sequence` → else `WRONG_ORDER`. Gaps are fine; relative order is what matters.
5. Otherwise `CORRECT`.

A **container is complete** when every item that belongs in it is in it and all of them are `CORRECT`. "Belongs in it" means every item whose category *only* this container accepts. Items whose category several containers accept are not required in any particular one, but a series may still never be split across containers.

> This was originally specified as "every series present has all its members present", which was wrong: an item with no series (the tent canvas, the schnapps bottle, the napkins) declared its container packed the moment it was dropped in alone.

The **island is clean** when every catalog item is placed and `CORRECT`.

## 4. Carrying

Players start with capacity 3. Each item has `size` (1 default; poles 2, canvas 3). `pick_up` fails with `hands_full` when `Σ size + item.size > capacity`. `drop` puts the last-held item on the ground in front of the player. `take_out` retrieves a placed item (to fix mistakes) if there is capacity.

## 5. Evaluation ("Lejrlederens vurdering")

Score 0–100 = `60 × completion + 25 × accuracy + 15 × speed`

- completion = correct / total
- accuracy = 1 − wrong_placements / placements (cumulative over the run; fixing a mistake doesn't erase it)
- speed = 1 within *par* (Island 01: 600 s), linear to 0 at *max* (1800 s)

| Points | Grade | Danish flavour |
|---|---|---|
| ≥ 95 | S | Spejderleder-standard |
| ≥ 85 | A | Flot arbejde |
| ≥ 70 | B | Godkendt |
| ≥ 50 | C | Tja... |
| < 50 | D | I padler ingen steder |

Multiplayer uses a single shared evaluation — it is a co-op score.

## 6. Progression & abilities

1 skill point per completed container (Island 01: max 8).

| Ability | Cost | Effect |
|---|---|---|
| Klarsyn (Insight) | 1 | Hold an item → its series siblings glow through walls for 5 s |
| Stedsans (Map sense) | 1 | HUD arrow toward the container that accepts the held item |
| Råb på en kammerat (Call a mate) | 2 | Remaining members of the held item's series fly to your feet (once per series) |
| Rolige hænder (Steady hands) | 2 | +2 carry capacity |
| Autopilot (Auto-place) | 3 | Within 2 m of the correct container, pressing E places the held item into the first correct slot |

Hidden collectibles (phase 3) give one-off bonuses, like the reference game's four key chests: sunglasses (reduce "hangover blur"), a headlamp, a trolley (+3 capacity), a whistle (calls everyone to you — multiplayer).

## 7. Island 01 content

8 containers: pant bag (cans, plastic bottles), bottle crate (glass), trash bag, cooler (food), tent bag (poles 1–4 *ordered*, pegs, canvas), dry bag (clothing), canoe (paddles, vests), fire pit (firewood). 57 items across 12 categories and 14 series. Five spawn zones weight where categories tend to land (cans near the fire, tent stuff by the tents, paddles by the shore) so the layout tells a story of the night.

Growth plan (phase 2): two canoes with crews (paddles A/B as series), sleeping bags in ordered tent bags, a "lost & found" for one-offs, ~150 items.

## 8. Multiplayer design (phase 4)

- Up to 6 players, one is the **host** (authority). Static hosting → WebRTC mesh or host-star, tiny signalling service (Cloudflare Worker free tier).
- Everyone runs the same `MessGenerator(seed)`; the host owns the `WorldState`; clients submit commands, the host applies and broadcasts the event list; late joiners get a full `WorldState.to_dict()` snapshot.
- Player transforms are replicated with `MultiplayerSynchronizer` (unreliable, 20 Hz). Item state never goes through physics replication — only through commands.
- Shared evaluation, shared skill points (party buys abilities together — encourages talking).

## 9. Open questions (decide in their WPs)

- Should items be physics bodies you can throw (like books over the railing)? Fun, but non-deterministic. Proposal: throwing is presentation-only; the item's *logical* position updates on landing via a `drop` command from the thrower's client (host validates range).
- Should wrong placements be visible to other players? Yes — red slot indicators are shared; it creates conversation.
- Hangover "blur" at start that clears as you tidy? Nice tone device; cheap with a screen shader. Phase 5.
