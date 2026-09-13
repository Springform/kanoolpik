class_name VerdictStyle
extends RefCounted
## Single source of truth for how a placement verdict LOOKS.
## Used by containers (slot colours), HUD (toast colours) and later abilities.
##
## Colour-blind safety: good/bad differ in hue AND brightness, and wrong slots
## additionally carry an ✕ marker, so colour is never the only channel.

const COLOR_EMPTY := Color(1.0, 1.0, 1.0, 0.25)
const COLOR_CORRECT := Color(0.25, 0.85, 0.35) # bright green
const COLOR_WRONG := Color(0.75, 0.15, 0.15) # dark red
const COLOR_COMPLETE := Color(1.0, 0.82, 0.25) # gold
const COLOR_FLASH_GOOD := Color(1.0, 0.95, 0.6)
const COLOR_FLASH_BAD := Color(0.5, 0.05, 0.05)

const MARK_WRONG := "✕"
const MARK_COMPLETE := "✓"

## Shared materials (built once, reused by every slot mesh).
static var _materials: Dictionary = {}


static func is_good(verdict: int) -> bool:
	return verdict == PlacementRules.Verdict.CORRECT


static func color_for(verdict: int) -> Color:
	return COLOR_CORRECT if is_good(verdict) else COLOR_WRONG


static func material(kind: String) -> StandardMaterial3D:
	if not _materials.has(kind):
		var m := StandardMaterial3D.new()
		match kind:
			"empty":
				m.albedo_color = COLOR_EMPTY
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			"correct":
				m.albedo_color = COLOR_CORRECT
			"wrong":
				m.albedo_color = COLOR_WRONG
			"complete":
				m.albedo_color = COLOR_COMPLETE
				m.emission_enabled = true
				m.emission = COLOR_COMPLETE
				m.emission_energy_multiplier = 0.8
			_:
				m.albedo_color = Color.MAGENTA
		_materials[kind] = m
	return _materials[kind]


## i18n key for a verdict toast, e.g. "ui.verdict.wrong_order".
static func toast_key(verdict: int) -> String:
	return "ui.verdict." + PlacementRules.verdict_name(verdict).to_lower()
