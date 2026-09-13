class_name ItemDef
extends RefCounted
## Static definition of a physical thing that can be lying around on the island.
##
## Pure data — no Node dependencies. Loaded from data/catalog/items.json via [Catalog].
##
## The three rule layers (mirroring the reference game's section → series → volume):
##  - [member category]  decides WHICH container the item belongs in.
##  - [member series]    groups items that must end up in the SAME container
##                       (e.g. all four tent poles, all cans of the same brand).
##  - [member sequence]  orders items within a series (0 = unordered).

var id: String
var category: String
var series: String = ""
var sequence: int = 0
var size: int = 1 ## Carry slots this item consumes.
var name_key: String = "" ## i18n key; defaults to "item.<id>".
var model: String = "" ## Optional res:// path to a .glb; empty means the generated box.
## Nudge on top of the automatic fit: 1.2 = a fifth bigger than the size the
## loader picked, 0.8 = a fifth smaller. 0.0 (the default) means no nudge.
## Never a raw multiplier — asset-library models arrive in arbitrary units, so
## tuning by eye must not require knowing that a log is 43 units long.
var model_scale: float = 0.0
var model_rotation: float = 0.0 ## Degrees around Y, for models that face the wrong way.
## Optional "#rrggbb" so one model can serve many items. Empty means the
## category colour for a placeholder, and the model's own colours for a model.
var tint: String = ""


static func from_dict(d: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id = String(d.get("id", ""))
	def.category = String(d.get("category", ""))
	def.series = String(d.get("series", ""))
	def.sequence = int(d.get("sequence", 0))
	def.size = maxi(1, int(d.get("size", 1)))
	def.name_key = String(d.get("name_key", "item.%s" % def.id))
	def.model = String(d.get("model", ""))
	def.model_scale = maxf(0.0, float(d.get("model_scale", 0.0)))
	def.model_rotation = float(d.get("model_rotation", 0.0))
	def.tint = String(d.get("tint", ""))
	return def


## The colour to paint this item: its own tint when it has one, otherwise the
## category colour. Presentation calls this; the catalog stays a plain string.
func tint_color(fallback: Color) -> Color:
	return Color(tint) if not tint.is_empty() and Color.html_is_valid(tint) else fallback


func to_dict() -> Dictionary:
	return {
		"id": id,
		"category": category,
		"series": series,
		"sequence": sequence,
		"size": size,
		"name_key": name_key,
		"model": model,
		"model_scale": model_scale,
		"model_rotation": model_rotation,
		"tint": tint,
	}


func is_valid() -> bool:
	if id.is_empty() or category.is_empty():
		return false
	if sequence > 0 and series.is_empty():
		return false
	return true


func is_ordered() -> bool:
	return not series.is_empty() and sequence > 0
