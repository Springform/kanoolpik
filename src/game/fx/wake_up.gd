class_name WakeUp
extends CanvasLayer
## The first seven seconds of a round: you come round face-down in a sleeping
## bag and the island resolves out of a blur (WP-5.4).
##
## [b]It is an overlay and nothing else.[/b] The world is already running
## underneath — the clock has started, the items are where the seed put them,
## and in multiplayer the host's round does not wait for anybody's animation.
## Skipping it therefore cannot leave anything half-initialised, because it
## initialises nothing. That is the whole of the design: a [CanvasLayer] on top
## of a game that does not know it is there.
##
## [b]Built in code, no `.tscn`.[/b] Four rects and a label, and a scene file is
## the one thing two agents cannot merge.
##
## [b]GL Compatibility, no threads[/b] (ADR 0007). Everything here is a
## [ColorRect] and a tween. The blur is one `canvas_item` shader reading
## `hint_screen_texture`, which Compatibility does support — verified by
## rendering it rather than by reading about it; see the work package. No
## post-process pass, no [Environment] depth of field, nothing that only exists
## on Forward+.

## Emitted when the intro is over, however it ended.
signal finished()

const LAYER := 8

## The whole thing, in seconds. Long enough to be a morning, short enough that
## the fifth restart of the evening is not a punishment — and it is skippable
## from the first frame anyway.
const DURATION := 7.0

## The eyelids, as a fraction of the screen each covers. Two blinks on the way
## up: a person coming round does not open their eyes once.
##
## Each entry is [time, how far the lids are apart, how blurred it is]. Read it
## as a storyboard, because that is what it is: a glimpse, a blink, a longer
## look, another blink, and then the island.
const FRAMES: Array = [
	{"at": 0.00, "open": 0.00, "blur": 1.00},
	{"at": 0.45, "open": 0.35, "blur": 1.00},
	{"at": 0.90, "open": 0.05, "blur": 1.00},
	{"at": 1.40, "open": 0.70, "blur": 0.80},
	{"at": 2.40, "open": 0.55, "blur": 0.65},
	{"at": 2.80, "open": 0.10, "blur": 0.75},
	{"at": 3.30, "open": 1.00, "blur": 0.45},
	{"at": 5.00, "open": 1.00, "blur": 0.18},
	{"at": DURATION, "open": 1.00, "blur": 0.00},
]

## A warm, heavy tint over everything, on its own curve: the inside of a tent at
## eight in the morning rather than a black screen.
const TINT := Color(0.16, 0.10, 0.06)
const TINT_ALPHA := 0.75
## When the tint has gone. Earlier than the blur, so the last couple of seconds
## are the island in its own colours, slightly soft.
const TINT_GONE := 4.0

## How far the blur reaches at full strength, as a fraction of the screen.
## Small: a nine-tap blur asked to reach further stops looking like a blur and
## starts looking like a mistake.
const BLUR_RADIUS := 0.010
## Mip level at full strength. Five halvings is a 60×34 picture of the island,
## which is about what a person sees through one eye a second after waking up.
const BLUR_LOD := 5.0

## The hint, once it is clear something is happening and before it gets old.
const HINT_AT := 1.2

const BLUR_SHADER := """
shader_type canvas_item;

// A mipmap IS a blur, and the back buffer has mipmaps the moment the sampler
// asks for them. One textureLod is therefore cheaper and smoother than any
// number of taps — and smoothness is the whole point here: a nine-tap square
// at this radius turned the grass into vertical stripes, which reads as a
// broken shader rather than as unfocused eyes. Four taps on top of the mip,
// because a mip alone is blocky at the level where it is doing real work.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float radius = 0.0;
uniform float lod = 0.0;

void fragment() {
	vec4 sum = vec4(0.0);
	vec2 offsets[4] = {vec2(-0.5, -0.5), vec2(0.5, -0.5), vec2(-0.5, 0.5), vec2(0.5, 0.5)};
	for (int i = 0; i < 4; i++) {
		vec2 at = clamp(SCREEN_UV + offsets[i] * radius, vec2(0.0), vec2(1.0));
		sum += textureLod(screen_texture, at, lod);
	}
	COLOR = sum * 0.25;
}
"""
var elapsed := 0.0
var _blur: ColorRect
var _tint: ColorRect
var _lid_top: ColorRect
var _lid_bottom: ColorRect
var _hint: Label
var _material := ShaderMaterial.new()


