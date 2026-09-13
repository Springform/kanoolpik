class_name PickupItem
extends StaticBody3D
## Presentation of one catalog item lying on the island.
##
## Placeholder visual: a coloured box (see [ItemPalette]) with the item name
## floating above it. Phase 2 swaps the box for real models via ItemDef.model.
## Reacts to core events on the bus; never mutates state itself.

var item_id: String
var def: ItemDef

@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $Label


func setup(p_def: ItemDef) -> void:
	def = p_def
	item_id = p_def.id


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = ItemPalette.box_size(def)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ItemPalette.color_for(def.category)
	mesh.material_override = mat
	var shape: BoxShape3D = $Collision.shape
	shape.size = box.size
	label.text = tr(def.name_key)
	label.position.y = box.size.y + 0.15
	GameEvents.item_picked_up.connect(_on_picked_up)
	GameEvents.item_dropped.connect(_on_dropped)
	GameEvents.item_placed.connect(_on_placed)
	GameEvents.item_taken_out.connect(_on_taken_out)


func _on_picked_up(id: String, _player_id: int) -> void:
	if id == item_id:
		_set_in_world(false)


func _on_dropped(id: String, _player_id: int, position: Vector3) -> void:
	if id == item_id:
		global_position = position + Vector3(0, mesh.mesh.size.y * 0.5, 0)
		_set_in_world(true)


func _on_placed(id: String, _player_id: int, _container_id: String, _slot: int, _verdict: int) -> void:
	if id == item_id:
		_set_in_world(false) # ContainerNode renders placed items itself.


func _on_taken_out(id: String, _player_id: int, _container_id: String) -> void:
	if id == item_id:
		_set_in_world(false)


func _set_in_world(in_world: bool) -> void:
	visible = in_world
	$Collision.disabled = not in_world
