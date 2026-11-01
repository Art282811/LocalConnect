class_name TownView
extends Node2D
## Zoom in on a settlement and it opens up: streets of houses around a plaza,
## fields and a windmill, a keep, and everything that has been built there
## (church, market stalls, walls, barracks, smithy, tavern, granary, port,
## lumber camp, quarry, mine, watchtower, caravanserai), with townsfolk about.
## Drawn in world units, so it grows naturally as you zoom.

const SHOW_ZOOM := 2.0
const INK := Color(0.25, 0.18, 0.11)
const WALL := Color(0.92, 0.86, 0.72)
const STONE := Color(0.70, 0.67, 0.62)
const STONE_DARK := Color(0.55, 0.52, 0.48)
const ROOFS := [Color(0.72, 0.30, 0.20), Color(0.62, 0.40, 0.22), Color(0.55, 0.26, 0.20), Color(0.45, 0.42, 0.40)]
const WOODC := Color(0.50, 0.34, 0.20)

var world: World
var zoom := 1.0
var view_rect := Rect2()
var _t := 0.0
var _layouts := {}   # province id -> layout (positions), built once


func _process(delta: float) -> void:
	_t += delta
	if zoom >= SHOW_ZOOM:
		queue_redraw()
	elif _drawn:
		_drawn = false
		queue_redraw()


var _drawn := false


func _draw() -> void:
	if world == null or zoom < SHOW_ZOOM:
		return
	_drawn = true
	var alpha := clampf((zoom - SHOW_ZOOM) / 0.6, 0.0, 1.0)
	var view := view_rect.grow(60.0)
	for p: Province in world.provinces:
		if not view.has_point(p.center) or world.battle_at(p.id) != null:
			continue
		_draw_town(p, alpha)


func _layout(p: Province) -> Dictionary:
	if _layouts.has(p.id):
		return _layouts[p.id]
	var rng := RandomNumberGenerator.new()
	rng.seed = p.id * 7919 + 13
	var streets: Array = []
	var n := rng.randi_range(4, 6)
	var base := rng.randf() * TAU
	for i in n:
		streets.append(base + TAU * i / n + rng.randf_range(-0.25, 0.25))
	var houses: Array = []
	for i in 40:
		var ang: float = streets[i % n] + rng.randf_range(-0.22, 0.22)
		var dist := 7.0 + float(i / n) * 3.2 + rng.randf_range(-0.6, 0.6)
		houses.append([Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(2.2, 3.4), rng.randf_range(1.8, 2.6), rng.randi() % ROOFS.size()])
	var fields: Array = []
	for i in 10:
		var ang := rng.randf() * TAU
		fields.append([Vector2(cos(ang), sin(ang)) * rng.randf_range(24.0, 34.0), rng.randf_range(5.0, 8.0), rng.randf_range(3.0, 5.0), rng.randf() * PI])
	# Which way is the sea? Away from the land around us.
	var sea := Vector2.ZERO
	if p.coastal:
		var avg := Vector2.ZERO
		for nb: int in p.neighbors:
			avg += world.provinces[nb].center - p.center
		sea = (-avg).normalized() if avg.length() > 0.1 else Vector2.DOWN
	var spots: Array = []   # places on the edge for special buildings
	for i in 10:
		var ang := base + PI / n + TAU * i / 10.0
		spots.append(Vector2(cos(ang), sin(ang)) * rng.randf_range(18.0, 22.0))
	var lay := {"streets": streets, "houses": houses, "fields": fields, "sea": sea, "spots": spots, "seed": p.id}
	_layouts[p.id] = lay
	return lay


