class_name BattleView
extends Node2D
## Draws battles where they happen. Far: a crossed-swords marker.
## Mid zoom: regiment blocks with counts. Close: individual stick-figure
## soldiers with bucket helms and tabards, flying arrows and the fallen.

const INK := Color(0.2, 0.14, 0.08)
const SKIN := Color(0.93, 0.80, 0.66)
const STEEL := Color(0.62, 0.64, 0.68)
const BLOCK_ZOOM := 1.4
const FIGURE_ZOOM := 3.2
const CROSS_CULTURES := ["latin", "frankish", "germanic", "norse", "slavic", "magyar", "baltic", "greek"]

var world: World
var zoom := 1.0
var view_rect := Rect2()
var font: Font
var selected_battle := -1
var selected_regiment := -1
var _t := 0.0
var _arrows: Array = []   # {from, to, t, life}


## Line width that never drops below about one screen pixel.
func _lw(w: float) -> float:
	return maxf(w, 0.9 / zoom)


func _process(delta: float) -> void:
	_t += delta
	var spd := 0.0 if world == null else world.speed
	for a in _arrows:
		a["t"] = float(a["t"]) + delta * maxf(spd, 0.25)
	_arrows = _arrows.filter(func(a: Dictionary) -> bool: return float(a["t"]) < float(a["life"]))
	if world != null and zoom >= FIGURE_ZOOM and spd > 0.0:
		_spawn_arrows(delta * spd)
	queue_redraw()


func _spawn_arrows(dt: float) -> void:
	for b: Battle in world.battles:
		if not _on_screen(b):
			continue
		for r: Regiment in b.regiments:
			if r.firing_at == -1 or not r.alive() or _arrows.size() > 160:
				continue
			var t := b.get_regiment(r.firing_at)
			if t == null:
				continue
			if randf() < r.men * 0.004 * dt * 10.0:
				var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1))
				_arrows.append({"from": r.pos + jitter * r.radius(), "to": t.pos + jitter.rotated(1.3) * t.radius(), "t": 0.0, "life": 0.7})


func _on_screen(b: Battle) -> bool:
	return view_rect.grow(b.radius).has_point(b.center)


func _draw() -> void:
	if world == null:
		return
	for b: Battle in world.battles:
		if not _on_screen(b):
			continue
		if zoom < BLOCK_ZOOM:
			_draw_marker(b)
		else:
			_draw_field(b)
			if zoom < FIGURE_ZOOM:
				_draw_blocks(b)
			else:
				_draw_fallen(b)
				_draw_figures(b)
				_draw_arrows()
				_draw_counts(b)


# --- Far: marker -----------------------------------------------------------------------------

func _draw_marker(b: Battle) -> void:
	var s := 1.0 / clampf(zoom, 0.3, 2.0)
	var c := b.center + Vector2(0, -40) * s
	var pulse := 1.0 + 0.12 * sin(_t * 5.0)
	draw_circle(c, 15.0 * s * pulse, Color(0.95, 0.88, 0.7, 0.9))
	draw_arc(c, 15.0 * s * pulse, 0, TAU, 24, Color(0.6, 0.12, 0.08), 2.0 * s)
	for dir: float in [1.0, -1.0]:
		var a := c + Vector2(-8 * dir, 8) * s
		var e := c + Vector2(8 * dir, -8) * s
		draw_line(a, e, INK, 2.5 * s)
		draw_line(a + Vector2(-3 * dir, -3) * s, a + Vector2(3 * dir, 3) * s, INK, 2.0 * s)
	# Strength bar: side colours in proportion to men.
	var m0 := float(b.side_men(0))
	var m1 := float(b.side_men(1))
	var w := 40.0 * s
	var split := w * m0 / maxf(m0 + m1, 1.0)
	var top := c + Vector2(-w * 0.5, 18.0 * s)
	draw_rect(Rect2(top, Vector2(split, 5.0 * s)), _side_color(b, 0))
	draw_rect(Rect2(top + Vector2(split, 0), Vector2(w - split, 5.0 * s)), _side_color(b, 1))
	draw_rect(Rect2(top, Vector2(w, 5.0 * s)), INK, false, 1.0 * s)


func _side_color(b: Battle, side: int) -> Color:
	var rid := b.side_realm[side]
	return world.realms[rid].color() if rid != -1 else Color(0.6, 0.6, 0.6)


