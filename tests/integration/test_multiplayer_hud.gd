extends GdUnitTestSuite
## WP-4.7 — the HUD stops speaking as if you are alone.
##
## The claim that matters most here is a negative one: **single player must read
## exactly as it did before.** Naming the actor is for the case where there is
## an actor other than you, and a game nobody else is in has no "Spiller 1" in
## it. Half of this suite exists to keep that true.
##
## The other half is the toast queue. Three deep, six people, and your own
## feedback must survive their news — which is a rule about what gets dropped,
## not about what gets shown.

const PUMP_LIMIT := 400

var _hud: HUD
var _relay: FakeRelay
var _transports: Array[WebSocketTransport] = []
var _cat: Catalog
var _room: String
var _url := ""
## The session's own transport, put back afterwards. Several tests swap in a
## real socket so the HUD can see a room; leaving one behind would hand the next
## suite a closed WebSocket to run a level on.
var _was_transport: Transport


func before_test() -> void:
	GameSession.start_level("island_01", 4242)
	_was_transport = GameSession.transport
	_cat = TestFixtures.catalog()
	_room = _random_room()
	_url = ""


func after_test() -> void:
	if is_instance_valid(_hud):
		remove_child(_hud)
		_hud.free()
	_hud = null
	for transport in _transports:
		transport.close()
	_transports.clear()
	GameSession.transport = _was_transport
	if _relay != null:
		_relay.stop()
		_relay = null
	GameSession.stop_level()


# --- Alone, it reads exactly as it did ----------------------------------------------

func test_single_player_never_names_anybody() -> void:
	await _open_hud()
	var pid := GameSession.local_player_id()
	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	GameSession.submit(Commands.pick_up(pid, item_id))
	GameSession.submit(Commands.place(pid, item_id, _a_container_for(item_id), 0))
	await get_tree().process_frame

	for text in _hud.toast_texts():
		assert_str(text).override_failure_message(
			"a solo round said %s to somebody who is on their own" % text
		).not_contains(TranslationServer.translate("ui.remote.player").split(" ")[0])


func test_the_party_line_is_hidden_when_there_is_no_party() -> void:
	await _open_hud()
	_hud.refresh_party()
	assert_bool(_hud.party_label.visible).override_failure_message(
		"a solo round is showing 1 i kanoen, which is a sad thing to read").is_false()


func test_names_are_empty_until_somebody_else_is_here() -> void:
	assert_bool(PlayerNames.others_present()).is_false()
	assert_str(PlayerNames.of(1)).is_empty()
	assert_int(PlayerNames.party_size()).is_equal(1)
	# label() is the unconditional one, and still answers.
	assert_str(PlayerNames.label(3)).is_not_empty()


# --- With other people in the room ---------------------------------------------------

func test_somebody_elses_placement_names_them_and_the_thing() -> void:
	var host: WebSocketTransport = await _open_room()
	await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	GameSession.transport = host
	await _open_hud()

	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	var item_name := TranslationServer.translate(GameSession.catalog.get_item(item_id).name_key)
	_hud._on_item_placed(item_id, 2, _a_container_for(item_id), 0, PlacementRules.Verdict.CORRECT)

	var texts := _hud.toast_texts()
	assert_int(texts.size()).is_equal(1)
	assert_str(texts[0]).override_failure_message(
		"the toast does not say who: %s" % texts[0]).contains(PlayerNames.label(2))
	assert_str(texts[0]).override_failure_message(
		"the toast does not say what: %s" % texts[0]).contains(item_name)


func test_your_own_placement_still_reads_as_feedback() -> void:
	var host: WebSocketTransport = await _open_room()
	await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	GameSession.transport = host
	await _open_hud()

	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	_hud._on_item_placed(item_id, host.local_player_id(), _a_container_for(item_id), 0,
		PlacementRules.Verdict.CORRECT)

	assert_str(_hud.toast_texts()[0]).override_failure_message(
		"your own placement was reported in the third person").is_equal(
		TranslationServer.translate(VerdictStyle.toast_key(PlacementRules.Verdict.CORRECT)))


func test_a_mates_mistake_is_not_your_problem() -> void:
	# The verdict is feedback, and feedback is for whoever can act on it. Six
	# people making mistakes would be a stream of red nobody can do anything
	# about, on top of the one thing you are trying to read.
	var host: WebSocketTransport = await _open_room()
	await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	GameSession.transport = host
	await _open_hud()

	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	_hud._on_item_placed(item_id, 2, _a_container_for(item_id), 0,
		PlacementRules.Verdict.WRONG_CATEGORY)

	assert_int(_hud.toast_count()).override_failure_message(
		"somebody else putting a bottle in the wrong box interrupted you").is_equal(0)


func test_a_completed_container_is_credited_to_whoever_filled_it() -> void:
	# container_completed carries no actor — the core has no opinion about who
	# deserves the credit. The placement from the same command arrives first,
	# so the HUD does.
	var host: WebSocketTransport = await _open_room()
	await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	GameSession.transport = host
	await _open_hud()

	var item_id := GameSession.state.items_of_kind(WorldState.Kind.GROUND)[0]
	var cid := _a_container_for(item_id)
	_hud._on_item_placed(item_id, 2, cid, 0, PlacementRules.Verdict.CORRECT)
	_hud._on_container_completed(cid)

	assert_str(_hud.toast_texts()[-1]).override_failure_message(
		"the completion was not credited to anybody: %s" % _hud.toast_texts()[-1]
	).contains(PlayerNames.label(2))