func _draw_town(p: Province, alpha: float) -> void:
	var lay := _layout(p)
	var c := p.center
	var owner: Realm = world.realms[p.owner] if p.owner != -1 else null
	var flag_col := owner.color() if owner != null else Color(0.6, 0.6, 0.6)
	var winter := world.season() == 3
	var lvl := p.level + (1 if owner != null and owner.capital == p.id else 0)
	# Fields and a windmill.
	var field_n := 2 + p.building_level("farm") * 2 + (2 if p.terrain == "plains" else 0)
	for i in mini(field_n, lay["fields"].size()):
		var f: Array = lay["fields"][i]
		_field(c + f[0], f[1], f[2], f[3], i, winter, alpha)
	if p.terrain == "forest" or p.building_level("lumber_camp") > 0:
		for i in 14:
			var ang := float(i) * 2.4 + p.id
			var at := c + Vector2(cos(ang), sin(ang)) * (26.0 + float(i % 4) * 3.0)
			_tree(at, alpha)
	var spots: Array = lay["spots"]
	var used := 0
	if p.terrain == "plains" or p.building_level("farm") > 0:
		_windmill(c + spots[used] * 1.15, alpha)
		used += 1
	# Roads out of town.
	var road_lvl := p.building_level("road")
	for ang in lay["streets"]:
		var dir := Vector2(cos(ang), sin(ang))
		var col := Color(0.62, 0.52, 0.38, alpha) if road_lvl < 2 else Color(0.6, 0.58, 0.55, alpha)
		draw_line(c + dir * 4.0, c + dir * (30.0 if road_lvl > 0 else 20.0), col, 1.4 if road_lvl > 0 else 0.9)
	# Plaza.
	draw_circle(c, 5.5, Color(0.80, 0.74, 0.62, alpha))
	# Houses: more as the town grows.
	var houses: Array = lay["houses"]
	var count := mini(6 + lvl * 7, houses.size())
	var placed: Array = []
	for i in count:
		placed.append(houses[i])
	placed.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).y < (b[0] as Vector2).y)
	for h in placed:
		_house(c + h[0], h[1], h[2], ROOFS[h[3]], alpha)
	# Keep in castles and capitals.
	if p.settlement == "castle" or (owner != null and owner.capital == p.id) or p.building_level("walls") >= 3:
		_keep(c + Vector2(0, -2.5), 7.0 + float(lvl), flag_col, alpha)
	# What has been built here.
	if p.building_level("church") > 0 or p.settlement == "monastery":
		_church(c + Vector2(5.5, 3.0), p.building_level("church") >= 3, alpha)
	if p.building_level("market") > 0:
		for i in 2 + p.building_level("market") * 2:
			var ang := TAU * i / (2 + p.building_level("market") * 2) + 0.3
			_stall(c + Vector2(cos(ang), sin(ang)) * 3.6, flag_col if i % 2 == 0 else Color(0.85, 0.75, 0.3), alpha)
	var specials := [["barracks", "_barracks"], ["blacksmith", "_smithy"], ["tavern", "_tavern"], ["granary", "_granary"],
		["quarry", "_quarry"], ["mine", "_mine"], ["watchtower", "_tower"], ["caravanserai", "_caravanserai"], ["lumber_camp", "_logs"]]
	for sp in specials:
		if p.building_level(sp[0]) > 0 and used < spots.size():
			call(sp[1], c + spots[used], flag_col, alpha)
			used += 1
	if p.building_level("port") > 0 or p.settlement == "port":
		_port(c, lay["sea"], flag_col, alpha)
	var walls := p.building_level("walls")
	if walls > 0:
		_walls(c, 13.0 + float(lvl) * 2.5, walls, alpha)
	# Something under construction?
	if p.build_id != "" and used < spots.size():
		_scaffold(c + spots[used], alpha)
	# Townsfolk going about their day.
	var folk := 3 + lvl * 2
	for i in folk:
		var ang: float = lay["streets"][i % (lay["streets"] as Array).size()]
		var dir := Vector2(cos(ang), sin(ang))
		var walk := fmod(_t * 0.6 + float(i) * 1.7, 2.0)
		var d := 4.0 + (walk if walk < 1.0 else 2.0 - walk) * 12.0
		var flip := 1.0 if (walk < 1.0) == (dir.x >= 0.0) else -1.0
		var coat: Color = [Color(0.55, 0.45, 0.3), Color(0.4, 0.5, 0.35), Color(0.6, 0.35, 0.3), Color(0.45, 0.45, 0.55)][i % 4]
		Figures.footman(self, c + dir * d + dir.orthogonal() * 1.2, 0.08, flip,
			{"surcoat": coat, "cross": false, "helm": "hood" if i % 2 == 0 else "bare", "weapon": "none", "moving": true, "phase": _t * 7.0 + i})


# --- Pieces ------------------------------------------------------------------------------------

