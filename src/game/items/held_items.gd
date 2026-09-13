class_name HeldItems
extends Node3D
## Shows what a player is carrying, as a small stack in the lower-right of the
## view (attach under the player's Camera3D). The most recently picked-up item
## sits on top and is slightly larger — that is the one E/Q act on.
##
## Reads GameSession.state.carried_by(pid) (pick-up order) on every relevant
## event; never mutates state. Remote players (phase 4) attach the same node to
## their avatar with [member is_first_person] = false to show items at the hip.

const BASE_OFFSET := Vector3(1.05, -0.62, -0.9) ## camera space, first person (lower-right at FOV 90)
const STACK_STEP := 0.045
const HELD_SCALE := 0.32
const ACTIVE_SCALE := 0.42
const ANIM_SECONDS := 0.18

@export var is_first_person := true

var player_id: int = -1
var _nodes: Dictionary = {} # item_id -> Node3D


func set_player(pid: int) -> void:
	player_id = pid
	if is_inside_tree():
		_rebuild()


func _ready() -> void:
	if is_first_person:
		position = BASE_OFFSET
	GameEvents.item_picked_up.connect(_on_changed_pid)
	GameEvents.item_taken_out.connect(_on_changed_pid_3)
	GameEvents.item_dropped.connect(_on_changed_pid_3v)
	GameEvents.item_placed.connect(_on_placed)
	_rebuild()


func item_count() -> int:
	return _nodes.size()


func top_item_id() -> String:
	return GameSession.state.active_item(player_id) if GameSession.state != null else ""


func held_ids() -> Array[String]:
	return GameSession.state.carried_by(player_id) if GameSession.state != null else []


# --- Event handlers ---------------------------------------------------------------

func _on_changed_pid(_item_id: String, pid: int) -> void:
	if pid == player_id:
		_rebuild()


func _on_changed_pid_3(_item_id: String, pid: int, _cid: String) -> void:
	if pid == player_id:
		_rebuild()


func _on_changed_pid_3v(_item_id: String, pid: int, _pos: Vector3) -> void:
	if pid == player_id:
		_rebuild()


func _on_placed(_item_id: String, pid: int, _cid: String, _slot: int, _verdict: int) -> void:
	if pid == player_id:
		_rebuild()


# --- Layout -------------------------------------------------------------------------

func _rebuild() -> void:
	if player_id < 0 or GameSession.state == null or GameSession.catalog == null:
		return
	var held := held_ids()
	# Remove nodes for items no longer held (shrink out).
	for id in _nodes.keys():
		if not held.has(id):
			var gone: Node3D = _nodes[id]
			_nodes.erase(id)
			var t := gone.create_tween()
			t.tween_property(gone, "scale", Vector3.ZERO, ANIM_SECONDS)
			t.tween_callback(gone.queue_free)
	# Add / reposition in pick-up order; last = top = active.
	for i in range(held.size()):
		var id: String = held[i]
		var is_top := i == held.size() - 1
		var target_scale := Vector3.ONE * (ACTIVE_SCALE if is_top else HELD_SCALE)
		var target_pos := Vector3(0, i * STACK_STEP, -i * 0.02)
		var node: Node3D
		if _nodes.has(id):
			node = _nodes[id]
			var t := node.create_tween()
			t.set_parallel(true)
			t.tween_property(node, "position", target_pos, ANIM_SECONDS)
			t.tween_property(node, "scale", target_scale, ANIM_SECONDS)
		else:
			node = ItemPalette.make_held_visual(GameSession.catalog.get_item(id))
			node.name = "Held_" + id
			for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = target_pos
			node.scale = Vector3.ZERO
			node.rotation_degrees = Vector3(10, -25, 0)
			add_child(node)
			_nodes[id] = node
			var t := node.create_tween()
			t.tween_property(node, "scale", target_scale, ANIM_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
