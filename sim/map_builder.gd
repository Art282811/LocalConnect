class_name MapBuilder
extends RefCounted
## Builds Layer 1 provinces: a hex grid laid over a hand-drawn Europe outline,
## each hex clipped to the coastline. Later layers can swap in real shapes.

const HEX_SAMPLES := [[0.0, 1], [0.5, 6], [0.85, 12]]  # [ring radius, points]

var lon_min: float
var lon_max: float
var lat_min: float
var lat_max: float
var lon_scale: float
var px: float
var radius: float

var land: Array[PackedVector2Array] = []
var water: Array[PackedVector2Array] = []
var rivers: Array[PackedVector2Array] = []
var provinces: Array[Province] = []
var map_size := Vector2.ZERO

var _data: Dictionary


func _init(data: Dictionary) -> void:
	_data = data
	var b: Dictionary = data["bounds"]
	lon_min = b["lon_min"]
	lon_max = b["lon_max"]
	lat_min = b["lat_min"]
	lat_max = b["lat_max"]
	lon_scale = data["projection"]["lon_scale"]
	px = data["projection"]["units_to_px"]
	radius = float(data["hex_radius"]) * px
	map_size = project(lon_max, lat_min)


func project(lon: float, lat: float) -> Vector2:
	return Vector2((lon - lon_min) * lon_scale * px, (lat_max - lat) * px)


func unproject(v: Vector2) -> Vector2:
	return Vector2(v.x / (lon_scale * px) + lon_min, lat_max - v.y / px)


func _poly(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(project(float(p[0]), float(p[1])))
	return out


func is_land(pt: Vector2) -> bool:
	var on_land := false
	for poly: PackedVector2Array in land:
		if Geometry2D.is_point_in_polygon(pt, poly):
			on_land = true
			break
	if not on_land:
		return false
	for poly: PackedVector2Array in water:
		if Geometry2D.is_point_in_polygon(pt, poly):
			return false
	return true


static func polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func polygon_centroid(poly: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var cr := p.x * q.y - q.x * p.y
		a += cr
		c += (p + q) * cr
	if absf(a) < 0.0001:
		var s := Vector2.ZERO
		for p in poly:
			s += p
		return s / maxf(poly.size(), 1)
	return c / (3.0 * a)


func hex_points(c: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i - 30.0)
		pts.append(c + Vector2(cos(ang), sin(ang)) * radius)
	return pts


func build(rng: RandomNumberGenerator) -> void:
	for l in _data["land"]:
		land.append(_poly(l["points"]))
	for w in _data["water"]:
		water.append(_poly(w["points"]))
	for r in _data["rivers"]:
		rivers.append(_poly(r["points"]))

	var min_fraction: float = _data.get("min_land_fraction", 0.35)
	var w := sqrt(3.0) * radius
	var h := 1.5 * radius
	var hex_area := 2.598076 * radius * radius
	var cells := {}  # Vector2i(col, row) -> province id
	var rows := int(ceil(map_size.y / h)) + 1
	var cols := int(ceil(map_size.x / w)) + 1

	for row in rows:
		for col in cols:
			var c := Vector2(col * w + (w * 0.5 if row % 2 == 1 else 0.0), row * h)
			var land_hits := 0
			var total := 0
			var best_land := Vector2.INF
			for ring in HEX_SAMPLES:
				var count: int = ring[1]
				for i in count:
					var ang := TAU * i / count
					var s: Vector2 = c + Vector2(cos(ang), sin(ang)) * radius * float(ring[0])
					total += 1
					if is_land(s):
						land_hits += 1
						if best_land == Vector2.INF:
							best_land = s
			var fraction := float(land_hits) / total
			if fraction < min_fraction:
				continue
			var hex := hex_points(c)
			var pieces: Array[PackedVector2Array] = []
			for lp: PackedVector2Array in land:
				for piece: PackedVector2Array in Geometry2D.intersect_polygons(hex, lp):
					pieces.append(piece)
			for wp: PackedVector2Array in water:
				var next: Array[PackedVector2Array] = []
				for piece: PackedVector2Array in pieces:
					for q: PackedVector2Array in Geometry2D.clip_polygons(piece, wp):
						next.append(q)
				pieces = next
			var kept: Array[PackedVector2Array] = []
			var biggest := -1.0
			var main_piece := PackedVector2Array()
			for piece: PackedVector2Array in pieces:
				var a := polygon_area(piece)
				if a < hex_area * 0.04:
					continue
				kept.append(piece)
				if a > biggest:
					biggest = a
					main_piece = piece
			if kept.is_empty():
				continue
			var p := Province.new()
			p.id = provinces.size()
			p.hex = hex
			p.polygons = kept
			p.coastal = fraction < 0.97
			var center := polygon_centroid(main_piece)
			if not Geometry2D.is_point_in_polygon(center, main_piece):
				center = c if Geometry2D.is_point_in_polygon(c, main_piece) else best_land
			p.center = center
			p.lonlat = unproject(center)
			provinces.append(p)
			cells[Vector2i(col, row)] = p.id

	_link_neighbors(cells)
	for p: Province in provinces:
		p.terrain = _terrain_at(p.lonlat)
		p.culture = _culture_at(p.lonlat)
		p.glyphs = _glyph_points(p, rng)


func _link_neighbors(cells: Dictionary) -> void:
	var even := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 1), Vector2i(-1, 1)]
	var odd := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(0, 1)]
	for key in cells:
		var cell: Vector2i = key
		var pid: int = cells[cell]
		var p := provinces[pid]
		var dirs: Array = odd if cell.y % 2 == 1 else even
		for d in dirs:
			var nkey: Vector2i = cell + d
			if not cells.has(nkey):
				continue
			var nid: int = cells[nkey]
			var shared := _shared_edge(p.hex, provinces[nid].hex)
			if shared.size() < 2:
				continue
			var segments := _land_segments(shared[0], shared[1])
			p.neighbors.append(nid)
			if segments.is_empty():
				p.straits.append(nid)
			else:
				p.edges.append({"nb": nid, "segments": segments})


