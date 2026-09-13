class_name Catalog
extends RefCounted
## Read-only registry of every [ItemDef] and [ContainerDef] in a level.
##
## Built from plain Dictionaries so it can be unit tested without touching the
## filesystem; [method load_from_files] is the convenience path used by the game.

var _items: Dictionary = {} # id -> ItemDef
var _containers: Dictionary = {} # id -> ContainerDef
var _series_members: Dictionary = {} # series -> Array[ItemDef]


static func from_dicts(items: Array, containers: Array) -> Catalog:
	var cat := Catalog.new()
	for d in items:
		cat.add_item(ItemDef.from_dict(d))
	for d in containers:
		cat.add_container(ContainerDef.from_dict(d))
	return cat


static func load_from_files(items_path: String, containers_path: String) -> Catalog:
	var items: Array = _read_json_array(items_path, "items")
	var containers: Array = _read_json_array(containers_path, "containers")
	return Catalog.from_dicts(items, containers)


static func _read_json_array(path: String, key: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("Catalog: file not found: %s" % path)
		return []
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary and parsed.has(key):
		return parsed[key]
	if parsed is Array:
		return parsed
	push_error("Catalog: %s does not contain a '%s' array" % [path, key])
	return []


func add_item(def: ItemDef) -> void:
	assert(def.is_valid(), "Invalid ItemDef: %s" % def.id)
	assert(not _items.has(def.id), "Duplicate item id: %s" % def.id)
	_items[def.id] = def
	if not def.series.is_empty():
		if not _series_members.has(def.series):
			_series_members[def.series] = []
		_series_members[def.series].append(def)


func add_container(def: ContainerDef) -> void:
	assert(def.is_valid(), "Invalid ContainerDef: %s" % def.id)
	assert(not _containers.has(def.id), "Duplicate container id: %s" % def.id)
	_containers[def.id] = def


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> ItemDef:
	return _items.get(id)


func get_container(id: String) -> ContainerDef:
	return _containers.get(id)


func item_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _items.keys():
		out.append(k)
	out.sort()
	return out


func container_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _containers.keys():
		out.append(k)
	out.sort()
	return out


func item_count() -> int:
	return _items.size()


func series_members(series: String) -> Array:
	return _series_members.get(series, [])


func containers_accepting(category: String) -> Array[ContainerDef]:
	var out: Array[ContainerDef] = []
	for id in container_ids():
		var c: ContainerDef = _containers[id]
		if c.accepts_category(category):
			out.append(c)
	return out


## Every item has at least one container that accepts it, and every ordered
## series has a contiguous 1..n sequence. Returns a list of problems (empty = OK).
func validate() -> Array[String]:
	var problems: Array[String] = []
	for id in item_ids():
		var item: ItemDef = _items[id]
		if containers_accepting(item.category).is_empty():
			problems.append("item '%s' has category '%s' no container accepts" % [id, item.category])
	for series in _series_members.keys():
		var members: Array = _series_members[series]
		var seqs: Array[int] = []
		for m in members:
			if m.sequence > 0:
				seqs.append(m.sequence)
		if seqs.is_empty():
			continue
		if seqs.size() != members.size():
			problems.append("series '%s' mixes ordered and unordered items" % series)
			continue
		seqs.sort()
		for i in range(seqs.size()):
			if seqs[i] != i + 1:
				problems.append("series '%s' sequence is not contiguous 1..n" % series)
				break
	return problems
