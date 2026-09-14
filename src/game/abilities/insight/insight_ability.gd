class_name InsightAbility
extends Node
## Klarsyn (WP-3.2): hold an item, press F, and every other member of its series
## that is still lying on the island glows through the terrain for five seconds.
##
## The fourth tent pole stops being a hunt and becomes a glance.
##
## Reads [GameSession] and [Catalog] only — it submits no command and mutates no
## state, because a highlight is presentation and nothing else. That is also why
## it is safe in multiplayer without doing anything: each client decides for
## itself what its own player can see.
##
## Lifetime: the highlights are children of the [PickupItem] nodes they wrap, so
## they die with the level. [method clear] frees them with `free()` rather than
## `queue_free()` — a queued node is still an orphan when the suite counts.

## Ability id in [Progression.ABILITIES].
const ABILITY_ID := "insight"
## Input action, declared in project.godot by WP-3.0. F for "Klarsyn".
const INPUT_ACTION := "ability_insight"
## GAME_DESIGN §6. One timer per activation, not per item.
const DURATION_SECONDS := 5.0
## A series-less item is the common case, so say so briefly and get out of the way.
const FEEDBACK_SECONDS := 1.5

## How long one activation lasts. Overridable so a test does not have to sit
## through five real seconds to prove that it ends.
@export var duration := DURATION_SECONDS

## item_id -> InsightHighlight currently on screen.
var _highlights: Dictionary = {}
var _remaining := 0.0


## Put an ability node under [param parent], replacing one that is already there.
## Idempotent on purpose: [Main] rebuilds the playing scene on every restart, and
## a second ability node would mean a second set of highlights and a doubled toast.
static func install(parent: Node) -> InsightAbility:
	for existing: Node in parent.get_children():
		if existing is InsightAbility:
			parent.remove_child(existing)
			existing.free()
	var ability := InsightAbility.new()
	ability.name = "InsightAbility"
	parent.add_child(ability)
	return ability


func _ready() -> void:
	set_process(false)
	# An item that leaves the ground has been dealt with; its glow goes with it.
	GameEvents.item_picked_up.connect(_on_item_left_the_ground)
	GameEvents.item_placed.connect(_on_item_placed)
	GameEvents.item_taken_out.connect(_on_item_left_the_ground)
	# A new level means new PickupItem nodes; whatever we were pointing at is gone.
	GameEvents.level_loaded.connect(_on_level_loaded)


func _exit_tree() -> void:
	clear()


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		clear()


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


# --- Public ----------------------------------------------------------------------

## True when [param event] was the ability key and was acted on.
##
## Split out of [method _unhandled_input] because Godot does not transport
## InputEvents in headless mode: a test cannot press F, it can only hand the
## event over. Without this seam the binding itself would be untested.
func handle_input(event: InputEvent) -> bool:
	if not event.is_action_pressed(INPUT_ACTION):
		return false
	activate()
	return true


## One press of F. Silent when the ability is not owned — a key you have not
## bought should behave exactly like a key that does nothing.
func activate() -> void:
	if not GameSession.is_running():
		return
	var owned := GameSession.progression
	if owned == null or not owned.has(ABILITY_ID):
		return
	var held := GameSession.state.active_item(GameSession.local_player_id())
	if held.is_empty():
		return # nothing in hand to be the sibling of
	var def := GameSession.catalog.get_item(held)
	if def == null or def.series.is_empty():
		clear()
		_say(tr("ui.ability.no_series"))
		return
	_light_up(siblings_on_ground(GameSession.catalog, GameSession.state, def.series, held))


## Which items a press should light up: every member of [param series] that is
## still on the ground, minus the one in your hand.
##
## Items already in a container are deliberately left out — the player has dealt
## with those, and glowing them is noise pointing at work already done.
static func siblings_on_ground(catalog: Catalog, state: WorldState,
		series: String, held_item_id: String) -> Array[String]:
	var out: Array[String] = []
	if series.is_empty():
		return out
	for member: ItemDef in catalog.series_members(series):
		if member.id == held_item_id:
			continue
		if state.kind_of(member.id) != WorldState.Kind.GROUND:
			continue
		out.append(member.id)
	out.sort()
	return out


