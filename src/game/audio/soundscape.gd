extends Node
## Autoload "Soundscape" (WP-2.6): ambience plus layered music that thickens as
## the island gets cleaner, and stays silent (except ambience) whenever no
## level is running — the title screen gets the lake, not the band.
##
## All audio here is synthesised in-repo by tools/gen_ambience.py and
## tools/gen_music.py (ADR 0008: no downloaded assets). Regenerate with
## `python3 tools/gen_ambience.py && python3 tools/gen_music.py`.
##
## Everything plays on named buses (Music / Ambience; SFX belongs to whoever
## plays it) so a settings screen can control volume per category later.
##
## Provides for later phases: [method set_intensity], [method mute],
## [method set_layer_muted] — "layer control" per the WP-2.6 interface.
##
## Design note: [method target_gain] and [method ambience_target_gain] are
## pure functions of the current state (intensity, mute flags, whether a
## level is running) — tests assert against them directly and instantly.
## The actual audible crossfade ([method refresh] tweening [member
## AudioStreamPlayer.volume_db] toward that target) is a presentation detail
## tests deliberately do not depend on, per the WP: mixing logic must not be
## timing-dependent, only the polish of getting there is.

const MUSIC_BUS := "Music"
const AMBIENCE_BUS := "Ambience"

const AMBIENCE_PATH := "res://assets/audio/ambience/lake_morning.wav"
const MUSIC_PATHS: Array[String] = [
	"res://assets/audio/music/stem_pad.wav",
	"res://assets/audio/music/stem_melody.wav",
	"res://assets/audio/music/stem_shimmer.wav",
]

## How long a volume change takes to glide to its new target. Long enough to
## be a crossfade, short enough that a burst of placements still feels alive.
const CROSSFADE_SECONDS := 1.5
const SILENT_DB := -80.0

var _ambience: AudioStreamPlayer
var _stems: Array[AudioStreamPlayer] = []
var _stem_muted: Array[bool] = []

var _intensity := 0.0
var _muted := false
var _level_loaded := false

## Audible volume right now, one entry per stem plus a trailing one for
## ambience (index [method layer_count]) — chased toward its target each
## frame in [method _advance]. Kept separate from the target so smoothing is
## purely a presentation detail nothing tests against (see file docs).
var _current_gain: Array[float] = []


func _ready() -> void:
	_ambience = _make_player(AMBIENCE_BUS, AMBIENCE_PATH)
	for path in MUSIC_PATHS:
		_stems.append(_make_player(MUSIC_BUS, path))
		_stem_muted.append(false)
	_current_gain.resize(_stems.size() + 1)
	_current_gain.fill(0.0)
	GameEvents.level_loaded.connect(_on_level_loaded)
	GameEvents.progress_changed.connect(_on_progress_changed)
	refresh()


func _process(delta: float) -> void:
	refresh()
	_advance(delta)


func _exit_tree() -> void:
	_ambience.stop()
	_ambience.stream = null
	for p in _stems:
		p.stop()
		p.stream = null


func _make_player(bus: String, stream_path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	var stream: Resource = load(stream_path)
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	p.stream = stream
	add_child(p)
	return p


# --- Public API (Provides) --------------------------------------------------

## Directly set music intensity (0..1). GameEvents.progress_changed normally
## drives this; a settings screen or test may call it too.
func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	refresh()


func intensity() -> float:
	return _intensity


## Mute (or restore) both the Music and Ambience buses. SFX is untouched.
func mute(should_mute: bool) -> void:
	_muted = should_mute
	refresh()


func is_muted() -> bool:
	return _muted


## Per-stem control, e.g. a future "ambience only" toggle.
func set_layer_muted(index: int, should_mute: bool) -> void:
	if index >= 0 and index < _stem_muted.size():
		_stem_muted[index] = should_mute
		refresh()


func layer_count() -> int:
	return _stems.size()


## The music stem player at [param index] — read-only access for tests and
## debug tooling; nothing outside this file should ever set its properties.
func stem_player(index: int) -> AudioStreamPlayer:
	return _stems[index]


## The ambience player — read-only access, see [method stem_player].
func ambience_player() -> AudioStreamPlayer:
	return _ambience


## Target linear gain (0..1) for music stem [param index] right now: 0 whenever
## muted (globally or per-layer) or no level is running, otherwise the mix
## curve from [MusicMix] at the current intensity. Pure and instant — no
## audio node or timing involved.
func target_gain(index: int) -> float:
	if _muted or _stem_muted[index] or not GameSession.is_running():
		return 0.0
	return MusicMix.stem_gain(index, _intensity)


## Target linear gain for the ambience bed: always on once a level has loaded,
## unless muted. Ambience is not gated by is_running() — the title screen
## still hears the lake.
func ambience_target_gain() -> float:
	return 0.0 if _muted else 1.0


# --- Event handlers ----------------------------------------------------------

func _on_level_loaded(_level_id: String) -> void:
	_level_loaded = true
	refresh()


func _on_progress_changed(progress: Dictionary) -> void:
	var completion: float = float(progress.get("completion", 0.0))
	set_intensity(completion)


# --- Mixing --------------------------------------------------------------------

## Recompute bus mute state and make sure loaded layers are looping.
## Idempotent and instant — called every frame for real playback, and safe to
## call directly (as tests do) so nothing has to wait for a frame to pass.
func refresh() -> void:
	var music_idx := AudioServer.get_bus_index(MUSIC_BUS)
	if music_idx >= 0:
		AudioServer.set_bus_mute(music_idx, _muted)
	var ambience_idx := AudioServer.get_bus_index(AMBIENCE_BUS)
	if ambience_idx >= 0:
		AudioServer.set_bus_mute(ambience_idx, _muted)
	if _level_loaded:
		if not _ambience.playing:
			_ambience.play()
		for p in _stems:
			if not p.playing:
				p.play()


## Glide every player's audible volume toward its current target by [param
## delta] seconds' worth of an exponential approach — a crossfade, not a step,
## without owning a Tween per volume change. Real gameplay calls this every
## frame from [method _process]; nothing in the test suite depends on it.
func _advance(delta: float) -> void:
	var rate := 1.0 - exp(-delta / CROSSFADE_SECONDS)
	_current_gain[_stems.size()] = lerpf(_current_gain[_stems.size()], ambience_target_gain(), rate)
	_apply_gain(_ambience, _current_gain[_stems.size()])
	for i in range(_stems.size()):
		_current_gain[i] = lerpf(_current_gain[i], target_gain(i), rate)
		_apply_gain(_stems[i], _current_gain[i])


func _apply_gain(player: AudioStreamPlayer, gain: float) -> void:
	player.volume_db = SILENT_DB if gain <= 0.0001 else linear_to_db(gain)