func test_a_purchase_says_who_spent_the_points() -> void:
	# Points are shared, so anybody can spend them without asking. The toast is
	# what starts the conversation about that.
	var host: WebSocketTransport = await _open_room()
	await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 2)
	GameSession.transport = host
	await _open_hud()

	_hud._on_ability_unlocked("insight", 2, 3)

	assert_str(_hud.toast_texts()[-1]).contains(PlayerNames.label(2))


func test_the_party_line_counts_the_room() -> void:
	var host: WebSocketTransport = await _open_room()
	await _add_guest()
	await _add_guest()
	await _until(func() -> bool: return host.known_peers().size() == 3)
	GameSession.transport = host
	await _open_hud()

	_hud.refresh_party()
	assert_bool(_hud.party_label.visible).is_true()
	assert_str(_hud.party_label.text).contains("3")


# --- The queue ------------------------------------------------------------------------

func test_six_peoples_news_does_not_bury_your_own() -> void:
	# Three deep, and a busy room can fill it in a second. Plain oldest-first
	# eviction means your "wrong box" lands and is gone before you look up.
	await _open_hud()
	_hud.show_toast("mine", 5.0, HUD.COLOR_INFO, true)
	_hud.show_toast("theirs 1", 5.0, HUD.COLOR_OTHER, false)
	_hud.show_toast("theirs 2", 5.0, HUD.COLOR_OTHER, false)
	_hud.show_toast("theirs 3", 5.0, HUD.COLOR_OTHER, false)
	_hud.show_toast("theirs 4", 5.0, HUD.COLOR_OTHER, false)

	assert_int(_hud.toast_count()).is_equal(HUD.MAX_TOASTS)
	assert_array(_hud.toast_texts()).override_failure_message(
		"your own feedback was pushed off the screen by somebody else's news: %s"
		% [_hud.toast_texts()]).contains(["mine"])


func test_your_own_toasts_still_make_way_for_each_other() -> void:
	# The rule protects your feedback from THEIR news, not from your own — four
	# of your own in a row should still leave the newest three.
	await _open_hud()
	for i in 4:
		_hud.show_toast("mine %d" % i, 5.0, HUD.COLOR_INFO, true)

	assert_int(_hud.toast_count()).is_equal(HUD.MAX_TOASTS)
	assert_array(_hud.toast_texts()).not_contains(["mine 0"])
	assert_array(_hud.toast_texts()).contains(["mine 3"])


# --- The connection ---------------------------------------------------------------------

func test_a_round_trip_is_measured() -> void:
	# The relay answers `ping` with `pong` at the edge (setWebSocketAutoResponse),
	# so this costs no Durable Object wake-up. FakeRelay copies that because the
	# Worker does it — read first, copy second.
	var host: WebSocketTransport = await _open_room()
	assert_int(host.latency_ms()).override_failure_message(
		"a latency was reported before anything had been measured").is_equal(-1)
	await _until(func() -> bool: return host.latency_ms() >= 0)
	assert_int(host.latency_ms()).is_greater_equal(0)


func test_single_player_has_no_latency_to_report() -> void:
	assert_int(GameSession.transport.latency_ms()).override_failure_message(
		"single player is reporting a ping to nowhere").is_equal(-1)


# --- Helpers -----------------------------------------------------------------------

func _open_hud() -> void:
	_hud = load("res://src/game/hud/hud.tscn").instantiate()
	add_child(_hud)
	await get_tree().process_frame
	# The clock and the prompt are not what this suite is about, and a toast
	# left over from setup would be.
	for child: Node in _hud.toasts_box.get_children():
		_hud.toasts_box.remove_child(child)
		child.free()


## A container this item actually belongs in, so a CORRECT verdict is honest.
func _a_container_for(item_id: String) -> String:
	for cid in GameSession.catalog.container_ids():
		if PlacementRules.find_correct_slot(GameSession.catalog, GameSession.state, item_id, cid) >= 0:
			return cid
	return GameSession.catalog.container_ids()[0]


func _external_url() -> String:
	return OS.get_environment("KANOOLPIK_RELAY_URL")


func _base_url() -> String:
	if _url.is_empty():
		if _relay == null and _external_url().is_empty():
			_relay = FakeRelay.new()
		var external := _external_url()
		_url = external if not external.is_empty() else _relay.start()
	return _url


func _fresh_state() -> WorldState:
	var state := TestFixtures.ground_state(_cat, Progression.BASE_CAPACITY)
	state.island_radius = 20.0
	return state


func _open_room() -> WebSocketTransport:
	var host := _join(true)
	await _until(func() -> bool: return host.is_joined())
	return host


func _add_guest() -> WebSocketTransport:
	var guest := _join(false)
	await _until(func() -> bool: return guest.is_joined())
	return guest


func _join(as_host: bool) -> WebSocketTransport:
	var processor := CommandProcessor.new(_cat)
	var transport := WebSocketTransport.new(_base_url(), _room, as_host, processor, _fresh_state())
	_transports.append(transport)
	return transport


func _turn() -> void:
	if _relay != null:
		_relay.poll()
	for transport in _transports:
		transport.poll()
	OS.delay_msec(2)


func _until(condition: Callable) -> void:
	var limit := PUMP_LIMIT * (12 if not _external_url().is_empty() else 1)
	for i in limit:
		if condition.call():
			return
		_turn()
	assert_bool(condition.call()).override_failure_message(
		"condition never became true within %d turns" % limit).is_true()


func _random_room() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code := ""
	for i in RoomCode.LENGTH:
		code += RoomCode.ALPHABET[rng.randi_range(0, RoomCode.ALPHABET.length() - 1)]
	return code
