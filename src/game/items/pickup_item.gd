class_name PickupItem
extends StaticBody3D
## Presentation of one catalog item lying on the island.
##
## Placeholder visual: a coloured box sized by ItemDef.size with the item name
## floating above it. Phase 2 swaps the box for real models via ItemDef.model.
## Reacts to core events on the bus; never mutates state itself.

const CATEGORY_COLOURS := {
	"can": Color(0.85, 0.75, 0.2), "bottle_plastic": Color(0.6, 0.3, 0.2), "bottle_glass": Color(0.3, 0.6, 0.35),
	"trash": Color(0.55, 0.55, 0.55), "food": Color(0.9, 0.5, 0.5), "tent_pole": Color(0.2, 0.4, 0.8),
	"tent_peg": Color(0.3, 0.3, 0.6), "tent_canvas": Color(0.15, 0.3, 0.6), "clothing": Color(0.8, 0.4, 0.8),
	"paddle": Color(0.6, 0.4, 0.2), "life_vest": Color(1.0, 0.5, 0.0), "firewood": Color(0.4, 0.25, 0.1),
}

var item_id: String
var def: ItemDef

@onready var mesh: MeshInstance3D = $Mesh
@onready var label: Label3D = $Label


func setup(p_def: ItemDef) -> void:
	def = p_def
	item_id = p_def.id


func _ready() -> void:
	var box := BoxMesh.new()
	var s := 0.18 + 0.08 * def.size
	box.size = Vector3(s, s * 0.8, s)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CATEGORY_COLOURS.get(def.category, Color.WHITE)
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
