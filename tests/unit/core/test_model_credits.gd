extends GdUnitTestSuite
## ADR 0009: every model file ships with its attribution, or it does not ship.
## This test is the enforcement — the folder and CREDITS.md must agree exactly.

const MODELS_DIR := "res://assets/models"
const CREDITS := "res://assets/models/CREDITS.md"
const MAX_TOTAL_BYTES := 8 * 1024 * 1024


func _model_files(path: String = MODELS_DIR) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var full := path + "/" + name
		if dir.current_is_dir():
			out.append_array(_model_files(full))
		elif name.get_extension().to_lower() in ["glb", "gltf"]:
			out.append(full.replace(MODELS_DIR + "/", ""))
		name = dir.get_next()
	dir.list_dir_end()
	return out


## Every `path` mentioned in a table row, as written between backticks.
func _credited_files() -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string(CREDITS)
	for line in text.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() < 6:
			continue
		var file := cells[1].strip_edges().replace("`", "")
		if file.get_extension().to_lower() in ["glb", "gltf"]:
			out.append(file)
	return out


func _licences() -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string(CREDITS)
	for line in text.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() < 6 or not cells[1].strip_edges().replace("`", "").get_extension().to_lower() in ["glb", "gltf"]:
			continue
		out.append(cells[5].strip_edges())
	return out


func test_every_model_file_is_credited() -> void:
	var credited := _credited_files()
	for file in _model_files():
		assert_array(credited).override_failure_message(
			"'%s' has no row in CREDITS.md — see ADR 0009. A model with no attribution does not ship."
			% file).contains([file])


func test_every_credited_file_exists() -> void:
	var present := _model_files()
	for file in _credited_files():
		assert_array(present).override_failure_message(
			"CREDITS.md credits '%s', which is not in assets/models/ — stale row?" % file).contains([file])


func test_only_permissive_licences() -> void:
	for licence in _licences():
		assert_bool(licence.begins_with("CC0") or licence.begins_with("CC-BY")).override_failure_message(
			"licence '%s' is not CC0 or CC-BY; ADR 0009 does not allow it" % licence).is_true()
		assert_bool(licence.contains("NC") or licence.contains("ND")).override_failure_message(
			"licence '%s' is non-commercial or no-derivatives" % licence).is_false()


func test_models_stay_within_the_download_budget() -> void:
	var total := 0
	for file in _model_files():
		total += FileAccess.get_file_as_bytes(MODELS_DIR + "/" + file).size()
	assert_int(total).override_failure_message(
		"models total %.1f MB; the whole rest of the game is about 2 MB" % (total / 1048576.0)
	).is_less_equal(MAX_TOTAL_BYTES)
