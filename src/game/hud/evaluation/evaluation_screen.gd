class_name EvaluationScreen
extends CanvasLayer
## "Lejrlederens vurdering" — the end-of-level screen (WP-1.5).
##
## Appears on [signal GameEvents.island_clean]: ends the session (which stops
## the simulation clock and locks out further commands), releases the mouse,
## counts the numbers up, and offers to play the same island again or roll a
## fresh mess.
##
## Deliberately NOT `get_tree().paused`: the level is finished, not suspended,
## and a global pause would also freeze timers this screen and the test runner
## depend on. Phase 1.6's pause menu is the place for a real pause.
##
## All figures come from [method Evaluation.score] using the level's par/max
## times, so this screen never computes anything itself.

const COUNT_UP_SECONDS := 1.4

@onready var panel: PanelContainer = $Root/Panel
@onready var completion_value: Label = $Root/Panel/VBox/Rows/CompletionValue
@onready var accuracy_value: Label = $Root/Panel/VBox/Rows/AccuracyValue
@onready var time_value: Label = $Root/Panel/VBox/Rows/TimeValue
@onready var points_label: Label = $Root/Panel/VBox/Points
@onready var grade_label: Label = $Root/Panel/VBox/Grade
@onready var seed_label: Label = $Root/Panel/VBox/Seed
@onready var skip_label: Label = $Root/Panel/VBox/Skip
@onready var again_button: Button = $Root/Panel/VBox/Buttons/Again
@onready var new_button: Button = $Root/Panel/VBox/Buttons/New
@onready var title_label: Label = $Root/Panel/VBox/Title

## The score being displayed, or {} while hidden.
var score: Dictionary = {}

var _tween: Tween
var _shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keep working even if something else pauses
	$Root.visible = false
	# Static text lives in code, not the scene, so it goes through tr().
	title_label.text = tr("ui.evaluation")
	$Root/Panel/VBox/Rows/CompletionLabel.text = tr("ui.completion")
	$Root/Panel/VBox/Rows/AccuracyLabel.text = tr("ui.accuracy")
	$Root/Panel/VBox/Rows/TimeLabel.text = tr("ui.time")
	again_button.text = tr("ui.eval.again")
	new_button.text = tr("ui.eval.new")
	GameEvents.island_clean.connect(_on_island_clean)
	again_button.pressed.connect(_on_again)
	new_button.pressed.connect(_on_new)


func _input(event: InputEvent) -> void:
	if _shown and event is InputEventMouseButton and event.pressed:
		skip_count_up()


func is_showing() -> bool:
	return _shown


## Show the screen for the current world state. Called by the island_clean
## event; exposed so tests and the flow WP can drive it directly.
func show_evaluation() -> void:
	score = Evaluation.score(
		GameSession.catalog, GameSession.state,
		float(GameSession.level.get("par_seconds", Evaluation.DEFAULT_PAR_SECONDS)),
		float(GameSession.level.get("max_seconds", Evaluation.DEFAULT_MAX_SECONDS)))
	_shown = true
	$Root.visible = true
	seed_label.text = tr("ui.eval.seed") % GameSession.state.rng_seed
	skip_label.text = tr("ui.eval.skip")
	grade_label.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSession.stop_level() # freezes the clock and blocks further commands
	_animate_count_up()


## Jump straight to the final figures (a click does this too).
func skip_count_up() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_render(1.0)
	_finish()


func hide_evaluation() -> void:
	_shown = false
	$Root.visible = false


# --- Rendering ------------------------------------------------------------------

func _animate_count_up() -> void:
	_render(0.0)
	_tween = create_tween()
	_tween.tween_method(_render, 0.0, 1.0, COUNT_UP_SECONDS).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finish)


## [param progress] 0..1 drives the count-up; 1.0 is the true result.
func _render(progress: float) -> void:
	completion_value.text = tr("ui.eval.percent") % int(round(score["completion"] * 100.0 * progress))
	accuracy_value.text = tr("ui.eval.percent") % int(round(score["accuracy"] * 100.0 * progress))
	time_value.text = HUD.format_time(int(score["elapsed_seconds"] * progress))
	points_label.text = tr("ui.eval.points") % int(round(score["points"] * progress))


func _finish() -> void:
	grade_label.text = tr(Evaluation.grade_key(score["grade"]))
	skip_label.text = ""


# --- Handlers -------------------------------------------------------------------

func _on_island_clean() -> void:
	show_evaluation()


func _on_again() -> void:
	_restart(true)


func _on_new() -> void:
	_restart(false)


func _restart(same_island: bool) -> void:
	hide_evaluation()
	var main := get_parent() as Main
	if main == null:
		return
	# Deferred: this runs from a button signal and the restart frees this node.
	if same_island:
		main.restart_same_island.call_deferred()
	else:
		main.restart_new_mess.call_deferred()