func _house(at: Vector2, w: float, h: float, roof: Color, a: float) -> void:
	draw_rect(Rect2(at + Vector2(-w * 0.5, -h), Vector2(w, h)), Color(WALL, a))
	draw_rect(Rect2(at + Vector2(-w * 0.5, -h), Vector2(w * 0.18, h)), Color(WALL.darkened(0.12), a))
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-w * 0.62, -h), at + Vector2(0, -h - w * 0.55), at + Vector2(w * 0.62, -h)]), Color(roof, a))
	draw_rect(Rect2(at + Vector2(-w * 0.12, -h * 0.55), Vector2(w * 0.24, h * 0.55)), Color(0.4, 0.28, 0.18, a))
	draw_rect(Rect2(at + Vector2(w * 0.2, -h * 0.8), Vector2(w * 0.16, h * 0.18)), Color(0.35, 0.45, 0.55, a))


func _field(at: Vector2, w: float, h: float, rot: float, i: int, winter: bool, a: float) -> void:
	var col: Color = [Color(0.80, 0.72, 0.35), Color(0.55, 0.68, 0.35), Color(0.70, 0.60, 0.38)][i % 3]
	if winter:
		col = Color(0.88, 0.88, 0.86)
	var dx := Vector2(cos(rot), sin(rot)) * w * 0.5
	var dy := Vector2(-sin(rot), cos(rot)) * h * 0.5
	Figures.safe_polygon(self, PackedVector2Array([at - dx - dy, at + dx - dy, at + dx + dy, at - dx + dy]), Color(col, a * 0.9))
	for k in 5:
		var off := dy * (-0.8 + 0.4 * k)
		draw_line(at - dx * 0.9 + off, at + dx * 0.9 + off, Color(col.darkened(0.2), a), 0.12)


func _tree(at: Vector2, a: float) -> void:
	draw_line(at, at + Vector2(0, 1.2), Color(0.4, 0.28, 0.15, a), 0.4)
	draw_circle(at + Vector2(0, -0.6), 1.3, Color(0.28, 0.45, 0.24, a))
	draw_circle(at + Vector2(-0.4, -1.0), 0.6, Color(0.36, 0.55, 0.30, a))


func _windmill(at: Vector2, a: float) -> void:
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-1.4, 0), at + Vector2(-0.9, -5.0), at + Vector2(0.9, -5.0), at + Vector2(1.4, 0)]), Color(WALL, a))
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-1.2, -5.0), at + Vector2(0, -6.4), at + Vector2(1.2, -5.0)]), Color(ROOFS[1], a))
	var hub := at + Vector2(0, -5.2)
	for k in 4:
		var ang := _t * 1.2 + k * PI / 2.0
		var d := Vector2(cos(ang), sin(ang))
		draw_line(hub, hub + d * 4.6, Color(WOODC, a), 0.3)
		Figures.safe_polygon(self, PackedVector2Array([hub + d * 1.2, hub + d * 4.5, hub + d * 4.5 + d.orthogonal() * 1.0, hub + d * 1.2 + d.orthogonal() * 1.0]), Color(0.95, 0.93, 0.86, a))
	draw_circle(hub, 0.35, Color(INK, a))


func _keep(at: Vector2, size: float, flag: Color, a: float) -> void:
	var r := Rect2(at + Vector2(-size * 0.5, -size), Vector2(size, size))
	draw_rect(r, Color(STONE, a))
	draw_rect(Rect2(r.position, Vector2(size * 0.25, size)), Color(STONE_DARK, a))
	for i in 5:
		draw_rect(Rect2(at + Vector2(-size * 0.5 + i * size * 0.22, -size - size * 0.12), Vector2(size * 0.12, size * 0.12)), Color(STONE, a))
	draw_rect(Rect2(at + Vector2(-size * 0.1, -size * 0.35), Vector2(size * 0.2, size * 0.35)), Color(0.3, 0.22, 0.15, a))
	for i in 2:
		draw_rect(Rect2(at + Vector2(-size * 0.3 + i * size * 0.45, -size * 0.75), Vector2(size * 0.1, size * 0.16)), Color(0.15, 0.12, 0.1, a))
	var pole := at + Vector2(0, -size * 1.12)
	draw_line(pole, pole + Vector2(0, -size * 0.6), Color(INK, a), 0.25)
	var wave := sin(_t * 3.0) * 0.4
	Figures.safe_polygon(self, PackedVector2Array([pole + Vector2(0, -size * 0.6), pole + Vector2(size * 0.45, -size * 0.5 + wave), pole + Vector2(0, -size * 0.38)]), Color(flag, a))


