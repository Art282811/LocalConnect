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
	if zoom >= 0.45:
		_draw_trade(s)
	_draw_crusades(s)
	_draw_occupations(s)
	_draw_puffs(s)
	_draw_armies(s)


var _clock := 0.0


func _route_points(route: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if route["sea"]:
		var a := world.provinces[int(route["from"])].center
		var b := world.provinces[int(route["to"])].center
		var mid := (a + b) * 0.5 + (b - a).orthogonal() * 0.15
		for i in 17:
			var t := i / 16.0
			pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	else:
		for pid in route["path"]:
			pts.append(world.provinces[int(pid)].center)
	return pts


func _draw_trade(s: float) -> void:
	_clock += get_process_delta_time() * maxf(world.speed, 0.0)
	for route in world.diplomacy.routes:
		var pts := _route_points(route)
		if pts.size() < 2:
			continue
		var active := world.diplomacy.route_active(route)
		var col := Color(0.85, 0.65, 0.15, 0.85) if active else Color(0.4, 0.4, 0.4, 0.6)
		for i in pts.size() - 1:
			draw_dashed_line(pts[i], pts[i + 1], col, 2.5 * s, 9.0 * s)
		if active:
			# A cart or ship travelling the route.
			var total := pts.size() - 1
			var f := fmod(_clock * 0.15 + float(route["from"]) * 0.37, 1.0) * total
			var seg := mini(int(f), total - 1)
			var at := pts[seg].lerp(pts[seg + 1], f - seg)
			if route["sea"]:
				draw_colored_polygon(PackedVector2Array([at + Vector2(-7, 0) * s, at + Vector2(7, 0) * s, at + Vector2(4, 4) * s, at + Vector2(-4, 4) * s]), Color(0.45, 0.3, 0.18))
				draw_colored_polygon(PackedVector2Array([at, at + Vector2(0, -9) * s, at + Vector2(6, -1) * s]), Color(0.96, 0.93, 0.85))
			else:
				draw_rect(Rect2(at + Vector2(-5, -4) * s, Vector2(10, 6) * s), Color(0.6, 0.42, 0.22))
				draw_circle(at + Vector2(-3, 3) * s, 2.0 * s, INK)
				draw_circle(at + Vector2(3, 3) * s, 2.0 * s, INK)
		if zoom >= 0.9:
			var mid := pts[pts.size() / 2]
			var label := str(route["goods"])
			var fs := int(11.0 * s)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, mid + Vector2(-w * 0.5, -8 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(3 * s), PAPER)
			draw_string(font, mid + Vector2(-w * 0.5, -8 * s), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.5, 0.35, 0.05))


func _draw_crusades(s: float) -> void:
	for c in world.religion.crusades:
		var target := world.provinces[int((c["provinces"] as Array)[0])]
		var col := world.religion.color_of(str(c["faith"]))
		# Banner over the target.
		var top := target.center + Vector2(0, -60) * s
		draw_circle(top, 13.0 * s, Color(0.97, 0.94, 0.85))
		draw_arc(top, 13.0 * s, 0, TAU, 24, col.darkened(0.3), 3.0 * s)
		if world.religion.group_of(str(c["faith"])) == "christian":
			draw_line(top + Vector2(0, -8) * s, top + Vector2(0, 8) * s, Color(0.7, 0.1, 0.08), 3.5 * s)
			draw_line(top + Vector2(-6, -2) * s, top + Vector2(6, -2) * s, Color(0.7, 0.1, 0.08), 3.5 * s)
		else:
			draw_arc(top, 7.0 * s, PI * 0.35, PI * 1.65, 16, Color(0.15, 0.45, 0.25), 3.0 * s)
		if c["phase"] != "war":
			continue
		# Arrows from each crusader's capital.
		for rid in c["members"]:
			var r := world.realms[int(rid)]
			if not r.alive or r.capital == -1:
				continue
			var from := world.provinces[r.capital].center
			var to := target.center
			var mid := (from + to) * 0.5 + (to - from).orthogonal() * 0.12
			var prev := from
			for i in range(1, 13):
				var t := i / 12.0
				var pt := from.lerp(mid, t).lerp(mid.lerp(to, t), t)
				draw_line(prev, pt, Color(col, 0.75), 4.0 * s)
				prev = pt
			var dir := (to - from).normalized()
			draw_colored_polygon(PackedVector2Array([to, to - dir * 14.0 * s + dir.orthogonal() * 8.0 * s, to - dir * 14.0 * s - dir.orthogonal() * 8.0 * s]), Color(col, 0.85))


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
