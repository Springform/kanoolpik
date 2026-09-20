class_name Settings
extends RefCounted
## Everything a player chose about how the game behaves, and the only thing
## that remembers it across sessions (WP-5.1).
##
## [b]Nothing was remembered before this.[/b] `user://` held saved games and
## nothing else, so the language toggle on the title screen reset on every
## reload and there was no way to change mouse sensitivity without editing a
## scene. That is what this file is for.
##
## [b]Not an autoload, and not a save game.[/b] Not an autoload because a
## preferences store has no per-frame work and nothing to tear down, and an
## autoload is a thing every WP can reach into; the statics below are reachable
## the same way without adding a line to `project.godot` that two agents would
## then both want to edit. Not a save game because [SaveGame] is a [WorldState]
## snapshot — a world and a preference have nothing to do with each other and
## sharing a file would tie a player's sensitivity to a half-finished island.
##
## [b]Usage[/b]
## [codeblock]
##   var s := Settings.get_float(Settings.LOOK_SENSITIVITY)
##   Settings.set_value(Settings.LOOK_FOV, 100.0)
##   Settings.changed().connect(_on_settings_changed)   # (key: String)
## [/codeblock]

## Where it lives by default. `user://` is IndexedDB in a web export, which a
## private window may refuse outright — see [method _save].
const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "kanoolpik"

## The file actually used. A [String] rather than a constant so a test can point
## it at a scratch file — see [method use_store].
static var path := DEFAULT_PATH
## Tri-state until [method _persists] works it out: -1 unknown, 0 no, 1 yes.
static var _persist := -1

# --- The keys other WPs read. Strings, so a typo is a missing value with a
# --- fallback rather than a parse error nobody sees until runtime.
const LOOK_SENSITIVITY := "look.sensitivity"
const LOOK_FOV := "look.fov"
const LOOK_HEAD_BOB := "look.head_bob"
const AUDIO_SFX := "audio.sfx"
const AUDIO_MUSIC := "audio.music"
const AUDIO_AMBIENCE := "audio.ambience"
const UI_LOCALE := "ui.locale"
## WP-5.4 reads this; declared here so the key is stated once even though
## nothing sets it yet.
const FX_INTRO := "fx.intro"

## Defaults are the values the game shipped with, so a first run and a deleted
## settings file both behave exactly like the build did before this WP existed.
## [constant LOOK_SENSITIVITY] and [constant LOOK_FOV] are [Player]'s and its
## camera's own numbers; the three volumes are 1.0 because
## `default_bus_layout.tres` has every bus at 0 dB.
const DEFAULTS := {
	LOOK_SENSITIVITY: 0.0025,
	LOOK_FOV: 90.0,
	LOOK_HEAD_BOB: false,
	AUDIO_SFX: 1.0,
	AUDIO_MUSIC: 1.0,
	AUDIO_AMBIENCE: 1.0,
	UI_LOCALE: "da",
	FX_INTRO: true,
}

## What a slider may offer, so the panel and any test agree about it without
## either of them inventing a range. Sensitivity spans a factor of sixteen
## because people genuinely differ by that much; FOV stops at 110 because
## beyond that the island fisheyes.
const RANGES := {
	LOOK_SENSITIVITY: {"min": 0.0005, "max": 0.008, "step": 0.0001},
	LOOK_FOV: {"min": 60.0, "max": 110.0, "step": 1.0},
	AUDIO_SFX: {"min": 0.0, "max": 1.0, "step": 0.05},
	AUDIO_MUSIC: {"min": 0.0, "max": 1.0, "step": 0.05},
	AUDIO_AMBIENCE: {"min": 0.0, "max": 1.0, "step": 0.05},
}

## Below this a volume is silence rather than a very quiet sound. `linear_to_db`
## of 0.0 is -inf, which Godot accepts but which no slider can come back from
## cleanly, so the bottom of the range is a mute.
const SILENT_BELOW := 0.001
const MUTED_DB := -80.0

## Bus names, from `default_bus_layout.tres`. Stated here rather than reached
## for through [Soundscape], which owns the music and has no business owning
## the volume of a sound effect it never plays.
const BUSES := {
	AUDIO_SFX: "SFX",
	AUDIO_MUSIC: "Music",
	AUDIO_AMBIENCE: "Ambience",
}

static var _values: Dictionary = {}
static var _loaded := false
## The signal lives on an object because GDScript has no static signals. One
## instance, created on first use, held for the life of the process.
static var _bus: SettingsBus = null


## Emitted with the key whenever a value actually changes. Writing the value a
## control already shows does not fire it — see [method set_value].
class SettingsBus extends RefCounted:
	signal changed(key: String)


static func changed() -> Signal:
	if _bus == null:
		_bus = SettingsBus.new()
	return _bus.changed


