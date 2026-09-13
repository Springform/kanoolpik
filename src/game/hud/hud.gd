extends CanvasLayer
## Minimal HUD: progress, carrying, crosshair prompt and a fading verdict toast.
## Phase 3 owns the real UI; keep this thin.

@onready var progress_label: Label = $Margin/VBox/Progress
@onready var carrying_label: Label = $Margin/VBox/Carrying
@onready var prompt_label: Label = $Prompt
@onready var toast_label: Label = $Toast
@onready var toast_timer: Timer = $ToastTimer

var _player: Player


func _ready() -> void:
	GameEvents.progress_changed.connect(_on_progress)
	GameEvents.item_placed.connect(_on_item_placed)
	GameEvents.container_completed.connect(_on_container_completed)
	GameEvents.island_clean.connect(_on_island_clean)
	GameEvents.command_rejected.connect(_on_rejected)
	GameEvents.local_player_spawned.connect(func(p): _player = p)
	toast_timer.timeout.connect(func(): toast_label.text = "")
	toast_label.text = ""
	prompt_label.text = ""
	if GameSession.catalog != null:
		_on_progress(Evaluation.progress(GameSession.catalog, GameSession.state))


func _process(_delta: float) -> void:
	if _player == null:
		return
	var held := _player.carried_items()
	var carried := GameSession.processor.carried_load(GameSession.state, _player.player_id)
	carrying_label.text = tr("ui.carrying") % [carried, GameSession.state.player_capacity(_player.player_id)]
	var target := _player.aimed_target()
	if target is PickupItem:
		prompt_label.text = tr("ui.interact")
	elif target is ContainerNode and not held.is_empty():
		prompt_label.text = tr("ui.place") % tr(target.def.name_key)
	elif not held.is_empty():
		prompt_label.text = tr("ui.drop")
	else:
		prompt_label.text = ""


func _on_progress(p: Dictionary) -> void:
	progress_label.text = tr("ui.progress") % [p["correct"], p["total"]]


func _on_item_placed(_item_id: String, _player_id: int, _cid: String, _slot: int, verdict: int) -> void:
	var key := "ui.verdict." + PlacementRules.verdict_name(verdict).to_lower()
	_toast(tr(key))


func _on_container_completed(cid: String) -> void:
	_toast(tr("ui.container_complete") % tr(GameSession.catalog.get_container(cid).name_key))


func _on_island_clean() -> void:
	_toast(tr("ui.island_clean"), 10.0)


func _on_rejected(_cmd: Dictionary, error: String) -> void:
	_toast(error, 1.0)


func _toast(text: String, seconds: float = 2.0) -> void:
	toast_label.text = text
	toast_timer.start(seconds)
