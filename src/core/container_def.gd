class_name ContainerDef
extends RefCounted
## Static definition of a place where items belong (the "shelf" of the island):
## the pant bag, the cooler, the dry bag, the canoe, the fire pit...
##
## Pure data — loaded from data/catalog/containers.json via [Catalog].

## Placeholder footprint, shared by the level layout, the mess generator and
## [ContainerNode] so "how much room does this take" is defined exactly once.
const SLOT_SPACING := 0.25
const EDGE_MARGIN := 0.3
const DEPTH := 0.8

var id: String
var accepts: Array[String] = [] ## Item categories this container is the correct home for.
var slot_count: int = 8
var ordered: bool = false ## If true, series sequence must increase with slot index.
var name_key: String = ""
var scene: String = "" ## Optional res:// path to a .glb; empty means the translucent box.
## Nudge on top of the automatic fit to the footprint: 1.2 = a fifth bigger,
## 0.8 = a fifth smaller. 0.0 (the default) means no nudge.
var model_scale: float = 0.0
var model_rotation: float = 0.0 ## Degrees around Y.


static func from_dict(d: Dictionary) -> ContainerDef:
	var def := ContainerDef.new()
	def.id = String(d.get("id", ""))
	var acc: Array[String] = []
	for c in d.get("accepts", []):
		acc.append(String(c))
	def.accepts = acc
	def.slot_count = maxi(1, int(d.get("slot_count", 8)))
	def.ordered = bool(d.get("ordered", false))
	def.name_key = String(d.get("name_key", "container.%s" % def.id))
	def.scene = String(d.get("scene", ""))
	def.model_scale = maxf(0.0, float(d.get("model_scale", 0.0)))
	def.model_rotation = float(d.get("model_rotation", 0.0))
	return def


func to_dict() -> Dictionary:
	return {
		"id": id,
		"accepts": accepts.duplicate(),
		"slot_count": slot_count,
		"ordered": ordered,
		"name_key": name_key,
		"scene": scene,
		"model_scale": model_scale,
		"model_rotation": model_rotation,
	}


## Width in metres of the placeholder box (grows with slot count).
func width() -> float:
	return SLOT_SPACING * slot_count + EDGE_MARGIN


## Radius of a circle that covers the whole footprint — used to keep containers
## apart and to keep items from spawning inside one.
func footprint_radius() -> float:
	return sqrt(pow(width() * 0.5, 2) + pow(DEPTH * 0.5, 2))


func accepts_category(category: String) -> bool:
	return accepts.has(category)


func is_valid() -> bool:
	return not id.is_empty() and not accepts.is_empty() and slot_count > 0
