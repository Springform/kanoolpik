class_name MessGenerator
extends RefCounted
## Turns a seed + level definition into the starting [WorldState]: every
## catalog item scattered on the ground inside the level's spawn zones.
##
## Deterministic: same seed + same catalog + same zones = identical state on
## every peer, so multiplayer only needs to share the seed.
##
## Zone shape (from data/levels/*.json):
##   { "id": "camp", "center": [x, y, z], "radius": 4.0, "weight": 3.0,
##     "categories": ["can", "bottle"] }   # optional bias; empty = any item
## Items are assigned to zones by weighted pick among zones that allow their
## category, then given a uniformly random point in the zone disc (XZ plane).
##
## Exclusions keep items out of places the player cannot reach into — above all
## the containers themselves. Each is { "center": [x, y, z], "radius": float }.
## A point landing inside one is re-rolled, and if that keeps failing it is
## pushed radially out to the edge, so generation always terminates.


## How many times a blocked point is re-rolled before it is pushed out instead.
const MAX_REROLLS := 12

static func generate(rng_seed: int, catalog: Catalog, zones: Array, ground_y: float = 0.0, exclusions: Array = []) -> WorldState:
	assert(not zones.is_empty(), "MessGenerator needs at least one spawn zone")
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var state := WorldState.new()
	state.rng_seed = rng_seed
	for id in catalog.item_ids(): # sorted → deterministic
		var item := catalog.get_item(id)
		var zone := _pick_zone(rng, zones, item.category)
		var pos := _random_point_in_zone(rng, zone, ground_y)
		var tries := 0
		while _blocking_exclusion(exclusions, pos) != -1 and tries < MAX_REROLLS:
			pos = _random_point_in_zone(rng, zone, ground_y)
			tries += 1
		var blocker := _blocking_exclusion(exclusions, pos)
		if blocker != -1:
			pos = _push_out(exclusions[blocker], pos, ground_y)
		state.set_on_ground(id, pos)
	return state


## Circles the items must stay out of, one per container, from the level layout.
## [param margin] adds breathing room so an item never touches a container box.
static func container_exclusions(catalog: Catalog, container_positions: Dictionary, margin: float = 0.4) -> Array:
	var out: Array = []
	for cid in catalog.container_ids(): # sorted → deterministic
		if not container_positions.has(cid):
			continue
		var p: Array = container_positions[cid]
		out.append({
			"id": cid,
			"center": [float(p[0]), float(p[1]), float(p[2])],
			"radius": catalog.get_container(cid).footprint_radius() + margin,
		})
	return out


## Index of the first exclusion containing [param position], or -1.
static func _blocking_exclusion(exclusions: Array, position: Vector3) -> int:
	for i in range(exclusions.size()):
		if zone_contains(exclusions[i], position):
			return i
	return -1


## Move a blocked point straight out to just past the exclusion edge.
static func _push_out(exclusion: Dictionary, position: Vector3, ground_y: float) -> Vector3:
	var c: Array = exclusion.get("center", [0.0, 0.0, 0.0])
	var radius := float(exclusion.get("radius", 1.0))
	var away := Vector3(position.x - float(c[0]), 0.0, position.z - float(c[2]))
	if away.length() < 0.0001:
		away = Vector3(1, 0, 0) # dead centre: pick a fixed direction so it stays deterministic
	away = away.normalized() * (radius + 0.15)
	return Vector3(float(c[0]) + away.x, ground_y, float(c[2]) + away.z)


static func _pick_zone(rng: RandomNumberGenerator, zones: Array, category: String) -> Dictionary:
	var candidates: Array = []
	for z in zones:
		var cats: Array = z.get("categories", [])
		if cats.is_empty() or cats.has(category):
			candidates.append(z)
	if candidates.is_empty():
		candidates = zones
	var total := 0.0
	for z in candidates:
		total += float(z.get("weight", 1.0))
	var roll := rng.randf() * total
	for z in candidates:
		roll -= float(z.get("weight", 1.0))
		if roll <= 0.0:
			return z
	return candidates[candidates.size() - 1]


static func _random_point_in_zone(rng: RandomNumberGenerator, zone: Dictionary, ground_y: float) -> Vector3:
	var c: Array = zone.get("center", [0.0, 0.0, 0.0])
	var radius := float(zone.get("radius", 1.0))
	# sqrt for uniform density over the disc.
	var r := radius * sqrt(rng.randf())
	var angle := rng.randf() * TAU
	return Vector3(float(c[0]) + r * cos(angle), ground_y, float(c[2]) + r * sin(angle))


static func zone_contains(zone: Dictionary, position: Vector3) -> bool:
	var c: Array = zone.get("center", [0.0, 0.0, 0.0])
	var dx := position.x - float(c[0])
	var dz := position.z - float(c[2])
	return dx * dx + dz * dz <= pow(float(zone.get("radius", 1.0)), 2) + 0.0001