## Does this process write a settings file at all?
##
## [b]A test run must not leave a player's preferences behind.[/b] These are
## statics with a file behind them, so any suite that moves a slider used to
## write `user://settings.cfg` — and the next run of the whole suite then
## started in whatever language that file said. One failed language test left it
## on English and `test_hud`'s Danish-glyph assertions failed on the next run,
## in a different suite, for no visible reason.
##
## Headless is the honest discriminator: every test runs headless and the game
## never does. A headless process keeps its settings in memory, behaves
## identically in every other way, and writes nothing. A test that wants the
## file back asks for it by name with [method use_store].
static func _persists() -> bool:
	if _persist < 0:
		_persist = 0 if DisplayServer.get_name() == "headless" else 1
	return _persist == 1


## Point the store at [param new_path] and turn persistence on, whatever the
## display server says. For the one suite that is actually testing the file.
static func use_store(new_path: String) -> void:
	path = new_path
	_persist = 1
	forget()


## Back to the real file, and to not writing it headless.
static func use_default_store() -> void:
	path = DEFAULT_PATH
	_persist = -1
	forget()


# --- Reading ---------------------------------------------------------------------

static func get_value(key: String) -> Variant:
	_ensure_loaded()
	return _values.get(key, DEFAULTS.get(key))


static func get_float(key: String) -> float:
	return float(get_value(key))


static func get_bool(key: String) -> bool:
	return bool(get_value(key))


static func get_string(key: String) -> String:
	return String(get_value(key))


## The slider bounds for [param key], or an empty dictionary for a value that
## is not a number.
static func range_for(key: String) -> Dictionary:
	return RANGES.get(key, {})


# --- Writing ---------------------------------------------------------------------

## Set, apply, save and announce — in that order, and only when something
## changed.
##
## [b]The "only when something changed" is not an optimisation.[/b] A slider
## emits `value_changed` while it is being dragged and again when it is
## released with the same number; without this, every drag writes the file
## dozens of times and every listener re-applies a value it already has.
static func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
	var clamped: Variant = _clamp(key, value)
	if _values.has(key) and typeof(_values[key]) == typeof(clamped) and _values[key] == clamped:
		return
	_values[key] = clamped
	apply(key)
	_save()
	changed().emit(key)


## Put every stored value back to its default, as though the file had never
## existed. Used by the panel's reset button and by tests, which must not
## inherit a sensitivity from whatever ran before them.
static func reset() -> void:
	_values.clear()
	_loaded = true
	apply_all()
	_save()
	changed().emit("")


# --- Applying --------------------------------------------------------------------

## Make the world match the stored value for [param key].
##
## Only the two that nothing else watches are applied here: the audio buses and
## the locale. Sensitivity, FOV and head bob belong to [Player], which reads
## them and listens for [method changed] (WP-5.2) — a settings file that
## reached into the player's camera would be the second place that decides how
## the camera works.
static func apply(key: String) -> void:
	if BUSES.has(key):
		_apply_bus(key)
	elif key == UI_LOCALE:
		var locale := get_string(UI_LOCALE)
		if not locale.is_empty() and TranslationServer.get_locale() != locale:
			TranslationServer.set_locale(locale)


static func apply_all() -> void:
	for key: String in BUSES:
		_apply_bus(key)
	apply(UI_LOCALE)


static func _apply_bus(key: String) -> void:
	var index := AudioServer.get_bus_index(String(BUSES[key]))
	if index < 0:
		return # a test scene without the project's bus layout
	var linear := get_float(key)
	AudioServer.set_bus_volume_db(index, MUTED_DB if linear < SILENT_BELOW else linear_to_db(linear))


# --- Storage ---------------------------------------------------------------------

## Load once, on the first read of anything.
##
## A missing file is the normal first run. A corrupt one is a browser that was
## closed mid-write, and it is treated identically: the defaults, no warning,
## and the next write replaces it. There is nothing a player can do about a
## broken preferences file and nothing worth telling them.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not _persists():
		return
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for key: String in file.get_section_keys(SECTION) if file.has_section(SECTION) else []:
		# Only keys we know: a file from a later version must not put a
		# stray value where a caller expects a float.
		if DEFAULTS.has(key):
			_values[key] = _clamp(key, file.get_value(SECTION, key))


static func _save() -> void:
	if not _persists():
		return
	var file := ConfigFile.new()
	for key: Variant in _values:
		file.set_value(SECTION, String(key), _values[key])
	# The return is deliberately ignored. In a web export `user://` is
	# IndexedDB, and a private window refuses it; the game must still play, it
	# just forgets. Nothing here is worth a broken session.
	file.save(path)


## Keep a value inside its declared range and its default's type, so a
## hand-edited file cannot hand [Player] a sensitivity of 400.
static func _clamp(key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS.get(key)
	if fallback == null:
		return value
	if typeof(fallback) == TYPE_BOOL:
		return bool(value)
	if typeof(fallback) == TYPE_STRING:
		return String(value)
	if typeof(fallback) == TYPE_FLOAT or typeof(fallback) == TYPE_INT:
		var bounds: Dictionary = RANGES.get(key, {})
		var number := float(value) if (value is float or value is int) else float(fallback)
		if bounds.is_empty():
			return number
		return clampf(number, float(bounds["min"]), float(bounds["max"]))
	return value


## Forget everything that was loaded, without touching the file. Tests call it
## so one suite's sensitivity does not leak into the next; nothing else should
## need it.
static func forget() -> void:
	_values.clear()
	_loaded = false
