class_name Dressing
extends Node3D
## The evidence of last night (WP-2.7): a tent that went down, a mate who never
## made it into it, and the flattened ground where everyone sat.
##
## Dressing is **not part of the mess**. Nothing here is in the catalog, nothing
## can be picked up, and — the rule that matters — nothing here has a collider.
## A prop with collision can pin the player against a container or hide a sock
## behind something that cannot be moved, and from the player's side there is no
## way to tell a prop from a 163rd object. So props are drawn and nothing else.
##
## Placement follows the level rather than the seed alone: the tent belongs by
## the tents zone, the trampled ground around the fire, because those are the
## places the level says things happened. Only the jitter is seeded, so the same
## island looks the same twice.

## How far a prop stays clear of the things the player actually interacts with.
## Slightly tighter than [Scenery]'s, because dressing is *meant* to be in the
## camp — it just may not stand on a container or in a spawn.
const CLEARANCE_CONTAINER := 1.2
const CLEARANCE_SPAWN := 2.5

const TENT_MODEL := "res://assets/models/scenary/tent.glb"
const TENT_HEIGHT := 1.5 ## Metres, as a standing tent; it is then tipped over.
const SNORE_SFX := "res://assets/audio/sfx/snore.wav"
## Loud enough to find him by ear from a few metres, gone from across the camp.
const SNORE_UNIT_SIZE := 3.5
const SNORE_MAX_DISTANCE := 14.0

var _island: Island
var _rng := RandomNumberGenerator.new()


## [param island] must already have built its terrain — dressing reads heights from it.
func setup(island: Island) -> void:
	_island = island


func _ready() -> void:
	assert(_island != null, "Dressing.setup() must be called before it enters the tree")
	# Seeded from the *mess*, not the terrain. The island is the same place every
	# time (terrain_seed is fixed); what changes run to run is last night — so a
	# new seed should move the tent as well as the socks.
	_rng.seed = GameSession.state.rng_seed ^ 0x0D2E55
	var camp := _zone_centre("tents", Vector3(-7.0, 0.0, 4.0))
	var fire := _zone_centre("fire", Vector3(6.0, 0.0, -5.0))
	_collapsed_tent(camp)
	_sleeping_mate(camp)
	_trampled_ground(fire)


# --- Props ------------------------------------------------------------------------

## A tent on its side, a couple of metres off the spot where its bag ended up.
func _collapsed_tent(near: Vector3) -> void:
	var spot := _spot_near(near, 2.0, 4.5)
	if is_nan(spot.x):
		return
	var holder := Node3D.new()
	holder.name = "CollapsedTent"
	# The model is fitted as if it were standing, then tipped: a tent that fell
	# is still tent-sized, and scaling a lying-down box would shrink it.
	var tent := ItemVisual.build(TENT_MODEL, Vector3(1.6, TENT_HEIGHT, 1.6), Color.WHITE, 0.0,
		_rng.randf_range(0.0, 360.0), TENT_HEIGHT)
	_strip_colliders(tent)
	tent.rotation.z = deg_to_rad(_rng.randf_range(74.0, 96.0)) # on its side, not quite square
	tent.position.y = 0.35 # the fitted model sits on y=0; tipping needs it lifted back onto its flank
	holder.add_child(tent)
	holder.position = _on_ground(spot)
	add_child(holder)


## Somebody still in his sleeping bag, breathing. A lump and a head: at the
## distance you see him from, a lump that rises and falls reads as a person
## more reliably than a badly modelled one would.
func _sleeping_mate(near: Vector3) -> void:
	var spot := _spot_near(near, 1.5, 4.0)
	if is_nan(spot.x):
		return
	var mate := Node3D.new()
	mate.name = "SleepingMate"
	mate.position = _on_ground(spot)
	mate.rotation.y = _rng.randf_range(0.0, TAU)

	var bag := MeshInstance3D.new()
	bag.name = "Bag"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.85
	bag.mesh = capsule
	bag.material_override = _matte(Color(0.72, 0.28, 0.22)) # a red sleeping bag, findable in the grass
	bag.rotation.z = PI * 0.5 # lying down
	bag.position.y = 0.3
	mate.add_child(bag)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	head.mesh = sphere
	head.material_override = _matte(Color(0.85, 0.68, 0.55))
	head.position = Vector3(0.95, 0.32, 0.0)
	mate.add_child(head)

	var snore := AudioStreamPlayer3D.new()
	snore.name = "Snore"
	var stream: AudioStream = load(SNORE_SFX)
	if stream is AudioStreamWAV:
		# The generator makes it seamless; tell Godot to actually loop it.
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	snore.stream = stream
	snore.bus = "SFX"
	snore.unit_size = SNORE_UNIT_SIZE
	snore.max_distance = SNORE_MAX_DISTANCE
	snore.position = Vector3(0.95, 0.3, 0.0)
	snore.autoplay = true
	mate.add_child(snore)
	add_child(mate)

	# The bag rises and falls in time with the snore: 6 s of audio, two breaths.
	var breathe := create_tween().set_loops()
	breathe.tween_property(bag, "scale", Vector3(1.0, 1.0, 1.06), 1.5).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(bag, "scale", Vector3.ONE, 1.5).set_trans(Tween.TRANS_SINE)