# --- Terrain of the field ---------------------------------------------------------------------------

func _draw_field(b: Battle) -> void:
	# A brighter cartoon field under the battle.
	draw_circle(b.center, b.radius + 4.0, Color(0.55, 0.70, 0.38, 0.55))
	draw_circle(b.center, b.radius, Color(0.58, 0.74, 0.40, 0.75))
	for h in b.hills:
		var hp: Vector2 = h[0]
		var hr: float = h[1]
		draw_circle(hp, hr, Color(0.50, 0.62, 0.34, 0.8))
		draw_circle(hp + Vector2(-1, -1), hr * 0.65, Color(0.56, 0.69, 0.38, 0.9))
		draw_arc(hp, hr, 0, TAU, 28, Color(INK, 0.3), _lw(0.3))
	for s in b.river_segs:
		draw_line(s[0], s[1], Color(0.35, 0.55, 0.78), 3.5)
	if b.bridge != Vector2.INF:
		draw_circle(b.bridge, 2.6, Color(0.55, 0.40, 0.25))
		draw_arc(b.bridge, 2.6, 0, TAU, 12, INK, _lw(0.3))
	for f in b.forests:
		var fp: Vector2 = f[0]
		var fr: float = f[1]
		draw_circle(fp, fr, Color(0.30, 0.48, 0.25, 0.55))
		var n := int(fr * 1.4)
		for i in n:
			var ang := i * 2.4
			var d := fr * sqrt(float(i) / n) * 0.9
			var tp := fp + Vector2(cos(ang), sin(ang)) * d
			draw_line(tp, tp + Vector2(0, 1.2), Color(0.35, 0.25, 0.15), _lw(0.35))
			draw_circle(tp, 1.3, Color(0.22, 0.42 + 0.05 * (i % 3), 0.20))
	# Village: houses and a windmill around the settlement.
	if b.walls_side == -1 or zoom >= FIGURE_ZOOM:
		for i in b.village.size():
			var hp := b.village[i]
			if i == 0:
				_windmill(hp)
			else:
				_house(hp, i)
		var keep := b.center
		draw_rect(Rect2(keep + Vector2(-2.2, -3.0), Vector2(4.4, 4.0)), Color(0.72, 0.68, 0.62))
		draw_rect(Rect2(keep + Vector2(-2.2, -3.0), Vector2(4.4, 4.0)), INK, false, 0.3)
		draw_colored_polygon(PackedVector2Array([keep + Vector2(-2.6, -3), keep + Vector2(0, -5.2), keep + Vector2(2.6, -3)]), Color(0.45, 0.4, 0.5))
	if b.walls_side != -1:
		_draw_walls(b)
	# Stakes in front of dug-in regiments.
	for r: Regiment in b.regiments:
		if r.stakes and r.alive():
			var front := r.pos + r.facing * (r.dims().y * 0.5 + 1.2)
			var perp := r.facing.orthogonal()
			var w := r.dims().x * 0.5
			var x := -w
			while x <= w:
				var base := front + perp * x
				draw_line(base, base + r.facing * 1.6 + perp * 0.4, Color(0.45, 0.32, 0.18), _lw(0.35))
				x += 1.2


func _house(at: Vector2, i: int) -> void:
	var roof := Color(0.70, 0.32, 0.22) if i % 2 == 0 else Color(0.62, 0.42, 0.24)
	draw_rect(Rect2(at + Vector2(-1.2, -0.6), Vector2(2.4, 1.8)), Color(0.90, 0.84, 0.70))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-1.6, -0.6), at + Vector2(0, -2.0), at + Vector2(1.6, -0.6)]), roof)
	draw_rect(Rect2(at + Vector2(-1.2, -0.6), Vector2(2.4, 1.8)), INK, false, 0.2)


func _windmill(at: Vector2) -> void:
	draw_rect(Rect2(at + Vector2(-0.9, -2.5), Vector2(1.8, 3.0)), Color(0.88, 0.84, 0.74))
	var hub := at + Vector2(0, -2.6)
	for k in 4:
		var ang := _t * 1.5 + k * PI / 2.0
		draw_line(hub, hub + Vector2(cos(ang), sin(ang)) * 2.6, Color(0.5, 0.38, 0.25), _lw(0.4))
	draw_circle(hub, 0.4, INK)


