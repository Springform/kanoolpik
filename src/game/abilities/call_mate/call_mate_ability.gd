class_name CallMateAbility
extends Node3D
## "Råb på en kammerat" (WP-3.4): hold something, shout, and every loose member
## of its series arcs over and lands at your feet.
##
## The split inside this folder is the work package's whole argument:
##
##   input  →  [method shout]  →  GameSession.submit(Commands.summon(...))
##   GameEvents.item_summoned  →  [SummonAnimator] (the arc) + the shout cue
##
## Nothing downstream of the command knows a key was pressed. The simulation
## moved the items the instant it applied the command; this node only asks, and
## then reacts to the same event every other peer will get in phase 4 — which
## is why someone else's shout will animate and sound correct for free.
##
## Add it to the playing scene and it wires itself up; it owns no .tscn because
## everything it needs is two nodes built here.

const ACTION := "ability_call_mate" # R, for Råb — declared in project.godot by WP-3.0
const SHOUT_SFX := "res://assets/audio/sfx/shout_mate.wav"
const SFX_BUS := "SFX"
## He is shouting, so he carries — but not across the whole lake.
const SHOUT_MAX_DISTANCE := 60.0
const SHOUT_UNIT_SIZE := 8.0

## Show our own toast for a rejected summon.
##
## [HUD.error_key] only names the errors phase 1 knew about and answers
## "ui.error.generic" for everything else, so without this a player who shouts
## for a series twice is told "you can't do that right now" instead of "you
## already shouted for those" — and the HUD belongs to another work package.
## Turn this off once [HUD.error_key] maps the four summon errors itself,
## otherwise the player gets both toasts.
@export var own_rejection_toasts := true

var animator: SummonAnimator

var _shout_player: AudioStreamPlayer3D
var _hud: HUD
## One shout per command, not one per item: the processor publishes an
## item_summoned for every member of the series, all in the same frame.
var _last_burst_frame := -1
var _shouts := 0


func _ready() -> void:
	animator = SummonAnimator.new()
	animator.name = "SummonAnimator"
	add_child(animator)
	_shout_player = AudioStreamPlayer3D.new()
	_shout_player.name = "Shout"
	_shout_player.bus = SFX_BUS
	_shout_player.stream = load(SHOUT_SFX)
	_shout_player.max_distance = SHOUT_MAX_DISTANCE
	_shout_player.unit_size = SHOUT_UNIT_SIZE
	add_child(_shout_player)
	GameEvents.item_summoned.connect(_on_item_summoned)
	GameEvents.command_rejected.connect(_on_command_rejected)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION):
		return
	if not GameSession.is_running():
		return
	get_viewport().set_input_as_handled()
	shout()


# --- Public API --------------------------------------------------------------

## Shout for whatever is in the local player's hands. Returns true when a
## command went out — false means there was nothing to ask for, not that the
## ability failed; a *rejected* command still returns true and arrives back on
## [signal GameEvents.command_rejected] as a toast.
##
## Public so a test — or a future touch button — can trigger the ability without
## synthesising a key event.
func shout() -> bool:
	if not GameSession.is_running() or GameSession.state == null:
		return false
	var pid := GameSession.local_player_id()
	var item_id := GameSession.state.active_item(pid)
	if item_id.is_empty():
		return false # empty hands: nothing to shout about, and nothing to say
	var def := GameSession.catalog.get_item(item_id)
	if def == null or def.series.is_empty():
		# The command would come back as "unknown_series", which is true but
		# unhelpful; the player wants to know this item is simply a loner.
		toast(tr("ui.ability.no_series"), true)
		return false
	GameSession.submit(Commands.summon(pid, def.series, summon_centre()))
	return true


