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
var progression: Progression
var transport: Transport
var level: Dictionary = {}
var level_id: String = ""

var _running := false


func _physics_process(delta: float) -> void:
	if _running and transport != null and transport.is_authority():
		transport.tick(delta)


## Load catalog + level, generate the mess and wire a local (single-player) transport.
## Multiplayer will pass its own transport in phase 4.
func start_level(p_level_id: String, level_seed: int = -1, p_transport: Transport = null) -> void:
	level_id = p_level_id
	level = load_level(p_level_id)
	catalog = Catalog.load_from_files(ITEMS_PATH, CONTAINERS_PATH)
	var problems := catalog.validate()
	for p in problems:
		push_error("Catalog problem: %s" % p)
	var use_seed := int(level.get("seed_default", 0)) if level_seed < 0 else level_seed
	var exclusions := MessGenerator.container_exclusions(
		catalog, level.get("container_positions", {}), float(level.get("container_clearance", 0.4)))
	state = MessGenerator.generate(
		use_seed, catalog, level["spawn_zones"], float(level.get("ground_y", 0.0)), exclusions)
	processor = CommandProcessor.new(catalog)
	progression = Progression.new()
	transport = p_transport if p_transport != null else LocalTransport.new(processor, state)
	transport.command_applied.connect(_on_command_applied)
	transport.command_rejected.connect(_on_command_rejected)
	transport.state_replaced.connect(_on_state_replaced)
	state.add_player(transport.local_player_id(), base_capacity())
	_running = true
	GameEvents.level_loaded.emit(level_id)
	_emit_progress()


func stop_level() -> void:
	_running = false


func local_player_id() -> int:
	return transport.local_player_id() if transport != null else 1


func submit(command: Dictionary) -> void:
	assert(_running, "No level running")
	transport.submit_command(command)


func base_capacity() -> int:
	return 3 + (progression.capacity_bonus() if progression != null else 0)


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
	for event in result["events"]:
		if event["type"] == "container_completed":
			progression.credit_container(event["container_id"])
		GameEvents.publish(event)
	if result["events"].size() > 0 and result["events"][0]["type"] != "ticked":
		_emit_progress()


func _on_command_rejected(command: Dictionary, error: String) -> void:
	GameEvents.command_rejected.emit(command, error)


func _on_state_replaced(new_state: WorldState) -> void:
	state = new_state
	_emit_progress()


func _emit_progress() -> void:
	GameEvents.progress_changed.emit(Evaluation.progress(catalog, state))
