class_name Heraldry
extends RefCounted
## Procedural coats of arms: a field in the realm's colour, a division
## (per pale, per fess, quarterly, bend, chevron, cross, saltire) and a charge.
## Stable for each realm (seeded by its id and name).

const METALS := [Color(0.95, 0.85, 0.35), Color(0.93, 0.93, 0.90)]   # or, argent
const PATTERNS := ["plain", "pale", "fess", "quarterly", "bend", "chevron", "cross", "saltire"]
const CHARGES := ["none", "roundel", "star", "lozenge", "crescent", "cross"]
const INK := Color(0.18, 0.12, 0.07)


static func arms(r: Realm) -> Dictionary:
	var h := hash(r.name + str(r.id))
	var field := r.color().darkened(0.1)
	var metal: Color = METALS[absi(h) % 2]
	var pattern: String = PATTERNS[absi(h / 3) % PATTERNS.size()]
	var charge: String = CHARGES[absi(h / 29) % CHARGES.size()]
	if r.faith != "" and ["catholic", "orthodox"].has(r.faith) and charge == "crescent":
		charge = "cross"
	elif ["sunni", "shia"].has(r.faith) and charge == "cross":
		charge = "crescent"
	return {"field": field, "metal": metal, "pattern": pattern, "charge": charge}


static func shield_points(at: Vector2, size: float) -> PackedVector2Array:
	var w := size * 0.5
	var pts := PackedVector2Array([at + Vector2(-w, -size * 0.55), at + Vector2(w, -size * 0.55), at + Vector2(w, 0.0)])
	for i in range(1, 8):
		var t := float(i) / 8.0
		pts.append(at + Vector2(w * (1.0 - t), size * 0.55 * sin(t * PI * 0.5)))
	pts.append(at + Vector2(0.0, size * 0.55))
	for i in range(7, 0, -1):
		var t := float(i) / 8.0
		pts.append(at + Vector2(-w * (1.0 - t), size * 0.55 * sin(t * PI * 0.5)))
	pts.append(at + Vector2(-w, 0.0))
	return pts


static var _cache := {}   # "realm id:pattern" -> unit-size metal pieces


static func draw_shield(ci: CanvasItem, at: Vector2, size: float, r: Realm, outline := 1.0) -> void:
	var a := arms(r)
	var field: Color = a["field"]
	var metal: Color = a["metal"]
	# Draw at unit size around the origin, scaled into place.
	ci.draw_set_transform(at, 0.0, Vector2(size, size))
	var shield := shield_points(Vector2.ZERO, 1.0)
	ci.draw_colored_polygon(shield, field)
	var key := "%d:%s" % [r.id, a["pattern"]]
	if not _cache.has(key):
		_cache[key] = _metal_pieces(str(a["pattern"]), shield)
	for piece in _cache[key]:
		ci.draw_colored_polygon(piece, metal)
	var charge_col := field.darkened(0.45) if a["pattern"] != "plain" else metal
	var c := Vector2(0, -0.05)
	var k := 0.17
	match str(a["charge"]):
		"roundel":
			ci.draw_circle(c, k, charge_col)
		"star":
			var star := PackedVector2Array()
			for i in 10:
				var ang := -PI / 2.0 + i * PI / 5.0
				var rad := k * (1.2 if i % 2 == 0 else 0.5)
				star.append(c + Vector2(cos(ang), sin(ang)) * rad)
			ci.draw_colored_polygon(star, charge_col)
		"lozenge":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k * 1.3), c + Vector2(k * 0.8, 0), c + Vector2(0, k * 1.3), c + Vector2(-k * 0.8, 0)]), charge_col)
		"crescent":
			ci.draw_arc(c, k, PI * 0.15, PI * 1.85, 16, charge_col, k * 0.55)
		"cross":
			ci.draw_rect(Rect2(c + Vector2(-k * 0.25, -k * 1.1), Vector2(k * 0.5, k * 2.2)), charge_col)
			ci.draw_rect(Rect2(c + Vector2(-k * 0.9, -k * 0.45), Vector2(k * 1.8, k * 0.5)), charge_col)
	var closed := shield.duplicate()
	closed.append(shield[0])
	ci.draw_polyline(closed, INK, outline / maxf(size, 0.001), true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _metal_pieces(pattern: String, shield: PackedVector2Array) -> Array:
	var parts: Array = []
	match pattern:
		"pale":
			parts.append(_rect(Vector2(0, -1), Vector2(1, 2)))
		"fess":
			parts.append(_rect(Vector2(-1, -1), Vector2(2, 1)))
		"quarterly":
			parts.append(_rect(Vector2(0, -1), Vector2(1, 1)))
			parts.append(_rect(Vector2(-1, 0), Vector2(1, 1)))
		"bend":
			parts.append(PackedVector2Array([Vector2(-1, -0.8), Vector2(-0.6, -1), Vector2(1, 0.8), Vector2(0.6, 1)]))
		"chevron":
			parts.append(PackedVector2Array([Vector2(-1, 0.35), Vector2(0, -0.2), Vector2(1, 0.35), Vector2(1, 0.6), Vector2(0, 0.05), Vector2(-1, 0.6)]))
		"cross":
			parts.append(_rect(Vector2(-0.1, -1), Vector2(0.2, 2)))
			parts.append(_rect(Vector2(-1, -0.18), Vector2(2, 0.2)))
		"saltire":
			parts.append(PackedVector2Array([Vector2(-1, -0.8), Vector2(-0.8, -1), Vector2(1, 0.8), Vector2(0.8, 1)]))
			parts.append(PackedVector2Array([Vector2(1, -0.8), Vector2(0.8, -1), Vector2(-1, 0.8), Vector2(-0.8, 1)]))
	var out: Array = []
	for part in parts:
		for piece in Geometry2D.intersect_polygons(shield, part):
			out.append(piece)
	return out


static func _rect(pos: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y)])
