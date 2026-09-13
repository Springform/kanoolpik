class_name SaveGame
extends RefCounted
## Turning a run into JSON and back (WP-1.8).
##
## A save is exactly [method WorldState.to_dict] plus the progression and the
## level id — the same snapshot multiplayer will hand a late joiner, which is
## why this lives in core and is tested for byte-for-byte round trips.
##
## JSON has only one number type, so every integer comes back as a float.
## [method WorldState.from_dict] and [method Progression.from_dict] already cast
## everything they read; [method unpack] relies on that, and a test pins it.

const SCHEMA_VERSION := 1
const SAVE_DIR := "user://saves"
const DEFAULT_SLOT := "auto"


## Snapshot of a running game, ready for [method JSON.stringify].
static func pack(state: WorldState, progression: Progression, level_id: String) -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"level_id": level_id,
		"saved_at": int(Time.get_unix_time_from_system()),
		"state": state.to_dict(),
		"progression": progression.to_dict(),
	}


## Rebuild a run from a packed Dictionary.
## Returns {} — never a half-built game — when the data is missing, from a
## different schema version, or structurally wrong.
## On success: { state: WorldState, progression: Progression, level_id: String, saved_at: int }.
static func unpack(data: Dictionary) -> Dictionary:
	if not is_usable(data):
		return {}
	return {
		"state": WorldState.from_dict(data["state"]),
		"progression": Progression.from_dict(data.get("progression", {})),
		"level_id": String(data["level_id"]),
		"saved_at": int(data.get("saved_at", 0)),
	}


## Can [method unpack] make a game out of this? Cheap enough to call before loading.
static func is_usable(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	if int(data.get("schema", -1)) != SCHEMA_VERSION:
		return false
	if not data.has("state") or not (data["state"] is Dictionary):
		return false
	if String(data.get("level_id", "")).is_empty():
		return false
	return true


# --- Files ---------------------------------------------------------------------

static func slot_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


static func has_save(slot: String = DEFAULT_SLOT) -> bool:
	return is_usable(read(slot))


static func write(slot: String, data: Dictionary) -> bool:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			push_error("SaveGame: cannot create %s (error %d)" % [SAVE_DIR, err])
			return false
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: cannot write %s (error %d)" % [slot_path(slot), FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


## The raw Dictionary in a slot, or {} when there is nothing readable there.
## A corrupt file is treated as "no save", never as a crash.
static func read(slot: String = DEFAULT_SLOT) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)):
		return {}
	# JSON.parse_string() logs an engine error on bad input; an unreadable save is
	# an ordinary "no save", so parse quietly and judge by the return code.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(slot_path(slot))) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


static func erase(slot: String = DEFAULT_SLOT) -> bool:
	if not FileAccess.file_exists(slot_path(slot)):
		return false
	return DirAccess.remove_absolute(slot_path(slot)) == OK
