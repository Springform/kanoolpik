class_name PlacementRules
extends RefCounted
## The three-layer "does this belong here?" check, plus container completion.
##
## Layer 1  category  — the container must accept the item's category.
## Layer 2  series    — all items of a series must share ONE container.
## Layer 3  sequence  — in an ordered container, a series' sequence numbers
##                      must increase left-to-right with slot index.
##
## Stateless: every function takes the [Catalog] and [WorldState] explicitly so
## it can be unit tested exhaustively and reused on host and clients alike.

enum Verdict {
	CORRECT,
	WRONG_CATEGORY,
	SPLIT_SERIES,
	WRONG_ORDER,
	SLOT_OCCUPIED,
	INVALID_SLOT,
	UNKNOWN_ITEM,
	UNKNOWN_CONTAINER,
}


static func verdict_name(v: int) -> String:
	return Verdict.keys()[v]


## Evaluate placing [param item_id] into [param container_id] at [param slot],
## given the current [param state] (the item itself is ignored if already placed
## there, so this can also re-validate existing placements).
static func evaluate(catalog: Catalog, state: WorldState, item_id: String, container_id: String, slot: int) -> int:
	var item := catalog.get_item(item_id)
	if item == null:
		return Verdict.UNKNOWN_ITEM
	var container := catalog.get_container(container_id)
	if container == null:
		return Verdict.UNKNOWN_CONTAINER
	if slot < 0 or slot >= container.slot_count:
		return Verdict.INVALID_SLOT
	var occupant := state.item_in_slot(container_id, slot)
	if not occupant.is_empty() and occupant != item_id:
		return Verdict.SLOT_OCCUPIED
	if not container.accepts_category(item.category):
		return Verdict.WRONG_CATEGORY
	if not item.series.is_empty():
		for member in catalog.series_members(item.series):
			if member.id == item_id:
				continue
			var other_container := state.container_of(member.id)
			if not other_container.is_empty() and other_container != container_id:
				return Verdict.SPLIT_SERIES
		if container.ordered and item.sequence > 0:
			for entry in state.items_in_container(container_id):
				var other_id: String = entry["item_id"]
				if other_id == item_id:
					continue
				var other := catalog.get_item(other_id)
				if other == null or other.series != item.series or other.sequence <= 0:
					continue
				var other_slot: int = entry["slot"]
				var slot_before := other_slot < slot
				var seq_before := other.sequence < item.sequence
				if slot_before != seq_before:
					return Verdict.WRONG_ORDER
	return Verdict.CORRECT


## Re-check every item currently placed in the container.
## Returns Dictionary item_id -> Verdict.
static func verdicts_in_container(catalog: Catalog, state: WorldState, container_id: String) -> Dictionary:
	var out := {}
	for entry in state.items_in_container(container_id):
		out[entry["item_id"]] = evaluate(catalog, state, entry["item_id"], container_id, entry["slot"])
	return out


## Every item that has nowhere else to go: this container is the only one that
## accepts its category, so it cannot be packed until they are all here.
##
## Items whose category several containers accept are not required anywhere in
## particular — for those, the series rule in [method is_container_complete]
## still keeps a series from being split.
static func required_items(catalog: Catalog, container_id: String) -> Array[String]:
	var container := catalog.get_container(container_id)
	var out: Array[String] = []
	if container == null:
		return out
	for id in catalog.item_ids():
		var item := catalog.get_item(id)
		if container.accepts_category(item.category) and catalog.containers_accepting(item.category).size() == 1:
			out.append(id)
	return out


## A container is complete when every item that belongs in it is in it, and
## every item in it is CORRECT.
##
## "Belongs in it" is [method required_items] — NOT merely "the series present
## are whole". An item without a series (the tent canvas, the schnapps bottle,
## the napkins) would otherwise declare its container packed all by itself.
static func is_container_complete(catalog: Catalog, state: WorldState, container_id: String) -> bool:
	var entries := state.items_in_container(container_id)
	if entries.is_empty():
		return false
	var present := {}
	for entry in entries:
		var id: String = entry["item_id"]
		if evaluate(catalog, state, id, container_id, entry["slot"]) != Verdict.CORRECT:
			return false
		present[id] = true
	for id in required_items(catalog, container_id):
		if not present.has(id):
			return false
	# Items that could live in several containers still may not be split up.
	for entry in entries:
		var item := catalog.get_item(entry["item_id"])
		if item.series.is_empty():
			continue
		for member in catalog.series_members(item.series):
			if not present.has(member.id):
				return false
	return true


## The island is clean when every catalog item is placed and CORRECT.
static func is_island_clean(catalog: Catalog, state: WorldState) -> bool:
	for id in catalog.item_ids():
		var loc := state.location(id)
		if loc.get("kind", -1) != WorldState.Kind.PLACED:
			return false
		if evaluate(catalog, state, id, loc["container_id"], loc["slot"]) != Verdict.CORRECT:
			return false
	return true


## Convenience for abilities/hints: the first free slot in [param container_id]
## where [param item_id] would be CORRECT, or -1.
static func find_correct_slot(catalog: Catalog, state: WorldState, item_id: String, container_id: String) -> int:
	var container := catalog.get_container(container_id)
	if container == null:
		return -1
	for slot in range(container.slot_count):
		if evaluate(catalog, state, item_id, container_id, slot) == Verdict.CORRECT:
			return slot
	return -1
