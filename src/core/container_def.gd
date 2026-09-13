class_name ContainerDef
extends RefCounted
## Static definition of a place where items belong (the "shelf" of the island):
## the pant bag, the cooler, the dry bag, the canoe, the fire pit...
##
## Pure data — loaded from data/catalog/containers.json via [Catalog].

## Slot-tray geometry, shared by the level layout, the mess generator and
## [ContainerNode] so "how much room does this take" is defined exactly once.
##
## The slots are a tray hovering above the container, not a shelf built into it:
## roughly square, so twenty of them are a hand's reach across rather than a
## five-metre row. Before real models arrived they *were* the container, which
## is why a 34-slot pant bag used to be 8.8 m wide.
const SLOT_SPACING := 0.25
const EDGE_MARGIN := 0.3

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
## How the slots are arranged on the model: "grid" (default) or "ring" for
## things you gather round, like the fire pit. Presentation decides what the
## name means; the catalog only carries it.
var slot_layout: String = "grid"
## How tall this thing is in real life, in metres. Containers differ wildly in
## shape — a canoe is five metres long and knee-high, a bin bag is a metre of
## nothing but height — so fitting the longest axis to one box budget produced a
## five-metre bin bag. Height is the one dimension a person can state about a
## real object without measuring the mesh. 0.0 keeps the old longest-axis fit.
var model_height: float = 0.0
## Footprint radius in metres, when the model's is not what the slot count
## implies. 0.0 means "work it out from slot_count" (the placeholder rule).
## Whoever sets this has measured the fitted model; see WP-2.3.
var footprint: float = 0.0


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
	def.slot_layout = String(d.get("slot_layout", "grid"))
	def.model_height = maxf(0.0, float(d.get("model_height", 0.0)))
	def.footprint = maxf(0.0, float(d.get("footprint", 0.0)))
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
		"slot_layout": slot_layout,
		"model_height": model_height,
		"footprint": footprint,
	}


## Columns and rows of the slot tray: as square as the count allows.
func slot_columns() -> int:
	return maxi(1, ceili(sqrt(float(slot_count))))


func slot_rows() -> int:
	return maxi(1, ceili(float(slot_count) / slot_columns()))


## Width in metres of the slot tray (and of the placeholder box under it).
func width() -> float:
	return SLOT_SPACING * slot_columns() + EDGE_MARGIN


## Depth in metres of the slot tray.
func depth() -> float:
	return SLOT_SPACING * slot_rows() + EDGE_MARGIN


## Radius of a circle that covers the whole footprint — used to keep containers
## apart and to keep items from spawning inside one.
func footprint_radius() -> float:
	if footprint > 0.0:
		return footprint
	return sqrt(pow(width() * 0.5, 2) + pow(depth() * 0.5, 2))


func accepts_category(category: String) -> bool:
	return accepts.has(category)


func is_valid() -> bool:
	return not id.is_empty() and not accepts.is_empty() and slot_count > 0
