class_name MapView
extends Node2D
## The parchment campaign map: sea, coastlines, terrain art, rivers,
## province fills in realm colours and realm borders.
## Redrawn only when ownership changes or the zoom moves a fair bit.

const SEA := Color(0.60, 0.68, 0.66)
const SEA_LINE := Color(0.50, 0.58, 0.57, 0.5)
const LAND := Color(0.91, 0.85, 0.69)
const INK := Color(0.29, 0.21, 0.13)
const RIVER := Color(0.33, 0.48, 0.62)
const TERRAIN_TINT := {
	"plains": Color(0.91, 0.86, 0.68),
	"forest": Color(0.78, 0.82, 0.63),
	"hills": Color(0.86, 0.79, 0.62),
	"mountains": Color(0.80, 0.74, 0.64),
	"marsh": Color(0.77, 0.81, 0.70),
	"desert": Color(0.94, 0.86, 0.62),
}

var world: World
var zoom := 1.0
var highlight := -1  # selected province
var mode := "realms"  # realms, faiths, diplomacy
var _drawn_zoom := -1.0


func set_zoom(z: float) -> void:
	zoom = z
	if _drawn_zoom < 0.0 or absf(log(z / _drawn_zoom)) > 0.18:
		queue_redraw()


## Line width that stays about `px` screen pixels wide.
func _w(px: float) -> float:
	return px / zoom


func _draw() -> void:
	if world == null:
		return
	_drawn_zoom = zoom
	var size := world.map_size
	draw_rect(Rect2(Vector2(-2000, -2000), size + Vector2(4000, 4000)), SEA)
	# Engraved sea lines.
	var y := 24.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), SEA_LINE, _w(1.0))
		y += 48.0

	for poly: PackedVector2Array in world.land_polys:
		draw_colored_polygon(poly, LAND)
	for poly: PackedVector2Array in world.water_polys:
		draw_colored_polygon(poly, SEA)

	for p: Province in world.provinces:
		var fill := _fill_for(p)
		for piece: PackedVector2Array in p.polygons:
			draw_colored_polygon(piece, fill)

	if zoom > 0.42:
		_draw_terrain_glyphs()

	for river in world.rivers:
		draw_polyline(river, RIVER, maxf(_w(2.0), 3.0), true)

	# Province outlines, faint.
	var thin := Color(INK, 0.22 if zoom > 0.6 else 0.12)
	for p: Province in world.provinces:
		for piece: PackedVector2Array in p.polygons:
			var closed := piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, thin, _w(1.0))

	# Sea crossings.
	for p: Province in world.provinces:
		for nb: int in p.straits:
			if nb > p.id:
				draw_dashed_line(p.center, world.provinces[nb].center, Color(INK, 0.35), _w(1.5), _w(6.0))

	# Coastlines.
	for poly: PackedVector2Array in world.land_polys:
		var c := poly.duplicate()
		c.append(poly[0])
		draw_polyline(c, INK, maxf(_w(1.6), 2.0), true)
	for poly: PackedVector2Array in world.water_polys:
		var c := poly.duplicate()
		c.append(poly[0])
		draw_polyline(c, INK, maxf(_w(1.6), 2.0), true)

	# Realm borders: drawn on land edges where owners differ.
	for p: Province in world.provinces:
		for e: Dictionary in p.edges:
			var nb: int = e["nb"]
			var other := world.provinces[nb].owner
			if other == p.owner or p.owner == -1:
				continue
			var col := world.realms[p.owner].border_color()
			for seg in e["segments"]:
				draw_polyline(seg, col, maxf(_w(2.5), 3.0), true)

	if highlight != -1:
		var hp := world.provinces[highlight]
		for piece: PackedVector2Array in hp.polygons:
			var closed := piece.duplicate()
			closed.append(piece[0])
			draw_polyline(closed, Color(1.0, 0.85, 0.3), _w(3.0), true)

	_draw_cartography(size)
	_draw_frame(size)


func _fill_for(p: Province) -> Color:
	var base: Color = TERRAIN_TINT.get(p.terrain, LAND)
	match mode:
		"faiths":
			return base.lerp(world.religion.color_of(p.faith), 0.65)
		"diplomacy":
			var me := world.player_realm
			if me == -1 or p.owner == -1:
				return base
			if p.owner == me:
				return base.lerp(Color(0.85, 0.7, 0.25), 0.7)
			if world.at_war(me, p.owner):
				return base.lerp(Color(0.7, 0.1, 0.08), 0.75)
			var o := world.diplomacy.opinion(p.owner, me)
			var col := Color(0.75, 0.25, 0.2).lerp(Color(0.3, 0.65, 0.3), (o + 100.0) / 200.0)
			if world.diplomacy.has_treaty("alliance", me, p.owner) or world.diplomacy.has_treaty("defensive", me, p.owner):
				col = Color(0.25, 0.45, 0.8)
			return base.lerp(col, 0.65)
	if p.owner == -1:
		return base
	var r := world.realms[p.owner]
	var rc := r.color()
	if r.liege != -1 and world.realms[r.liege].alive:
		rc = rc.lerp(world.realms[r.liege].color(), 0.45)
	return base.lerp(rc, 0.7)