## Where the series is asked to gather: the local player's feet, pushed clear of
## any container the landing ring would otherwise drop items inside.
##
## The core clamps this to the island (and to ground level) but knows nothing
## about containers — it holds no level geometry. Keeping containers clear is
## therefore the caller's job, and it is the same exclusion [MessGenerator]
## respects when it scatters the mess in the first place: a summoned paddle must
## be no harder to pick up than a scattered one.
func summon_centre() -> Vector3:
	var centre := feet_position()
	if GameSession.catalog == null:
		return centre
	var margin := float(GameSession.level.get("container_clearance", 0.4))
	# Pushing clear of one container can push into the next, so settle it:
	# a handful of passes over a sorted list, deterministic and quick.
	for _pass in range(3):
		var moved := false
		for cid in GameSession.catalog.container_ids():
			var clear := GameSession.catalog.get_container(cid).footprint_radius() \
				+ margin + CommandProcessor.SUMMON_RING_RADIUS
			var origin := GameSession.container_position(cid)
			var away := Vector2(centre.x - origin.x, centre.z - origin.z)
			if away.length() >= clear:
				continue
			if away.length() < 0.001:
				away = Vector2.RIGHT # standing dead centre on it; any way out will do
			away = away.normalized() * clear
			centre = Vector3(origin.x + away.x, centre.y, origin.z + away.y)
			moved = true
		if not moved:
			break
	return centre


## The local player's feet, or the island centre when no player is in the tree.
func feet_position() -> Vector3:
	var node := get_tree().get_first_node_in_group(Player.LOCAL_GROUP)
	if not (node is Node3D):
		return Vector3.ZERO
	var body := node as Node3D
	var feet := body.global_position
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is CapsuleShape3D:
		feet.y -= (collision.shape as CapsuleShape3D).height * 0.5
	return feet


## Put [param text] in front of the player. The HUD belongs to another work
## package, so this only ever calls its public [method HUD.show_toast].
func toast(text: String, is_error: bool) -> void:
	var hud := hud_node()
	if hud == null:
		return
	hud.show_toast(text, HUD.TOAST_SECONDS, HUD.COLOR_ERROR if is_error else HUD.COLOR_INFO)


func hud_node() -> HUD:
	if not is_instance_valid(_hud) or not _hud.is_inside_tree():
		_hud = _find_hud(get_tree().root)
	return _hud if is_instance_valid(_hud) else null


func shout_player() -> AudioStreamPlayer3D:
	return _shout_player


## How many times the cue has been fired — one per summon command, however many
## items it moved. Counted rather than read off the player because a headless
## audio driver is not a thing to assert against.
func shout_count() -> int:
	return _shouts


## The i18n key explaining a rejected summon, or "" when it is not an error this
## ability is responsible for wording.
static func rejection_key(error: String) -> String:
	match error:
		CommandProcessor.E_ABILITY_LOCKED, CommandProcessor.E_UNKNOWN_SERIES, \
		CommandProcessor.E_SERIES_SPENT, CommandProcessor.E_NOTHING_TO_SUMMON:
			return "ui.error." + error
		_:
			return ""


# --- Event handlers ----------------------------------------------------------

## The cue and the confirmation hang off the event, not off [method shout], for
## the same reason the arc does: in phase 4 a mate's shout should be heard.
func _on_item_summoned(_item_id: String, player_id: int, position: Vector3) -> void:
	var frame := Engine.get_process_frames()
	if frame == _last_burst_frame:
		return # same command, later item — he only shouts once
	_last_burst_frame = frame
	_shouts += 1
	# At the summon centre, which is the shouter's feet — so a mate's shout in
	# phase 4 comes from where he is standing, not from your own head.
	_shout_player.global_position = position
	_shout_player.play()
	if player_id == GameSession.local_player_id():
		toast(tr("ui.ability.called"), false)
		return
	# WP-5.3: the shout was audible to everybody and visible to nobody but the
	# shouter. Mute the tab — or simply be somebody who cannot hear it — and a
	# mate hauling a whole series across the camp happened in silence and in
	# secret. The dedupe above is why this belongs here and not in the HUD: one
	# summon publishes an event per item, and the burst is counted in this file.
	var who := PlayerNames.of(player_id)
	if not who.is_empty():
		var hud := hud_node()
		if hud != null:
			hud.show_toast(tr("ui.multi.called") % who, HUD.TOAST_SECONDS, HUD.COLOR_OTHER, false)


func _on_command_rejected(command: Dictionary, error: String) -> void:
	if not own_rejection_toasts or String(command.get("type", "")) != Commands.SUMMON:
		return
	var key := rejection_key(error)
	if not key.is_empty():
		toast(tr(key), true)


func _find_hud(node: Node) -> HUD:
	if node is HUD:
		return node as HUD
	for child in node.get_children():
		var found := _find_hud(child)
		if found != null:
			return found
	return null
