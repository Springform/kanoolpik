class_name ColourVision
extends RefCounted
## Simulate dichromatic vision, so "these colours are distinguishable" is a
## measurement and not an opinion (WP-5.3).
##
## [b]Why this exists at all.[/b] The six avatar colours used to be
## `Color.from_hsv(id * 0.16, ...)` — six even steps round the wheel. The wheel
## is not perceptually even, and it is very much not even once two of the three
## cone types are doing one job: peers 1 and 2 came out at ΔE 1.9 under
## protanopia, which is to say identical. Nobody would have found that by
## looking at the palette, and no assertion about hue would have caught it.
##
## Viénot, Brettel & Mollon (1999): convert to LMS, collapse the missing cone
## onto the plane the other two span, convert back. It is the standard
## simplification — good enough to answer "can these two be told apart", which
## is the only question asked here.

enum Kind { NORMAL, PROTAN, DEUTAN, TRITAN }

## Hunt–Pointer–Estevez, as used by Viénot: linear RGB to LMS.
const RGB_TO_LMS := [
	Vector3(17.8824, 43.5161, 4.11935),
	Vector3(3.45565, 27.1554, 3.86714),
	Vector3(0.0299566, 0.184309, 1.46709),
]
const LMS_TO_RGB := [
	Vector3(0.0809445, -0.130504, 0.116721),
	Vector3(-0.0102485, 0.0540194, -0.113615),
	Vector3(-0.000365297, -0.00412161, 0.693513),
]

## The collapse, one per missing cone type.
const PROJECT := {
	Kind.PROTAN: [Vector3(0.0, 2.02344, -2.52581), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	Kind.DEUTAN: [Vector3(1, 0, 0), Vector3(0.494207, 0.0, 1.24827), Vector3(0, 0, 1)],
	Kind.TRITAN: [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(-0.395913, 0.801109, 0.0)],
}

## sRGB's transfer curve, near enough. The exact piecewise function changes the
## third decimal of a ΔE and nothing about any answer here.
const GAMMA := 2.2

const D65 := Vector3(0.95047, 1.0, 1.08883)
const RGB_TO_XYZ := [
	Vector3(0.4124, 0.3576, 0.1805),
	Vector3(0.2126, 0.7152, 0.0722),
	Vector3(0.0193, 0.1192, 0.9505),
]


static func _apply(rows: Array, v: Vector3) -> Vector3:
	return Vector3((rows[0] as Vector3).dot(v), (rows[1] as Vector3).dot(v), (rows[2] as Vector3).dot(v))


## [param colour] as somebody with [param kind] vision sees it.
static func seen_as(colour: Color, kind: Kind) -> Color:
	var linear := Vector3(pow(colour.r, GAMMA), pow(colour.g, GAMMA), pow(colour.b, GAMMA))
	if kind != Kind.NORMAL:
		var lms := _apply(RGB_TO_LMS, linear)
		linear = _apply(LMS_TO_RGB, _apply(PROJECT[kind], lms))
	linear = Vector3(maxf(linear.x, 0.0), maxf(linear.y, 0.0), maxf(linear.z, 0.0))
	return Color(pow(linear.x, 1.0 / GAMMA), pow(linear.y, 1.0 / GAMMA), pow(linear.z, 1.0 / GAMMA))


## CIE L*a*b*, so two colours can be subtracted and the answer mean something.
static func lab(colour: Color) -> Vector3:
	var linear := Vector3(pow(colour.r, GAMMA), pow(colour.g, GAMMA), pow(colour.b, GAMMA))
	var xyz := _apply(RGB_TO_XYZ, linear)
	var f := Vector3(_f(xyz.x / D65.x), _f(xyz.y / D65.y), _f(xyz.z / D65.z))
	return Vector3(116.0 * f.y - 16.0, 500.0 * (f.x - f.y), 200.0 * (f.y - f.z))


static func _f(r: float) -> float:
	return pow(r, 1.0 / 3.0) if r > 0.008856 else 7.787 * r + 16.0 / 116.0


## How far apart two colours are to somebody with [param kind] vision (CIE76).
## Below about 2 is "the same colour"; 10 is a difference nobody argues about.
static func distance(a: Color, b: Color, kind: Kind) -> float:
	return lab(seen_as(a, kind)).distance_to(lab(seen_as(b, kind)))


## The closest pair in [param palette] across normal vision and all three
## dichromacies — the number that decides whether a palette works.
static func worst_distance(palette: Array) -> float:
	var worst := INF
	for kind: Kind in [Kind.NORMAL, Kind.PROTAN, Kind.DEUTAN, Kind.TRITAN]:
		for i in palette.size():
			for j in range(i + 1, palette.size()):
				worst = minf(worst, distance(palette[i], palette[j], kind))
	return worst


## Luminance as a screen renders it, for checking a thing still reads with the
## colour taken away entirely.
static func grey(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
