class_name Island
extends Node3D
## Builds the level from data: a procedurally generated low-poly landmass +
## water, one [ContainerNode] per catalog container at its level position, one
## [PickupItem] per item at its generated ground position.
## Requires GameSession.start_level() to have run.
##
## Terrain is generated in code from [member terrain_seed] (ADR 0008): a
## radial "dome" shaped island (higher near the middle, tapering to a beach)
## with gentle Perlin noise for variation, sampled on a regular grid that
## backs both the render mesh and a matching [HeightMapShape3D]. Nothing here
## is a downloaded asset; the whole shape is data the generator can rebuild
## byte-for-byte from [member terrain_seed].

const PICKUP_ITEM := preload("res://src/game/items/pickup_item.tscn")
const CONTAINER_NODE := preload("res://src/game/containers/container_node.tscn")

## Vertex budget for the terrain mesh (web build stays small — see ADR 0007).
const MAX_TERRAIN_VERTICES := 20000
## Slope steeper than this is not guaranteed walkable; kept as a soft ceiling
## the terrain shape must respect (see [method slope_degrees_at]).
const MAX_WALKABLE_SLOPE_DEG := 40.0

@onready var items_root: Node3D = $Items
@onready var containers_root: Node3D = $Containers

# TODO(2.4): these terrain shape parameters belong in level data once WP-2.4
# owns level authoring; for now they are @export vars on Island per WP-2.1.
## Drives every random choice below (noise + rock scatter). Same seed, same island.
@export var terrain_seed: int = 4242
## How far beyond island_radius the land tapers down to the sea floor.
@export var beach_width: float = 5.0
## Extra collision/mesh margin beyond the beach so the shore never looks clipped.
@export var terrain_margin: float = 2.0
## Grid spacing in metres. 1.0 keeps the HeightMapShape3D math simple (its
## native unit is 1 per cell) and gives a deliberately low-poly look.
@export var cell_size: float = 1.0
## Height of the gentle central dome above sea level, at the island's centre.
@export var dome_height: float = 0.7
## Amplitude of the Perlin variation added on top of the dome.
@export var noise_amplitude: float = 0.4
## Perlin frequency; low = large, gentle undulations.
@export var noise_frequency: float = 0.09
## How far below sea level the terrain settles once past the beach.
@export var water_floor_depth: float = 1.3
## Smallest height land is allowed to reach above sea level (keeps every point
## with r <= island_radius comfortably above the shoreline, and the drop-test
## and player water-check margins in [method height_at] consistent).
@export var min_land_height: float = 0.12
## Small decorative rocks scattered on the island; visual only.
@export var rock_count: int = 9
@export var rock_min_radius: float = 6.0

var island_radius := 16.0

var _noise: FastNoiseLite
var _sea_level := 0.0
var _half_extent_i := 0
var _grid_size := 0
## Cached heights for the built grid, row-major: _heights[z_index * _grid_size + x_index].
var _heights: PackedFloat32Array = PackedFloat32Array()
var _ready_for_sampling := false


func _ready() -> void:
	island_radius = GameSession.island_radius()
	_sea_level = GameSession.ground_y()
	_setup_terrain_params()
	_build_terrain()
	_scatter_rocks()
	_grow_scenery()
	_spawn_containers()
	_spawn_items()


## Idempotent setup so height_at()/is_on_land() work even if called before
## _ready() (e.g. from a test that builds an Island without adding it to the
## tree yet), and so _ready() doesn't redo this work.
func _setup_terrain_params() -> void:
	if _ready_for_sampling:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = noise_frequency
	_half_extent_i = int(ceil(island_radius + beach_width + terrain_margin))
	_grid_size = _half_extent_i * 2 + 1
	_ready_for_sampling = true


## Ground height at a point on the island, in world units.
func height_at(x: float, z: float) -> float:
	_setup_terrain_params()
	var r := Vector2(x, z).length()
	if r <= island_radius:
		return _land_height(x, z, r)
	if r <= island_radius + beach_width:
		var edge_dir := Vector2(x, z).normalized() if r > 0.0 else Vector2.RIGHT
		var edge_point := edge_dir * island_radius
		var edge_height := _land_height(edge_point.x, edge_point.y, island_radius)
		var t := (r - island_radius) / beach_width
		var s: float = smoothstep(0.0, 1.0, t)
		return lerp(edge_height, _sea_level - water_floor_depth, s)
	return _sea_level - water_floor_depth


