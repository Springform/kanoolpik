class_name TestPanel
extends CanvasLayer
## The test-mode admin panel (WP-3.10). F1 opens and closes it.
##
## It exists so a piece of the game can be reached without playing the whole
## game to get there. The win condition is the reason it was built: verifying it
## used to cost a complete tidy-up of 162 items.
##
## [b]The one rule this panel obeys[/b]
##
## Every world change it makes is submitted as a command, exactly like a
## keypress. It never writes to [WorldState] or [Progression] directly. That is
## not tidiness for its own sake:
##
##   - a peer replaying the command list lands in the same place, cheats and all,
##     so test mode stays usable in phase 4 instead of desyncing the party;
##   - the things it exercises are the real code paths, so a bug it fails to
##     find is a bug a player would not have hit either. A panel that poked the
##     state directly would "pass" through code the game never runs.
##
## The one command that exists only for this panel is
## [method Commands.grant_points], and the processor refuses it unless
## [member CommandProcessor.allow_debug_commands] is set.
##
## Presentation-only conveniences — teleporting, opening the evaluation screen —
## do not go through commands, because a camera position is not world state.

const ACTION := "ui_test_panel" # F1, declared in project.godot
const WIDTH := 380.0
const MARGIN := 12.0
## Clock jumps offered as buttons, in minutes. Par is 20 and max is 40, so these
## straddle every grade boundary worth looking at.
const CLOCK_JUMPS: Array[int] = [5, 15, 25, 45]
const TICKS_PER_SECOND := 60

var _root: PanelContainer
var _body: VBoxContainer
var _status: RichTextLabel
var _containers_box: VBoxContainer
var _player: Player


func _ready() -> void:
	layer = 128 # above the HUD, which is where a debug overlay belongs
	_build()
	visible = false
	GameEvents.local_player_spawned.connect(func(p: Node3D) -> void: _player = p)
	var existing := get_tree().get_first_node_in_group(Player.LOCAL_GROUP)
	if existing is Player:
		_player = existing
	for signal_name in ["progress_changed", "ability_unlocked", "container_completed"]:
		GameEvents.connect(signal_name, func(_a = null, _b = null, _c = null) -> void: _refresh())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	visible = true
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	if GameSession.is_running():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- The tools ----------------------------------------------------------------

## Skill points, straight into the party's pocket.
func grant_points(points: int) -> void:
	if not GameSession.is_running():
		return
	GameSession.submit(Commands.grant_points(GameSession.local_player_id(), points))


## Buy an ability whether or not the points are there: top up first, then use the
## ordinary unlock command, so what gets exercised is the real purchase path.
func unlock(ability_id: String) -> void:
	if not GameSession.is_running() or GameSession.progression.has(ability_id):
		return
	var cost := int(Progression.ABILITIES[ability_id]["cost"])
	var short := cost - GameSession.progression.available_points()
	if short > 0:
		grant_points(short)
	GameSession.submit(Commands.unlock(GameSession.local_player_id(), ability_id))


## Pack everything except one item, which is left where it lies.
##
## This is the win-condition tool: walk to the survivor, put it away by hand, and
## watch `island_clean`, the canoes and the evaluation screen happen for real.
## Returns the id of the item left behind, or "" when there was nothing to do.
##
## The survivor is the one nearest the player, so it is a walk and not an
## expedition. Items already correctly placed are skipped; anything with no
## correct slot free is left alone rather than forced somewhere wrong.
func pack_all_but_one() -> String:
	if not GameSession.is_running():
		return ""
	var survivor := _nearest_loose_item()
	if survivor.is_empty():
		return ""
	var pid := GameSession.local_player_id()
	for item_id in GameSession.catalog.item_ids():
		if item_id == survivor:
			continue
		if GameSession.state.kind_of(item_id) == WorldState.Kind.PLACED:
			continue
		_put_away(pid, item_id)
	_refresh()
	return survivor


## Advance the simulation clock, which is what the speed score reads.
func set_clock_minutes(minutes: int) -> void:
	if not GameSession.is_running():
		return
	var target := minutes * 60 * TICKS_PER_SECOND
	var delta := target - GameSession.state.elapsed_ticks
	if delta > 0:
		GameSession.submit(Commands.tick(delta))
	_refresh()


## Show the evaluation with whatever the run looks like right now. Presentation
## only: nothing about the world changes, so the island is exactly as it was if
## the screen is dismissed.
func show_evaluation() -> void:
	var main := _main()
	if main != null and main.evaluation != null:
		close()
		main.evaluation.show_evaluation()


## Put the player next to a container. A position is presentation, so this is a
## direct move and not a command.
func teleport_to(container_id: String) -> void:
	if _player == null or not GameSession.is_running():
		return
	var target := GameSession.container_position(container_id)
	# Stand a couple of metres off so the container is in front of him rather
	# than inside him, and on the terrain rather than under it.
	var x := target.x + 2.0
	var z := target.z + 2.0
	var main := _main()
	var y := main.island.height_at(x, z) if main != null and main.island != null else target.y
	_player.global_position = Vector3(x, y + 1.2, z)
	close()


## Which items each container is still waiting for.
func missing_by_container() -> Dictionary:
	var out: Dictionary = {}
	if not GameSession.is_running():
		return out
	for cid in GameSession.catalog.container_ids():
		var missing: Array[String] = []
		for item_id in GameSession.catalog.item_ids():
			if GameSession.state.container_of(item_id) == cid:
				continue
			var item := GameSession.catalog.get_item(item_id)
			if not GameSession.catalog.get_container(cid).accepts.has(item.category):
				continue
			if GameSession.state.kind_of(item_id) != WorldState.Kind.PLACED:
				missing.append(item_id)
		out[cid] = missing
	return out


