class_name SkillMenu
extends Control
## The Tab panel (WP-3.1): what the party can buy with its shared skill points.
##
## Rows are built from [constant Progression.ABILITIES] — that dictionary is the
## source of truth, so a later phase can add an ability without editing this file.
## An ability nobody can afford stays visible and legible: seeing that Autopilot
## costs 3 is what makes packing the next container feel like progress.
##
## Buying submits [method Commands.unlock] and then does nothing else. A row only
## changes when [signal GameEvents.ability_unlocked] comes back off the bus, so a
## mate's purchase in phase 4 updates this panel exactly like our own does.
##
## Deliberately does NOT pause the tree — a co-op game cannot stop the world
## because one player is shopping. It freezes the local player instead.

## Emitted instead of buying when the click could not become a command. The HUD
## turns [param error_id] into a toast; the id matches [CommandProcessor]'s.
signal purchase_refused(ability_id: String, error_id: String)

const NAME_FONT_SIZE := 20
const DESC_FONT_SIZE := 16
const BUTTON_FONT_SIZE := 17
const DESC_MIN_WIDTH := 380.0
const RIGHT_COLUMN_WIDTH := 200.0
const COLOR_OWNED := Color(0.55, 0.85, 0.55)
const COLOR_AFFORDABLE := Color(0.96, 0.96, 0.94)
const COLOR_LOCKED := Color(0.72, 0.69, 0.63)
const KEY_FONT_SIZE := 17
const COLOR_KEY := Color(1.0, 0.78, 0.35)

## Which input action fires each ability, so the panel can tell the player how to
## use what they just bought. Read from the [InputMap] rather than written out as
## text: a rebind then moves the label with it instead of quietly lying.
##
## Two do not have a key of their own and say so instead:
##   steady_hands — passive, it just raises your capacity
##   auto_place   — no new key; it changes what `interact` already does
const ABILITY_ACTIONS := {
	"insight": "ability_insight",
	"map_sense": "ability_map_sense",
	"call_mate": "ability_call_mate",
	"auto_place": "interact",
	"steady_hands": "",
}

@onready var title_label: Label = $Center/Panel/VBox/Title
@onready var points_label: Label = $Center/Panel/VBox/Points
@onready var empty_label: Label = $Center/Panel/VBox/Empty
@onready var rows_box: VBoxContainer = $Center/Panel/VBox/Rows
@onready var hint_label: Label = $Center/Panel/VBox/Hint

## ability_id -> { name, desc, cost, buy, status } — the widgets of one row.
var _rows: Dictionary = {}
var _order: Array[String] = []
## The pointer state the panel last asked for. A headless build has no pointer
## to capture and always reports MOUSE_MODE_VISIBLE, so this is what a test can
## check; [member Input.mouse_mode] is still the thing that matters on screen.
var _mouse_mode_request := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	visible = false
	$Center/Panel.add_theme_stylebox_override("panel", opaque_panel_style())
	_order = display_order()
	_build_rows()
	_apply_texts()
	GameEvents.ability_unlocked.connect(_on_ability_unlocked)
	GameEvents.points_awarded.connect(_on_points_awarded)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_texts()
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_skills"):
		return
	# Nothing to shop for before a level starts or once the score is up, but a
	# panel that is somehow still open must always be closable.
	if not is_open() and not GameSession.is_running():
		return
	toggle()
	get_viewport().set_input_as_handled()


# --- Public ----------------------------------------------------------------------

func is_open() -> bool:
	return visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	visible = true
	refresh()
	_set_player_frozen(true)
	_request_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_focus_first_buyable()


func close() -> void:
	visible = false
	_set_player_frozen(false)
	# Not while the score is up: the evaluation screen wants the pointer free.
	if GameSession.is_running():
		_request_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## The pointer state this panel last asked for — see [member _mouse_mode_request].
func requested_mouse_mode() -> int:
	return _mouse_mode_request


