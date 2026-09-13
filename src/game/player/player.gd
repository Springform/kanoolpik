class_name Player
extends CharacterBody3D
## First-person controller + interaction raycast for the LOCAL player.
##
## Owns nothing about game rules: it only turns input into [Commands] submitted
## through [GameSession]. Remote players (phase 4) reuse this scene with
## [member is_local] = false and no input processing.

## Group the local player joins so late-created UI can find it (the spawn signal may already have fired).
const LOCAL_GROUP := "local_player"

@export var is_local := true
@export var walk_speed := 4.5
@export var sprint_speed := 7.5
@export var jump_velocity := 4.8
@export var mouse_sensitivity := 0.0025
@export var interact_distance := 3.0

var player_id: int = 1
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _pitch := 0.0

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/InteractRay
@onready var held_items: HeldItems = $Camera3D/HeldItems


func _ready() -> void:
	camera.current = is_local
	ray.target_position = Vector3(0, 0, -interact_distance)
	set_process_input(is_local)
	set_physics_process(is_local)
	held_items.set_player(player_id)
	if is_local:
		add_to_group(LOCAL_GROUP)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		GameEvents.local_player_spawned.emit(self)


func _input(event: InputEvent) -> void:
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


## What the crosshair is on: a PickupItem, a ContainerNode, or null.
func aimed_target() -> Node:
	if not ray.is_colliding():
		return null
	var hit := ray.get_collider()
	while hit != null and not (hit is PickupItem or hit is ContainerNode):
		hit = hit.get_parent()
	return hit


func carried_items() -> Array[String]:
	return GameSession.state.carried_by(player_id)


func _interact() -> void:
	var target := aimed_target()
	if target is PickupItem:
		GameSession.submit(Commands.pick_up(player_id, target.item_id))
	elif target is ContainerNode:
		var held := carried_items()
		if held.is_empty():
			return
		var item_id := held[held.size() - 1] # carried_by() is in pick-up order: last = in hand
		var slot := PlacementRules.find_correct_slot(GameSession.catalog, GameSession.state, item_id, target.container_id)
		if slot < 0:
			slot = target.first_free_slot()
		if slot >= 0:
			GameSession.submit(Commands.place(player_id, item_id, target.container_id, slot))


func _drop_one() -> void:
	var held := carried_items()
	if held.is_empty():
		return
	var drop_pos := global_position + (-camera.global_transform.basis.z) * 1.2
	drop_pos.y = global_position.y - 0.5
	GameSession.submit(Commands.drop(player_id, held[held.size() - 1], drop_pos))
