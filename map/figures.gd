class_name Figures
extends RefCounted
## Flat, side-on medieval figures: surcoats with a cross, flowing capes, mail
## legs, belts and scabbards, and three kinds of helm (great helm with gold
## trim, nasal helm, striped kettle hat). Drawn from simple shapes so hundreds
## can be on screen. Units: a standing figure is 20 units tall, feet at y = 0;
## `k` converts units to world pixels, `flip` is 1 facing right, -1 facing left.

const MAIL := Color(0.63, 0.64, 0.67)
const MAIL_DARK := Color(0.50, 0.51, 0.55)
const STEEL := Color(0.72, 0.74, 0.78)
const STEEL_DARK := Color(0.55, 0.57, 0.62)
const GOLD := Color(0.86, 0.68, 0.22)
const SKIN := Color(0.96, 0.89, 0.80)
const LEATHER := Color(0.55, 0.36, 0.22)
const WOOD := Color(0.50, 0.34, 0.20)
const SLIT := Color(0.12, 0.10, 0.10)


static func _p(at: Vector2, k: float, flip: float, x: float, y: float) -> Vector2:
	return at + Vector2(x * flip, y) * k


static func _poly(ci: CanvasItem, at: Vector2, k: float, flip: float, pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_p(at, k, flip, p[0], p[1]))
	safe_polygon(ci, out, col)


static var debug_bad := false


