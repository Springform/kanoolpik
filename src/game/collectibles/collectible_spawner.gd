class_name CollectibleSpawner
extends Node3D
## Puts the four hidden things on the island and notices when somebody walks
## into one (WP-3.7).
##
## Where they hide is level data, hand-authored in `data/levels/*.json` under
## `collectibles` — not generated. A hiding place only reads as a hiding place
## if a person chose it, so the spawner places exactly what the level says and
## invents nothing. The only thing it computes is the height: the level stores
## a flat x/z (Y is presentation, like the player spawns), and the spawner drops
## it onto the terrain with [method Island.height_at] so nothing floats or sinks.
##
## Finding is a flat distance test against the local player, run per frame, not
## an [Area3D]: a collectible has no collider at all (see [Collectible]), and a
## trigger volume that can catch the player on a container edge is exactly the
## frustration this WP is supposed to avoid. Walking near it is enough.
##
## It owns no state. The find goes through [method Commands.collect] like every
## other change, so the core refuses the second one, the save carries it, and a
## future multiplayer client gets the same event everybody else does.
##
## Lifetime: installed on [Main] next to the abilities, and freed with them on
## restart. [method clear] uses `free()` rather than `queue_free()` — a queued
## node is still an orphan when the suite counts.

## Level-data key holding the hand-authored placements.
const LEVEL_KEY := "collectibles"
## How near you have to get. Roughly [member Player.interact_distance], so a
## collectible you can see and walk up to is a collectible you have found — no
## aiming, no button, nothing to discover about the controls.
const FIND_RADIUS := 1.5
## Vertical slack on the same test. Flat distance alone would let you collect
## something from the top of the hill above it; this keeps it to the same ground.
const FIND_HEIGHT := 3.0
const TOAST_SECONDS := 3.5

## collectible_id -> Collectible node currently on the island.
var _nodes: Dictionary = {}
var _island: Island
var _player: Node3D


## Put a spawner under [param parent], replacing one that is already there.
## Idempotent for the same reason [method InsightAbility.install] is: [Main]
## rebuilds the playing scene on restart, and a second spawner would mean two
## trolleys in the same bush and a doubled toast.
static func install(parent: Node) -> CollectibleSpawner:
	for existing: Node in parent.get_children():
		if existing is CollectibleSpawner:
			parent.remove_child(existing)
			existing.free()
	var spawner := CollectibleSpawner.new()
	spawner.name = "CollectibleSpawner"
	parent.add_child(spawner)
	return spawner


## The hand-authored placements in [param level], in file order.
static func placements(level: Dictionary) -> Array:
	var out: Array = []
	for entry: Variant in level.get(LEVEL_KEY, []):
		if entry is Dictionary:
			out.append(entry)
	return out


func _ready() -> void:
	_island = _find_island()
	_build()
	GameEvents.collectible_found.connect(_on_collectible_found)
	GameEvents.local_player_spawned.connect(_on_local_player_spawned)
	set_process(not _nodes.is_empty())


func _exit_tree() -> void:
	clear()


func _process(_delta: float) -> void:
	check_for_finds()


# --- Public ------------------------------------------------------------------------

## Ids still on the island, sorted. Deterministic order for tests and diffs.
##
## Between levels there is no progression to ask, and nothing has been found —
## the next level's state decides that, not this one's leftovers.
func remaining_ids() -> Array[String]:
	var found := GameSession.progression
	var out: Array[String] = []
	for id: String in _nodes.keys():
		if found == null or not found.has_found(id):
			out.append(id)
	out.sort()
	return out


## The node for [param collectible_id], or null when the level does not place it.
func node_for(collectible_id: String) -> Collectible:
	return _nodes.get(collectible_id) as Collectible


## Every placed node, sorted by id.
func nodes() -> Array[Collectible]:
	var out: Array[Collectible] = []
	for id: String in _sorted_ids():
		out.append(_nodes[id])
	return out


