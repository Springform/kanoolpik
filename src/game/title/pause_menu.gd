class_name PauseMenu
extends CanvasLayer
## Esc menu during play (WP-1.6): resume, start the same island over, or go back
## to the title.
##
## This one DOES use `get_tree().paused` — unlike the evaluation screen, the
## level really is suspended and must resume exactly where it left off. The menu
## runs with PROCESS_MODE_ALWAYS so it can unpause itself; the player is
## pausable, so it stops receiving input the moment the tree pauses.

signal resume_requested()
signal restart_requested()
signal title_requested()
## The player wants the settings panel (WP-5.1). [Main] owns it — the panel is
## also reachable from the title screen, and it must not be built twice.
signal settings_requested()

@onready var title_label: Label = $Root/Panel/VBox/Title
@onready var resume_button: Button = $Root/Panel/VBox/Resume
@onready var restart_button: Button = $Root/Panel/VBox/Restart
@onready var settings_button: Button = $Root/Panel/VBox/Settings
@onready var title_button: Button = $Root/Panel/VBox/ToTitle

## Set false by [Main] while the evaluation screen is up, so Esc does nothing there.
var can_open := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Root.visible = false
	_apply_texts()
	resume_button.pressed.connect(close)
	# NOT through _request: settings opens ON TOP of the pause menu, which must
	# stay up and the tree must stay paused behind it.
	settings_button.pressed.connect(settings_requested.emit)
	restart_button.pressed.connect(func() -> void: _request(restart_requested))
	title_button.pressed.connect(func() -> void: _request(title_requested))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_texts()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_open():
		close()
	elif can_open:
		open()
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return $Root.visible


func open() -> void:
	$Root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()


func close() -> void:
	$Root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resume_requested.emit()


func _apply_texts() -> void:
	title_label.text = tr("ui.pause.title")
	resume_button.text = tr("ui.pause.resume")
	settings_button.text = tr("ui.pause.settings")
	restart_button.text = tr("ui.pause.restart")
	title_button.text = tr("ui.pause.to_title")


## Leave the menu and unpause before handing over, so whatever comes next starts
## from a clean tree. Main connects these deferred, since acting on them frees
## this node while it is still emitting.
func _request(what: Signal) -> void:
	$Root.visible = false
	get_tree().paused = false
	what.emit()
