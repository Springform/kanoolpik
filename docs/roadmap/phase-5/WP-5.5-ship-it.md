# WP-5.5 — Ship it

**Phase:** 5 · **Lane:** infra · **Size:** M · **Status:** unclaimed · **Depends on:** —

## Goal
A link a person can put on their phone's home screen, a mirror on itch.io for the people who will not click a github.io address, and a proper icon instead of the Godot one. The game already deploys to GitHub Pages; this is about it looking like something rather than like a build output.

## Owns (may edit)
- `export_presets.cfg`
- `.github/workflows/` (deploy only — `ci.yml` and `net-live.yml` belong to whoever is fixing them)
- `icon.svg` and whatever the PWA needs beside it

## Must not touch
`src/` · `data/` · `infra/relay/` (the Worker is deployed separately and by hand).

## The trap, read this first
`progressive_web_app/enabled=false` and `progressive_web_app/ensure_cross_origin_isolation_headers=false` are both **deliberate**, and only one of them changes.

ADR 0007 chose the GL Compatibility renderer with **no thread support** precisely so the export needs no COOP/COEP headers — which is what makes plain GitHub Pages work at all. Turning on PWA must not turn on cross-origin isolation: that would add headers Pages cannot serve, and the symptom is a game that works locally and shows a blank canvas on the real URL. Turn on the first, leave the second alone, and **verify on the deployed URL, not on localhost.**

## Design notes
- **The size budget is enforced in CI** at 15 MB gzipped, currently 12.5 MB. A PWA adds a manifest, a service worker and icon sizes; check the budget still passes rather than raising it.
- **A service worker caches the build.** That is the point, and it is also how a player ends up on last week's version after you deploy. Decide the update behaviour and write it down — at minimum, the version must be visible somewhere in-game so a bug report can name it.
- **The relay URL is baked into the build** (`RelayEndpoint.HOST`). An itch.io mirror is a *second* copy of the same build talking to the *same* relay, which is fine — rooms are addressed by code, not by origin. Confirm the Worker's CORS/origin handling does not care.
- itch.io wants a zip with `index.html` at the root and the "this file will be played in the browser" box ticked. Its frame is a fixed size; check the canvas resize policy (`html/canvas_resize_policy=2`) behaves inside it.

## Acceptance criteria
- [ ] Installable from the deployed URL: the browser offers "Add to home screen" / "Install".
- [ ] Cross-origin isolation is still **off**, and the deployed build still boots on GitHub Pages.
- [ ] The icon is the game's, at every size the manifest asks for.
- [ ] itch.io mirror plays in the browser frame, and a room opened there can be joined from the Pages build.
- [ ] The gzipped budget still passes in CI, unraised.
- [ ] The build's version (commit or tag) is readable from inside the game.
- [ ] Deploy workflow is green and the two URLs serve the same commit.

## Playtest checklist (human, 5 min)
- [ ] Install it on a phone home screen and open it. It will not play well — it is not a mobile game — but it must not be broken.
- [ ] Deploy twice in a row and confirm the second one actually reaches a browser that already loaded the first.

## Notes / decisions