## Put one over [param parent] and start it, unless the player has asked not to
## see it. Returns null when it was skipped, so the caller has nothing to hold.
##
## [b]The setting is checked here, not inside[/b], so that `fx.intro = false`
## means the node is never built — not that it is built and draws nothing. One
## frame of blur is exactly what somebody who turned it off is complaining
## about.
static func install(parent: Node) -> WakeUp:
	if not Settings.get_bool(Settings.FX_INTRO):
		return null
	var made := WakeUp.new()
	made.name = "WakeUp"
	parent.add_child(made)
	return made


func _ready() -> void:
	layer = LAYER
	# It draws over a paused tree too: Esc during the intro should show the
	# pause menu over it rather than freeze it half-blinked.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material.shader = Shader.new()
	_material.shader.code = BLUR_SHADER

	_blur = _rect(Color.WHITE)
	_blur.material = _material
	_tint = _rect(TINT)
	_lid_top = _rect(Color.BLACK)
	_lid_bottom = _rect(Color.BLACK)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = tr("ui.intro.skip")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate = Color(1, 1, 1, 0)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -70.0
	_hint.offset_bottom = -30.0
	add_child(_hint)

	_apply(0.0)


func _rect(colour: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = colour
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	return rect


func _process(delta: float) -> void:
	elapsed += delta
	_apply(elapsed)
	if elapsed >= DURATION:
		finish()


## Any key, any button, any time — including the first frame. Nobody wants this
## on the fifth run of the evening, and a playtest is mostly restarts.
func _input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() \
			and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		get_viewport().set_input_as_handled()
		finish()


## End it, now, leaving nothing behind. Safe to call twice.
func finish() -> void:
	if is_queued_for_deletion():
		return
	finished.emit()
	queue_free()


func _apply(at: float) -> void:
	var frame := state_at(at)
	var open: float = frame["open"]
	var blur: float = frame["blur"]
	var height := float(get_viewport().get_visible_rect().size.y)
	# The lids meet in the middle and part from there, so the last thing to
	# arrive is the horizon rather than the sky.
	var lid := height * 0.5 * (1.0 - open)
	_lid_top.size.y = lid
	_lid_bottom.position.y = height - lid
	_lid_bottom.size.y = lid
	_material.set_shader_parameter("radius", blur * BLUR_RADIUS)
	_material.set_shader_parameter("lod", blur * BLUR_LOD)
	_tint.color = Color(TINT.r, TINT.g, TINT.b,
		TINT_ALPHA * clampf(1.0 - at / TINT_GONE, 0.0, 1.0))
	if _hint != null:
		_hint.modulate.a = clampf((at - HINT_AT) * 2.0, 0.0, 1.0)


## Where the storyboard is at [param at] seconds, interpolated between frames.
##
## Static and pure so the shape of the thing — it starts shut, it blinks twice,
## it ends with nothing on the screen — is checked by arithmetic rather than by
## staring at seven seconds of video.
static func state_at(at: float) -> Dictionary:
	if at <= 0.0:
		return {"open": float(FRAMES[0]["open"]), "blur": float(FRAMES[0]["blur"])}
	for i in range(1, FRAMES.size()):
		var next: Dictionary = FRAMES[i]
		if at > float(next["at"]):
			continue
		var previous: Dictionary = FRAMES[i - 1]
		var span := float(next["at"]) - float(previous["at"])
		var t := 1.0 if span <= 0.0 else (at - float(previous["at"])) / span
		# Smoothstep, because an eyelid does not move at a constant speed and a
		# linear one reads as a shutter.
		t = t * t * (3.0 - 2.0 * t)
		return {
			"open": lerpf(float(previous["open"]), float(next["open"]), t),
			"blur": lerpf(float(previous["blur"]), float(next["blur"]), t),
		}
	return {"open": 1.0, "blur": 0.0}
