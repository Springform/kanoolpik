class_name Scenery
extends Node3D
## Trees, bushes, grass and reeds on the island (WP-2.5).
##
## Everything is generated from the terrain seed (ADR 0008) and placed through
## [Island.height_at], so scenery follows the ground without any authored data.
##
## The one rule that matters: **scenery never stands where the game happens.**
## It keeps clear of container footprints, of the spawn zones where items land,
## and of the player spawns. Otherwise a tree eventually swallows a sock, and a
## sock you cannot see is a run you cannot finish.

## Grass is drawn as one MultiMesh of small tufts — thousands of instances, one
## draw call. Trees and bushes are ordinary nodes; there are few enough of them.
const GRASS_TUFTS := 4000
const TREE_COUNT := 34
const BUSH_COUNT := 26
const REED_CLUMPS := 90

## How far scenery stays away from the things the player interacts with.
const CLEARANCE_CONTAINER := 2.5
const CLEARANCE_ZONE := 1.0
const CLEARANCE_SPAWN := 4.0
## Grass is allowed inside the play area (it is flat and ankle-high); solid
## things are not.
const GRASS_CLEARANCE_CONTAINER := 1.2

const MAX_SLOPE_DEGREES := 28.0
const SHORELINE_BAND := 2.2 ## Metres inland from the waterline where reeds grow.

var _island: Island
var _rng := RandomNumberGenerator.new()
var _blocked: Array[Dictionary] = []


## [param island] must already have built its terrain — scenery reads heights from it.
func setup(island: Island) -> void:
	_island = island


func _ready() -> void:
	assert(_island != null, "Scenery.setup() must be called before it enters the tree")
	_rng.seed = _island.terrain_seed
	_blocked = _keep_out_areas()
	_grow_grass()
	_grow_trees()
	_grow_bushes()
	_grow_reeds()


# --- Where scenery may not go ---------------------------------------------------

## Circles scenery keeps out of: containers, item spawn zones, player spawns.
func _keep_out_areas() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cid in GameSession.catalog.container_ids():
		var position := GameSession.container_position(cid)
		out.append({
			"kind": "container",
			"x": position.x, "z": position.z,
			"radius": GameSession.catalog.get_container(cid).footprint_radius() + CLEARANCE_CONTAINER,
			"grass_radius": GameSession.catalog.get_container(cid).footprint_radius() + GRASS_CLEARANCE_CONTAINER,
		})
	for zone: Dictionary in GameSession.level.get("spawn_zones", []):
		var centre: Array = zone["center"]
		out.append({
			"kind": "zone",
			"x": float(centre[0]), "z": float(centre[2]),
			"radius": float(zone["radius"]) + CLEARANCE_ZONE,
			"grass_radius": 0.0, # grass is fine among the litter
		})
	for spawn: Array in GameSession.level.get("player_spawns", []):
		out.append({
			"kind": "spawn",
			"x": float(spawn[0]), "z": float(spawn[2]),
			"radius": CLEARANCE_SPAWN,
			"grass_radius": 0.0,
		})
	return out


func is_clear(x: float, z: float, for_grass: bool = false) -> bool:
	if not _island.is_on_land(x, z):
		return false
	if _island.slope_degrees_at(x, z) > MAX_SLOPE_DEGREES:
		return false
	for area in _blocked:
		var radius: float = area["grass_radius"] if for_grass else area["radius"]
		if radius <= 0.0:
			continue
		if Vector2(x - area["x"], z - area["z"]).length() < radius:
			return false
	return true


## A clear spot, or a position with NAN x when none was found in [param tries].
func _find_spot(tries: int, for_grass: bool = false, min_radius: float = 0.0) -> Vector2:
	var limit := GameSession.island_radius()
	for i in range(tries):
		var r := sqrt(_rng.randf_range(min_radius * min_radius / (limit * limit), 1.0)) * limit
		var a := _rng.randf_range(0.0, TAU)
		var x := cos(a) * r
		var z := sin(a) * r
		if is_clear(x, z, for_grass):
			return Vector2(x, z)
	return Vector2(NAN, NAN)


# --- Grass -----------------------------------------------------------------------

func _grow_grass() -> void:
	var multi := MultiMeshInstance3D.new()
	multi.name = "Grass"
	multi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tuft_mesh(0.17)
	var placements: Array[Transform3D] = []
	for i in range(GRASS_TUFTS):
		var spot := _find_spot(4, true)
		if is_nan(spot.x):
			continue
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
			Vector3.ONE * _rng.randf_range(0.7, 1.4))
		placements.append(Transform3D(basis, Vector3(spot.x, _island.height_at(spot.x, spot.y), spot.y)))
	mm.instance_count = placements.size()
	for i in range(placements.size()):
		mm.set_instance_transform(i, placements[i])
	multi.multimesh = mm
	# Barely lighter than the terrain underneath: grass should read as texture on
	# the ground, not as objects competing with the litter you are hunting for.
	multi.material_override = _foliage_material(Color(0.42, 0.66, 0.31), true)
	add_child(multi)