## Age spots on the parchment, a compass rose and a title cartouche.
func _draw_cartography(size: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1187
	for i in 140:
		var at := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		draw_circle(at, rng.randf_range(20.0, 120.0), Color(0.45, 0.32, 0.15, 0.035))
	var font := ThemeDB.fallback_font
	# Compass rose in the North Atlantic.
	var c := Vector2(150, 360)
	var points := PackedVector2Array()
	for i in 16:
		var ang := -PI / 2.0 + i * PI / 8.0
		var rad := 70.0 if i % 4 == 0 else (40.0 if i % 2 == 0 else 22.0)
		points.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_colored_polygon(points, Color(0.9, 0.84, 0.68))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, INK, 2.0, true)
	for i in 4:
		var ang := -PI / 2.0 + i * PI / 2.0
		draw_line(c, c + Vector2(cos(ang), sin(ang)) * 70.0, INK, 1.5)
	draw_circle(c, 8.0, Color(0.7, 0.15, 0.1))
	draw_arc(c, 28.0, 0, TAU, 40, INK, 1.5, true)
	draw_string(font, c + Vector2(-9, -78), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, INK)
	# Title cartouche.
	var box := Rect2(Vector2(40, 40), Vector2(420, 110))
	draw_rect(box, Color(0.93, 0.87, 0.7))
	draw_rect(box, INK, false, 4.0)
	draw_rect(box.grow(-10), INK, false, 1.5)
	for corner in [box.position, box.position + Vector2(box.size.x, 0), box.position + Vector2(0, box.size.y), box.end]:
		draw_circle(corner, 12.0, Color(0.7, 0.15, 0.1))
		draw_arc(corner, 12.0, 0, TAU, 20, INK, 2.0)
	draw_string(font, box.position + Vector2(0, 62), "EUROPA ET ORIENS", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 40, INK)
	draw_string(font, box.position + Vector2(0, 92), "the known world", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 22, Color(INK, 0.7))


func _draw_frame(size: Vector2) -> void:
	draw_rect(Rect2(Vector2(-30, -30), size + Vector2(60, 60)), INK, false, 10.0)
	draw_rect(Rect2(Vector2(-12, -12), size + Vector2(24, 24)), INK, false, 3.0)
	for corner in [Vector2(-30, -30), Vector2(size.x + 30, -30), Vector2(-30, size.y + 30), size + Vector2(30, 30)]:
		draw_circle(corner, 22.0, INK)
		draw_circle(corner, 14.0, LAND)


func _draw_terrain_glyphs() -> void:
	var ink := Color(INK, 0.55)
	var few := zoom < 1.0   # one doodle per province until you are close
	for p: Province in world.provinces:
		var glyphs := p.glyphs if not few or p.glyphs.size() <= 1 else p.glyphs.slice(0, 1)
		match p.terrain:
			"mountains":
				for g: Vector2 in glyphs:
					var pts := PackedVector2Array([g + Vector2(-13, 8), g + Vector2(0, -12), g + Vector2(13, 8)])
					draw_colored_polygon(pts, Color(0.62, 0.55, 0.46))
					draw_colored_polygon(PackedVector2Array([g + Vector2(-4, -6), g + Vector2(0, -12), g + Vector2(4, -6)]), Color(0.97, 0.95, 0.9))
					draw_polyline(pts, ink, 1.5, true)
			"hills":
				for g: Vector2 in glyphs:
					draw_arc(g, 10.0, PI * 1.1, PI * 1.9, 10, ink, 1.5, true)
					draw_arc(g + Vector2(10, 4), 7.0, PI * 1.1, PI * 1.9, 8, ink, 1.5, true)
			"forest":
				for g: Vector2 in glyphs:
					for off in [Vector2(-7, 2), Vector2(6, 0), Vector2(0, -5)]:
						var t: Vector2 = g + off
						draw_line(t, t + Vector2(0, 8), ink, 1.5)
						draw_circle(t, 5.5, Color(0.42, 0.53, 0.33))
			"marsh":
				for g: Vector2 in glyphs:
					for i in 3:
						var row := g + Vector2(0, i * 5 - 5)
						draw_line(row + Vector2(-9 + i * 2, 0), row + Vector2(7 - i, 0), ink, 1.2)
					draw_line(g + Vector2(-3, -8), g + Vector2(-5, -14), ink, 1.2)
					draw_line(g + Vector2(2, -8), g + Vector2(3, -15), ink, 1.2)
			"desert":
				for g: Vector2 in glyphs:
					draw_arc(g, 12.0, PI * 1.2, PI * 1.8, 10, Color(0.68, 0.55, 0.32), 1.5, true)
					draw_circle(g + Vector2(-6, 6), 1.5, ink)
					draw_circle(g + Vector2(5, 7), 1.5, ink)