## One pass of "is the local player standing on top of one of these". Public
## because a headless test cannot walk, it can only put the player somewhere and
## ask — and because a find must not depend on a frame having been rendered.
##
## Submits at most one find per pass: two toasts in one frame read as one.
func check_for_finds() -> void:
	if not GameSession.is_running():
		return
	var player := local_player()
	if player == null:
		return
	var pid := GameSession.local_player_id()
	for id: String in remaining_ids():
		var node: Collectible = _nodes[id]
		if _within_reach(player.global_position, node.global_position):
			GameSession.submit(Commands.collect(pid, id))
			return


## The local player node, looked up lazily and cached. Null before one spawns.
func local_player() -> Node3D:
	if is_instance_valid(_player):
		return _player
	_player = null
	if is_inside_tree():
		_player = get_tree().get_first_node_in_group(Player.LOCAL_GROUP) as Node3D
	return _player


## Take every collectible off the island, now. `free()` and not `queue_free()`:
## a queued node is still an orphan when the suite counts them, and the parent
## it hangs off may be gone before the queue is flushed.
func clear() -> void:
	for id: String in _nodes.keys():
		var node: Variant = _nodes[id]
		if is_instance_valid(node):
			var doomed := node as Node
			var parent := doomed.get_parent()
			if parent != null:
				parent.remove_child(doomed)
			doomed.free()
	_nodes.clear()
	set_process(false)


# --- Internals ---------------------------------------------------------------------

func _build() -> void:
	if not GameSession.is_running():
		return
	var index := 0
	for entry: Dictionary in placements(GameSession.level):
		var id := String(entry.get("id", ""))
		if not Progression.COLLECTIBLES.has(id):
			push_warning("Level places unknown collectible '%s'" % id)
			continue
		if _nodes.has(id):
			push_warning("Level places collectible '%s' twice" % id)
			continue
		var node := Collectible.new()
		node.setup(id, float(index) * 0.6)
		node.name = "Collectible_" + id
		node.position = _ground_position(entry)
		add_child(node)
		# A resumed save may already have this one; it must not be back in the bush.
		node.set_found(GameSession.progression.has_found(id))
		_nodes[id] = node
		index += 1


## The authored x/z, dropped onto the terrain. The level's Y is ignored the way
## the player spawns' is — the terrain is generated, so only the ground knows
## how high the ground is.
func _ground_position(entry: Dictionary) -> Vector3:
	var p: Array = entry.get("position", [0, 0, 0])
	var x := float(p[0])
	var z := float(p[2])
	var y := float(p[1]) if p.size() > 1 else 0.0
	if _island != null:
		y = _island.height_at(x, z)
	return Vector3(x, y, z)


func _within_reach(player_at: Vector3, thing_at: Vector3) -> bool:
	if absf(player_at.y - thing_at.y) > FIND_HEIGHT:
		return false
	return Vector2(player_at.x - thing_at.x, player_at.z - thing_at.z).length() <= FIND_RADIUS


func _sorted_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _nodes.keys():
		out.append(id)
	out.sort()
	return out


func _find_island() -> Island:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_root().find_children("*", "Island", true, false):
		return node as Island
	return null


func _on_local_player_spawned(player: Node3D) -> void:
	_player = player


## Fires for any player's find, including a remote one later: everybody watches
## the thing leave the island, and everybody reads the same line about it.
func _on_collectible_found(collectible_id: String, _player_id: int) -> void:
	var node: Collectible = _nodes.get(collectible_id)
	if node != null:
		node.set_found(true)
	_announce(collectible_id)


func _announce(collectible_id: String) -> void:
	var entry: Dictionary = Progression.COLLECTIBLES.get(collectible_id, {})
	var name_key := String(entry.get("name_key", ""))
	if name_key.is_empty():
		return
	_say(tr("ui.collectible.found") % tr(name_key))
	if GameSession.progression.found_collectibles().size() == Progression.COLLECTIBLES.size():
		_say(tr("ui.collectible.found_all"))


## Brief feedback through the HUD's own toast queue. The HUD belongs to another
## WP, so this calls its public API and touches nothing else — the same seam
## [InsightAbility] uses.
func _say(text: String) -> void:
	var hud := _find_hud()
	if hud != null:
		hud.show_toast(text, TOAST_SECONDS, HUD.COLOR_INFO)


func _find_hud() -> HUD:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_root().find_children("*", "HUD", true, false):
		return node as HUD
	return null