func _draw_walls(b: Battle) -> void:
	var stone := Color(0.66, 0.64, 0.60)
	var gate_ang := b.gate_dir.angle()
	var gap := 0.35
	draw_arc(b.center, b.wall_r, gate_ang + gap, gate_ang + TAU - gap, 48, stone, 2.2)
	draw_arc(b.center, b.wall_r + 1.1, gate_ang + gap, gate_ang + TAU - gap, 48, INK, _lw(0.3))
	draw_arc(b.center, b.wall_r - 1.1, gate_ang + gap, gate_ang + TAU - gap, 48, INK, _lw(0.3))
	for k in 8:
		var ang := gate_ang + gap + (TAU - 2.0 * gap) * k / 7.0
		var tp := b.center + Vector2(cos(ang), sin(ang)) * b.wall_r
		draw_circle(tp, 1.8, stone)
		draw_arc(tp, 1.8, 0, TAU, 12, INK, _lw(0.3))
	var g := b.gate_point()
	if b.gate_hp > 0.0:
		var perp := b.gate_dir.orthogonal()
		var health := b.gate_hp / maxf(b.gate_max, 1.0)
		draw_line(g - perp * 2.4, g + perp * 2.4, Color(0.42, 0.28, 0.14).lerp(Color(0.2, 0.1, 0.05), 1.0 - health), 1.6)
	else:
		draw_circle(g, 1.2, Color(0.3, 0.3, 0.3, 0.6))


# --- Mid zoom: regiment blocks ----------------------------------------------------------------------

func _draw_blocks(b: Battle) -> void:
	for r: Regiment in b.regiments:
		if not r.alive():
			continue
		var d := r.dims()
		var col := _side_color(b, r.side)
		if r.routed:
			col = col.lerp(Color(0.8, 0.8, 0.8), 0.5)
		var pts := _block_points(r, d)
		draw_colored_polygon(pts, col)
		var outline := pts.duplicate()
		outline.append(pts[0])
		var sel := b.id == selected_battle and r.id == selected_regiment
		draw_polyline(outline, Color(1.0, 0.85, 0.2) if sel else col.darkened(0.5), 0.8 if sel else 0.4)
		# Front edge and a kind glyph.
		draw_line(pts[0], pts[1], INK, _lw(0.6))
		_kind_glyph(r)
		_morale_bar(r, d)
	_draw_counts(b)


func _block_points(r: Regiment, d: Vector2) -> PackedVector2Array:
	var f := r.facing
	var p := f.orthogonal()
	var hw := d.x * 0.5
	var hd := d.y * 0.5
	if r.formation == "wedge":
		return PackedVector2Array([r.pos + f * hd * 1.4 - p * 0.6, r.pos + f * hd * 1.4 + p * 0.6, r.pos - f * hd + p * hw, r.pos - f * hd - p * hw])
	return PackedVector2Array([r.pos + f * hd - p * hw, r.pos + f * hd + p * hw, r.pos - f * hd + p * hw, r.pos - f * hd - p * hw])


func _kind_glyph(r: Regiment) -> void:
	var c := r.pos
	match r.kind:
		"spear":
			draw_line(c + Vector2(-1.2, 1.2), c + Vector2(1.2, -1.2), INK, _lw(0.35))
		"sword":
			draw_line(c + Vector2(-1.0, 1.0), c + Vector2(1.0, -1.0), INK, _lw(0.35))
			draw_line(c + Vector2(-1.0, -1.0), c + Vector2(1.0, 1.0), INK, _lw(0.35))
		"archer", "horse_archer":
			draw_arc(c, 1.2, -PI * 0.5, PI * 0.5, 8, INK, _lw(0.35))
		"cavalry":
			draw_circle(c, 0.9, INK)
	if r.kind == "horse_archer":
		draw_circle(c + Vector2(-0.8, 0), 0.5, INK)


