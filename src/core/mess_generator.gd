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


static func generate(rng_seed: int, catalog: Catalog, zones: Array, ground_y: float = 0.0) -> WorldState:
	assert(not zones.is_empty(), "MessGenerator needs at least one spawn zone")
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var state := WorldState.new()
	state.rng_seed = rng_seed
	for id in catalog.item_ids(): # sorted → deterministic
		var item := catalog.get_item(id)
		var zone := _pick_zone(rng, zones, item.category)
		var pos := _random_point_in_zone(rng, zone, ground_y)
		state.set_on_ground(id, pos)
	return state


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