func _church(at: Vector2, cathedral: bool, a: float) -> void:
	var w := 5.0 if cathedral else 3.6
	var h := 3.4 if cathedral else 2.6
	draw_rect(Rect2(at + Vector2(-w * 0.5, -h), Vector2(w, h)), Color(STONE.lightened(0.15), a))
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-w * 0.55, -h), at + Vector2(0, -h - 1.6), at + Vector2(w * 0.55, -h)]), Color(0.45, 0.4, 0.5, a))
	var tower := at + Vector2(w * 0.5 - 0.8, -h)
	draw_rect(Rect2(tower + Vector2(-0.8, -3.0 if cathedral else -2.2), Vector2(1.6, 3.0 if cathedral else 2.2)), Color(STONE.lightened(0.15), a))
	var top := tower + Vector2(0, -3.0 if cathedral else -2.2)
	Figures.safe_polygon(self, PackedVector2Array([top + Vector2(-1.0, 0), top + Vector2(0, -3.2 if cathedral else -2.4), top + Vector2(1.0, 0)]), Color(0.45, 0.4, 0.5, a))
	var cross := top + Vector2(0, -3.6 if cathedral else -2.8)
	draw_line(cross + Vector2(0, -0.8), cross + Vector2(0, 0.4), Color(0.85, 0.7, 0.25, a), 0.25)
	draw_line(cross + Vector2(-0.4, -0.4), cross + Vector2(0.4, -0.4), Color(0.85, 0.7, 0.25, a), 0.25)
	draw_circle(at + Vector2(0, -h * 0.6), 0.5, Color(0.6, 0.35, 0.5, a))   # rose window


func _stall(at: Vector2, awning: Color, a: float) -> void:
	draw_rect(Rect2(at + Vector2(-0.9, -0.8), Vector2(1.8, 0.8)), Color(WOODC, a))
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-1.1, -0.8), at + Vector2(-0.8, -1.8), at + Vector2(0.8, -1.8), at + Vector2(1.1, -0.8)]), Color(awning, a))
	draw_circle(at + Vector2(-0.4, -0.9), 0.25, Color(0.85, 0.35, 0.25, a))
	draw_circle(at + Vector2(0.3, -0.9), 0.25, Color(0.9, 0.75, 0.3, a))


func _walls(c: Vector2, r: float, level: int, a: float) -> void:
	if level == 1:
		# A wooden palisade.
		for i in 48:
			var ang := TAU * i / 48.0
			if absf(wrapf(ang - PI / 2.0, -PI, PI)) < 0.18:
				continue   # the gate
			var at := c + Vector2(cos(ang), sin(ang)) * r
			draw_line(at, at + Vector2(0, -1.6), Color(WOODC, a), 0.55)
		return
	var thick := 1.4 if level == 2 else 2.2
	var gate := PI / 2.0
	draw_arc(c, r, gate + 0.2, gate + TAU - 0.2, 64, Color(STONE, a), thick)
	draw_arc(c, r - thick * 0.5, gate + 0.2, gate + TAU - 0.2, 64, Color(STONE_DARK, a), 0.25)
	var towers := 4 if level == 2 else 6
	for i in towers:
		var ang := gate + 0.2 + (TAU - 0.4) * i / (towers - 1)
		var at := c + Vector2(cos(ang), sin(ang)) * r
		draw_rect(Rect2(at + Vector2(-1.3, -3.0), Vector2(2.6, 3.4)), Color(STONE, a))
		Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-1.5, -3.0), at + Vector2(0, -4.6), at + Vector2(1.5, -3.0)]), Color(ROOFS[0], a))
	var g := c + Vector2(0, r)
	draw_rect(Rect2(g + Vector2(-1.8, -3.2), Vector2(3.6, 3.6)), Color(STONE_DARK, a))
	draw_rect(Rect2(g + Vector2(-0.8, -1.8), Vector2(1.6, 2.2)), Color(0.3, 0.22, 0.15, a))


