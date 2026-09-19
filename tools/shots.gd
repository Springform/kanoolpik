extends Node
## Screenshot harness: boots the real game with the real renderer and saves PNGs
## of chosen situations, so "look at it on screen" stops depending on somebody
## sitting at a machine.
##
## That house rule has already caught bugs no test could: font glyphs that drew
## as nothing, `Label3D` ignoring `visibility_range_end` under GL Compatibility,
## 150 item labels forming a wall of text, and collectibles that were unreadable
## smudges at true scale. Every one of those was invisible to a green suite.
##
## Run it under a virtual display, with the same renderer the web export uses:
##
##   xvfb-run -s "-screen 0 1920x1080x24" \
##     godot --path . --rendering-driver opengl3 --resolution 1920x1080 \
##     res://tools/shots.tscn
##
## It runs as a SCENE, not with `--script`: autoloads (GameSession, GameEvents)
## do not exist in script mode, and the whole point is to boot the real game.
##
## Add `-- --only=skills,klarsyn` to shoot a subset, `-- --out=/tmp/shots` to
## choose the folder, `-- --seed=1234` to fix the mess.
##
## It is a looking tool, not a test: it asserts nothing and fails nothing. What
## it produces is evidence for a person (or for Claude) to actually look at.

const DEFAULT_OUT := "user://shots"
const SETTLE_FRAMES := 12

var main: Main
var out_dir := DEFAULT_OUT
var only: Array[String] = []
var level_seed := 20260914
var shot_count := 0


func _ready() -> void:
	_read_args()
	_ensure_out_dir()
	_run.call_deferred()


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			for name in arg.substr(7).split(",", false):
				only.append(String(name).strip_edges())
		elif arg.begins_with("--seed="):
			level_seed = int(arg.substr(7))


func _ensure_out_dir() -> void:
	if out_dir.begins_with("user://") or out_dir.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	else:
		DirAccess.make_dir_recursive_absolute(out_dir)


func _wants(shot_name: String) -> bool:
	return only.is_empty() or only.has(shot_name)


## Let the renderer catch up, then write the frame.
func _shot(shot_name: String, frames := SETTLE_FRAMES) -> void:
	for i in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%02d-%s.png" % [out_dir, shot_count, shot_name]
	shot_count += 1
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	image.save_png(absolute)
	print("shot: ", absolute, "  ", image.get_width(), "x", image.get_height())


func _boot() -> void:
	main = load("res://src/game/main/main.tscn").instantiate()
	main.skip_title = true
	main.level_seed = level_seed
	get_tree().root.add_child(main)
	for i in range(30):
		await get_tree().process_frame


func _panel() -> TestPanel:
	return main.test_panel


## Put the player somewhere and point the camera at something.
func _stand_at(position: Vector3, look_at: Vector3, eye_height := 1.7) -> void:
	var player := main.player
	# Snap to the terrain. Teleporting to a fixed Y buries the camera inside a
	# hill, and the shot then shows the inside of the island — which looks like a
	# rendering bug and is not one.
	var ground := main.island.height_at(position.x, position.z) if main.island != null else position.y
	player.global_position = Vector3(position.x, ground + eye_height, position.z)
	var camera := player.get_viewport().get_camera_3d()
	if camera != null:
		var flat := Vector2(look_at.x - player.global_position.x, look_at.z - player.global_position.z)
		player.rotation.y = atan2(-flat.x, -flat.y)
		var drop := player.global_position.y - look_at.y
		var run := maxf(flat.length(), 0.001)
		camera.rotation.x = clampf(-atan2(drop, run), -0.5, 0.2)
	for i in range(4):
		await get_tree().process_frame


func _run() -> void:
	await _boot()
	print("--- booted: %d items, test mode %s ---" % [
		GameSession.catalog.item_count(), "on" if TestMode.is_enabled() else "OFF"])

	if _wants("island"):
		await _shot("island")

	if _wants("skills"):
		_panel().grant_points(6)
		main.hud.skill_menu.open()
		await _shot("skills")
		main.hud.skill_menu.close()

	if _wants("testpanel"):
		_panel().open()
		await _shot("testpanel")
		_panel().close()

	if _wants("klarsyn"):
		_panel().unlock("insight")
		var pole := "tent_pole_1"
		GameSession.submit(Commands.pick_up(GameSession.local_player_id(), pole))
		await get_tree().process_frame
		var insight := main.find_children("*", "InsightAbility", true, false)
		if not insight.is_empty():
			insight[0].activate()
		await _shot("klarsyn-near")
		# From across the island, which is the case the ability exists for.
		await _stand_at(Vector3(9, 0, 9), Vector3(-6, 0.5, -5))
		await _shot("klarsyn-far")

	if _wants("stedsans"):
		_panel().unlock("map_sense")
		var arrow := main.find_children("*", "MapSenseAbility", true, false)
		if not arrow.is_empty() and arrow[0].has_method("toggle"):
			arrow[0].toggle()
		await _shot("stedsans")

	if _wants("collectibles"):
		var spawner := main.find_children("*", "CollectibleSpawner", true, false)
		if not spawner.is_empty():
			var found := spawner[0].find_children("*", "Collectible", true, false)
			for c: Node3D in found:
				var name_bit := String(c.name).to_lower()
				await _stand_at(c.global_position + Vector3(2.5, 1.4, 2.5), c.global_position)
				await _shot("collectible-" + name_bit, 6)

	if _wants("summon"):
		_panel().unlock("call_mate")
		await _stand_at(Vector3(0, 2.0, 0), Vector3(0, 0, -5))
		var call_mate := main.find_children("*", "CallMateAbility", true, false)
		if not call_mate.is_empty():
			GameSession.submit(Commands.pick_up(GameSession.local_player_id(), "tent_peg_1"))
			await get_tree().process_frame
			call_mate[0].shout()
		await _shot("summon", 40)

	if _wants("lobby"):
		# The two multiplayer screens (WP-4.4), drawn over the booted island but
		# with no relay anywhere near them: LobbyScreen is a view, so the host's
		# room is a code, a roster and a button whether or not a socket exists.
		# What is being looked at is the 64 px code, whether the roster fits,
		# and whether every glyph actually draws — Godot's default font has no
		# Dingbats, which is why the "you" marker is a Latin-1 guillemet.
		var title: TitleScreen = load("res://src/game/title/title_screen.tscn").instantiate()
		main.add_child(title)
		await _shot("title-multiplayer")
		main.remove_child(title)
		title.free()

		var lobby: LobbyScreen = load("res://src/game/lobby/lobby_screen.tscn").instantiate()
		main.add_child(lobby)
		lobby.show_room("BCDFGH", true, 1)
		lobby.set_peers([1, 2, 3])
		await _shot("lobby-host")
		lobby.show_room("BCDFGH", false, 4)
		await _shot("lobby-client")
		# A join that failed: no room was ever opened, so the heading must not
		# say "Du er med" above a sentence explaining that we are not. It did.
		lobby.is_open = false
		lobby.code = ""
		lobby.apply_texts()
		lobby.show_status("ui.lobby.error.no_such_room")
		await _shot("lobby-refused")
		main.remove_child(lobby)
		lobby.free()

	if _wants("evaluation"):
		_panel().pack_all_but_one()
		_panel().set_clock_minutes(18)
		_panel().show_evaluation()
		await _shot("evaluation", 90)

	print("--- %d shots written to %s ---" % [shot_count, out_dir])
	get_tree().quit()
