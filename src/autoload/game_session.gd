extends Node
## Autoload "GameSession": owns the core objects for the running level and is
## the single entry point gameplay scenes use to act on the world.
##
##   GameSession.start_level("island_01", level_seed)
##   GameSession.submit(Commands.pick_up(GameSession.local_player_id(), item_id))
##   GameSession.state / .catalog / .progression   (read-only from outside)
##
## Everything flows: scene → submit() → Transport → CommandProcessor → events →
## GameEvents bus → scenes react. Scenes never mutate state directly.

const LEVELS_DIR := "res://data/levels/"
const ITEMS_PATH := "res://data/catalog/items.json"
const CONTAINERS_PATH := "res://data/catalog/containers.json"

var catalog: Catalog
var state: WorldState
var processor: CommandProcessor
var transport: Transport
var level: Dictionary = {}
var level_id: String = ""

## The party's skill points and abilities. Since ADR 0010 this lives inside the
## replicated [WorldState]; the accessor stays so callers did not have to change.
## Read it freely; change it only by submitting a command.
var progression: Progression:
	get:
		return state.progression if state != null else null

var _running := false
## Autosave after each container is packed. Tests turn this off.
var autosave_enabled := true


func _physics_process(delta: float) -> void:
	if _running and transport != null and transport.is_authority():
		transport.tick(delta)


## Load catalog + level, generate the mess and wire a local (single-player) transport.
## Multiplayer will pass its own transport in phase 4.
func start_level(p_level_id: String, level_seed: int = -1, p_transport: Transport = null) -> void:
	var lvl := load_level(p_level_id)
	var cat := Catalog.load_from_files(ITEMS_PATH, CONTAINERS_PATH)
	for p in cat.validate():
		push_error("Catalog problem: %s" % p)
	var use_seed := int(lvl.get("seed_default", 0)) if level_seed < 0 else level_seed
	var exclusions := MessGenerator.container_exclusions(
		cat, lvl.get("container_positions", {}), float(lvl.get("container_clearance", 0.4)))
	var fresh := MessGenerator.generate(
		use_seed, cat, lvl["spawn_zones"], float(lvl.get("ground_y", 0.0)), exclusions)
	_begin(p_level_id, lvl, cat, fresh, p_transport)


## Resume a saved run instead of generating a new mess.
## Returns false (changing nothing) when the slot is empty, corrupt or from an
## older schema — the caller can then simply start a new game.
func load_save(slot: String = SaveGame.DEFAULT_SLOT) -> bool:
	var unpacked := SaveGame.unpack(SaveGame.read(slot))
	if unpacked.is_empty():
		return false
	var saved_level_id: String = unpacked["level_id"]
	var lvl := load_level(saved_level_id)
	if lvl.is_empty():
		push_error("Save refers to an unknown level: %s" % saved_level_id)
		return false
	_begin(saved_level_id, lvl, Catalog.load_from_files(ITEMS_PATH, CONTAINERS_PATH),
		unpacked["state"], null)
	return true


## Write the running game to a slot. False when nothing is running or the write failed.
func save(slot: String = SaveGame.DEFAULT_SLOT) -> bool:
	if state == null or level_id.is_empty():
		return false
	return SaveGame.write(slot, SaveGame.pack(state, level_id))


func has_save(slot: String = SaveGame.DEFAULT_SLOT) -> bool:
	return SaveGame.has_save(slot)


## Shared tail of start_level and load_save: adopt these objects as the running game.
func _begin(p_level_id: String, p_level: Dictionary, p_catalog: Catalog,
		p_state: WorldState, p_transport: Transport) -> void:
	level_id = p_level_id
	level = p_level
	catalog = p_catalog
	state = p_state
	# The core clamps summoned items to walkable ground, so it needs to know
	# where the ground ends. A freshly generated state does not carry it.
	state.island_radius = island_radius()
	state.ground_y = ground_y()
	processor = CommandProcessor.new(catalog)
	transport = p_transport if p_transport != null else LocalTransport.new(processor, state)
	transport.command_applied.connect(_on_command_applied)
	transport.command_rejected.connect(_on_command_rejected)
	transport.state_replaced.connect(_on_state_replaced)
	# A loaded state already knows its players (and their earned capacity).
	if not state.has_player(transport.local_player_id()):
		state.add_player(transport.local_player_id(), base_capacity())
	_running = true
	GameEvents.level_loaded.emit(level_id)
	_emit_progress()


func stop_level() -> void:
	_running = false


## False once the level is over (or before one starts): nothing may act on the
## world, and the simulation clock no longer advances.
func is_running() -> bool:
	return _running


func local_player_id() -> int:
	return transport.local_player_id() if transport != null else 1


func submit(command: Dictionary) -> void:
	assert(_running, "No level running")
	transport.submit_command(command)


func base_capacity() -> int:
	return progression.capacity() if progression != null else Progression.BASE_CAPACITY


static func load_level(p_level_id: String) -> Dictionary:
	var path := LEVELS_DIR + p_level_id + ".json"
	if not FileAccess.file_exists(path):
		push_error("Level not found: %s" % path)
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Radius of the walkable island; anything beyond it is water.
func island_radius() -> float:
	return float(level.get("island_radius", 16.0))


func ground_y() -> float:
	return float(level.get("ground_y", 0.0))


func container_position(container_id: String) -> Vector3:
	var p: Array = level.get("container_positions", {}).get(container_id, [0, 0, 0])
	return Vector3(p[0], p[1], p[2])


func player_spawn(index: int) -> Vector3:
	var spawns: Array = level.get("player_spawns", [[0, 1, 0]])
	var p: Array = spawns[index % spawns.size()]
	return Vector3(p[0], p[1], p[2])


func _on_command_applied(_command: Dictionary, result: Dictionary) -> void:
	var pack_completed := false
	for event in result["events"]:
		if event["type"] == "container_completed":
			pack_completed = true
		GameEvents.publish(event)
	# Autosave only at a natural milestone — never on a tick, never mid-placement.
	if pack_completed and autosave_enabled:
		save()
	if result["events"].size() > 0 and result["events"][0]["type"] != "ticked":
		_emit_progress()


func _on_command_rejected(command: Dictionary, error: String) -> void:
	GameEvents.command_rejected.emit(command, error)


func _on_state_replaced(new_state: WorldState) -> void:
	state = new_state
	_emit_progress()


func _emit_progress() -> void:
	GameEvents.progress_changed.emit(Evaluation.progress(catalog, state))
