class_name AutoPlaceAbility
extends Node
## Autopilot (WP-3.6): standing within [constant RANGE_METRES] of a container the
## held item belongs in, pressing E puts it in the first correct slot. No looking
## down, no cycling — carrying an armful to the right place is one press per item.
##
## **Precedence is the whole design.** The player's aim always wins. [Player]
## offers this node the press only when the interaction ray found nothing at all,
## so Autopilot can never override a deliberate placement: it fills in a press
## that would otherwise have done nothing.
##
## It submits the ordinary [method Commands.place] a manual placement sends, so
## the core, the event stream and phase 4's replication need to know nothing
## about the ability — and someone else's autopilot will animate correctly on
## your screen for free.
##
## It never places wrongly. If no container in range has a CORRECT slot for the
## held item, the press buys a toast and nothing else. Spending the player's
## accuracy score for them is the one thing an assist must not do.
##
## Owns no nodes and caches nothing, so there is nothing to tear down: it reads
## [GameSession] fresh on every press and a rebuilt level cannot leave it stale.

## Ability id in [Progression.ABILITIES]. Costs 3 points.
const ABILITY_ID := "auto_place"
## GAME_DESIGN §6 — "within 2 m of the correct container". The one place the
## radius is written down; WP-3.8 tunes it here and nowhere else.
const RANGE_METRES := 2.0
## Group the installed ability joins so [Player] can find it in O(1) without
## knowing where [Main] parented it.
const GROUP := "auto_place_ability"
## A press that could not act should say why and get out of the way.
const FEEDBACK_SECONDS := 1.5

## Keys of the Dictionary [method choose_target] returns.
const KEY_CONTAINER := "container_id"
const KEY_SLOT := "slot"
const KEY_DISTANCE := "distance"


## Put an ability node under [param parent], replacing one that is already there.
## Idempotent on purpose: [Main] rebuilds the playing scene on every restart, and
## a second ability node would mean two place commands per press.
static func install(parent: Node) -> AutoPlaceAbility:
	for existing: Node in parent.get_children():
		if existing is AutoPlaceAbility:
			parent.remove_child(existing)
			existing.free()
	var ability := AutoPlaceAbility.new()
	ability.name = "AutoPlaceAbility"
	parent.add_child(ability)
	return ability


## The Autopilot installed in [param context]'s scene tree, or null when this
## build has none (or [param context] is not in a tree yet).
static func find_in_tree(context: Node) -> AutoPlaceAbility:
	if context == null or not context.is_inside_tree():
		return null
	return context.get_tree().get_first_node_in_group(GROUP) as AutoPlaceAbility


func _ready() -> void:
	add_to_group(GROUP)


# --- Public ----------------------------------------------------------------------

## Has the party bought Autopilot? False also when no level is loaded.
func is_unlocked() -> bool:
	var owned := GameSession.progression
	return owned != null and owned.has(ABILITY_ID)


## One press of E that had nothing to aim at, made by the player standing at
## [param from].
##
## Returns true when a place command went out. False covers every "not mine"
## case — no level, locked, empty hands, nothing correct in range — so the
## caller never has to ask which.
func attempt(player_id: int, from: Vector3) -> bool:
	if not GameSession.is_running() or GameSession.state == null:
		return false
	if not is_unlocked():
		return false
	var item_id := GameSession.state.active_item(player_id)
	if item_id.is_empty():
		return false # empty hands: E at thin air stays the no-op it has always been
	var target := choose_target(item_id, from)
	if target.is_empty():
		_say(tr("ui.ability.nothing_nearby"))
		return false
	var container_id: String = target[KEY_CONTAINER]
	var slot: int = target[KEY_SLOT]
	GameSession.submit(Commands.place(player_id, item_id, container_id, slot))
	_say(tr("ui.ability.auto_placed") % _item_name(item_id))
	return true


## Where a press would put [param item_id] from [param from]: the *nearest*
## container in range that has a free CORRECT slot for it. Empty Dictionary when
## there is none — which is the answer that makes the ability safe.
##
## Returns { [constant KEY_CONTAINER]: String, [constant KEY_SLOT]: int,
## [constant KEY_DISTANCE]: float }.
##
## The slot comes from [method PlacementRules.find_correct_slot], which walks
## slots in index order and takes the first CORRECT one. An ordered container
## therefore fills in sequence without this ability knowing that ordered
## containers exist — the rules already say so.
func choose_target(item_id: String, from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	if GameSession.catalog == null or GameSession.state == null:
		return best
	# container_ids() is sorted, so equidistant containers resolve the same way
	# on every machine — which phase 4 will care about.
	for container_id: String in GameSession.catalog.container_ids():
		var distance := distance_to(container_id, from)
		if distance > RANGE_METRES:
			continue
		if not best.is_empty() and distance >= float(best[KEY_DISTANCE]):
			continue # already have a strictly nearer candidate
		var slot := PlacementRules.find_correct_slot(
			GameSession.catalog, GameSession.state, item_id, container_id)
		if slot < 0:
			continue
		best = {KEY_CONTAINER: container_id, KEY_SLOT: slot, KEY_DISTANCE: distance}
	return best


## Player-to-container distance, measured flat.
##
## The level's `container_positions` carry no meaningful Y — like the player
## spawns, they are flat data that presentation lifts onto the terrain — so
## counting the player's eye height against a container's 0 would quietly eat
## half the 2 m budget on a hill.
func distance_to(container_id: String, from: Vector3) -> float:
	var at := GameSession.container_position(container_id)
	return Vector2(from.x - at.x, from.z - at.z).length()


# --- Internals -------------------------------------------------------------------

func _item_name(item_id: String) -> String:
	var def := GameSession.catalog.get_item(item_id) if GameSession.catalog != null else null
	return tr(def.name_key) if def != null else item_id


## Brief feedback through the HUD's own toast queue. The HUD belongs to another
## work package, so this calls its public API and touches nothing else.
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
