class_name MapSenseAbility
extends Node
## Stedsans (WP-3.3): with the ability bought, C turns on a small arrow that
## points at the container the item in your hands belongs in.
##
## Knowing *where* stops being the puzzle; deciding *what* still is. It is a
## toggle rather than a hold, because a man carrying three things wants it on
## while he walks, not while he holds a key down.
##
## Reads [GameSession], [PlacementRules] and the local player's camera; submits
## no command and mutates nothing. Navigation is presentation, which is also why
## it is already multiplayer-safe: each client decides for itself what its own
## player can see.
##
## The two halves are deliberately separate:
##
##   which container  →  [method correct_container] (pure, asks [PlacementRules])
##   which way on screen  →  [method screen_direction] / [method fade_alpha]
##                           (pure, a camera transform in and an angle out)
##
## Both are static and take everything they need as arguments, so the test can
## state an angle in radians from a camera transform it wrote down itself, rather
## than looking at a picture of an arrow.
##
## Lifetime: the arrow is a child of [method HUD.ability_layer] and therefore
## outlives this node if the HUD does. [method _exit_tree] frees it with `free()`,
## not `queue_free()` — a queued node is still an orphan when gdUnit4 counts.

## Ability id in [Progression.ABILITIES].
const ABILITY_ID := "map_sense"
## Input action, declared in project.godot by WP-3.0. C for "Stedsans".
const INPUT_ACTION := "ability_map_sense"
## How long the on/off confirmation stays up.
const FEEDBACK_SECONDS := 1.5

## Inside this angle off the crosshair the container is the thing you are already
## looking at, and the arrow is drawn at nothing.
const FADE_INNER_DEGREES := 6.0
## Outside this angle the arrow is at full strength. Between the two it fades, so
## turning toward the container dims it smoothly instead of blinking it away.
const FADE_OUTER_DEGREES := 18.0

## Picking the target again every frame would make the arrow flick between two
## equally-good containers as the player walks the line between them, and costs a
## [PlacementRules] sweep per frame for no benefit. Anything that could change the
## answer marks it dirty; this is only the "I have walked a bit" case.
const RETARGET_INTERVAL := 0.2
## A rival container has to be this much nearer before the arrow will swap to it.
## Pure hysteresis: without it, standing halfway between the two beer coolers
## makes the arrow twitch every time you sway.
const SWAP_MARGIN := 0.85

## Overrides the local player's camera. Tests set a camera whose transform they
## wrote down; nothing in the game does.
var camera_override: Camera3D = null

var arrow: MapSenseArrow

var _enabled := false
var _target := ""
var _targeted_item := ""
var _since_retarget := 0.0
var _dirty := true


## Put an ability node under [param parent], replacing one that is already there.
## Idempotent for the same reason [InsightAbility.install] is: [Main] rebuilds the
## playing scene on every restart, and a second ability node means two arrows and
## a toggle that turns one of them on.
static func install(parent: Node) -> MapSenseAbility:
	for existing: Node in parent.get_children():
		if existing is MapSenseAbility:
			parent.remove_child(existing)
			existing.free()
	var ability := MapSenseAbility.new()
	ability.name = "MapSenseAbility"
	parent.add_child(ability)
	return ability


func _ready() -> void:
	set_process(false)
	# Anything that can change where the held item belongs.
	GameEvents.item_picked_up.connect(_on_carry_changed)
	GameEvents.item_dropped.connect(_on_item_dropped)
	GameEvents.item_placed.connect(_on_item_placed)
	GameEvents.item_taken_out.connect(_on_item_taken_out)
	GameEvents.item_summoned.connect(_on_item_dropped)
	# A new level is a new island: new containers, and nothing in hand.
	GameEvents.level_loaded.connect(_on_level_loaded)


func _exit_tree() -> void:
	_drop_arrow()


func _process(delta: float) -> void:
	_since_retarget += delta
	if _dirty or _since_retarget >= RETARGET_INTERVAL:
		_retarget()
	_aim()


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


