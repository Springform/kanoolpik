class_name Island
extends Node3D
## Builds the level from data: gray-box ground + water, one [ContainerNode] per
## catalog container at its level position, one [PickupItem] per item at its
## generated ground position. Requires GameSession.start_level() to have run.
##
## Phase 2 replaces the gray-box with real terrain; keep the spawning logic.

const PICKUP_ITEM := preload("res://src/game/items/pickup_item.tscn")
const CONTAINER_NODE := preload("res://src/game/containers/container_node.tscn")

@onready var items_root: Node3D = $Items
@onready var containers_root: Node3D = $Containers


var island_radius := 16.0


func _ready() -> void:
	island_radius = GameSession.island_radius()
	_build_ground()
	_spawn_containers()
	_spawn_items()


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = island_radius
	cyl.height = 1.0
	shape.shape = cyl
	shape.position.y = -0.5
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = island_radius
	cm.bottom_radius = island_radius + 1.5
	cm.height = 1.0
	mesh.mesh = cm
	mesh.position.y = -0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.55, 0.28)
	mesh.material_override = mat
	ground.add_child(mesh)
	add_child(ground)

	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	water.mesh = plane
	water.position.y = -0.35
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1, 0.35, 0.55, 0.85)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wmat
	add_child(water)


func _spawn_containers() -> void:
	for cid in GameSession.catalog.container_ids():
		var node: ContainerNode = CONTAINER_NODE.instantiate()
		node.setup(GameSession.catalog.get_container(cid))
		node.name = "Container_" + cid
		node.position = GameSession.container_position(cid)
		containers_root.add_child(node)


func _spawn_items() -> void:
	for id in GameSession.catalog.item_ids():
		var node: PickupItem = PICKUP_ITEM.instantiate()
		node.setup(GameSession.catalog.get_item(id))
		node.name = "Item_" + id
		var pos: Vector3 = GameSession.state.location(id)["position"]
		node.position = pos + Vector3(0, 0.15, 0)
		items_root.add_child(node)