## The items glowing right now, sorted.
func highlighted_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _highlights.keys():
		out.append(id)
	out.sort()
	return out


func is_active() -> bool:
	return not _highlights.is_empty()


## Seconds left on the current activation (0 when nothing is glowing).
func seconds_remaining() -> float:
	return maxf(_remaining, 0.0)


## Take every highlight off the island. Frees immediately rather than queueing:
## a queued node still counts as an orphan, and the level it hangs off may be
## gone by the time the queue is flushed.
func clear() -> void:
	for id: String in _highlights.keys():
		_free_highlight(_highlights[id])
	_highlights.clear()
	_remaining = 0.0
	set_process(false)


# --- Internals ---------------------------------------------------------------------

func _light_up(item_ids: Array[String]) -> void:
	clear() # re-pressing restarts the activation rather than stacking onto it
	var nodes := _pickup_nodes()
	for id: String in item_ids:
		var item: PickupItem = nodes.get(id)
		if item == null:
			continue # in the state but not on screen; nothing to draw on
		var highlight := InsightHighlight.create(_item_size(item))
		item.add_child(highlight)
		_highlights[id] = highlight
	# Nothing drawn means nothing to time out — every sibling is already packed.
	_remaining = duration if not _highlights.is_empty() else 0.0
	set_process(not _highlights.is_empty())


## Every [PickupItem] in the running scene, by item id. Walked per activation
## rather than cached: the cache would outlive exactly one level.
func _pickup_nodes() -> Dictionary:
	var out: Dictionary = {}
	if not is_inside_tree():
		return out
	for node: Node in get_tree().get_root().find_children("*", "PickupItem", true, false):
		out[(node as PickupItem).item_id] = node
	return out


## How big the shell has to be. The item already worked this out for its own
## collision box, so use that answer rather than measuring the meshes again.
static func _item_size(item: PickupItem) -> Vector3:
	var collision := item.get_node_or_null("Collision") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		return (collision.shape as BoxShape3D).size
	return ItemPalette.box_size(item.def) if item.def != null else Vector3.ONE * 0.2


## Brief feedback through the HUD's own toast queue. The HUD is another WP's
## territory this wave, so this calls its public API and touches nothing else.
func _say(text: String) -> void:
	var hud := _find_hud()
	if hud != null:
		hud.show_toast(text, FEEDBACK_SECONDS, HUD.COLOR_INFO)


func _find_hud() -> HUD:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_root().find_children("*", "HUD", true, false):
		return node as HUD
	return null


func _on_item_left_the_ground(item_id: String, _player_id: int) -> void:
	_drop_highlight(item_id)


func _on_item_placed(item_id: String, _player_id: int, _container_id: String,
		_slot: int, _verdict: int) -> void:
	_drop_highlight(item_id)


func _on_level_loaded(_level_id: String) -> void:
	clear()


func _drop_highlight(item_id: String) -> void:
	if not _highlights.has(item_id):
		return
	var doomed: Variant = _highlights[item_id]
	_highlights.erase(item_id)
	_free_highlight(doomed)


## Take one shell off the island, now.
##
## [param value] is deliberately untyped: when the level has already been torn
## down these entries point at freed nodes, and assigning one of those to a
## `Node`-typed variable is itself a runtime error ("Trying to assign invalid
## previously freed instance"). Check validity first, type afterwards.
##
## `free()` and not `queue_free()`: a queued node is still an orphan when the
## suite counts them, and the parent it hangs off may be gone before the queue
## is flushed.
static func _free_highlight(value: Variant) -> void:
	if not is_instance_valid(value):
		return
	var node := value as Node
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()
