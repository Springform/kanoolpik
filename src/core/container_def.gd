class_name ContainerDef
extends RefCounted
## Static definition of a place where items belong (the "shelf" of the island):
## the pant bag, the cooler, the dry bag, the canoe, the fire pit...
##
## Pure data — loaded from data/catalog/containers.json via [Catalog].

var id: String
var accepts: Array[String] = [] ## Item categories this container is the correct home for.
var slot_count: int = 8
var ordered: bool = false ## If true, series sequence must increase with slot index.
var name_key: String = ""
var scene: String = "" ## Optional res:// path to a 3D scene for presentation.


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
	return def


func to_dict() -> Dictionary:
	return {
		"id": id,
		"accepts": accepts.duplicate(),
		"slot_count": slot_count,
		"ordered": ordered,
		"name_key": name_key,
		"scene": scene,
	}


func accepts_category(category: String) -> bool:
	return accepts.has(category)


func is_valid() -> bool:
	return not id.is_empty() and not accepts.is_empty() and slot_count > 0