func _shared_edge(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for va in a:
		for vb in b:
			if va.distance_squared_to(vb) < 1.0:
				out.append(va)
				break
	return out


## Splits a hex edge into pieces and keeps the runs that lie on land, so realm
## borders stop at the coast instead of running out to sea.
func _land_segments(a: Vector2, b: Vector2) -> Array[PackedVector2Array]:
	const STEPS := 8
	var out: Array[PackedVector2Array] = []
	var current := PackedVector2Array()
	for i in STEPS:
		var p0 := a.lerp(b, float(i) / STEPS)
		var p1 := a.lerp(b, float(i + 1) / STEPS)
		if is_land((p0 + p1) * 0.5):
			if current.is_empty():
				current.append(p0)
			current.append(p1)
		elif not current.is_empty():
			out.append(current)
			current = PackedVector2Array()
	if not current.is_empty():
		out.append(current)
	return out


func _terrain_at(ll: Vector2) -> String:
	var result := "forest" if ll.y > float(_data.get("forest_lat", 90.0)) else "plains"
	for t in _data["terrain"]:
		if t.get("type", "") == "comment":
			continue
		var dx := (ll.x - float(t["lon"])) / float(t["rx"])
		var dy := (ll.y - float(t["lat"])) / float(t["ry"])
		if dx * dx + dy * dy <= 1.0:
			result = t["type"]
	return result


func _culture_at(ll: Vector2) -> String:
	var best := "latin"
	var best_d := INF
	for c in _data["cultures"]:
		for a in c["anchors"]:
			var d := Vector2((ll.x - float(a[0])) * lon_scale, ll.y - float(a[1])).length_squared()
			if d < best_d:
				best_d = d
				best = c["id"]
	return best


func _glyph_points(p: Province, rng: RandomNumberGenerator) -> PackedVector2Array:
	var out := PackedVector2Array()
	var want := 0 if p.terrain == "plains" else 3
	var tries := 0
	while out.size() < want and tries < 30:
		tries += 1
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * radius * 0.62
		var pt := _hex_center(p) + off
		if pt.distance_to(p.center) < radius * 0.3:
			continue
		for piece: PackedVector2Array in p.polygons:
			if Geometry2D.is_point_in_polygon(pt, piece):
				out.append(pt)
				break
	return out


func _hex_center(p: Province) -> Vector2:
	var s := Vector2.ZERO
	for v in p.hex:
		s += v
	return s / 6.0
