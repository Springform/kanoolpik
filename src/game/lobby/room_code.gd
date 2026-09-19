class_name RoomCode
extends RefCounted
## Room codes, and the island each one names (WP-4.4).
##
## The alphabet is the relay's, restated here because the client validates
## before it opens a socket — a typo should cost a red field, not a connection
## attempt and a timeout. `docs/NETWORKING.md` is the source of truth and
## `test_lobby.gd` checks this copy against it.
##
## [b]The code is the seed.[/b] Every peer derives the island from the six
## characters it already has, so nothing about the level layout ever travels: a
## client that connects before the host has generated anything still lands on
## the same island, and a client that connects after does too. This is what the
## determinism in [MessGenerator] was for, and it is why the lobby needs no
## message of its own (session 5 decision — the alternative was a second
## envelope kind in [WebSocketTransport], for one integer).
##
## It also means [b]the same code is always the same island[/b], which is worth
## more than it cost: a crew that liked a particular mess can ask for that room
## again. The price is that a host cannot type a custom seed in multiplayer —
## making a new room is how you roll a new island.

## No `0`/`O`, no `1`/`I`/`L`, no vowels: nothing can be misheard across a
## table and no room is accidentally a word.
const ALPHABET := "BCDFGHJKMNPQRSTVWXYZ23456789"
const LENGTH := 6

## FNV-1a, written out rather than borrowed from [method String.hash].
##
## The engine's hash is an implementation detail that may change between Godot
## versions; this one may not, because it decides which island six people are
## standing on. A build that hashed differently would put a 4.7 player and a 4.8
## player in visibly different worlds with no error anywhere.
## `test_lobby.gd` pins two known codes to two known numbers.
const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619
const MASK_32 := 0xFFFFFFFF
## Godot seeds are signed; keep it positive so nothing downstream has to care.
const MASK_31 := 0x7FFFFFFF


## Upper-cased, with the separators people add when reading one aloud removed.
## Codes are case-insensitive on the way in, as the relay says.
static func normalize(text: String) -> String:
	return text.strip_edges().to_upper().replace(" ", "").replace("-", "")


## True for something the relay would accept. Checked before a socket is opened.
static func is_valid(text: String) -> bool:
	var code := normalize(text)
	if code.length() != LENGTH:
		return false
	for i in code.length():
		if not ALPHABET.contains(code[i]):
			return false
	return true


## The island this code names. Same on every peer, every platform, every run.
static func seed_for(text: String) -> int:
	var code := normalize(text)
	var h := FNV_OFFSET
	for byte in code.to_utf8_buffer():
		h ^= byte
		h = (h * FNV_PRIME) & MASK_32
	return h & MASK_31


## For reading aloud: "BCDFGH" → "BCD-FGH". Display only — [method normalize]
## takes it straight back.
static func spaced(text: String) -> String:
	var code := normalize(text)
	if code.length() != LENGTH:
		return code
	return code.substr(0, 3) + "-" + code.substr(3, 3)
