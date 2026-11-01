class_name LabelsView
extends Node2D
## Settlements, roads and names. What is shown depends on zoom:
## continent = realm names + capitals; region = towns, villages, roads, names.

const INK := Color(0.25, 0.17, 0.10)
const PAPER := Color(0.95, 0.90, 0.76)
const REGION_ZOOM := 0.62
const DETAIL_ZOOM := 1.15

var world: World
var zoom := 1.0
var serif: Font
var _drawn_zoom := -1.0


func _ready() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Georgia", "Times New Roman", "Noto Serif", "DejaVu Serif", "Liberation Serif", "serif"])
	f.font_weight = 700
	f.multichannel_signed_distance_field = true
	serif = f


func set_zoom(z: float) -> void:
	zoom = z
	if _drawn_zoom < 0.0 or absf(log(z / _drawn_zoom)) > 0.08:
		queue_redraw()


func _draw() -> void:
	if world == null:
		return
	_drawn_zoom = zoom
	var region := zoom >= REGION_ZOOM
	var detail := zoom >= DETAIL_ZOOM
	var icon_scale := 1.0 / clampf(zoom, 0.55, 1.8)

	if detail and zoom < 4.0:
		_draw_roads()

	var close_battle := zoom >= BattleView.BLOCK_ZOOM
	for p: Province in world.provinces:
		var is_cap := p.owner != -1 and world.realms[p.owner].capital == p.id
		if close_battle and world.battle_at(p.id) != null:
			continue  # the battle view draws this village up close
		if region:
			if detail:
				_draw_villages(p)
			draw_settlement(self, p.center, p.settlement, p.level + (1 if is_cap else 0), icon_scale, is_cap)
		elif is_cap and world.realms[p.owner].provinces.size() >= 3:
			draw_settlement(self, p.center, "castle", 2, icon_scale * 0.8, true)

	if region and zoom < 4.0:
		var fs := int(clampf(13.0 / zoom, 4.0, 40.0))
		for p: Province in world.provinces:
			_text_centered(p.name, p.center + Vector2(0, 22.0 * icon_scale + fs * 0.6), fs, INK, PAPER, 3)

	_draw_realm_names(region)


func _draw_realm_names(region: bool) -> void:
	if zoom > 1.4:
		return
	var alpha := 0.3 if region else 0.9
	for r: Realm in world.realms:
		if not r.alive or r.provinces.is_empty():
			continue
		var n := r.provinces.size()
		if region and n < 3:
			continue
		var sum := Vector2.ZERO
		for pid: int in r.provinces:
			sum += world.provinces[pid].center
		var c := sum / n
		var size := int(clampf(16.0 + sqrt(float(n)) * 22.0, 18.0, 150.0))
		var text := r.name.to_upper()
		if r.rank >= 2:
			text = _spaced(text)  # spaced capitals for great realms
		var col := Color(r.border_color(), alpha)
		_text_centered(text, c, size, col, Color(PAPER, alpha * 0.8), maxi(2, size / 10))
		if n >= 3 and not region:
			var w := serif.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			Heraldry.draw_shield(self, c - Vector2(w * 0.5 + size * 0.7, 0), size * 1.1, r, maxf(size / 25.0, 1.0))
		if n >= 3:
			_text_centered(r.title().to_upper(), c - Vector2(0, size * 0.75), int(size * 0.4), col, Color(PAPER, alpha * 0.8), 2)


func _spaced(text: String) -> String:
	var chars := PackedStringArray()
	for i in text.length():
		chars.append(text[i])
	return " ".join(chars)