func _port(c: Vector2, sea: Vector2, flag: Color, a: float) -> void:
	if sea == Vector2.ZERO:
		sea = Vector2.DOWN
	var start := c + sea * 14.0
	var side := sea.orthogonal()
	draw_line(start, start + sea * 9.0, Color(WOODC, a), 1.2)
	draw_line(start + sea * 6.0 - side * 3.5, start + sea * 6.0 + side * 3.5, Color(WOODC, a), 1.0)
	for k in 2:
		var bob := sin(_t * 1.5 + k) * 0.3
		var at := start + sea * (8.0 + k * 3.0) + side * (4.5 if k == 0 else -4.5) + Vector2(0, bob)
		Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-2.6, 0), at + Vector2(2.6, 0), at + Vector2(1.8, 1.2), at + Vector2(-1.8, 1.2)]), Color(0.45, 0.3, 0.18, a))
		draw_line(at, at + Vector2(0, -4.2), Color(INK, a), 0.25)
		Figures.safe_polygon(self, PackedVector2Array([at + Vector2(0, -4.0), at + Vector2(2.2, -1.0), at + Vector2(0, -0.6)]), Color(0.96, 0.94, 0.86, a))
		Figures.safe_polygon(self, PackedVector2Array([at + Vector2(0, -4.2), at + Vector2(1.0, -3.8), at + Vector2(0, -3.4)]), Color(flag, a))


func _barracks(at: Vector2, flag: Color, a: float) -> void:
	draw_rect(Rect2(at + Vector2(-3.5, -2.2), Vector2(7.0, 2.2)), Color(WALL.darkened(0.08), a))
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-3.8, -2.2), at + Vector2(3.8, -2.2), at + Vector2(3.2, -3.4), at + Vector2(-3.2, -3.4)]), Color(ROOFS[2], a))
	draw_rect(Rect2(at + Vector2(-3.5, 0.3), Vector2(7.0, 3.0)), Color(0.72, 0.64, 0.48, a))   # drill yard
	draw_line(at + Vector2(3.6, -3.4), at + Vector2(3.6, -7.0), Color(INK, a), 0.25)
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(3.6, -7.0), at + Vector2(6.0, -6.3 + sin(_t * 3.0) * 0.3), at + Vector2(3.6, -5.6)]), Color(flag, a))
	for i in 3:
		Figures.footman(self, at + Vector2(-2.0 + i * 2.0, 2.8), 0.07, 1.0, {"surcoat": flag.lightened(0.5), "emblem": flag.darkened(0.3), "helm": "nasal", "weapon": "spear", "fighting": true, "phase": _t * 6.0 + i})


func _smithy(at: Vector2, _flag: Color, a: float) -> void:
	_house(at, 3.2, 2.2, ROOFS[3], a)
	draw_rect(Rect2(at + Vector2(0.6, -4.6), Vector2(0.7, 1.6)), Color(STONE_DARK, a))
	for k in 3:
		var t := fmod(_t * 0.5 + k * 0.33, 1.0)
		draw_circle(at + Vector2(1.0 + t * 1.5, -4.8 - t * 4.0), 0.5 + t * 0.8, Color(0.6, 0.6, 0.6, a * (1.0 - t) * 0.7))
	draw_circle(at + Vector2(-1.0, -0.6), 0.35, Color(1.0, 0.55, 0.15, a * (0.6 + 0.4 * sin(_t * 8.0))))


func _tavern(at: Vector2, _flag: Color, a: float) -> void:
	_house(at, 3.6, 2.6, ROOFS[1], a)
	draw_line(at + Vector2(1.8, -2.0), at + Vector2(3.0, -2.0), Color(WOODC, a), 0.25)
	draw_rect(Rect2(at + Vector2(2.4, -2.0), Vector2(1.0, 0.8)), Color(0.85, 0.6, 0.2, a))


func _granary(at: Vector2, _flag: Color, a: float) -> void:
	draw_rect(Rect2(at + Vector2(-2.6, -3.0), Vector2(5.2, 3.0)), Color(0.65, 0.25, 0.18, a))
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-2.9, -3.0), at + Vector2(0, -5.0), at + Vector2(2.9, -3.0)]), Color(0.45, 0.3, 0.2, a))
	draw_rect(Rect2(at + Vector2(-0.9, -2.0), Vector2(1.8, 2.0)), Color(0.35, 0.22, 0.14, a))