## Ask to buy [param ability_id]. Submits the command and returns — the panel is
## updated by the resulting event, never by this call.
func buy(ability_id: String) -> void:
	var p := GameSession.progression
	if p == null or not GameSession.is_running():
		return
	if not Progression.ABILITIES.has(ability_id):
		purchase_refused.emit(ability_id, CommandProcessor.E_UNKNOWN_ABILITY)
		return
	if p.has(ability_id):
		purchase_refused.emit(ability_id, CommandProcessor.E_ALREADY_UNLOCKED)
		return
	if not p.can_unlock(ability_id):
		purchase_refused.emit(ability_id, CommandProcessor.E_NOT_ENOUGH_POINTS)
		return
	GameSession.submit(Commands.unlock(GameSession.local_player_id(), ability_id))


## Re-read the progression and restate every row. Cheap: nothing is rebuilt.
func refresh() -> void:
	var p := GameSession.progression
	var available := p.available_points() if p != null else 0
	points_label.text = tr("ui.skills.points") % available
	empty_label.visible = available <= 0
	for id in _order:
		var row: Dictionary = _rows[id]
		var buy_button: Button = row["buy"]
		var status: Label = row["status"]
		var name_label: Label = row["name"]
		var owned: bool = p != null and p.has(id)
		var affordable: bool = p != null and p.can_unlock(id)
		buy_button.visible = not owned
		buy_button.disabled = not affordable
		status.visible = owned or not affordable
		if owned:
			status.text = tr("ui.skills.owned")
			name_label.modulate = COLOR_OWNED
		elif affordable:
			status.text = ""
			name_label.modulate = COLOR_AFFORDABLE
		else:
			status.text = tr("ui.skills.cannot_afford")
			name_label.modulate = COLOR_LOCKED


## The ability ids in the order they are listed: cheapest first, then by id so
## two abilities of the same cost never swap places between runs.
static func display_order() -> Array[String]:
	var ids: Array[String] = []
	for k in Progression.ABILITIES.keys():
		ids.append(String(k))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var cost_a := int(Progression.ABILITIES[a]["cost"])
		var cost_b := int(Progression.ABILITIES[b]["cost"])
		return a < b if cost_a == cost_b else cost_a < cost_b)
	return ids


func ability_ids() -> Array[String]:
	return _order.duplicate()


func buy_button(ability_id: String) -> Button:
	return _rows[ability_id]["buy"]


## What the right-hand column says about this ability right now ("" when it is
## affordable and the button speaks for itself).
func row_status(ability_id: String) -> String:
	var status: Label = _rows[ability_id]["status"]
	return status.text if status.visible else ""


func row_name(ability_id: String) -> String:
	return (_rows[ability_id]["name"] as Label).text


func row_description(ability_id: String) -> String:
	return (_rows[ability_id]["desc"] as Label).text


func row_cost(ability_id: String) -> String:
	return (_rows[ability_id]["cost"] as Label).text


## True when this row can be bought by clicking it.
func can_buy(ability_id: String) -> bool:
	var button: Button = _rows[ability_id]["buy"]
	return button.visible and not button.disabled


# --- Building ----------------------------------------------------------------------

