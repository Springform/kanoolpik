class_name RelayEndpoint
extends RefCounted
## Where the relay lives. [b]Stated once, here[/b] (WP-4.4).
##
## The address is baked into the build rather than typed into a lobby field.
## It is visible to anyone who opens the game either way, so nothing is lost by
## shipping it; what is gained is one fewer thing for a friend to get wrong on
## the phone. Changing relay costs a rebuild, which is one Actions run.
##
## [b]This constant is the only statement of the host.[/b] It used to be in
## three places — here, `docs/NETWORKING.md`, and the repository variable
## `KANOOLPIK_RELAY_URL` that fed `net-live.yml`. The workflow now reads
## [constant HOST] out of this file and the variable is gone, because
## `compatibility_date` was stated twice, the test copy won in silence, and all
## 17 tests passed against a runtime nobody ships.
##
## [b]The environment overrides exist for tests, not for players.[/b]
## [FakeRelay] listens on a random loopback port, and `net-live` points the same
## suite at the deployed Worker. In a web export [method OS.get_environment]
## always returns an empty string, so a shipped build can only ever use
## [constant HOST] — the override cannot be reached from a browser even in
## principle.

## The deployed Cloudflare Worker (see `infra/relay/`).
##
## [b]The `net-live` workflow greps this line.[/b] Keep the declaration on one
## line, starting at column one; `test_lobby.gd` runs the workflow's own
## pattern against this file and fails if it stops matching.
const HOST := "kanoolpik-relay.kennet-hoejmark.workers.dev"

## The pattern `net-live.yml` uses to read [constant HOST]. Stated here so the
## test and the workflow cannot drift into disagreeing about it.
##
## [b]Anchored to the start of a line[/b], which is not decoration: `grep` is
## line-based and gets that for free, while [RegEx] scans the whole file and
## would otherwise happily match the first mention of the constant in a comment
## — including this one. It did, on the first run.
const HOST_PATTERN := "^const HOST := \"([^\"]+)\""
const SOURCE_PATH := "res://src/game/lobby/relay_endpoint.gd"

## Tests and `net-live` point the client somewhere else with these. Empty in
## every build a player can download.
const ENV_WS := "KANOOLPIK_RELAY_URL"
const ENV_HTTP := "KANOOLPIK_RELAY_HTTP"


## Base for the WebSocket upgrade: `…/room/<code>` is appended by
## [WebSocketTransport].
static func ws_base() -> String:
	var override := OS.get_environment(ENV_WS)
	if not override.is_empty():
		return override.rstrip("/")
	return "wss://" + HOST


## Base for `GET /new`. Derived from the socket override when only that is set,
## so a test that redirects one does not accidentally leave the other pointing
## at the real relay — which would mint live room codes from a unit test.
static func http_base() -> String:
	var override := OS.get_environment(ENV_HTTP)
	if not override.is_empty():
		return override.rstrip("/")
	var ws := OS.get_environment(ENV_WS)
	if not ws.is_empty():
		var base := ws.rstrip("/")
		if base.begins_with("wss://"):
			return "https://" + base.substr(6)
		if base.begins_with("ws://"):
			return "http://" + base.substr(5)
		return base
	return "https://" + HOST


## True when this build talks to the address it shipped with. False in a test.
static func is_default() -> bool:
	return OS.get_environment(ENV_WS).is_empty() and OS.get_environment(ENV_HTTP).is_empty()
