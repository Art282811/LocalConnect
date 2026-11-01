class_name OverlayView
extends Node2D
## Things that move: army banners, siege camps, claim markers, battle smoke,
## the selected army's route. Redrawn every frame (only a few dozen items).

const INK := Color(0.22, 0.15, 0.09)
const PAPER := Color(0.96, 0.92, 0.80)
const PUFF_SECONDS := 2.5

var world: World
var zoom := 1.0
var selected_army := -1
var font: Font
var positions := {}  # army id -> drawn world position (for tapping)
var _puffs: Array = []


func _ready() -> void:
	font = ThemeDB.fallback_font


func add_battle(pos: Vector2, troops: int) -> void:
	_puffs.append({"pos": pos, "t": 0.0, "big": troops > 2000})


func _process(delta: float) -> void:
	for p in _puffs:
		p["t"] = float(p["t"]) + delta
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return float(p["t"]) < PUFF_SECONDS)
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var s := 1.0 / clampf(zoom, 0.3, 2.0)
	_draw_occupations(s)
	_draw_puffs(s)
	_draw_armies(s)


func _draw_occupations(s: float) -> void:
	for p: Province in world.provinces:
		if p.siege_army == -1:
			continue
		var a := world.army_by_id(p.siege_army)
		if a == null:
			continue
		var col := world.realms[a.realm].color()
		var r := 34.0 * s
		if p.owner == -1:
			# Claiming: a dashed ring of stakes.
			draw_arc(p.center, r, 0, TAU, 32, Color(col, 0.5), 2.0 * s)
		else:
			# Siege: a ring of tents.
			for i in 8:
				var ang := TAU * i / 8.0
				var at := p.center + Vector2(cos(ang), sin(ang)) * r
				var tent := PackedVector2Array([at + Vector2(-5, 4) * s, at + Vector2(0, -5) * s, at + Vector2(5, 4) * s])
				draw_colored_polygon(tent, Color(0.93, 0.89, 0.8))
				draw_polyline(tent, INK, 1.0 * s)
		draw_arc(p.center, r + 6.0 * s, -PI / 2, -PI / 2 + TAU * p.siege_progress, 32, col.darkened(0.3), 4.0 * s)


func _draw_puffs(s: float) -> void:
	for p in _puffs:
		var t: float = float(p["t"]) / PUFF_SECONDS
		var base: Vector2 = p["pos"]
		var grow := 1.6 if p["big"] else 1.0
		for i in 5:
			var ang := i * 1.7
			var off := Vector2(cos(ang), sin(ang)) * (8.0 + 22.0 * t) * s * grow
			draw_circle(base + off + Vector2(0, -16.0 * t * s), (7.0 + 12.0 * t) * s * grow, Color(0.55, 0.53, 0.5, 0.6 * (1.0 - t)))
		if t < 0.3:
			draw_circle(base, 10.0 * s * grow, Color(1.0, 0.75, 0.3, 0.7 * (1.0 - t / 0.3)))


func _draw_armies(s: float) -> void:
	positions.clear()
	var stack := {}
	for a: Army in world.armies:
		if a.dead:
			continue
		if a.battle != -1 and zoom >= BattleView.BLOCK_ZOOM:
			continue
		var pos := world.army_position(a)
		var key := Vector2i(int(pos.x / 8.0), int(pos.y / 8.0))
		var n: int = stack.get(key, 0)
		stack[key] = n + 1
		pos += Vector2(14.0 * n, -6.0 * n) * s
		positions[a.id] = pos
		if a.id == selected_army:
			_draw_route(a, s)
		_banner(a, pos, s)


func _draw_route(a: Army, s: float) -> void:
	var prev := world.army_position(a)
	for pid: int in a.path:
		var next := world.provinces[pid].center
		draw_dashed_line(prev, next, Color(0.75, 0.1, 0.08), 3.0 * s, 10.0 * s)
		prev = next
	if not a.path.is_empty():
		draw_circle(prev, 7.0 * s, Color(0.75, 0.1, 0.08))


func _banner(a: Army, at: Vector2, s: float) -> void:
	var r := world.realms[a.realm]
	var col := r.color()
	var dark := r.border_color()
	if a.id == selected_army:
		draw_circle(at, 26.0 * s, Color(1.0, 0.85, 0.3, 0.55))
	# Pole and swallow-tail flag in the realm colour.
	var top := at + Vector2(-8, -30) * s
	draw_line(at + Vector2(-8, 4) * s, top, INK, 2.0 * s)
	var flag := PackedVector2Array([top, top + Vector2(22, 0) * s, top + Vector2(17, 7) * s, top + Vector2(22, 14) * s, top + Vector2(0, 14) * s])
	draw_colored_polygon(flag, col)
	var outline := flag.duplicate()
	outline.append(top)
	draw_polyline(outline, dark, 1.5 * s)
	draw_line(top + Vector2(4, 7) * s, top + Vector2(14, 7) * s, dark, 2.0 * s)
	if r.is_player:
		draw_circle(top + Vector2(0, -3) * s, 3.0 * s, Color(0.95, 0.75, 0.2))
	# Troop count plaque.
	var text := _short(a.troops)
	var fs := int(13.0 * s)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var plaque := Rect2(at + Vector2(-w * 0.5 - 4 * s, -1 * s), Vector2(w + 8 * s, fs + 4 * s))
	draw_rect(plaque, PAPER)
	draw_rect(plaque, dark, false, 1.2 * s)
	draw_string(font, plaque.position + Vector2(4 * s, fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)


static func _short(n: int) -> String:
	if n >= 10000:
		return "%dk" % (n / 1000)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)