## Draws a filled polygon. Triangles and quads (most of every figure) go
## straight to the GPU as primitives: faster, and immune to the renderer's
## trouble with triangulating very small shapes.
static func safe_polygon(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() == 3 or pts.size() == 4:
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(col)
		ci.draw_primitive(pts, cols, PackedVector2Array())
		return
	# Specks smaller than a pixel or two: a dot looks the same and always works.
	if pts.size() >= 3:
		var extent := maxf(pts[0].distance_to(pts[1]), pts[0].distance_to(pts[2]))
		if extent < 0.4:
			ci.draw_circle((pts[0] + pts[1] + pts[2]) / 3.0, extent * 0.45, col)
			return
	if debug_bad and Geometry2D.triangulate_polygon(pts).is_empty():
		print("BAD POLYGON ", pts)
		return
	ci.draw_colored_polygon(pts, col)


## A limb with rounded ends.
static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	if a.distance_squared_to(b) < 0.000001:
		ci.draw_circle(a, w * 0.5, col)
		return
	var n := (b - a).orthogonal().normalized() * w * 0.5
	safe_polygon(ci, PackedVector2Array([a + n, b + n, b - n, a - n]), col)
	ci.draw_circle(a, w * 0.5, col)
	ci.draw_circle(b, w * 0.5, col)


## opts: surcoat (Color), cross (bool), emblem (Color), helm ("great"/"nasal"/"kettle"),
## weapon ("spear"/"sword"/"bow"), phase (float), moving, fighting, routed (bool)
static func footman(ci: CanvasItem, at: Vector2, k: float, flip: float, o: Dictionary) -> void:
	var phase: float = o.get("phase", 0.0)
	var moving: bool = o.get("moving", false)
	var fighting: bool = o.get("fighting", false)
	var routed: bool = o.get("routed", false)
	var coat: Color = o.get("surcoat", Color(0.95, 0.95, 0.93))
	var cape := coat.lightened(0.1)
	var weapon: String = o.get("weapon", "spear")
	var swing := sin(phase) * (1.8 if moving or routed else 0.0)
	var flutter := (1.8 + sin(phase * 0.8) * 1.0) if (moving or routed) else 0.6

	# Big draping cape behind everything.
	_poly(ci, at, k, flip, [[-1.9, -16.4], [-0.3, -16.8], [-2.4, -9.0], [-2.2, -2.0], [-6.2 - flutter, -1.4], [-4.6 - flutter * 0.6, -10.0]], cape.darkened(0.07))
	# Back arm and back leg (darker, further away).
	_limb(ci, _p(at, k, flip, -0.4, -15.2), _p(at, k, flip, -1.3 - swing * 0.4, -10.4), 1.7 * k, MAIL_DARK)
	_limb(ci, _p(at, k, flip, -0.7, -8.6), _p(at, k, flip, -0.9 - swing, -1.8), 2.0 * k, MAIL_DARK)
	_poly(ci, at, k, flip, [[-2.0 - swing, -2.3], [0.5 - swing, -2.3], [1.1 - swing, -0.4], [-2.0 - swing, -0.3]], LEATHER.darkened(0.15))
	# Front leg.
	_limb(ci, _p(at, k, flip, 0.6, -8.6), _p(at, k, flip, 0.8 + swing, -1.8), 2.0 * k, MAIL)
	_poly(ci, at, k, flip, [[-0.5 + swing, -2.3], [2.1 + swing, -2.3], [2.7 + swing, -0.4], [-0.5 + swing, -0.3]], LEATHER)
	# Broad surcoat, flaring to the hem, with a shaded back panel.
	_poly(ci, at, k, flip, [[-2.1, -16.4], [2.1, -16.4], [2.8, -9.8], [3.5, -4.6], [-3.3, -4.6], [-2.7, -9.8]], coat)
	_poly(ci, at, k, flip, [[-3.3, -4.6], [-2.7, -9.8], [-1.4, -9.8], [-1.2, -4.6]], coat.darkened(0.08))
	if o.get("cross", true):
		var c: Color = o.get("emblem", Color(0.8, 0.12, 0.1))
		_poly(ci, at, k, flip, [[0.55, -14.6], [1.25, -14.6], [1.25, -10.9], [0.55, -10.9]], c)
		_poly(ci, at, k, flip, [[-0.4, -13.5], [2.2, -13.5], [2.2, -12.8], [-0.4, -12.8]], c)
	# Belt and scabbard.
	_poly(ci, at, k, flip, [[-2.7, -9.9], [2.8, -9.9], [2.8, -9.3], [-2.7, -9.3]], LEATHER)
	if weapon == "spear" or weapon == "sword":
		_limb(ci, _p(at, k, flip, -0.8, -9.5), _p(at, k, flip, -3.7, -4.0), 0.95 * k, LEATHER.darkened(0.1))
	# Head: a big helm, as in the old illustrations.
	ci.draw_circle(_p(at, k, flip, 0.6, -18.6), 1.95 * k, SKIN)
	_helm(ci, at, k, flip, str(o.get("helm", "nasal")))
	# Front arm and weapon.
	var hand := Vector2(1.7, -10.4)
	if routed:
		hand = Vector2(2.2, -18.0 + sin(phase * 2.0))
	elif fighting:
		var t := sin(phase * 1.6)
		hand = Vector2(3.2 + t * 1.6, -13.0 - t * 0.7)
	elif weapon == "spear" or weapon == "bow":
		hand = Vector2(2.6, -12.2)
	var hand_w := _p(at, k, flip, hand.x, hand.y)
	if not routed:
		match weapon:
			"spear":
				var tip := Vector2(7.5, -24.0) if not fighting else Vector2(hand.x + 8.5, hand.y - 1.0)
				var butt := Vector2(-1.0, -3.0) if not fighting else Vector2(hand.x - 5.0, hand.y + 0.6)
				_limb(ci, _p(at, k, flip, butt.x, butt.y), _p(at, k, flip, tip.x, tip.y), 0.55 * k, WOOD)
				var d := (tip - butt).normalized()
				var side := Vector2(-d.y, d.x) * 0.7
				_poly(ci, at, k, flip, [[tip.x + d.x * 2.0, tip.y + d.y * 2.0], [tip.x + side.x, tip.y + side.y], [tip.x - side.x, tip.y - side.y]], STEEL)
			"sword":
				if fighting:
					var up := Vector2(hand.x + 1.2, hand.y - 5.5)
					_limb(ci, hand_w, _p(at, k, flip, up.x, up.y), 0.55 * k, STEEL)
					_limb(ci, _p(at, k, flip, hand.x - 0.9, hand.y - 0.1), _p(at, k, flip, hand.x + 0.9, hand.y + 0.1), 0.45 * k, GOLD)
			"bow":
				var top := _p(at, k, flip, hand.x + 0.7, hand.y - 5.6)
				var bottom := _p(at, k, flip, hand.x + 0.7, hand.y + 5.0)
				var mid := _p(at, k, flip, hand.x + 2.4, hand.y)
				ci.draw_polyline(PackedVector2Array([top, mid, bottom]), WOOD, 0.55 * k, true)
				ci.draw_line(top, bottom, Color(0.9, 0.88, 0.8), 0.18 * k)
	_limb(ci, _p(at, k, flip, 0.6, -15.4), hand_w, 1.7 * k, MAIL)
	ci.draw_circle(hand_w, 0.75 * k, MAIL_DARK)


static func _helm(ci: CanvasItem, at: Vector2, k: float, flip: float, kind: String) -> void:
	match kind:
		"great":
			# A flat-topped great helm with a gold cross trim, eye slit and breathing holes.
			_poly(ci, at, k, flip, [[-2.2, -22.4], [2.4, -22.4], [2.6, -16.2], [-2.1, -16.2]], STEEL)
			_poly(ci, at, k, flip, [[-2.2, -22.4], [-0.8, -22.4], [-0.8, -16.2], [-2.1, -16.2]], STEEL_DARK)
			_poly(ci, at, k, flip, [[-2.2, -22.4], [2.4, -22.4], [2.4, -21.6], [-2.2, -21.6]], GOLD)
			_poly(ci, at, k, flip, [[1.5, -21.6], [2.4, -21.6], [2.6, -16.2], [1.7, -16.2]], GOLD)
			_poly(ci, at, k, flip, [[0.0, -20.0], [2.5, -20.0], [2.5, -19.2], [0.0, -19.2]], SLIT)
			for row in 3:
				for col in 2:
					ci.draw_circle(_p(at, k, flip, 0.45 + col * 0.6, -18.5 + row * 0.55), 0.17 * k, SLIT)
		"kettle":
			var dome := [[-2.2, -19.0]]
			for i in 9:
				var a := PI + PI * i / 8.0
				dome.append([0.5 + cos(a) * 2.5, -19.0 + sin(a) * 2.8])
			_poly(ci, at, k, flip, dome, STEEL)
			_poly(ci, at, k, flip, [[-3.2, -19.3], [4.0, -19.3], [3.7, -18.5], [-2.9, -18.5]], STEEL_DARK)
			_poly(ci, at, k, flip, [[-0.3, -21.6], [0.6, -21.8], [0.7, -19.3], [-0.2, -19.3]], Color(0.78, 0.15, 0.12))
			_poly(ci, at, k, flip, [[1.6, -21.3], [2.4, -20.8], [2.4, -19.3], [1.6, -19.3]], Color(0.78, 0.15, 0.12))
		"hood":
			# Townsfolk: a simple cloth hood.
			var hood := Color(0.55, 0.42, 0.28)
			_poly(ci, at, k, flip, [[-2.2, -18.0], [-1.6, -20.8], [0.5, -21.4], [2.2, -20.4], [2.6, -18.8], [1.0, -19.6], [-0.6, -17.0]], hood)
		"bare":
			_poly(ci, at, k, flip, [[-1.6, -19.6], [0.4, -20.7], [2.2, -19.9], [1.6, -19.2], [-1.2, -18.6]], Color(0.35, 0.25, 0.15))
		_:
			# Conical nasal helm: the face shows below.
			_poly(ci, at, k, flip, [[-1.8, -19.2], [-1.2, -21.6], [0.5, -22.8], [2.0, -21.5], [2.7, -19.2]], STEEL)
			_poly(ci, at, k, flip, [[-1.9, -19.6], [2.8, -19.6], [2.8, -18.9], [-1.9, -18.9]], STEEL_DARK)
			_poly(ci, at, k, flip, [[1.95, -19.0], [2.45, -19.0], [2.45, -17.2], [1.95, -17.2]], STEEL_DARK)


## A mounted knight on a caparisoned horse, couching a lance with a pennant.
static func rider(ci: CanvasItem, at: Vector2, k: float, flip: float, o: Dictionary) -> void:
	var phase: float = o.get("phase", 0.0)
	var moving: bool = o.get("moving", false)
	var fighting: bool = o.get("fighting", false)
	var coat: Color = o.get("surcoat", Color(0.95, 0.95, 0.93))
	var horse: Color = o.get("horse", Color(0.45, 0.30, 0.20))
	var g := sin(phase * 1.3) * (1.8 if moving else 0.0)
	# Legs (far side darker).
	for leg in [[-3.8, -1.0, true], [3.0, 1.0, true], [-3.0, 1.0, false], [3.8, -1.0, false]]:
		var x: float = leg[0]
		var s: float = leg[1]
		var col := horse.darkened(0.25) if leg[2] else horse
		_limb(ci, _p(at, k, flip, x, -6.2), _p(at, k, flip, x + g * s, -0.6), 1.5 * k, col)
		ci.draw_circle(_p(at, k, flip, x + g * s, -0.4), 0.8 * k, Color(0.2, 0.17, 0.15))
	# Tail, body, neck and head.
	_limb(ci, _p(at, k, flip, -5.2, -8.5), _p(at, k, flip, -6.6 - g * 0.3, -4.5), 0.9 * k, horse.darkened(0.3))
	var body := []
	for i in 16:
		var a := TAU * i / 16.0
		body.append([cos(a) * 6.0, -8.0 + sin(a) * 3.0])
	_poly(ci, at, k, flip, body, horse)
	_poly(ci, at, k, flip, [[3.6, -10.0], [5.4, -14.6], [7.2, -14.6], [6.4, -8.2]], horse)
	_poly(ci, at, k, flip, [[5.0, -15.0], [9.4, -13.6], [9.6, -12.2], [5.8, -12.4]], horse)
	ci.draw_circle(_p(at, k, flip, 7.0, -14.0), 0.3 * k, SLIT)
	# Caparison in the rider's colours.
	_poly(ci, at, k, flip, [[-5.8, -10.6], [5.0, -10.6], [5.4, -6.0], [4.0, -3.8], [-4.0, -3.8], [-6.0, -6.0]], coat)
	if o.get("cross", true):
		var c: Color = o.get("emblem", Color(0.8, 0.12, 0.1))
		_poly(ci, at, k, flip, [[-0.3, -9.0], [0.5, -9.0], [0.5, -5.0], [-0.3, -5.0]], c)
		_poly(ci, at, k, flip, [[-1.6, -7.4], [1.8, -7.4], [1.8, -6.6], [-1.6, -6.6]], c)
	# Rider: leg, torso with surcoat, helm.
	_limb(ci, _p(at, k, flip, 0.3, -11.0), _p(at, k, flip, 1.3, -6.0), 1.9 * k, MAIL)
	_poly(ci, at, k, flip, [[-4.6, -10.4], [-2.2, -11.0], [-1.0, -17.8], [-2.0, -17.6]], coat.lightened(0.12))
	_poly(ci, at, k, flip, [[-1.9, -17.8], [1.9, -17.8], [2.6, -10.6], [-2.4, -10.6]], coat)
	ci.draw_circle(_p(at, k, flip, 0.5, -19.8), 1.9 * k, SKIN)
	_helm(ci, at + Vector2(0, -1.4) * k, k, flip, "great")
	# Lance: couched for the charge when fighting or moving, raised when waiting.
	var butt := Vector2(-2.4, -14.0)
	var tip := Vector2(13.0, -17.0) if (fighting or moving) else Vector2(5.0, -30.0)
	_limb(ci, _p(at, k, flip, butt.x, butt.y), _p(at, k, flip, tip.x, tip.y), 0.65 * k, WOOD)
	var d := (tip - butt).normalized()
	var pen := tip - d * 1.2
	var pennant: Color = o.get("pennant", coat)
	_poly(ci, at, k, flip, [[pen.x, pen.y], [pen.x - d.x * 2.2, pen.y - d.y * 2.2], [pen.x - d.x * 0.6 - 2.4, pen.y - d.y * 0.6 + 0.8 + sin(phase) * 0.3]], pennant)
	_limb(ci, _p(at, k, flip, 0.6, -16.4), _p(at, k, flip, 1.9, -14.0), 1.7 * k, MAIL)


## A fallen soldier lying on the ground.
static func fallen(ci: CanvasItem, at: Vector2, k: float, flip: float, coat: Color) -> void:
	_poly(ci, at, k, flip, [[-6.5, 0.2], [-3.0, -1.0], [2.0, -1.6], [2.0, 0.6], [-6.0, 1.0]], coat.darkened(0.15))
	_limb(ci, _p(at, k, flip, 2.0, -0.8), _p(at, k, flip, 6.4, -0.6), 1.8 * k, MAIL_DARK)
	_limb(ci, _p(at, k, flip, 2.0, 0.2), _p(at, k, flip, 6.0, 0.9), 1.8 * k, MAIL)
	ci.draw_circle(_p(at, k, flip, -4.0, -1.6), 1.6 * k, STEEL_DARK)
	_limb(ci, _p(at, k, flip, -2.0, -0.6), _p(at, k, flip, -1.0, -3.2), 1.4 * k, MAIL)