func _land_height(x: float, z: float, r: float) -> float:
	var dome := dome_height * (1.0 - pow(r / island_radius, 2.0))
	var n := _noise.get_noise_2d(x, z) * noise_amplitude
	return maxf(_sea_level + dome + n, _sea_level + min_land_height)


## True when the point is on walkable land (inside the shoreline): the
## terrain there is above sea level. Every point with r <= island_radius is
## guaranteed true by construction (see [member min_land_height]); the beach
## band beyond it is land where it's still above water, water where it isn't.
func is_on_land(x: float, z: float) -> bool:
	return height_at(x, z) > _sea_level


## Outward normal of the terrain surface at (x, z), from central differences.
## Used for collision-agreement and slope checks, and to shade the mesh.
func normal_at(x: float, z: float, step: float = 0.5) -> Vector3:
	var h_l := height_at(x - step, z)
	var h_r := height_at(x + step, z)
	var h_d := height_at(x, z - step)
	var h_u := height_at(x, z + step)
	var dx := Vector3(2.0 * step, h_r - h_l, 0.0)
	var dz := Vector3(0.0, h_u - h_d, 2.0 * step)
	return dz.cross(dx).normalized()


## Slope at (x, z) in degrees, 0 = flat, 90 = vertical cliff.
func slope_degrees_at(x: float, z: float) -> float:
	return rad_to_deg(normal_at(x, z).angle_to(Vector3.UP))


func terrain_vertex_count() -> int:
	_setup_terrain_params()
	return _grid_size * _grid_size


func terrain_grid_size() -> int:
	_setup_terrain_params()
	return _grid_size


func terrain_half_extent() -> int:
	_setup_terrain_params()
	return _half_extent_i


# --- Mesh + collision ------------------------------------------------------

func _build_terrain() -> void:
	_heights = PackedFloat32Array()
	_heights.resize(_grid_size * _grid_size)
	for zi in range(_grid_size):
		var z := float(zi - _half_extent_i) * cell_size
		for xi in range(_grid_size):
			var x := float(xi - _half_extent_i) * cell_size
			_heights[zi * _grid_size + xi] = height_at(x, z)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.add_child(_build_collision_shape())
	ground.add_child(_build_mesh_instance())
	add_child(ground)

	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	# Large enough that its edge never shows, even from the title camera looking
	# down from 26 m — at 400 m you could see the plane end against the sky.
	plane.size = Vector2(2000, 2000)
	water.mesh = plane
	water.position.y = _sea_level - 0.05
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1, 0.35, 0.55, 0.85)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wmat
	add_child(water)


func _build_collision_shape() -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var hm := HeightMapShape3D.new()
	hm.map_width = _grid_size
	hm.map_depth = _grid_size
	hm.map_data = _heights
	shape.shape = hm
	return shape


func _build_mesh_instance() -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"

	# Built by hand (rather than via SurfaceTool.commit_to_arrays()) so the
	# surface carries exactly VERTEX/NORMAL/COLOR/UV/INDEX and no zeroed
	# TANGENT array — an all-zero tangent attribute reliably breaks lighting
	# under the GL Compatibility renderer (verified empirically; see WP-2.1
	# decisions in the roadmap doc).
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(_grid_size * _grid_size)
	normals.resize(_grid_size * _grid_size)
	colors.resize(_grid_size * _grid_size)
	uvs.resize(_grid_size * _grid_size)
	for zi in range(_grid_size):
		var z := float(zi - _half_extent_i) * cell_size
		for xi in range(_grid_size):
			var x := float(xi - _half_extent_i) * cell_size
			var idx := zi * _grid_size + xi
			var h := _heights[idx]
			var n := normal_at(x, z)
			vertices[idx] = Vector3(x, h, z)
			normals[idx] = n
			colors[idx] = _terrain_color(h, n)
			uvs[idx] = Vector2(float(xi), float(zi))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _build_index_array()
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_inst.mesh = array_mesh

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mesh_inst.material_override = mat
	return mesh_inst


