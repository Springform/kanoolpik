class_name TestMode
extends RefCounted
## Whether this build may open the test panel, and whether it currently is.
##
## The panel exists so the game can be checked a piece at a time instead of
## played from the top every time — the win condition in particular, which
## otherwise costs a full tidy-up to reach once.
##
## Two questions, deliberately separate:
##
##   [method is_available]  may this build offer test mode at all?
##   [method is_enabled]    has it been switched on for this run?
##
## Availability is a property of the build. Enablement is a choice on the title
## screen, so a debug run can still be played honestly.
##
## [b]Where it is available[/b]
##   - any debug build (running from the editor, or a debug export)
##   - a release web build ONLY when the page is opened with `?test=1`
##   - any build launched with `--test-mode` on the command line, which is how
##     the test suite turns it on without pretending to be a debug build
##
## A release web build with a plain URL therefore has no way in. The code still
## ships in it — that is the price of being able to debug the real browser build
## on the oldest laptop in the canoe crew — so this is a lock on the door, not a
## claim that the room isn't there.

const QUERY_FLAG := "test=1"
const CLI_FLAG := "--test-mode"

static var _enabled_override: Variant = null


## May this build offer test mode?
static func is_available() -> bool:
	if OS.has_feature("debug"):
		return true
	if CLI_FLAG in OS.get_cmdline_args() or CLI_FLAG in OS.get_cmdline_user_args():
		return true
	return _web_query_asks_for_it()


## Is test mode on for this run? Defaults to on wherever it is available, so
## pressing F5 in the editor needs no ceremony.
static func is_enabled() -> bool:
	if not is_available():
		return false
	return true if _enabled_override == null else bool(_enabled_override)


## Turn it on or off for this run (the title screen's toggle). Does nothing in a
## build where it is not available — a release build cannot be talked into it.
static func set_enabled(value: bool) -> void:
	_enabled_override = value


## Forget the override, so [method is_enabled] goes back to its default. Tests
## call this in teardown; nothing else should need it.
static func reset() -> void:
	_enabled_override = null


## `?test=1` in the page URL. Only meaningful on the web export, and wrapped
## because JavaScriptBridge does not exist on other platforms.
static func _web_query_asks_for_it() -> bool:
	if not OS.has_feature("web"):
		return false
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	return search is String and QUERY_FLAG in String(search)