## Three crossed blades: enough to read as grass from standing height, three
## triangles per tuft. Built by hand rather than with SurfaceTool, which bakes a
## zero tangent array and silently kills lighting under GL Compatibility.
##
## Every normal points straight UP, not out of the blade's face. Blades are
## vertical, so face normals get shaded like walls and the grass came out as a
## field of near-black spikes. Borrowing the ground's normal makes it catch the
## same light as the terrain and read as part of it.
func _tuft_mesh(height: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var width := height * 0.34
	for blade in range(3):
		var angle := TAU * blade / 3.0
		var side := Vector3(cos(angle), 0.0, sin(angle)) * width * 0.5
		var lean := Vector3(cos(angle + 1.2), 0.0, sin(angle + 1.2)) * height * 0.22
		# A tapered blade: two base corners and a tip.
		vertices.append_array([-side, side, Vector3(0, height, 0) + lean])
		for v in range(3):
			normals.append(Vector3.UP)
		# A little darker at the root than the tip — depth without a texture.
		colors.append_array([Color(0.82, 0.82, 0.82), Color(0.82, 0.82, 0.82), Color(1, 1, 1)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _foliage_material(color: Color, use_vertex_color: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # blades are single-sided triangles
	mat.roughness = 0.95
	mat.vertex_color_use_as_albedo = use_vertex_color
	return mat


# --- Trees and bushes --------------------------------------------------------------

func _grow_trees() -> void:
	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	for i in range(TREE_COUNT):
		var spot := _find_spot(40, false, 6.0)
		if is_nan(spot.x):
			continue
		trees.add_child(_make_tree(Vector3(spot.x, _island.height_at(spot.x, spot.y), spot.y)))


## A pine: tapered trunk with three stacked cones. Trunks collide so you cannot
## walk through them; the foliage does not, so branches never trap the player.
func _make_tree(at: Vector3) -> StaticBody3D:
	var tree := StaticBody3D.new()
	tree.position = at
	tree.rotation.y = _rng.randf_range(0.0, TAU)
	var height := _rng.randf_range(3.4, 6.2)
	var trunk_radius := height * 0.035

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = trunk_radius * 0.7
	trunk_mesh.bottom_radius = trunk_radius
	trunk_mesh.height = height * 0.45
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	trunk.mesh = trunk_mesh
	trunk.position.y = trunk_mesh.height * 0.5
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.34, 0.24, 0.16)
	bark.roughness = 1.0
	trunk.material_override = bark
	tree.add_child(trunk)

	var foliage := _foliage_material(Color(0.18, 0.42, 0.24).lerp(Color(0.26, 0.52, 0.28), _rng.randf()), false)
	for tier in range(3):
		var cone := MeshInstance3D.new()
		var cone_mesh := CylinderMesh.new()
		var shrink := 1.0 - tier * 0.28
		cone_mesh.top_radius = 0.0
		cone_mesh.bottom_radius = height * 0.26 * shrink
		cone_mesh.height = height * 0.34
		cone_mesh.radial_segments = 7
		cone_mesh.rings = 1
		cone.mesh = cone_mesh
		cone.material_override = foliage
		cone.position.y = height * (0.36 + tier * 0.21)
		tree.add_child(cone)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = trunk_radius * 1.6
	shape.height = height * 0.6
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	tree.add_child(collision)
	return tree


## Low mounds of leaves you can walk straight through — they dress the ground
## without becoming obstacles.
func _grow_bushes() -> void:
	var bushes := Node3D.new()
	bushes.name = "Bushes"
	add_child(bushes)
	for i in range(BUSH_COUNT):
		var spot := _find_spot(30, false, 4.0)
		if is_nan(spot.x):
			continue
		var bush := Node3D.new()
		bush.position = Vector3(spot.x, _island.height_at(spot.x, spot.y), spot.y)
		var mat := _foliage_material(Color(0.22, 0.46, 0.24).lerp(Color(0.34, 0.56, 0.28), _rng.randf()), false)
		var size := _rng.randf_range(0.5, 1.0)
		for lump in range(3):
			var piece := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = size * _rng.randf_range(0.6, 1.0)
			sphere.height = sphere.radius * 1.5
			sphere.radial_segments = 7
			sphere.rings = 4
			piece.mesh = sphere
			piece.material_override = mat
			piece.position = Vector3(
				_rng.randf_range(-size, size), sphere.height * 0.3, _rng.randf_range(-size, size))
			bush.add_child(piece)
		bushes.add_child(bush)


## Taller blades in the shallow band where the land meets the lake.
func _grow_reeds() -> void:
	var reeds := MultiMeshInstance3D.new()
	reeds.name = "Reeds"
	reeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tuft_mesh(0.95)
	var placements: Array[Transform3D] = []
	var limit := GameSession.island_radius()
	for i in range(REED_CLUMPS * 12):
		if placements.size() >= REED_CLUMPS:
			break
		var a := _rng.randf_range(0.0, TAU)
		var r := limit - _rng.randf_range(0.0, SHORELINE_BAND)
		var x := cos(a) * r
		var z := sin(a) * r
		if not _island.is_on_land(x, z):
			continue
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
			Vector3.ONE * _rng.randf_range(0.8, 1.3))
		placements.append(Transform3D(basis, Vector3(x, _island.height_at(x, z), z)))
	mm.instance_count = placements.size()
	for i in range(placements.size()):
		mm.set_instance_transform(i, placements[i])
	reeds.multimesh = mm
	reeds.material_override = _foliage_material(Color(0.58, 0.62, 0.34), true)
	add_child(reeds)


# --- Queries for tests -------------------------------------------------------------

func grass_count() -> int:
	return ($Grass as MultiMeshInstance3D).multimesh.instance_count


func reed_count() -> int:
	return ($Reeds as MultiMeshInstance3D).multimesh.instance_count


func tree_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for tree in $Trees.get_children():
		out.append((tree as Node3D).global_position)
	return out


func bush_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for bush in $Bushes.get_children():
		out.append((bush as Node3D).global_position)
	return out