func _text_centered(text: String, pos: Vector2, size: int, col: Color, outline: Color, outline_px: int) -> void:
	var w := serif.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var at := pos + Vector2(-w.x * 0.5, size * 0.35)
	draw_string_outline(serif, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_px * 2, outline)
	draw_string(serif, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_roads() -> void:
	var road := Color(0.48, 0.36, 0.22, 0.6)
	for p: Province in world.provinces:
		if p.owner == -1:
			continue
		for e: Dictionary in p.edges:
			var nb: int = e["nb"]
			if nb > p.id and world.provinces[nb].owner != -1:
				draw_dashed_line(p.center, world.provinces[nb].center, road, 2.0, 7.0)


func _draw_villages(p: Province) -> void:
	if p.owner == -1:
		return
	var huts := 1 + p.level
	for i in huts:
		var ang := TAU * i / huts + p.id
		var at := p.center + Vector2(cos(ang), sin(ang)) * (30.0 + (i % 2) * 8.0)
		var inside := false
		for piece: PackedVector2Array in p.polygons:
			if Geometry2D.is_point_in_polygon(at, piece):
				inside = true
				break
		if inside:
			_hut(self, at, 0.6)


## Draws a settlement icon. Static so the overlay and UI can reuse it.
static func draw_settlement(ci: CanvasItem, at: Vector2, kind: String, level: int, s: float, capital: bool) -> void:
	var stone := Color(0.72, 0.68, 0.62)
	var roof := Color(0.66, 0.30, 0.22)
	var k := s * (0.8 + 0.15 * level)
	match kind:
		"castle":
			var body := Rect2(at + Vector2(-9, -8) * k, Vector2(18, 14) * k)
			ci.draw_rect(body, stone)
			for i in 3:
				ci.draw_rect(Rect2(at + Vector2(-9 + i * 7, -12) * k, Vector2(4, 4) * k), stone)
			ci.draw_rect(Rect2(at + Vector2(-3, -20) * k, Vector2(6, 12) * k), stone)
			ci.draw_rect(Rect2(at + Vector2(-2, 0) * k, Vector2(4, 6) * k), INK)
			ci.draw_rect(body, INK, false, 1.2)
			ci.draw_rect(Rect2(at + Vector2(-3, -20) * k, Vector2(6, 12) * k), INK, false, 1.2)
		"town":
			for i in 3:
				var o := at + Vector2(-10 + i * 7, -2 + (i % 2) * -4) * k
				_house(ci, o, k, roof)
		"port":
			_house(ci, at + Vector2(-6, -4) * k, k, roof)
			ci.draw_line(at + Vector2(-2, 6) * k, at + Vector2(14, 6) * k, INK, 2.0 * k)
			var hull := PackedVector2Array([at + Vector2(4, 8) * k, at + Vector2(16, 8) * k, at + Vector2(13, 12) * k, at + Vector2(7, 12) * k])
			ci.draw_colored_polygon(hull, Color(0.45, 0.32, 0.2))
			ci.draw_line(at + Vector2(10, 8) * k, at + Vector2(10, -2) * k, INK, 1.2)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(10, -2) * k, at + Vector2(15, 5) * k, at + Vector2(10, 5) * k]), Color(0.95, 0.93, 0.85))
		"monastery":
			ci.draw_rect(Rect2(at + Vector2(-8, -6) * k, Vector2(16, 12) * k), stone)
			ci.draw_rect(Rect2(at + Vector2(-8, -6) * k, Vector2(16, 12) * k), INK, false, 1.2)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -6) * k, at + Vector2(0, -22) * k, at + Vector2(3, -6) * k]), Color(0.45, 0.4, 0.5))
			ci.draw_line(at + Vector2(0, -22) * k, at + Vector2(0, -27) * k, INK, 1.5)
			ci.draw_line(at + Vector2(-2.5, -25) * k, at + Vector2(2.5, -25) * k, INK, 1.5)
		_:
			_hut(ci, at + Vector2(-5, 0) * k, k)
			_hut(ci, at + Vector2(5, 3) * k, k * 0.85)
	if capital:
		var flag := at + Vector2(0, -28) * k
		ci.draw_line(flag, flag + Vector2(0, 12) * k, INK, 1.5)
		ci.draw_colored_polygon(PackedVector2Array([flag, flag + Vector2(10, 3) * k, flag + Vector2(0, 6) * k]), Color(0.75, 0.15, 0.12))


static func _house(ci: CanvasItem, at: Vector2, k: float, roof: Color) -> void:
	ci.draw_rect(Rect2(at + Vector2(-3, 0) * k, Vector2(6, 6) * k), Color(0.86, 0.78, 0.62))
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-4.5, 0) * k, at + Vector2(0, -5) * k, at + Vector2(4.5, 0) * k]), roof)
	ci.draw_rect(Rect2(at + Vector2(-3, 0) * k, Vector2(6, 6) * k), INK, false, 1.0)


static func _hut(ci: CanvasItem, at: Vector2, k: float) -> void:
	ci.draw_rect(Rect2(at + Vector2(-3, 0) * k, Vector2(6, 4) * k), Color(0.70, 0.58, 0.40))
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-4, 0) * k, at + Vector2(0, -5) * k, at + Vector2(4, 0) * k]), Color(0.78, 0.66, 0.35))