func _quarry(at: Vector2, _flag: Color, a: float) -> void:
	draw_circle(at, 3.4, Color(0.6, 0.58, 0.54, a))
	draw_circle(at + Vector2(0.4, 0.4), 2.2, Color(0.48, 0.46, 0.43, a))
	for k in 4:
		draw_rect(Rect2(at + Vector2(-2.5 + k * 1.4, -3.8 + (k % 2) * 0.6), Vector2(1.1, 0.8)), Color(STONE, a))


func _mine(at: Vector2, _flag: Color, a: float) -> void:
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-4.0, 0), at + Vector2(0, -4.5), at + Vector2(4.0, 0)]), Color(0.55, 0.5, 0.42, a))
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(-1.0, 0), at + Vector2(-1.0, -1.6), at + Vector2(0, -2.2), at + Vector2(1.0, -1.6), at + Vector2(1.0, 0)]), Color(0.12, 0.1, 0.09, a))
	draw_line(at + Vector2(-1.2, -1.7), at + Vector2(1.2, -1.7), Color(WOODC, a), 0.3)


func _tower(at: Vector2, flag: Color, a: float) -> void:
	draw_rect(Rect2(at + Vector2(-1.1, -7.0), Vector2(2.2, 7.0)), Color(STONE, a))
	draw_rect(Rect2(at + Vector2(-1.5, -8.2), Vector2(3.0, 1.2)), Color(STONE_DARK, a))
	draw_line(at + Vector2(0, -8.2), at + Vector2(0, -10.0), Color(INK, a), 0.2)
	Figures.safe_polygon(self, PackedVector2Array([at + Vector2(0, -10.0), at + Vector2(1.4, -9.6), at + Vector2(0, -9.2)]), Color(flag, a))


func _caravanserai(at: Vector2, _flag: Color, a: float) -> void:
	draw_rect(Rect2(at + Vector2(-4.0, -3.0), Vector2(8.0, 3.0)), Color(0.85, 0.75, 0.55, a))
	draw_rect(Rect2(at + Vector2(-2.6, -2.2), Vector2(5.2, 1.6)), Color(0.75, 0.64, 0.45, a))
	draw_rect(Rect2(at + Vector2(-0.7, -1.4), Vector2(1.4, 1.4)), Color(0.4, 0.28, 0.18, a))
	for k in 2:
		var cam := at + Vector2(-3.0 + k * 5.0, 2.0)
		draw_rect(Rect2(cam + Vector2(-1.0, -1.0), Vector2(2.0, 0.8)), Color(0.72, 0.55, 0.32, a))
		draw_circle(cam + Vector2(-0.2, -1.2), 0.45, Color(0.72, 0.55, 0.32, a))
		draw_line(cam + Vector2(1.0, -0.8), cam + Vector2(1.6, -2.0), Color(0.72, 0.55, 0.32, a), 0.4)


func _logs(at: Vector2, _flag: Color, a: float) -> void:
	for k in 3:
		for j in 3 - k:
			draw_circle(at + Vector2(-1.2 + j * 1.1 + k * 0.55, -k * 0.95), 0.55, Color(0.6, 0.42, 0.25, a))
			draw_circle(at + Vector2(-1.2 + j * 1.1 + k * 0.55, -k * 0.95), 0.3, Color(0.82, 0.68, 0.45, a))
	for k in 3:
		draw_rect(Rect2(at + Vector2(3.0 + k * 1.3, -0.6), Vector2(0.8, 0.6)), Color(0.5, 0.35, 0.2, a))


func _scaffold(at: Vector2, a: float) -> void:
	for x in [-2.5, 0.0, 2.5]:
		draw_line(at + Vector2(x, 0.5), at + Vector2(x, -5.0), Color(WOODC, a), 0.35)
	draw_line(at + Vector2(-3.0, -2.0), at + Vector2(3.0, -2.0), Color(WOODC, a), 0.35)
	draw_line(at + Vector2(-3.0, -4.5), at + Vector2(3.0, -4.5), Color(WOODC, a), 0.35)
	draw_line(at + Vector2(-2.5, 0.5), at + Vector2(2.5, -4.5), Color(WOODC, a), 0.25)
	draw_rect(Rect2(at + Vector2(-2.0, -1.5), Vector2(4.0, 2.0)), Color(STONE, a * 0.8))
