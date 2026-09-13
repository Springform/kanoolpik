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
var model: String = "" ## Optional res:// path to a 3D scene for presentation.


static func from_dict(d: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id = String(d.get("id", ""))
	def.category = String(d.get("category", ""))
	def.series = String(d.get("series", ""))
	def.sequence = int(d.get("sequence", 0))
	def.size = maxi(1, int(d.get("size", 1)))
	def.name_key = String(d.get("name_key", "item.%s" % def.id))
	def.model = String(d.get("model", ""))
	return def


func to_dict() -> Dictionary:
	return {
		"id": id,
		"category": category,
		"series": series,
		"sequence": sequence,
		"size": size,
		"name_key": name_key,
		"model": model,
	}


func is_valid() -> bool:
	if id.is_empty() or category.is_empty():
		return false
	if sequence > 0 and series.is_empty():
		return false
	return true


func is_ordered() -> bool:
	return not series.is_empty() and sequence > 0
