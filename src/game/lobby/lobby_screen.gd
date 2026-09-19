class_name LobbyScreen
extends CanvasLayer
## The waiting room (WP-4.4). Draws what [LobbyController] knows and sends two
## button presses back; it owns no network state of its own.
##
## The code is set in 64 px because its whole job is to be read to somebody on
## the other side of a table, and it is shown grouped ("BCD-FGH") because that
## is how people say six characters out loud. [method RoomCode.normalize] takes
## the grouping straight back out, so a friend who types the dash is fine.
##
## Only Latin-1 glyphs: Godot's default font has no Dingbats, so a tick mark
## would draw as nothing at all while every string assertion passed.

signal start_pressed()
signal back_pressed()

const YOU_MARK := " «" ## "«" — Latin-1, unlike a check mark
## The relay's ceiling, restated for display only (`docs/NETWORKING.md`).
const MAX_PEERS := 6

@onready var heading: Label = $Root/Panel/VBox/Heading
@onready var code_label: Label = $Root/Panel/VBox/Code
@onready var copy_button: Button = $Root/Panel/VBox/Copy
@onready var status_label: Label = $Root/Panel/VBox/Status
@onready var roster: VBoxContainer = $Root/Panel/VBox/Roster
@onready var start_button: Button = $Root/Panel/VBox/Start
@onready var back_button: Button = $Root/Panel/VBox/Back
@onready var panel: PanelContainer = $Root/Panel

var is_host := false
var code := ""
var local_peer_id := 0
## False until the relay has actually let us in. Without it a failed join read
## "Du er med" above the sentence explaining that we are not — the screenshot
## pass caught it; no string assertion could have.
var is_open := false
var _peers: Array[int] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	copy_button.pressed.connect(_copy_code)
	start_button.pressed.connect(start_pressed.emit)
	back_button.pressed.connect(back_pressed.emit)
	apply_texts()
	back_button.grab_focus()


## The roster grows as friends arrive and the reason line wraps, so the panel is
## sized to its contents every time rather than to a number in the scene file.
## See the note in [TitleScreen] — the same fixed offsets left three controls
## sitting on the island with no background behind them.
func _fit_panel() -> void:
	if panel != null:
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		apply_texts()


## Called by [Main] once the relay has answered.
func show_room(p_code: String, p_is_host: bool, p_local_peer_id: int) -> void:
	code = p_code
	is_host = p_is_host
	local_peer_id = p_local_peer_id
	is_open = true
	apply_texts()


func set_peers(peers: Array) -> void:
	_peers.clear()
	for id: int in peers:
		_peers.append(id)
	_draw_roster()
	_fit_panel.call_deferred()


## A reason the player can act on, or "" to clear it.
func show_status(reason_key: String) -> void:
	status_label.text = tr(reason_key) if not reason_key.is_empty() else ""
	_fit_panel.call_deferred()


func apply_texts() -> void:
	if is_host:
		heading.text = tr("ui.lobby.host_heading")
	else:
		heading.text = tr("ui.lobby.client_heading") if is_open else tr("ui.lobby.joining_heading")
	code_label.text = RoomCode.spaced(code)
	# A 64 px label with nothing in it is still 64 px of hole.
	code_label.visible = not code.is_empty()
	copy_button.text = tr("ui.lobby.copy")
	copy_button.visible = is_host and not code.is_empty()
	start_button.text = tr("ui.lobby.start")
	# Only the host starts. A client's screen says so rather than offering a
	# button that would do nothing — a dead control teaches people to distrust
	# the live ones.
	start_button.visible = is_host
	back_button.text = tr("ui.lobby.leave")
	_draw_roster()
	_fit_panel.call_deferred()


func _copy_code() -> void:
	DisplayServer.clipboard_set(code)
	show_status("ui.lobby.copied")


func _draw_roster() -> void:
	if roster == null:
		return
	for child in roster.get_children():
		roster.remove_child(child)
		child.free()
	if not is_open:
		return
	if not is_host:
		# See the note on LobbyController.peers: a client is not told who else
		# is already here, so it would draw a roster that is quietly wrong.
		# Better to say what we do know.
		var waiting := Label.new()
		waiting.text = tr("ui.lobby.waiting_for_host")
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		roster.add_child(waiting)
		return
	for id in _peers:
		var row := Label.new()
		var who := tr("ui.lobby.player_n") % id
		row.text = who + (YOU_MARK if id == local_peer_id else "")
		roster.add_child(row)
	var free_seats := MAX_PEERS - _peers.size()
	if free_seats > 0:
		var room_left := Label.new()
		room_left.text = tr("ui.lobby.seats_left") % free_seats
		room_left.modulate = Color(1, 1, 1, 0.55)
		roster.add_child(room_left)
	_fit_panel.call_deferred()
