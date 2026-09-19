class_name PanelFit
extends RefCounted
## Centre a panel and size it to exactly what is in it (WP-4.4, fixed WP-4.6).
##
## [b]Two bugs live here, so it is one function in one file rather than four
## lines copied into every screen.[/b]
##
## The first: a panel whose height is typed into the `.tscn` outgrows its own
## background the moment somebody adds a row. WP-4.4 pushed three controls past
## the panel art and onto the island with every string assertion green.
##
## The second: the obvious fix,
## [code]set_anchors_and_offsets_preset(PRESET_CENTER, PRESET_MODE_MINSIZE)[/code],
## does not settle. Called again before the container has laid out — which is
## what happens when a screen re-applies its texts and then shows a notice, both
## deferred — it sizes from the panel's current size rather than its minimum,
## and the two calls compound: a 545 px panel became 1039 px, centred, with its
## title off the top of the screen. Measured, not guessed.
##
## So the offsets are written from [method Control.get_combined_minimum_size]
## every time, which is idempotent however often it runs.

## Never grow within this many pixels of the window edge.
const MARGIN := 24.0


## Anchors are expected to be centred already (preset 8 in the scene); only the
## offsets are touched.
static func centre(panel: Control) -> void:
	if panel == null or not panel.is_inside_tree():
		return
	var wanted := panel.get_combined_minimum_size()
	var room := panel.get_viewport_rect().size
	# A panel taller than the window is centred half off the top, which hides the
	# title rather than the least important row. Capping means the content
	# overflows instead — still wrong, but wrong downwards and visibly so, which
	# is the version somebody notices and fixes with a scroll container.
	wanted.x = minf(wanted.x, maxf(room.x - MARGIN * 2.0, 1.0))
	wanted.y = minf(wanted.y, maxf(room.y - MARGIN * 2.0, 1.0))
	panel.offset_left = -wanted.x * 0.5
	panel.offset_right = wanted.x * 0.5
	panel.offset_top = -wanted.y * 0.5
	panel.offset_bottom = wanted.y * 0.5