# --- Public ----------------------------------------------------------------------

## True when [param event] was the ability key and was acted on.
##
## Split out of [method _unhandled_input] because Godot does not transport
## InputEvents in headless mode: a test cannot press C, it can only hand the event
## over. Without this seam the binding itself would be untested.
func handle_input(event: InputEvent) -> bool:
	if not event.is_action_pressed(INPUT_ACTION):
		return false
	toggle()
	return true


## One press of C. A key you have not bought behaves exactly like a key that does
## nothing: no arrow, no state change, and nothing said about it.
func toggle() -> void:
	if not GameSession.is_running():
		return
	var owned := GameSession.progression
	if owned == null or not owned.has(ABILITY_ID):
		return
	set_enabled(not _enabled)


## Turn the sense on or off directly. Public so the test — and, later, a settings
## screen or a touch button — does not have to synthesise a key event.
func set_enabled(value: bool) -> void:
	if value == _enabled:
		return
	_enabled = value
	_dirty = true
	_since_retarget = RETARGET_INTERVAL
	set_process(_enabled)
	if _enabled:
		_say(tr("ui.ability.map_sense_on"))
		# Answer the keypress in the same frame rather than on the next _process:
		# a player who presses C expects the arrow, not the arrow one tick later.
		_retarget()
		_aim()
	else:
		_target = ""
		_targeted_item = ""
		if arrow != null:
			arrow.stand_down()
		_say(tr("ui.ability.map_sense_off"))


func is_enabled() -> bool:
	return _enabled


## Re-pick the container and re-point the arrow immediately, instead of waiting
## for the next frame and the [constant RETARGET_INTERVAL] that goes with it.
##
## Public so a test can move a camera and ask what the arrow does about it without
## awaiting frames — and so anything that changes the world in a way this node
## does not subscribe to can still keep the arrow honest.
func refresh() -> void:
	_dirty = true
	_retarget()
	_aim()


## The container the arrow is pointing at right now, or "" when it is pointing at
## nothing (off, empty-handed, or nowhere sensible to point).
func target_container() -> String:
	return _target


## The camera the arrow is drawn relative to: the local player's, unless a test
## has supplied its own. Null when no player is in the tree yet.
func active_camera() -> Camera3D:
	if is_instance_valid(camera_override):
		return camera_override
	if not is_inside_tree():
		return null
	var node := get_tree().get_first_node_in_group(Player.LOCAL_GROUP)
	if node is Player:
		return (node as Player).camera
	return null


# --- The two pure halves -----------------------------------------------------------

## Which container [param item_id] belongs in, given where everything is now.
##
## The answer is [PlacementRules]' and not this file's: a container qualifies when
## [method PlacementRules.find_correct_slot] finds a slot in it, which already
## encodes both "accepts the category" and "the series lives here" — a sibling
## already placed makes every *other* container answer SPLIT_SERIES, so the series
## rule falls out rather than being re-implemented.
##
## [param positions] is container id -> world position and [param from] is the
## player. When two containers qualify and neither holds a sibling, the nearer one
## wins. [param current] is what the arrow points at already: a rival has to be
## [constant SWAP_MARGIN] times nearer to take over, so walking the line between
## the two beer coolers does not make the arrow twitch.
##
## Returns "" when there is nothing sensible to point at.
static func correct_container(catalog: Catalog, state: WorldState, item_id: String,
		positions: Dictionary, from: Vector3, current: String = "") -> String:
	if catalog == null or state == null or item_id.is_empty():
		return ""
	if catalog.get_item(item_id) == null:
		return ""
	var eligible := _containers_with_room(catalog, state, item_id)
	if eligible.is_empty():
		# Every slot that would be CORRECT is taken. The item still belongs
		# somewhere: with its series if any of it is placed, otherwise in whatever
		# accepts its category. Pointing at a full container beats pointing nowhere
		# — the player is the one who has to work out what to take back out.
		eligible = _fallback_containers(catalog, state, item_id)
	return _nearest(eligible, positions, from, current)