# --- Internals -----------------------------------------------------------------

## One item, picked up and placed in the first container with a correct slot.
## Two ordinary commands — the same two a player issues.
func _put_away(pid: int, item_id: String) -> void:
	var item := GameSession.catalog.get_item(item_id)
	if item == null:
		return
	for container in GameSession.catalog.containers_accepting(item.category):
		var slot := PlacementRules.find_correct_slot(
			GameSession.catalog, GameSession.state, item_id, container.id)
		if slot < 0:
			continue
		if GameSession.state.kind_of(item_id) != WorldState.Kind.CARRIED:
			GameSession.submit(Commands.pick_up(pid, item_id))
		GameSession.submit(Commands.place(pid, item_id, container.id, slot))
		return


## The loose item closest to the player — the one it costs least to go and get.
func _nearest_loose_item() -> String:
	var from := _player.global_position if _player != null else Vector3.ZERO
	var best := ""
	var best_distance := INF
	for item_id in GameSession.state.items_of_kind(WorldState.Kind.GROUND):
		var d: float = from.distance_to(GameSession.state.location(item_id)["position"])
		if d < best_distance:
			best_distance = d
			best = item_id
	# Nothing on the ground: anything still in hand will do.
	if best.is_empty():
		var carried := GameSession.state.carried_by(GameSession.local_player_id())
		if not carried.is_empty():
			best = carried[0]
	return best


func _main() -> Main:
	var node := get_parent()
	while node != null and not (node is Main):
		node = node.get_parent()
	return node as Main


# --- The panel itself ----------------------------------------------------------
#
# Built in code rather than as a .tscn on purpose: it is a developer tool whose
# contents follow the ability list and the container list, and a scene file would
# be one more thing to keep in step with them.

func _build() -> void:
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_root.offset_left = -WIDTH - MARGIN
	_root.offset_right = -MARGIN
	_root.offset_top = MARGIN
	_root.offset_bottom = 620.0
	add_child(_root)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	scroll.add_child(_body)

	_heading(tr("ui.test.title"))
	_status = RichTextLabel.new()
	_status.fit_content = true
	_status.bbcode_enabled = false
	_status.custom_minimum_size = Vector2(0, 78)
	_body.add_child(_status)

	_heading(tr("ui.test.win_condition"))
	_button(tr("ui.test.pack_all_but_one"), func() -> void:
		var left := pack_all_but_one()
		close()
		_toast(tr("ui.test.left_behind") % tr(GameSession.catalog.get_item(left).name_key) if not left.is_empty() else tr("ui.test.nothing_left")))
	_button(tr("ui.test.show_evaluation"), show_evaluation)

	_heading(tr("ui.test.points"))
	var points_row := HBoxContainer.new()
	_body.add_child(points_row)
	for n in [1, 3, 10]:
		var b := Button.new()
		b.text = "+%d" % n
		b.pressed.connect(func() -> void: grant_points(n))
		points_row.add_child(b)
	for ability_id: String in Progression.ABILITIES.keys():
		_button(tr("ui.test.unlock") % tr(String(Progression.ABILITIES[ability_id]["name_key"])),
			func() -> void: unlock(ability_id))

	_heading(tr("ui.test.clock"))
	var clock_row := HBoxContainer.new()
	_body.add_child(clock_row)
	for minutes in CLOCK_JUMPS:
		var b := Button.new()
		b.text = "%d min" % minutes
		b.pressed.connect(func() -> void: set_clock_minutes(minutes))
		clock_row.add_child(b)

	_heading(tr("ui.test.containers"))
	_containers_box = VBoxContainer.new()
	_body.add_child(_containers_box)


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	_body.add_child(HSeparator.new())
	_body.add_child(label)


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	_body.add_child(b)
	return b


func _toast(text: String) -> void:
	var hud := _main().hud if _main() != null else null
	if hud != null:
		hud.show_toast(text, 3.0)


## Redraw the readouts. Cheap enough to run on every event the panel listens to,
## and it only matters while the panel is open.
func _refresh() -> void:
	if _status == null or not GameSession.is_running():
		return
	var progress := Evaluation.progress(GameSession.catalog, GameSession.state)
	var seconds := int(GameSession.state.elapsed_ticks / float(TICKS_PER_SECOND))
	_status.text = "%s\n%s\n%s" % [
		tr("ui.test.status_items") % [int(progress.get("correct", 0)), int(progress.get("total", 0))],
		tr("ui.test.status_points") % [GameSession.progression.available_points(),
			GameSession.progression.unlocked.size()],
		tr("ui.test.status_clock") % [HUD.format_time(seconds),
			int(GameSession.state.stats.get("wrong_placements", 0))],
	]
	_rebuild_container_rows()


func _rebuild_container_rows() -> void:
	if _containers_box == null or not is_open():
		return
	for child in _containers_box.get_children():
		child.queue_free()
	var missing := missing_by_container()
	for cid: String in GameSession.catalog.container_ids():
		var left: Array = missing.get(cid, [])
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s — %d" % [tr(GameSession.catalog.get_container(cid).name_key), left.size()]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var go := Button.new()
		go.text = tr("ui.test.go")
		go.pressed.connect(func() -> void: teleport_to(cid))
		row.add_child(go)
		_containers_box.add_child(row)