func _morale_bar(r: Regiment, d: Vector2) -> void:
	var top := r.pos + Vector2(-d.x * 0.5, -d.y * 0.5 - 1.6)
	var m := clampf(r.morale / 100.0, 0.0, 1.0)
	draw_rect(Rect2(top, Vector2(d.x, 0.5)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(top, Vector2(d.x * m, 0.5)), Color(0.3, 0.8, 0.3).lerp(Color(0.9, 0.2, 0.1), 1.0 - m))


func _draw_counts(b: Battle) -> void:
	var fs := maxi(int(11.0 / zoom * 4.0), 6)
	var text_scale := 0.25
	for r: Regiment in b.regiments:
		if not r.alive():
			continue
		var text := str(int(r.men))
		if r.routed:
			text += " (fleeing)"
		var at := r.pos + Vector2(0, r.dims().y * 0.5 + 2.4)
		draw_set_transform(at, 0.0, Vector2(text_scale, text_scale))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(1, 1, 1, 0.8))
		draw_string(font, Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Close: soldiers ----------------------------------------------------------------------------------

func _draw_figures(b: Battle) -> void:
	for r: Regiment in b.regiments:
		if not r.alive():
			continue
		var col := _side_color(b, r.side)
		var culture := world.realms[b.side_realm[r.side]].culture if b.side_realm[r.side] != -1 else "latin"
		var cross := CROSS_CULTURES.has(culture)
		var n := clampi(int(r.men / 12.0), 1, 36)
		var d := r.dims()
		var cols := maxi(1, int(ceil(sqrt(n * d.x / maxf(d.y, 0.1)))))
		var rows := int(ceil(float(n) / cols))
		var f := r.facing
		var p := f.orthogonal()
		var sel := b.id == selected_battle and r.id == selected_regiment
		if sel:
			draw_arc(r.pos, r.radius() + 0.8, 0, TAU, 24, Color(1.0, 0.85, 0.2, 0.9), _lw(0.4))
		for i in n:
			var cx := (float(i % cols) + 0.5) / cols - 0.5
			var cy := (float(i / cols) + 0.5) / rows - 0.5
			var jitter := Vector2(sin(i * 12.9898 + r.id) , cos(i * 78.233 + r.id)) * 0.35
			if r.routed:
				jitter *= 4.0
			var at := r.pos + p * (cx * d.x) - f * (cy * d.y) + jitter
			var phase := _t * 9.0 + i * 1.7
			var flip := 1.0 if f.x >= 0.0 else -1.0
			if r.is_cavalry():
				_rider(at, col, cross, r, phase, flip)
			else:
				_soldier(at, col, cross, r, phase, flip)


func _soldier(at: Vector2, col: Color, cross: bool, r: Regiment, phase: float, flip: float) -> void:
	var u := 0.55
	var swing := sin(phase) * 0.5 if r.moving else 0.0
	var hip := at + Vector2(0, -1.4) * u
	var neck := at + Vector2(0, -2.7) * u
	draw_line(hip, at + Vector2(-0.5 + swing, 0) * u, INK, _lw(0.12))
	draw_line(hip, at + Vector2(0.5 - swing, 0) * u, INK, _lw(0.12))
	# Tabard.
	var tab := Rect2(at + Vector2(-0.45, -2.6) * u, Vector2(0.9, 1.3) * u)
	draw_rect(tab, col)
	if cross:
		draw_line(at + Vector2(0, -2.5) * u, at + Vector2(0, -1.45) * u, Color(0.95, 0.93, 0.88), _lw(0.07))
		draw_line(at + Vector2(-0.35, -2.15) * u, at + Vector2(0.35, -2.15) * u, Color(0.95, 0.93, 0.88), _lw(0.07))
	draw_line(neck, hip, INK, _lw(0.1))
	# Head and bucket helm (archers go bare-headed under a hood).
	var head := at + Vector2(0, -3.1) * u
	draw_circle(head, 0.42 * u, SKIN)
	if r.kind == "archer":
		draw_arc(head, 0.46 * u, PI, TAU, 8, col.darkened(0.3), _lw(0.12))
	else:
		draw_rect(Rect2(head + Vector2(-0.45, -0.55) * u, Vector2(0.9, 0.8) * u), STEEL)
		draw_line(head + Vector2(-0.3, -0.05) * u, head + Vector2(0.3, -0.05) * u, INK, _lw(0.05))
	# Weapon.
	var hand := at + Vector2(0.45 * flip, -2.1) * u
	var fight := r.engaged and not r.routed
	var thrust := sin(phase * 1.6) * 0.6 if fight else 0.0
	match r.kind:
		"spear":
			draw_line(hand + Vector2(-0.3 * flip, 0.9) * u, hand + Vector2((0.6 + thrust) * flip, -2.3 + absf(thrust)) * u, Color(0.45, 0.32, 0.2), _lw(0.08))
			draw_circle(hand + Vector2((0.6 + thrust) * flip, -2.3 + absf(thrust)) * u, 0.12 * u, STEEL)
		"sword":
			var tip := hand + Vector2((0.6 + thrust) * flip, -1.2 + thrust) * u
			draw_line(hand, tip, STEEL, _lw(0.1))
			draw_circle(at + Vector2(-0.55 * flip, -1.9) * u, 0.45 * u, col.darkened(0.25))
		"archer":
			draw_arc(hand + Vector2(0.2 * flip, -0.2) * u, 0.8 * u, -PI * 0.5 if flip > 0 else PI * 0.5, PI * 0.5 if flip > 0 else PI * 1.5, 8, Color(0.45, 0.32, 0.2), _lw(0.08))
	if r.routed:
		draw_line(at + Vector2(-0.3, -3.9) * u, at + Vector2(0.3, -3.6) * u, Color(0.9, 0.9, 0.9), _lw(0.06))


func _rider(at: Vector2, col: Color, cross: bool, r: Regiment, phase: float, flip: float) -> void:
	var u := 0.55
	var gallop := sin(phase * 1.4) * 0.4 if r.moving else 0.0
	var horse := Color(0.42, 0.28, 0.18) if int(at.x * 7.0) % 3 != 0 else Color(0.25, 0.2, 0.17)
	var body := Rect2(at + Vector2(-1.3, -2.0) * u, Vector2(2.6, 0.9) * u)
	for leg in [-1.0, -0.6, 0.6, 1.0]:
		var lx: float = leg
		draw_line(at + Vector2(lx, -1.2) * u, at + Vector2(lx + gallop * signf(lx), 0) * u, horse.darkened(0.2), _lw(0.12))
	draw_rect(body, horse)
	draw_rect(Rect2(at + Vector2(-1.1, -1.95) * u, Vector2(2.2, 0.75) * u), col)  # caparison
	var head := at + Vector2(1.6 * flip, -2.7) * u
	draw_line(at + Vector2(1.1 * flip, -1.9) * u, head, horse, _lw(0.25))
	draw_circle(head, 0.3 * u, horse)
	# Rider.
	var seat := at + Vector2(0, -2.1) * u
	draw_rect(Rect2(seat + Vector2(-0.4, -1.2) * u, Vector2(0.8, 1.2) * u), col)
	if cross:
		draw_line(seat + Vector2(0, -1.1) * u, seat + Vector2(0, -0.2) * u, Color(0.95, 0.93, 0.88), _lw(0.07))
	var rh := seat + Vector2(0, -1.6) * u
	draw_circle(rh, 0.4 * u, SKIN)
	draw_rect(Rect2(rh + Vector2(-0.43, -0.5) * u, Vector2(0.86, 0.75) * u), STEEL)
	if r.kind == "cavalry":
		var tilt := 0.0 if r.engaged else -0.8
		draw_line(seat + Vector2(0.2 * flip, -0.7) * u, seat + Vector2(2.4 * flip, -0.9 + tilt) * u, Color(0.5, 0.36, 0.22), _lw(0.1))
	else:
		draw_arc(seat + Vector2(0.6 * flip, -0.8) * u, 0.7 * u, -PI * 0.5, PI * 0.5, 8, Color(0.45, 0.32, 0.2), _lw(0.08))


func _draw_fallen(b: Battle) -> void:
	var c := Color(0.35, 0.3, 0.27, 0.7)
	for i in b.fallen.size():
		var at := b.fallen[i]
		var ang := float(i) * 2.1
		var dir := Vector2(cos(ang), sin(ang)) * 0.6
		draw_line(at - dir, at + dir, c, _lw(0.18))
		draw_circle(at + dir, 0.17, c)


func _draw_arrows() -> void:
	for a in _arrows:
		var from: Vector2 = a["from"]
		var to: Vector2 = a["to"]
		var k := float(a["t"]) / float(a["life"])
		var pos := from.lerp(to, k) + Vector2(0, -sin(k * PI) * from.distance_to(to) * 0.3)
		var nk := minf(k + 0.05, 1.0)
		var next := from.lerp(to, nk) + Vector2(0, -sin(nk * PI) * from.distance_to(to) * 0.3)
		var dir := (next - pos).normalized()
		draw_line(pos - dir * 0.7, pos, Color(0.25, 0.18, 0.1), _lw(0.08))
