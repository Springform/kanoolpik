class_name Player
extends CharacterBody3D
## First-person controller + interaction raycast for the LOCAL player.
##
## Owns nothing about game rules: it only turns input into [Commands] submitted
## through [GameSession].
##
## [b]Remote players do not reuse this scene[/b] — [RemoteAvatar] draws them
## instead (WP-4.5). This is a body that simulates itself from input, and a
## remote player's position is a fact that arrives on the wire; running both
## would give two answers to where somebody is standing. [member is_local] stays
## because tests and the shots harness want a player that does not grab the
## mouse.

## Group the local player joins so late-created UI can find it (the spawn signal may already have fired).
const LOCAL_GROUP := "local_player"

@export var is_local := true
@export var walk_speed := 4.5
@export var sprint_speed := 7.5
@export var jump_velocity := 4.8
@export var mouse_sensitivity := 0.0025
@export var interact_distance := 3.0
## Falling below this (relative to ground level) counts as being in the lake.
@export var water_depth := 2.0

var player_id: int = 1
## Where to put the player back after a swim. Set by whoever spawns the player.
var spawn_position := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _pitch := 0.0

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractRay
@onready var held_items: HeldItems = $Camera3D/HeldItems


func _ready() -> void:
	camera.current = is_local
	# WP-5.1: the two the player can change. Read here and re-read on change, so
	# dragging a slider moves the camera while it is being dragged — which is
	# the only way anybody finds the sensitivity that suits them.
	#
	# The acceleration, head bob and FOV kick that WP-5.2 adds go here too; this
	# is the hook, not the whole story.
	if is_local:
		_apply_settings()
		Settings.changed().connect(_on_settings_changed)
	ray.target_position = Vector3(0, 0, -interact_distance)
	set_process_input(is_local)
	set_physics_process(is_local)
	held_items.set_player(player_id)
	if spawn_position == Vector3.ZERO:
		spawn_position = global_position
	if is_local:
		add_to_group(LOCAL_GROUP)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		GameEvents.local_player_spawned.emit(self)


## An empty key means "everything changed" — see [method Settings.reset].
func _on_settings_changed(key: String) -> void:
	if key.is_empty() or key == Settings.LOOK_SENSITIVITY or key == Settings.LOOK_FOV:
		_apply_settings()


func _apply_settings() -> void:
	mouse_sensitivity = Settings.get_float(Settings.LOOK_SENSITIVITY)
	camera.fov = Settings.get_float(Settings.LOOK_FOV)


func _input(event: InputEvent) -> void:
	if not GameSession.is_running():
		return # level over (or not started): the evaluation screen has the stage
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.4)
		camera.rotation.x = _pitch
	if event.is_action_pressed("ui_toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("interact"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		_interact()
	if event.is_action_pressed("drop"):
		_drop_one()


func _physics_process(delta: float) -> void:
	if not GameSession.is_running():
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	move_and_slide()
	if global_position.y < GameSession.ground_y() - water_depth:
		respawn()


## Put the player back on dry land. Carried items come along — losing them to a
## misstep would be punishing for no reason.
func respawn() -> void:
	velocity = Vector3.ZERO
	global_position = spawn_position
	GameEvents.player_respawned.emit(player_id)


## What the crosshair is on: a PickupItem, a ContainerNode, or null.
func aimed_target() -> Node:
	if not ray.is_colliding():
		return null
	var hit := ray.get_collider()
	while hit != null and not (hit is PickupItem or hit is ContainerNode):
		hit = hit.get_parent()
	return hit


## The specific slot the crosshair is on, or -1 when aiming at a container body
## or at anything else. Used by the HUD to say what [E] will do.
func aimed_slot() -> int:
	if not ray.is_colliding():
		return -1
	var target := aimed_target()
	return (target as ContainerNode).slot_at(ray.get_collider()) if target is ContainerNode else -1


func carried_items() -> Array[String]:
	return GameSession.state.carried_by(player_id)


func _interact() -> void:
	interact_with(aimed_target(), aimed_slot())


## What one press of [E] does, given what the crosshair found. Split out of
## [method _interact] so a test can drive a whole press — the Autopilot fallback
## included — without simulating a raycast.
##   a PickupItem     -> pick it up
##   a ContainerNode  -> [method interact_with_container] at the aimed slot
##   nothing          -> the press is free; offer it to Autopilot (WP-3.6)
func interact_with(target: Node, slot: int) -> void:
	if target is PickupItem:
		GameSession.submit(Commands.pick_up(player_id, (target as PickupItem).item_id))
	elif target is ContainerNode:
		interact_with_container(target as ContainerNode, slot)
	else:
		_auto_place()


## The ray found nothing, so there is no aim to override and no manual placement
## on the table: hand the press to Autopilot (WP-3.6). The ability checks its own
## unlock, so until the party buys it this is one group lookup and nothing else.
func _auto_place() -> void:
	var autopilot := AutoPlaceAbility.find_in_tree(self)
	if autopilot != null:
		autopilot.attempt(player_id, global_position)


## Split out from [method _interact] so tests can drive it without simulating a raycast.
##   aimed at an occupied slot  -> take that item back out
##   aimed at an empty slot     -> put the active item exactly there
##   aimed at the body (-1)     -> put it in its correct slot, else the first free one
func interact_with_container(container: ContainerNode, slot: int) -> void:
	var occupant := GameSession.state.item_in_slot(container.container_id, slot) if slot >= 0 else ""
	if not occupant.is_empty():
		GameSession.submit(Commands.take_out(player_id, occupant))
		return
	var item_id := GameSession.state.active_item(player_id)
	if item_id.is_empty():
		return
	var target_slot := slot
	if target_slot < 0:
		target_slot = PlacementRules.find_correct_slot(GameSession.catalog, GameSession.state, item_id, container.container_id)
		if target_slot < 0:
			target_slot = container.first_free_slot()
	if target_slot >= 0:
		GameSession.submit(Commands.place(player_id, item_id, container.container_id, target_slot))


func _drop_one() -> void:
	var held := carried_items()
	if held.is_empty():
		return
	var drop_pos := global_position + (-camera.global_transform.basis.z) * 1.2
	drop_pos.y = GameSession.ground_y()
	GameSession.submit(Commands.drop(player_id, held[held.size() - 1], clamp_to_island(drop_pos)))


## Keep a position on the island so a dropped item never lands in the lake where
## it cannot be picked up again.
static func clamp_to_island(position: Vector3) -> Vector3:
	var limit := GameSession.island_radius() - 1.0
	var flat := Vector2(position.x, position.z)
	if flat.length() <= limit:
		return position
	flat = flat.normalized() * limit
	return Vector3(flat.x, position.y, flat.y)
