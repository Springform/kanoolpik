class_name ItemVisual
extends RefCounted
## Turns a `.glb` path into something you can put on the island — or, when there
## is no model, into the generated placeholder box (WP-2.2).
##
## Two promises, because a half-populated model kit is the normal state for a
## long time and the game has to stay playable throughout:
##
##   1. [method build] never returns null and never throws. A missing, corrupt
##      or unloadable path becomes a placeholder and one warning.
##   2. Nothing has to be measured by hand. Models from asset libraries arrive
##      in arbitrary units — 0.05 or 50 units tall for the same object — so the
##      instance is scaled to fit the size budget it is given and set down on
##      its own base. [param scale_override] exists only for the cases where
##      that reads badly.
##
## Shared by items, held items and containers: one loader, one set of quirks.

## Paths already known to be unloadable, so a broken model warns once rather
## than 21 times for 21 cans.
static var _failed: Dictionary = {}


## The visual for one object. [param fallback_size] is both the placeholder's
## size and the box the model is fitted into.
static func build(model_path: String, fallback_size: Vector3, color: Color,
		scale_override: float = 0.0, y_rotation_degrees: float = 0.0) -> Node3D:
	var model := _load_model(model_path)
	if model == null:
		return _placeholder(fallback_size, color)
	_fit(model, fallback_size, scale_override)
	model.rotate_y(deg_to_rad(y_rotation_degrees))
	if color != Color.WHITE:
		_tint(model, color)
	return model


## True when this path names a model that actually loads. False means whatever
## [method build] returns for it will be a placeholder.
static func has_model(model_path: String) -> bool:
	var probe := _load_model(model_path)
	if probe == null:
		return false
	probe.free() # the probe is thrown away; keeping it leaks a scene per call
	return true


## Size the collision box should be, given what [method build] produced.
##
## [method combined_aabb] measures in the node's own space, so the node's scale —
## which is exactly what auto-fit sets — has to be applied on top, or collision
## comes out the size of the raw imported model.
static func visual_size(node: Node3D, fallback_size: Vector3) -> Vector3:
	var bounds := combined_aabb(node)
	return fallback_size if bounds.size.length() <= 0.0001 else bounds.size * node.scale


## Bounding box of every mesh under [param node], in [param node]'s own space.
##
## Transforms are accumulated by walking up to [param node] rather than read from
## global transforms, so this gives the same answer whether or not the node is in
## the scene tree. It used to switch between the two, and the two disagreed:
## collision ended up sized to the fallback box while the model drew at its own
## size. Measure the same way every time.
static func combined_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var box: AABB = _transform_to(mesh, node) * mesh.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## [param from]'s transform expressed in [param ancestor]'s space, without
## touching the scene tree.
static func _transform_to(from: Node3D, ancestor: Node3D) -> Transform3D:
	var accumulated := Transform3D.IDENTITY
	var node := from
	while node != null and node != ancestor:
		accumulated = node.transform * accumulated
		node = node.get_parent() as Node3D
	return accumulated


# --- Internals -------------------------------------------------------------------

static func _load_model(model_path: String) -> Node3D:
	if model_path.is_empty() or _failed.has(model_path):
		return null
	if not ResourceLoader.exists(model_path):
		_fail(model_path, "no such file")
		return null
	# load() caches the PackedScene, so 21 cans cost one load and 21 instances.
	var scene := load(model_path)
	if not (scene is PackedScene):
		_fail(model_path, "not a scene — .glb and .tscn are what work here")
		return null
	var instance := (scene as PackedScene).instantiate()
	if not (instance is Node3D):
		_fail(model_path, "scene root is not a Node3D")
		instance.free()
		return null
	return instance


static func _fail(model_path: String, why: String) -> void:
	_failed[model_path] = true
	push_warning("Model '%s' not used (%s); falling back to the placeholder box." % [model_path, why])


static func _placeholder(size: Vector3, color: Color) -> Node3D:
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	mesh.position.y = size.y * 0.5 # placeholders sit on the ground like models do
	holder.add_child(mesh)
	return holder


## Scale the model so its longest horizontal-or-vertical extent matches the
## budget, then drop it so its lowest point is at y = 0 and it is centred in XZ.
##
## [param scale_override] is a nudge *on top of* the fit, not a raw multiplier:
## 1.2 means "a fifth bigger than the automatic size" whatever units the model
## arrived in. Tuning it by eye must not require knowing that a log is 43 units
## long — that is the whole point of auto-fit.
static func _fit(model: Node3D, budget: Vector3, scale_override: float) -> void:
	var bounds := combined_aabb(model)
	if bounds.size.length() <= 0.0001:
		return # nothing to measure; leave it alone rather than dividing by zero
	var longest_model := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var longest_budget := maxf(budget.x, maxf(budget.y, budget.z))
	var factor := longest_budget / longest_model
	if scale_override > 0.0:
		factor *= scale_override
	model.scale = Vector3.ONE * factor
	var centre := bounds.get_center() * factor
	model.position = Vector3(-centre.x, -bounds.position.y * factor, -centre.z)


## Multiply the model's albedo, so one model can serve many items.
##
## On a flat untextured model this is exactly "paint it this colour". On a
## textured one it *multiplies* the texture, which darkens as much as it
## colours — if a tinted model looks muddy, that is why, and the answer is a
## second model rather than a cleverer tint.
static func _tint(model: Node3D, color: Color) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.get_surface_override_material_count()):
			var source := mesh.get_active_material(surface)
			var tinted := source.duplicate() if source is StandardMaterial3D else StandardMaterial3D.new()
			tinted.albedo_color = (source as StandardMaterial3D).albedo_color * color \
				if source is StandardMaterial3D else color
			mesh.set_surface_override_material(surface, tinted)