## A darker, flatter patch where everyone sat: a disc laid just above the ground,
## following the terrain rather than floating over it.
func _trampled_ground(centre: Vector3) -> void:
	var patch := MeshInstance3D.new()
	patch.name = "TrampledGround"
	patch.mesh = _patch_mesh(centre, 3.2)
	patch.material_override = _matte(Color(0.29, 0.26, 0.16))
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)


# --- Helpers ----------------------------------------------------------------------

## A fan of triangles at ground height + a hair, so it reads as trodden earth
## rather than a sheet hovering over a hill. Built by hand, not with SurfaceTool,
## which bakes a zero tangent array and kills lighting under GL Compatibility.
func _patch_mesh(centre: Vector3, radius: float) -> ArrayMesh:
	const RINGS := 3
	const SEGMENTS := 20
	const LIFT := 0.03
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for ring in range(RINGS + 1):
		var r := radius * ring / RINGS
		for seg in range(SEGMENTS):
			var a := TAU * seg / SEGMENTS
			var x := centre.x + cos(a) * r
			var z := centre.z + sin(a) * r
			vertices.append(Vector3(x, _island.height_at(x, z) + LIFT, z))
			normals.append(Vector3.UP)
			# Fades out at the edge instead of stopping at a hard circle.
			colors.append(Color(1, 1, 1, 1.0 - pow(float(ring) / RINGS, 1.6)))
	for ring in range(RINGS):
		for seg in range(SEGMENTS):
			var next_seg := (seg + 1) % SEGMENTS
			var a := ring * SEGMENTS + seg
			var b := ring * SEGMENTS + next_seg
			var c := (ring + 1) * SEGMENTS + seg
			var d := (ring + 1) * SEGMENTS + next_seg
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _matte(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	return mat


func _zone_centre(zone_id: String, fallback: Vector3) -> Vector3:
	for zone: Dictionary in GameSession.level.get("spawn_zones", []):
		if String(zone.get("id", "")) == zone_id:
			var c: Array = zone["center"]
			return Vector3(float(c[0]), 0.0, float(c[2]))
	return fallback


func _on_ground(spot: Vector2) -> Vector3:
	return Vector3(spot.x, _island.height_at(spot.x, spot.y), spot.y)


## A clear spot in a ring around [param near], or NAN x when the camp is too
## crowded — in which case that prop simply does not appear. Dressing is the
## first thing to give way; the play area comes first.
func _spot_near(near: Vector3, min_radius: float, max_radius: float) -> Vector2:
	for i in range(40):
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(min_radius, max_radius)
		var x := near.x + cos(a) * r
		var z := near.z + sin(a) * r
		if _is_clear(x, z):
			return Vector2(x, z)
	return Vector2(NAN, NAN)


func _is_clear(x: float, z: float) -> bool:
	if not _island.is_on_land(x, z):
		return false
	if _island.slope_degrees_at(x, z) > 22.0:
		return false
	for cid in GameSession.catalog.container_ids():
		var p := GameSession.container_position(cid)
		var keep_out := GameSession.catalog.get_container(cid).footprint_radius() + CLEARANCE_CONTAINER
		if Vector2(x - p.x, z - p.z).length() < keep_out:
			return false
	for spawn: Array in GameSession.level.get("player_spawns", []):
		if Vector2(x - float(spawn[0]), z - float(spawn[2])).length() < CLEARANCE_SPAWN:
			return false
	return true


## Imported models can carry collision shapes (a `-col` suffix in the source is
## enough). Dressing must have none, so any that arrive are removed rather than
## trusted not to exist.
func _strip_colliders(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_colliders(child)
