class_name WavPcm
extends RefCounted
## Reads the PCM out of a source `.wav` file, for tests that check the audio we
## generated rather than the audio Godot imported.
##
## Two things make this less trivial than it looks, and both have already cost
## a red build:
##
##   1. **The imported [AudioStreamWAV] is not PCM.** Godot's WAV importer
##      compresses to QOA (`compress/mode=2`), so `stream.data` is codec bytes.
##      Decoding those as 16-bit samples reads noise that happens to look
##      statistically like audio — which is how a loop-seam test passed for
##      weeks while proving nothing.
##   2. **A `.wav` is a container, not a header plus samples.** Assuming the
##      audio starts at byte 44 and runs to the end of the file is true for what
##      `tools/gen_*.py` writes and false the moment anything else touches the
##      file. Something on a Windows machine in this project appends a `C2PA`
##      (Content Credentials) chunk after the audio — playback is unaffected,
##      but "the last sample" then lands in the middle of the metadata and the
##      seam looks like a click. Walk the chunks; find `data`; read that.

const HEADER_BYTES := 12 ## "RIFF" + size + "WAVE"


## The `data` chunk as 16-bit samples, or an empty array when the file is not a
## readable 16-bit PCM RIFF.
static func samples(res_path: String) -> PackedFloat32Array:
	var bytes := FileAccess.get_file_as_bytes(res_path)
	var out := PackedFloat32Array()
	var span := data_span(bytes)
	if span.is_empty():
		return out
	var start: int = span["offset"]
	var count: int = span["size"] / 2
	out.resize(count)
	for i in range(count):
		out[i] = float(bytes.decode_s16(start + i * 2)) / 32768.0
	return out


## Where the audio actually lives: `{offset, size}` in bytes, or `{}` when there
## is no `data` chunk to find.
static func data_span(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_BYTES + 8 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {}
	var offset := HEADER_BYTES
	while offset + 8 <= bytes.size():
		var chunk_id := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var size := bytes.decode_u32(offset + 4)
		if chunk_id == "data":
			return {"offset": offset + 8, "size": mini(size, bytes.size() - offset - 8)}
		# Chunks are word-aligned: an odd size is followed by a pad byte.
		offset += 8 + size + (size & 1)
	return {}