func _build_index_array() -> PackedInt32Array:
	var indices := PackedInt32Array()
	indices.resize((_grid_size - 1) * (_grid_size - 1) * 6)
	var k := 0
	for zi in range(_grid_size - 1):
		for xi in range(_grid_size - 1):
			var i0 := zi * _grid_size + xi
			var i1 := i0 + 1
			var i2 := i0 + _grid_size
			var i3 := i2 + 1
			indices[k] = i0; k += 1
			indices[k] = i1; k += 1
			indices[k] = i2; k += 1
			indices[k] = i1; k += 1
			indices[k] = i3; k += 1
			indices[k] = i2; k += 1
	return indices


func _terrain_color(h: float, n: Vector3) -> Color:
	var slope := rad_to_deg(n.angle_to(Vector3.UP))
	if h < _sea_level + 0.35:
		return Color(0.62, 0.54, 0.36) # sand
	if slope > 32.0:
		return Color(0.4, 0.38, 0.36) # rock
	return Color(0.24, 0.38, 0.18) # grass


## Trees, grass and reeds. Kept in its own node so WP-2.5 owns the look without
## touching terrain generation.
func _grow_scenery() -> void:
	var scenery := Scenery.new()
	scenery.name = "Scenery"
	scenery.setup(self)
	add_child(scenery)


func _scatter_rocks() -> void:
	var rocks := Node3D.new()
	rocks.name = "Rocks"
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
	var placed := 0
	var attempts := 0
	while placed < rock_count and attempts < rock_count * 20:
		attempts += 1
		var r := rng.randf_range(rock_min_radius, island_radius - 1.0)
		var a := rng.randf_range(0.0, TAU)
		var x := cos(a) * r
		var z := sin(a) * r
		if slope_degrees_at(x, z) > 25.0:
			continue
		# Two tilted, unevenly scaled boxes rather than a sphere: angular reads as
		# stone, and it matches the boxy language of the items. A smooth sphere
		# looked like a marshmallow at eye level.
		var rock := Node3D.new()
		var scale_f := rng.randf_range(0.18, 0.45)
		var shade := rng.randf_range(-0.05, 0.05)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45 + shade, 0.44 + shade, 0.42 + shade)
		mat.roughness = 0.95
		for chunk in range(2):
			var piece := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(
				scale_f * rng.randf_range(1.4, 2.2),
				scale_f * rng.randf_range(0.7, 1.3),
				scale_f * rng.randf_range(1.4, 2.2))
			piece.mesh = box
			piece.material_override = mat
			piece.rotation = Vector3(
				rng.randf_range(-0.25, 0.25), rng.randf_range(0.0, TAU), rng.randf_range(-0.25, 0.25))
			piece.position = Vector3(
				rng.randf_range(-scale_f, scale_f), chunk * scale_f * 0.45, rng.randf_range(-scale_f, scale_f))
			rock.add_child(piece)
		rock.position = Vector3(x, height_at(x, z), z)
		rocks.add_child(rock)
		placed += 1
	add_child(rocks)


func _spawn_containers() -> void:
	for cid in GameSession.catalog.container_ids():
		var node: ContainerNode = CONTAINER_NODE.instantiate()
		node.setup(GameSession.catalog.get_container(cid))
		node.name = "Container_" + cid
		var pos := GameSession.container_position(cid)
		pos.y = height_at(pos.x, pos.z)
		node.position = pos
		containers_root.add_child(node)


func _spawn_items() -> void:
	for id in GameSession.catalog.item_ids():
		var node: PickupItem = PICKUP_ITEM.instantiate()
		node.setup(GameSession.catalog.get_item(id))
		node.name = "Item_" + id
		# Placed and carried items have no meaningful ground position; PickupItem
		# hides them on _ready, so only the position of loose items matters.
		var pos: Vector3 = GameSession.state.location(id)["position"]
		pos.y = height_at(pos.x, pos.z) + 0.15
		node.position = pos
		items_root.add_child(node)