## Which way the arrow points, as a unit vector in screen space (x right, y down),
## for a container at [param target] seen from a camera at [param view].
##
## The camera looks down its own -Z, so a target's offset from the centre of the
## screen is proportional to (local.x, -local.y) whenever it is in front. Behind
## the camera the same vector still answers usefully: something behind and to your
## left gives a negative x, and "turn left" is exactly the advice wanted. Since
## containers sit on the ground and the camera is at head height, a container
## directly behind reads as "down", which is the conventional compass answer.
static func screen_direction(view: Transform3D, target: Vector3) -> Vector2:
	var local := view.affine_inverse() * target
	var flat := Vector2(local.x, -local.y)
	if flat.length() < 0.0001:
		# Dead ahead or dead behind: the direction is genuinely undefined. Ahead is
		# faded to nothing anyway; behind, "down" means "turn around".
		return Vector2.DOWN if local.z >= 0.0 else Vector2.RIGHT
	return flat.normalized()


## Angle in radians between where the camera is looking and the container — 0 when
## it is dead centre in the crosshair, PI when it is directly behind.
static func off_axis_angle(view: Transform3D, target: Vector3) -> float:
	var to_target := target - view.origin
	if to_target.length() < 0.0001:
		return 0.0
	return (-view.basis.z).angle_to(to_target)


## How strongly to draw the arrow at [param off_axis] radians off the crosshair.
##
## Nothing at all once the container is the thing the player is looking at: the
## point of the ability is finding the container, and a marker painted on top of
## something already in view is just clutter over the view.
static func fade_alpha(off_axis: float) -> float:
	var inner := deg_to_rad(FADE_INNER_DEGREES)
	var outer := deg_to_rad(FADE_OUTER_DEGREES)
	if off_axis <= inner:
		return 0.0
	if off_axis >= outer:
		return 1.0
	return (off_axis - inner) / (outer - inner)


# --- Internals ---------------------------------------------------------------------

## Every container [param item_id] has a CORRECT free slot in, sorted by id so the
## answer does not depend on dictionary order.
static func _containers_with_room(catalog: Catalog, state: WorldState,
		item_id: String) -> Array[String]:
	var out: Array[String] = []
	for cid: String in catalog.container_ids():
		if PlacementRules.find_correct_slot(catalog, state, item_id, cid) >= 0:
			out.append(cid)
	return out


## Where the item belongs when nothing has room: the container its series already
## lives in, or failing that anything that accepts its category.
static func _fallback_containers(catalog: Catalog, state: WorldState,
		item_id: String) -> Array[String]:
	var item := catalog.get_item(item_id)
	var accepting: Array[String] = []
	for cid: String in catalog.container_ids():
		var container := catalog.get_container(cid)
		if container != null and container.accepts_category(item.category):
			accepting.append(cid)
	if item.series.is_empty():
		return accepting
	for member: ItemDef in catalog.series_members(item.series):
		if member.id == item_id:
			continue
		var home := state.container_of(member.id)
		if not home.is_empty() and accepting.has(home):
			var only: Array[String] = [home]
			return only
	return accepting


## The nearest of [param candidates] to [param from], keeping [param current] if
## no rival is [constant SWAP_MARGIN] times closer.
static func _nearest(candidates: Array[String], positions: Dictionary, from: Vector3,
		current: String) -> String:
	if candidates.is_empty():
		return ""
	var best := ""
	var best_distance := INF
	for cid: String in candidates:
		var where: Vector3 = positions.get(cid, Vector3.ZERO)
		var d := from.distance_to(where)
		if d < best_distance:
			best_distance = d
			best = cid
	if current.is_empty() or not candidates.has(current) or current == best:
		return best
	var held_position: Vector3 = positions.get(current, Vector3.ZERO)
	var current_distance := from.distance_to(held_position)
	return best if best_distance < current_distance * SWAP_MARGIN else current


