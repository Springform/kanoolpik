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

## Somebody's foot hit the ground. Local to this node on purpose (WP-5.2): a
## footstep fires two or three times a second and is not a fact about the world,
## so it has no business on [GameEvents], which is the bus every peer's
## presentation listens on. Audio picks it up from the player it belongs to.
signal footstep(at: Vector3)

## Group the local player joins so late-created UI can find it (the spawn signal may already have fired).
const LOCAL_GROUP := "local_player"

## --- How it feels to walk (WP-5.2) -------------------------------------------
##
## Every one of these is per SECOND, and that is the whole point. The version
## before this one stopped the player with `move_toward(velocity, 0, speed)` —
## no delta — so the distance it took to stop depended on the frame rate, and
## the web export's frame rate depends on whether the tab is in front. At any
## rate the game actually runs at, that expression stops a walking player inside
## one frame, which is why walking felt like a debug camera: full speed and zero
## speed, nothing in between.

## Metres per second per second, on the ground. Reaching [member walk_speed]
## takes about a twelfth of a second — long enough to feel like a person
## starting to walk, short enough that nobody calls it lag.
const GROUND_ACCELERATION := 60.0
## Slightly gentler than starting, so stopping reads as a step and a half rather
## than as hitting a wall.
const GROUND_FRICTION := 45.0
## In the air you have some say and not much. Without this a jump is a rail;
## with too much of it, the ground stops mattering.
const AIR_ACCELERATION := 12.0

## How long after walking off an edge a jump still counts.
##
## Named and stated because it is a lie the game tells on purpose: for this long
## the player is airborne and the game pretends otherwise. Two or three frames'
## worth at 60 fps — enough to cover the frame somebody was one pixel past the
## rock they meant to jump from, and short enough that nobody can use it to
## cross a gap they should not.
const COYOTE_TIME := 0.12

## Degrees added to the field of view at full sprint.
##
## Small, because a big one reads as a bug rather than as speed. Fast in and
## slow out for the same reason a car's speedometer needle is: the change is the
## signal, and it should arrive when the sprint does and fade after it.
const SPRINT_FOV_KICK := 6.0
const FOV_KICK_IN := 8.0
const FOV_KICK_OUT := 3.0

## Metres of ground covered per footstep. A stride, near enough — it is what
## decides how often [signal footstep] fires and it is deliberately not tied to
## the head bob, which the player can switch off.
const STRIDE_LENGTH := 0.9
## How far the camera drops and rises, and how many full bob cycles a metre of
## walking is worth. Off by default: this is the one option that genuinely makes
## some people feel ill, so it is opt-in rather than opt-out.
const BOB_AMPLITUDE := 0.045
const BOB_CYCLES_PER_METRE := 0.55
## Below this the player is standing still as far as the bob is concerned, and
## the camera settles back to level instead of trembling.
const BOB_STILL_SPEED := 0.3

@export var is_local := true
@export var walk_speed := 4.5
@export var sprint_speed := 7.5
## Apex is v² / 2g — 1.03 m at 4.5 with Godot's default gravity. Chosen against
## the island rather than for the number: you can get onto a rock or a cool box,
## and you cannot get onto the roof of the shelter. See
## [method jump_apex_height], which is what the test asserts on.
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0025
@export var interact_distance := 3.0
## Falling below this (relative to ground level) counts as being in the lake.
@export var water_depth := 2.0

var player_id: int = 1
## Where to put the player back after a swim. Set by whoever spawns the player.
var spawn_position := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _pitch := 0.0
## Seconds of [constant COYOTE_TIME] left. Counted down rather than up so "may
## still jump" is one comparison.
var _coyote := 0.0
## Ground covered since the last footstep, and the bob's own phase in metres.
var _stride := 0.0
var _bob_distance := 0.0
## The field of view the player chose, before any sprint kick.
var _base_fov := 90.0
## Where the camera sits when nothing is bobbing it.
var _camera_rest_y := 0.0
var _head_bob := false

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
	_camera_rest_y = camera.position.y
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
	if key.is_empty() or key == Settings.LOOK_SENSITIVITY or key == Settings.LOOK_FOV \
			or key == Settings.LOOK_HEAD_BOB:
		_apply_settings()


