class_name SlotLayout
extends RefCounted
## Where a container's slots sit, given the shape of whatever is actually drawn
## (WP-2.3).
##
## The placeholder box was easy: slots in one straight row along a lid whose
## width was invented from the slot count. A real model has its own size and its
## own proportions, and neither has anything to do with how many things you can
## put in it — so the slots are a tray that hovers above whatever is drawn,
## taking its height from the model and its shape from [ContainerDef].
##
## Two invariants the rest of the game leans on:
##
##   1. **Slots live above the model, never inside it.** [ContainerNode]'s body
##      collider covers the model, and a slot inside that box can never be hit
##      by the interaction ray — the box is in front of it (WP-1.3 learned this
##      the hard way). Everything here starts at `bounds` top + [constant LIFT].
##   2. **Spacing never drops below [constant MIN_SPACING].** Slots are the
##      thing you aim at; a tidy-looking row you cannot click is worse than a
##      loose one you can.

## Metres between neighbouring slots. Below this, aiming from 2-3 m stops working.
const MIN_SPACING := 0.25
## Gap between the top of the model and the first layer of slots.
const LIFT := 0.14
## Beyond this many slots a ring is a smear, so it falls back to the grid.
const MAX_RING := 12
## How far inside the model's silhouette a ring sits.
const RING_INSET := 0.12

enum Kind {
	GRID, ## A flat, roughly square tray hovering over the model.
	RING, ## A circle around the model — for things you gather round, like a fire.
}


## Layout named in the catalog. Unknown names fall back to the grid rather than
## failing: a typo in content data should not take a container out of the game.
static func kind_from(layout_name: String) -> Kind:
	return Kind.RING if layout_name == "ring" else Kind.GRID


## Slot positions in the container's own space, one per slot, in slot order.
##
## [param bounds] is the drawn model's box (see [method ItemVisual.combined_aabb]
## multiplied by its scale); [param def] supplies the tray's shape.
static func positions(def: ContainerDef, bounds: AABB) -> Array[Vector3]:
	var top := bounds.position.y + bounds.size.y + LIFT
	if kind_from(def.slot_layout) == Kind.RING and def.slot_count <= MAX_RING:
		return _ring(def.slot_count, bounds, top)
	return _grid(def, top)


# --- Layouts ----------------------------------------------------------------------

## Evenly around a circle just inside the model's silhouette — you put wood *on*
## the fire, not in a wreath around it — and inside matters for another reason:
## the space a container reserves on the island comes from
## [method ContainerDef.footprint_radius], and a slot outside that circle can
## have an item spawned on top of it. Slot 0 sits at the front (-Z) and they run
## clockwise, so an ordered container still reads left to right as you walk up.
static func _ring(count: int, bounds: AABB, top: float) -> Array[Vector3]:
	var radius := minf(bounds.size.x, bounds.size.z) * 0.5 - RING_INSET
	# Never let neighbours crowd closer than you can aim at.
	radius = maxf(radius, MIN_SPACING * count / TAU)
	var out: Array[Vector3] = []
	for i in range(count):
		var angle := TAU * i / count
		out.append(Vector3(sin(angle) * radius, top, -cos(angle) * radius))
	return out


## One flat tray of slots, centred over the model: left to right, then front to
## back, in the roughly-square shape [ContainerDef] works out.
##
## An earlier version sized the grid from the model and stacked upward when it
## ran out of room. On a real cooler that produced a four-metre tower of slot
## cubes. The tray is a UI affordance, not part of the object, so it takes its
## shape from the slot count and simply hovers.
static func _grid(def: ContainerDef, top: float) -> Array[Vector3]:
	var columns := def.slot_columns()
	var rows := def.slot_rows()
	var out: Array[Vector3] = []
	for i in range(def.slot_count):
		var column := i % columns
		var row := i / columns
		out.append(Vector3(
			(column - (columns - 1) * 0.5) * ContainerDef.SLOT_SPACING,
			top,
			(row - (rows - 1) * 0.5) * ContainerDef.SLOT_SPACING))
	return out