## World position of every container in the running level.
func _container_positions() -> Dictionary:
	var out: Dictionary = {}
	if GameSession.catalog == null:
		return out
	for cid: String in GameSession.catalog.container_ids():
		out[cid] = GameSession.container_position(cid)
	return out


func _retarget() -> void:
	_dirty = false
	_since_retarget = 0.0
	if not _enabled or not GameSession.is_running() or GameSession.state == null:
		_target = ""
		_targeted_item = ""
		return
	var held := GameSession.state.active_item(GameSession.local_player_id())
	if held.is_empty():
		_target = ""
		_targeted_item = ""
		return
	# The arrow follows the *active* item — the last one picked up — because that
	# is the one a `place` would act on.
	var sticky := _target if held == _targeted_item else ""
	_targeted_item = held
	_target = correct_container(GameSession.catalog, GameSession.state, held,
		_container_positions(), _viewer_position(), sticky)


## Where "nearer" is measured from: the camera, which is the player's head and the
## only thing in the scene this ability is allowed to read.
func _viewer_position() -> Vector3:
	var cam := active_camera()
	return cam.global_position if cam != null else Vector3.ZERO


func _aim() -> void:
	if not _enabled:
		# Switched off: put away whatever is on screen, and do not go looking for a
		# HUD to hang a new arrow on.
		if is_instance_valid(arrow):
			arrow.stand_down()
		return
	var overlay := _ensure_arrow()
	if overlay == null:
		return
	var cam := active_camera()
	if _target.is_empty() or cam == null:
		overlay.stand_down()
		return
	var view := cam.global_transform
	var where := GameSession.container_position(_target)
	overlay.aim(screen_direction(view, where), fade_alpha(off_axis_angle(view, where)))


## The arrow, hung on the HUD's ability layer the first time there is a HUD to
## hang it on. The HUD belongs to another work package, so this touches nothing
## but its published extension point.
func _ensure_arrow() -> MapSenseArrow:
	if is_instance_valid(arrow) and arrow.is_inside_tree():
		return arrow
	arrow = null
	var hud := _find_hud()
	if hud == null:
		return null
	var layer := hud.ability_layer()
	if layer == null:
		return null
	arrow = MapSenseArrow.create()
	# The ability layer is anchored full-rect at the origin, so a child's position
	# is already screen space.
	layer.add_child(arrow)
	return arrow


## Take the arrow off the HUD, now. `free()` and not `queue_free()`: a queued node
## is still an orphan when the suite counts, and the HUD it hangs off may be gone
## before the queue is flushed.
func _drop_arrow() -> void:
	if not is_instance_valid(arrow):
		arrow = null
		return
	var parent := arrow.get_parent()
	if parent != null:
		parent.remove_child(arrow)
	arrow.free()
	arrow = null


func _find_hud() -> HUD:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_root().find_children("*", "HUD", true, false):
		return node as HUD
	return null


## Brief feedback through the HUD's own toast queue.
func _say(text: String) -> void:
	var hud := _find_hud()
	if hud != null:
		hud.show_toast(text, FEEDBACK_SECONDS, HUD.COLOR_INFO)


func _on_carry_changed(_item_id: String, _player_id: int) -> void:
	_dirty = true


func _on_item_dropped(_item_id: String, _player_id: int, _position: Vector3) -> void:
	_dirty = true


func _on_item_placed(_item_id: String, _player_id: int, _container_id: String,
		_slot: int, _verdict: int) -> void:
	_dirty = true


func _on_item_taken_out(_item_id: String, _player_id: int, _container_id: String) -> void:
	_dirty = true


func _on_level_loaded(_level_id: String) -> void:
	_dirty = true
	_target = ""
	_targeted_item = ""
	if is_instance_valid(arrow):
		arrow.stand_down()
