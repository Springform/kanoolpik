# Architecture decision records

One file per decision, numbered, never deleted — superseded ADRs get a "Superseded by" line. Format: Context → Decision → Consequences.

| # | Decision | Status |
|---|---|---|
| [0001](0001-godot-engine.md) | Godot 4.7 with GDScript over Three.js/Unity | Accepted |
| [0002](0002-static-hosting-webrtc.md) | Static hosting; multiplayer via WebRTC with a player as host | Accepted |
| [0003](0003-pure-core-command-pattern.md) | Pure GDScript core with command pattern and event list | Accepted |
| [0004](0004-gdunit4-testing.md) | gdUnit4 for unit/integration tests, run headless in CI | Accepted |
| [0005](0005-content-as-json.md) | Content (items, containers, levels) as JSON, validated by tests | Accepted |
| [0006](0006-i18n-danish-default.md) | Danish default UI, all strings via tr() and a CSV | Accepted |
| [0007](0007-web-export-no-threads.md) | Web export with threads disabled, GL Compatibility renderer | Accepted |
| [0008](0008-procedural-assets.md) | Assets are generated in code, not downloaded | Accepted (amended by 0009) |
| [0009](0009-third-party-models.md) | Third-party models allowed, with tracked attribution | Accepted |
| [0010](0010-progression-is-replicated-state.md) | Progression is replicated state; unlocking is a command | Accepted |
| [0011](0011-websocket-relay.md) | Multiplayer over a WebSocket relay, not WebRTC | Accepted (supersedes 0002 transport) |
