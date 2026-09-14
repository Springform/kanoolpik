class_name SummonAnimator
extends Node
## Flies summoned items to where the simulation already put them (WP-3.4).
##
## **This node never reads input.** It reacts to
## [signal GameEvents.item_summoned] and nothing else, which is the whole point
## of the work package: the `summon` command moved the item the instant it
## applied, so the arc is pure presentation catching up. Because the event — not
## the keypress — starts the flight, a shout by another player in phase 4
## animates here for free, and a test can prove the animation works without
## pressing anything.
##
## Nothing here mutates the world: it writes a [PickupItem]'s transform and
## reads [GameSession] read-only, like every other scene.

## Matches the lift [Island] gives an item when it first spawns one, so a
## summoned paddle sits on the grass exactly like a scattered one.
const LANDING_LIFT := 0.15

## item_id -> { node: PickupItem, from: Vector3, to: Vector3, spin_from: float, elapsed: float }
var _flights: Dictionary = {}
## item_id -> PickupItem. Rebuilt when a level loads, or when a cached node has
## gone (a restart throws every item node away and builds new ones).
var _items: Dictionary = {}
var _island: Island


func _ready() -> void:
	GameEvents.item_summoned.connect(_on_item_summoned)
	GameEvents.level_loaded.connect(_on_level_loaded)


func _process(delta: float) -> void:
	advance(delta)


# --- Public API --------------------------------------------------------------

## Move every flight on by [param delta] seconds. Public so tests can step the
## animation exactly rather than awaiting frames — the same trick [Soundscape]
## uses, and for the same reason: timing is polish, the positions are the
## contract.
func advance(delta: float) -> void:
	for key in _flights.keys():
		var item_id := String(key)
		var flight: Dictionary = _flights[item_id]
		var node: PickupItem = flight["node"]
		# A mate can grab a summoned item out of the air; once it is no longer
		# on the ground the item node belongs to whoever holds it, not to us.
		if not is_instance_valid(node) or not _is_on_the_ground(item_id):
			_flights.erase(item_id)
			continue
		var elapsed: float = float(flight["elapsed"]) + delta
		flight["elapsed"] = elapsed
		var t := clampf(elapsed / SummonArc.FLIGHT_SECONDS, 0.0, 1.0)
		var spin_from: float = flight["spin_from"]
		var from: Vector3 = flight["from"]
		var to: Vector3 = flight["to"]
		node.global_position = SummonArc.point(from, to, t)
		node.rotation.y = spin_from + SummonArc.spin(t)
		if t >= 1.0:
			# Land exactly on the decided spot, not on wherever the last frame
			# happened to sample: the visual must agree with the world state.
			node.global_position = to
			node.rotation.y = spin_from
			_flights.erase(item_id)


func is_flying(item_id: String) -> bool:
	return _flights.has(item_id)


func flight_count() -> int:
	return _flights.size()


## Where [param item_id] is heading, or [constant Vector3.INF] when it is not
## in the air.
func flight_target(item_id: String) -> Vector3:
	if not _flights.has(item_id):
		return Vector3.INF
	var flight: Dictionary = _flights[item_id]
	var to: Vector3 = flight["to"]
	return to


## The spot an item summoned to [param position] should come to rest on: the
## core decided the x/z (and clamped them to the island), the terrain decides
## the height. Without this an item summoned onto the central dome lands at
## ground_y — which is inside the hill.
func landing_point(position: Vector3) -> Vector3:
	var island := _island_node()
	if island == null:
		return position + Vector3(0.0, LANDING_LIFT, 0.0)
	return Vector3(position.x, island.height_at(position.x, position.z) + LANDING_LIFT, position.z)


## The [PickupItem] drawing [param item_id], or null when no scene shows it.
func item_node(item_id: String) -> PickupItem:
	var cached := _items.get(item_id) as PickupItem
	if is_instance_valid(cached) and cached.is_inside_tree():
		return cached
	_rebuild_index()
	return _items.get(item_id) as PickupItem


# --- Event handlers ----------------------------------------------------------

func _on_item_summoned(item_id: String, _player_id: int, position: Vector3) -> void:
	var node := item_node(item_id)
	if node == null:
		return
	_flights[item_id] = {
		"node": node,
		"from": node.global_position,
		"to": landing_point(position),
		"spin_from": node.rotation.y,
		"elapsed": 0.0,
	}


func _on_level_loaded(_level_id: String) -> void:
	_flights.clear()
	_items.clear()
	_island = null


# --- Finding the scene -------------------------------------------------------

func _is_on_the_ground(item_id: String) -> bool:
	if GameSession.state == null or not GameSession.state.has_item(item_id):
		return false
	return GameSession.state.kind_of(item_id) == WorldState.Kind.GROUND


func _island_node() -> Island:
	if not is_instance_valid(_island) or not _island.is_inside_tree():
		_rebuild_index()
	return _island if is_instance_valid(_island) else null


## One walk of the tree, by type rather than by node name: this feature owns
## neither [Island] nor [PickupItem] and should not depend on what they call
## their children. Cheap enough at a couple of hundred nodes, and done once per
## level rather than once per event.
func _rebuild_index() -> void:
	_items.clear()
	_island = null
	if not is_inside_tree():
		return
	_scan(get_tree().root)


func _scan(node: Node) -> void:
	if node is PickupItem:
		_items[(node as PickupItem).item_id] = node
		return # nothing interesting below an item
	if node is Island:
		_island = node
	for child in node.get_children():
		_scan(child)