func _apply_settings() -> void:
	mouse_sensitivity = Settings.get_float(Settings.LOOK_SENSITIVITY)
	_base_fov = Settings.get_float(Settings.LOOK_FOV)
	camera.fov = _base_fov
	_head_bob = Settings.get_bool(Settings.LOOK_HEAD_BOB)
	if not _head_bob:
		# Switching it off mid-stride must put the camera back, not leave it
		# wherever the sine happened to be.
		camera.position.y = _camera_rest_y


func _input(event: InputEvent) -> void:
	if not GameSession.is_running():
		return # level over (or not started): the evaluation screen has the stage
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.4, 1.4)
		camera.rotation.x = _pitch
	# There was an `ui_toggle_mouse` handler here, bound to Escape — the same key
	# as `ui_cancel`, so one press released the mouse AND opened the pause menu,
	# which releases the mouse itself. WP-1.6 noticed and called it harmless
	# because the end state matched. It is the shape that keeps biting us: a
	# second statement of a rule another file enforces. PauseMenu.open() and
	# close() own the mouse now, and they are the only ones who do.
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
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var sprinting := Input.is_action_pressed("sprint")
	step_motion(delta, wish, sprinting, Input.is_action_just_pressed("jump"))
	_step_camera(delta, sprinting)
	if global_position.y < GameSession.ground_y() - water_depth:
		respawn()


## One tick of movement, given what the player asked for.
##
## Split out of [method _physics_process] so a test can drive it at 30 fps and
## at 144 fps and compare the distance covered — which is the acceptance
## criterion, not a nicety. Nothing in here reads [Input].
func step_motion(delta: float, wish: Vector3, sprinting: bool, jump_pressed: bool) -> void:
	var grounded := is_on_floor()
	if grounded:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		velocity.y -= _gravity * delta
	if jump_pressed and _coyote > 0.0:
		velocity.y = jump_velocity
		# No "spend the window" line here. One press is one jump because
		# is_action_just_pressed is true for exactly one physics frame; zeroing
		# _coyote as well would be a second statement of that, and this project
		# has found four of those the hard way.
	var speed := sprint_speed if sprinting else walk_speed
	velocity = next_horizontal_velocity(velocity, wish, speed, grounded, delta)
	var before := global_position
	move_and_slide()
	if grounded:
		_advance_stride(global_position - before)


## The horizontal half of a tick, as arithmetic.
##
## Static and pure so "the same distance per second at any frame rate" can be
## checked by integrating it rather than by running a physics server. The y
## component is passed through untouched — gravity and jumping are the caller's.
static func next_horizontal_velocity(
		current: Vector3, wish: Vector3, speed: float, grounded: bool, delta: float) -> Vector3:
	var flat := Vector3(current.x, 0.0, current.z)
	var rate := (GROUND_ACCELERATION if grounded else AIR_ACCELERATION) if wish.length_squared() > 0.0 \
		else (GROUND_FRICTION if grounded else 0.0)
	var target := wish * speed
	var next := flat.move_toward(target, rate * delta)
	return Vector3(next.x, current.y, next.z)


## Ground covered since the last footstep, and the sound when it adds up to one.
func _advance_stride(moved: Vector3) -> void:
	var distance := Vector2(moved.x, moved.z).length()
	_bob_distance += distance
	_stride += distance
	while _stride >= STRIDE_LENGTH:
		_stride -= STRIDE_LENGTH
		footstep.emit(global_position)


## The sprint kick and the head bob. Camera only: nothing here moves the body,
## and the interaction ray hangs off the camera's rotation rather than its
## height, so a bobbing head does not change what the crosshair can reach.
func _step_camera(delta: float, sprinting: bool) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var wanted := _base_fov + (SPRINT_FOV_KICK if sprinting and speed > walk_speed * 0.5 else 0.0)
	var rate := FOV_KICK_IN if wanted > camera.fov else FOV_KICK_OUT
	camera.fov = lerpf(camera.fov, wanted, clampf(rate * delta, 0.0, 1.0))
	if not _head_bob:
		return
	if speed < BOB_STILL_SPEED:
		camera.position.y = move_toward(camera.position.y, _camera_rest_y, BOB_AMPLITUDE * 4.0 * delta)
		return
	camera.position.y = _camera_rest_y + sin(_bob_distance * BOB_CYCLES_PER_METRE * TAU) * BOB_AMPLITUDE


## How high a jump gets, from the numbers rather than from a playtest: v² / 2g.
static func jump_apex_height(velocity_up: float, gravity: float) -> float:
	return (velocity_up * velocity_up) / (2.0 * gravity)


func gravity() -> float:
	return _gravity


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