## The shared theme paints panels at 62% alpha, which is right for a readout in
## a corner of the screen and wrong for a panel full of text sitting over 162
## labelled objects: on screen the world reads straight through the words. A
## modal panel gets its own opaque style rather than changing the theme, so the
## HUD keeps the translucency it was designed with.
static func opaque_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Fully opaque. At 0.97 the item labels behind it still ghosted through the
	# words, which is the problem this style exists to solve.
	style.bg_color = Color(0.05, 0.09, 0.13, 1.0)
	style.border_color = Color(0.55, 0.62, 0.68, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	return style


func _build_rows() -> void:
	for id in _order:
		var row := HBoxContainer.new()
		row.name = "Row_" + id
		row.add_theme_constant_override("separation", 12)

		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 10)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
		# How you actually use it. Buying an ability and then having to ask which
		# key it is on is the panel failing at its one job.
		var key_label := Label.new()
		key_label.add_theme_font_size_override("font_size", KEY_FONT_SIZE)
		key_label.add_theme_color_override("font_color", COLOR_KEY)
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_row.add_child(name_label)
		name_row.add_child(key_label)
		var desc_label := Label.new()
		desc_label.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(DESC_MIN_WIDTH, 0)
		left.add_child(name_row)
		left.add_child(desc_label)

		var right := VBoxContainer.new()
		right.custom_minimum_size = Vector2(RIGHT_COLUMN_WIDTH, 0)
		var cost_label := Label.new()
		cost_label.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var buy_button := Button.new()
		buy_button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
		var status_label := Label.new()
		status_label.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# Status under the cost it explains, button last — otherwise "not enough
		# points yet" ends up at the foot of the panel reading like a footnote.
		right.add_child(cost_label)
		right.add_child(status_label)
		right.add_child(buy_button)

		row.add_child(left)
		row.add_child(right)
		rows_box.add_child(row)
		buy_button.pressed.connect(_on_buy_pressed.bind(id))
		_rows[id] = {
			"name": name_label, "key": key_label, "desc": desc_label, "cost": cost_label,
			"buy": buy_button, "status": status_label,
		}


## Everything that changes only when the language does.
func _apply_texts() -> void:
	title_label.text = tr("ui.skills.title")
	hint_label.text = tr("ui.skills.hint")
	empty_label.text = tr("ui.skills.empty")
	for id in _order:
		var row: Dictionary = _rows[id]
		var name_key: String = Progression.ABILITIES[id]["name_key"]
		(row["name"] as Label).text = tr(name_key)
		(row["desc"] as Label).text = tr(name_key + ".desc")
		(row["cost"] as Label).text = tr("ui.skills.cost") % int(Progression.ABILITIES[id]["cost"])
		(row["buy"] as Button).text = tr("ui.skills.buy")
		(row["key"] as Label).text = key_hint(id)


## What to press, in square brackets, or a word when there is nothing to press.
## Public so a test can pin it — an ability whose key label goes stale is worse
## than no label, because the player believes it.
func key_hint(ability_id: String) -> String:
	var action := String(ABILITY_ACTIONS.get(ability_id, ""))
	if action.is_empty():
		return tr("ui.skills.passive")
	var key := first_key_of(action)
	if key.is_empty():
		return ""
	if action == "interact":
		# Autopilot has no key of its own; it changes what interact already does.
		return tr("ui.skills.same_key") % key
	return "[%s]" % key


## The first keyboard key bound to an action, as the player sees it printed on
## the keyboard. Taken from the live [InputMap] so a rebind moves the label too.
static func first_key_of(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			if code != KEY_NONE:
				return OS.get_keycode_string(DisplayServer.keyboard_get_label_from_physical(code))
	return ""


func _request_mouse_mode(mode: Input.MouseMode) -> void:
	_mouse_mode_request = mode
	Input.mouse_mode = mode


func _focus_first_buyable() -> void:
	for id in _order:
		var button: Button = _rows[id]["buy"]
		if button.visible and not button.disabled:
			button.grab_focus()
			return


## The world keeps running while the panel is open, but the local player stops
## taking input: no walking, no mouse-look, no picking things up by accident.
## Physics goes with it — [Player] polls movement in `_physics_process`, so that
## is the only place the walking can be switched off from outside the player.
func _set_player_frozen(frozen: bool) -> void:
	if not is_inside_tree():
		return
	var node: Node = get_tree().get_first_node_in_group(Player.LOCAL_GROUP)
	if not (node is Player):
		return
	var player := node as Player
	if frozen:
		player.velocity = Vector3.ZERO
	player.set_physics_process(player.is_local and not frozen)
	player.set_process_input(player.is_local and not frozen)


# --- Event handlers -----------------------------------------------------------------

func _on_buy_pressed(ability_id: String) -> void:
	buy(ability_id)


func _on_ability_unlocked(_ability_id: String, _player_id: int, _points_left: int) -> void:
	refresh()


func _on_points_awarded(_container_id: String, _points: int, _total_available: int) -> void:
	refresh()
