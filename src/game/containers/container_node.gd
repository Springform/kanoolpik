class_name ContainerNode
extends StaticBody3D
## Presentation of one container (pant bag, cooler, canoe...).
##
## Placeholder visual: a translucent box with a label and a row of small
## "slot" cubes that fill in as items are placed. Green = correct, red = wrong.
## Phase 2 replaces the box with a real model via ContainerDef.scene.

var container_id: String
var def: ContainerDef

@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $Label
@onready var slots_root: Node3D = $Slots

var _slot_meshes: Array[MeshInstance3D] = []
var _mat_correct := StandardMaterial3D.new()
var _mat_wrong := StandardMaterial3D.new()
var _mat_empty := StandardMaterial3D.new()


func setup(p_def: ContainerDef) -> void:
	def = p_def
	container_id = p_def.id


func _ready() -> void:
	_mat_correct.albedo_color = Color(0.2, 0.8, 0.3)
	_mat_wrong.albedo_color = Color(0.9, 0.2, 0.2)
	_mat_empty.albedo_color = Color(1, 1, 1, 0.25)
	_mat_empty.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var width := 0.25 * def.slot_count + 0.3
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.6, 0.8)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.4, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	var shape: BoxShape3D = $Collision.shape
	shape.size = box.size
	label.text = tr(def.name_key)
	label.position.y = 0.9
	for i in range(def.slot_count):
		var m := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.18, 0.18, 0.18)
		m.mesh = cube
		m.material_override = _mat_empty
		m.position = Vector3(-width * 0.5 + 0.25 + i * 0.25, 0.4, 0)
		slots_root.add_child(m)
		_slot_meshes.append(m)
	GameEvents.item_placed.connect(_on_item_placed)
	GameEvents.item_taken_out.connect(_on_item_taken_out)
	GameEvents.container_completed.connect(_on_completed)


func first_free_slot() -> int:
	for i in range(def.slot_count):
		if GameSession.state.item_in_slot(container_id, i).is_empty():
			return i
	return -1


func refresh() -> void:
	var verdicts := PlacementRules.verdicts_in_container(GameSession.catalog, GameSession.state, container_id)
	for i in range(_slot_meshes.size()):
		_slot_meshes[i].material_override = _mat_empty
	for entry in GameSession.state.items_in_container(container_id):
		var v: int = verdicts[entry["item_id"]]
		_slot_meshes[entry["slot"]].material_override = _mat_correct if v == PlacementRules.Verdict.CORRECT else _mat_wrong


func _on_item_placed(_item_id: String, _player_id: int, cid: String, _slot: int, _verdict: int) -> void:
	if cid == container_id:
		refresh()


func _on_item_taken_out(_item_id: String, _player_id: int, cid: String) -> void:
	if cid == container_id:
		refresh()


func _on_completed(cid: String) -> void:
	if cid == container_id:
		label.text = "✓ " + tr(def.name_key)
