class_name Battle
extends RefCounted
## A battle fought where the armies met, on that province's own terrain.
## Simulated as regiments with positions, facing and morale. The same numbers
## drive the blocks you see from afar and the soldiers you see up close.

const SECONDS_PER_DAY := 6.0   # battle seconds per in-game day
const STEP := 0.1
const MAX_SECONDS := 150.0
const DEPLOY := 20.0           # distance of each line from the centre
const KINDS := {
	"spear": {"speed": 2.4, "melee": 1.0, "armor": 1.0, "vs_cav": 2.0, "range": 0.0, "label": "Spearmen"},
	"sword": {"speed": 2.3, "melee": 1.6, "armor": 1.4, "vs_cav": 1.0, "range": 0.0, "label": "Men-at-arms"},
	"archer": {"speed": 2.6, "melee": 0.5, "armor": 0.7, "vs_cav": 0.6, "range": 24.0, "label": "Archers"},
	"cavalry": {"speed": 6.0, "melee": 1.4, "armor": 1.3, "vs_cav": 1.0, "range": 0.0, "label": "Knights"},
	"horse_archer": {"speed": 6.5, "melee": 0.6, "armor": 0.8, "vs_cav": 0.8, "range": 20.0, "label": "Horse archers"},
}
const STANCE_GIVE_UP := [0.6, 0.35, 0.0]   # cautious / balanced / aggressive

var id: int
var world: World
var province: int
var center := Vector2.ZERO
var radius: float = 44.0
var axis := Vector2.RIGHT      # from the centre toward the attacker's side
var time: float = 0.0
var regiments: Array[Regiment] = []
var side_realm: Array[int] = [-1, -1]
var armies: Array = [[], []]   # army ids per side
var general: Array[String] = ["", ""]
var trait_of: Array[String] = ["steady", "steady"]
var skill: Array[int] = [0, 0]
var stance: Array[int] = [1, 1]
var might: Array[float] = [1.0, 1.0]   # holy relics
var spirit: Array[float] = [0.0, 0.0]
var commanded: Array[bool] = [false, false]
var withdrawing: Array[bool] = [false, false]
var withdraw_time: Array[float] = [0.0, 0.0]
var attacker: int = 0          # side that marched in
var assault := false           # attacking a town's walls and garrison

var forests: Array = []        # [Vector2, radius]
var hills: Array = []          # [Vector2, radius]
var river_segs: Array = []     # [Vector2, Vector2]
var bridge := Vector2.INF
var village := PackedVector2Array()
var walls_side: int = -1
var wall_r: float = 13.0
var gate_dir := Vector2.RIGHT
var gate_hp: float = 0.0
var gate_max: float = 0.0

var fallen := PackedVector2Array()
var over := false
var winner: int = -1
var losses: Array[float] = [0.0, 0.0]
var _next_reg := 0
var _acc: float = 0.0
var _think_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


# --- Setup ----------------------------------------------------------------------------

func setup(w: World, battle_id: int, pid: int, side0: Array[Army], side1: Array[Army], attacking_side: int, is_assault: bool) -> void:
	world = w
	id = battle_id
	province = pid
	assault = is_assault
	attacker = attacking_side
	_rng.seed = hash([pid, w.day, battle_id])
	var p := w.provinces[pid]
	center = p.center
	radius = w.hex_radius * 0.85
	# Face the attacker toward where they came from.
	var lead: Army = side0[0] if attacking_side == 0 else side1[0]
	if lead.came_from != -1 and lead.came_from != pid:
		axis = (w.provinces[lead.came_from].center - center).normalized()
	else:
		var ang := _rng.randf() * TAU
		axis = Vector2(cos(ang), sin(ang))
	if attacking_side == 1:
		axis = -axis   # axis always points toward side 0
	side_realm[0] = side0[0].realm
	side_realm[1] = side1[0].realm if not side1.is_empty() else p.owner
	_build_terrain(p)
	var defender := 1 - attacking_side
	if p.owner == side_realm[defender] and (p.fort > 0 or assault):
		walls_side = defender
		gate_dir = axis if attacking_side == 0 else -axis
		gate_max = 60.0 + 70.0 * p.fort
		gate_hp = gate_max
	for a in side0:
		add_army(a, 0)
	for a in side1:
		add_army(a, 1)
	if assault:
		_add_garrison(p, defender)


func _build_terrain(p: Province) -> void:
	var counts := {"forest": 5, "plains": 1, "hills": 1, "mountains": 1, "marsh": 2, "desert": 0}
	for i in int(counts.get(p.terrain, 1)) + _rng.randi_range(0, 1):
		forests.append([_random_spot(14.0), _rng.randf_range(5.0, 9.0)])
	var hill_n := 3 if p.terrain == "hills" or p.terrain == "mountains" else _rng.randi_range(0, 1)
	for i in hill_n:
		hills.append([_random_spot(10.0), _rng.randf_range(8.0, 13.0)])
	for river in world.rivers:
		for i in river.size() - 1:
			var a: Vector2 = river[i]
			var b: Vector2 = river[i + 1]
			var closest := Geometry2D.get_closest_point_to_segment(center, a, b)
			if closest.distance_to(center) < radius:
				river_segs.append([a, b])
				if world.has_bridge(p) and (bridge == Vector2.INF or closest.distance_to(center) < bridge.distance_to(center)):
					bridge = closest
	var houses := 4 + p.level * 3
	for i in houses:
		var ang := TAU * i / houses + _rng.randf() * 0.4
		village.append(center + Vector2(cos(ang), sin(ang)) * _rng.randf_range(4.0, 10.0))


func _random_spot(min_from_center: float) -> Vector2:
	for attempt in 12:
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(min_from_center, radius * 0.9)
		var pt := center + Vector2(cos(ang), sin(ang)) * d
		# Keep the main approach lanes mostly open.
		if absf((pt - center).normalized().dot(axis)) < 0.85 or attempt > 8:
			return pt
	return center + axis.orthogonal() * radius * 0.6


func _composition(culture: String, quality: float) -> Dictionary:
	var c := {"spear": 0.45, "sword": 0.10, "archer": 0.25, "cavalry": 0.20, "horse_archer": 0.0}
	var maa := clampf((quality - 1.0) / 0.8, 0.0, 1.0)
	c["sword"] += 0.4 * maa
	c["spear"] -= 0.4 * maa
	match culture:
		"turkic", "arab", "berber":
			c["horse_archer"] = c["cavalry"] * 0.6
			c["cavalry"] *= 0.4
		"norse":
			c["sword"] += 0.1
			c["archer"] -= 0.1
		"frankish":
			c["cavalry"] += 0.05
			c["spear"] -= 0.05
	return c


func add_army(a: Army, side: int) -> void:
	(armies[side] as Array).append(a.id)
	a.battle = id
	if general[side] == "" or a.skill > skill[side]:
		general[side] = a.general
		trait_of[side] = a.general_trait
		skill[side] = a.skill
		stance[side] = a.stance
	var realm := world.realms[a.realm]
	might[side] = 1.0 + 0.1 * realm.has_relic_effect("battle")
	spirit[side] = 10.0 * realm.has_relic_effect("morale")
	var hero := world.dynasty.person(a.hero)
	if hero != null:
		spirit[side] += hero.leadership * 2.0
		if hero.id == realm.ruler:
			spirit[side] += 8.0   # the ruler in person is on the field
	var culture := realm.culture
	var regs := _make_regiments(float(a.troops), a.quality, _composition(culture, a.quality), a.id, side)
	var dug := a.order == "hold" and a.dug_in >= 4.0
	for r: Regiment in regs:
		r.stakes = dug and not r.is_cavalry()
	_arrange(regs, side)


func _add_garrison(p: Province, side: int) -> void:
	var men := clampf(p.pop * 0.03 + p.fort * 120.0, 60.0, 900.0)
	var regs := _make_regiments(men, 0.85, {"spear": 0.6, "archer": 0.4}, -1, side)
	_arrange(regs, side)


func _make_regiments(total: float, quality: float, comp: Dictionary, army_id: int, side: int) -> Array[Regiment]:
	var out: Array[Regiment] = []
	var size := clampf(total / 7.0, 80.0, 600.0)
	var placed := 0.0
	for kind in comp:
		var m := total * float(comp[kind])
		if m < 30.0:
			continue
		var n := maxi(1, int(round(m / size)))
		for i in n:
			var r := Regiment.new()
			r.id = _next_reg
			_next_reg += 1
			r.side = side
			r.army = army_id
			r.kind = kind
			r.men = m / n
			r.quality = quality
			r.base_morale = 62.0 + quality * 10.0 + skill[side] * 3.0 + spirit[side]
			r.morale = r.base_morale
			out.append(r)
			placed += r.men
	if out.is_empty():
		var r := Regiment.new()
		r.id = _next_reg
		_next_reg += 1
		r.side = side
		r.army = army_id
		r.men = total
		r.quality = quality
		r.base_morale = 70.0
		r.morale = 70.0
		out.append(r)
		placed = total
	out[0].men += total - placed
	for r: Regiment in out:
		r.start_men = r.men
		regiments.append(r)
	return out


## Spears and men-at-arms in front, archers behind, cavalry on the wings.
func _arrange(regs: Array[Regiment], side: int) -> void:
	var toward_enemy := -axis if side == 0 else axis
	var home := center - toward_enemy * DEPLOY
	if side == walls_side:
		home = center + toward_enemy * (wall_r - 4.0)
	var already := 0
	for r: Regiment in regiments:
		if r.side == side and not regs.has(r):
			already += 1
	if already > 0:
		home -= toward_enemy * 9.0   # reinforcements arrive behind the line
	var perp := toward_enemy.orthogonal()
	var front: Array[Regiment] = []
	var back: Array[Regiment] = []
	var wings: Array[Regiment] = []
	for r: Regiment in regs:
		r.facing = toward_enemy
		if r.kind == "cavalry":
			wings.append(r)
		elif r.is_ranged():
			back.append(r)
		else:
			front.append(r)
	var width := 0.0
	for r: Regiment in front:
		width += r.dims().x + 1.5
	var x := -width * 0.5
	for r: Regiment in front:
		var w := r.dims().x
		r.pos = home + perp * (x + w * 0.5)
		x += w + 1.5
	var bw := 0.0
	for r: Regiment in back:
		bw += r.dims().x + 1.5
	x = -bw * 0.5
	for r: Regiment in back:
		var w := r.dims().x
		r.pos = home - toward_enemy * 7.0 + perp * (x + w * 0.5)
		x += w + 1.5
	var edge := maxf(width, bw) * 0.5 + 3.0
	for i in wings.size():
		var r := wings[i]
		var side_sign := -1.0 if i % 2 == 0 else 1.0
		var row := float(i / 2)
		r.pos = home + perp * side_sign * (edge + r.dims().x * 0.5 + row * (r.dims().x + 1.5))
	for r: Regiment in regs:
		r.goal = r.pos
		var off := r.pos - center
		if off.length() > radius:
			r.pos = center + off.normalized() * radius
		r.hidden = _in_forest(r.pos)


# --- Terrain queries -----------------------------------------------------------------------

func _in_forest(pt: Vector2) -> bool:
	for f in forests:
		if pt.distance_to(f[0]) < float(f[1]):
			return true
	return false


func _on_hill(pt: Vector2) -> bool:
	for h in hills:
		if pt.distance_to(h[0]) < float(h[1]):
			return true
	return false


func _in_river(pt: Vector2) -> bool:
	if bridge != Vector2.INF and pt.distance_to(bridge) < 4.0:
		return false
	for s in river_segs:
		if Geometry2D.get_closest_point_to_segment(pt, s[0], s[1]).distance_to(pt) < 2.5:
			return true
	return false


func _in_village(pt: Vector2) -> bool:
	return pt.distance_to(center) < 11.0


func _inside_walls(pt: Vector2) -> bool:
	return walls_side != -1 and pt.distance_to(center) < wall_r


func gate_point() -> Vector2:
	return center + gate_dir * wall_r


func gate_open() -> bool:
	return walls_side == -1 or gate_hp <= 0.0


# --- Running the battle ----------------------------------------------------------------------

func update(dt: float) -> void:
	if over:
		return
	_acc += dt
	var steps := 0
	while _acc >= STEP and steps < 40 and not over:
		_acc -= STEP
		_step()
		steps += 1


func _step() -> void:
	time += STEP
	_think_timer -= STEP
	if _think_timer <= 0.0:
		_think_timer = 1.0
		_consider_withdrawal()
	for r: Regiment in regiments:
		if r.alive():
			_think(r)
	for r: Regiment in regiments:
		if r.alive():
			_move(r)
	_separate()
	_fight()
	_check_end()


func _enemies_of(r: Regiment) -> Array[Regiment]:
	var out: Array[Regiment] = []
	for o: Regiment in regiments:
		if o.side != r.side and o.alive():
			out.append(o)
	return out


func _visible(viewer: Regiment, target: Regiment) -> bool:
	if not target.hidden:
		return true
	return viewer.pos.distance_to(target.pos) < 14.0


func _nearest_enemy(r: Regiment, prefer: String = "") -> Regiment:
	var best: Regiment = null
	var best_d := INF
	for o: Regiment in _enemies_of(r):
		if o.routed or not _visible(r, o):
			continue
		var d := r.pos.distance_to(o.pos)
		if prefer != "" and o.kind == prefer:
			d *= 0.6
		if d < best_d:
			best_d = d
			best = o
	return best


func _reg(reg_id: int) -> Regiment:
	for r: Regiment in regiments:
		if r.id == reg_id:
			return r
	return null


func _think(r: Regiment) -> void:
	r.firing_at = -1
	if r.routed or withdrawing[r.side]:
		var away := (r.pos - center).normalized()
		var threat := _nearest_enemy(r)
		if threat != null:
			away = (away + (r.pos - threat.pos).normalized()).normalized()
		r.goal = r.pos + away * 10.0
		return
	var style := trait_of[r.side]
	if commanded[r.side]:
		_think_commanded(r)
		return
	var t := _nearest_enemy(r, "archer" if r.kind == "cavalry" else ("cavalry" if r.kind == "spear" else ""))
	r.target = t.id if t != null else -1
	if t == null:
		r.goal = r.pos
		return
	var d := r.pos.distance_to(t.pos)
	var is_attacker := r.side == attacker
	if r.is_ranged():
		var rng: float = _range_of(r)
		if d > rng * 0.9 and not (r.side == walls_side):
			r.goal = t.pos
		elif d < 8.0 and not t.is_ranged() and not r.engaged:
			r.goal = r.pos + (r.pos - t.pos).normalized() * 6.0
		else:
			r.goal = r.pos
		return
	if r.kind == "cavalry":
		if time < 5.0 and style != "reckless" and d > 15.0:
			r.goal = r.pos
			return
		var rear := t.pos - t.facing * (t.radius() + r.radius() + 4.0)
		if not r.engaged and r.pos.distance_to(rear) > 4.0 and d > t.radius() + r.radius() + 2.0 and t.formation != "square":
			# Swing round the side rather than through the front.
			var side_pt := t.pos + t.facing.orthogonal() * signf((r.pos - t.pos).dot(t.facing.orthogonal()) + 0.01) * (t.radius() + r.radius() + 6.0)
			r.goal = side_pt if (r.pos - t.pos).dot(t.facing) > 0.0 else rear
		else:
			r.goal = t.pos
		return
	# Infantry.
	if r.side == walls_side and not is_attacker:
		r.goal = r.pos if d > 9.0 else t.pos
		return
	if r.stakes and d > 7.0:
		r.goal = r.pos
		return
	if not is_attacker and style == "cautious" and d > 12.0:
		r.goal = r.pos
		return
	r.goal = t.pos


func _think_commanded(r: Regiment) -> void:
	if r.order_target != -1:
		var t := _reg(r.order_target)
		if t != null and t.alive():
			r.target = t.id
			var d := r.pos.distance_to(t.pos)
			r.goal = r.pos if r.is_ranged() and d < _range_of(r) * 0.9 else t.pos
			return
		r.order_target = -1
	if r.order_pos != Vector2.INF:
		r.goal = r.order_pos
		if r.pos.distance_to(r.order_pos) < 1.0:
			r.order_pos = Vector2.INF
		return
	var t := _nearest_enemy(r)
	r.target = t.id if t != null else -1
	r.goal = r.pos
	if t == null:
		return
	var d := r.pos.distance_to(t.pos)
	match r.stance:
		"charge":
			r.goal = t.pos
		"skirmish":
			if d < 9.0 and not r.engaged:
				r.goal = r.pos + (r.pos - t.pos).normalized() * 6.0
			elif r.is_ranged() and d > _range_of(r) * 0.9:
				r.goal = t.pos


func _range_of(r: Regiment) -> float:
	var rng: float = KINDS[r.kind]["range"]
	if _on_hill(r.pos):
		rng *= 1.3
	if r.side == walls_side and _inside_walls(r.pos):
		rng *= 1.25
	return rng


func _speed_of(r: Regiment) -> float:
	var s: float = KINDS[r.kind]["speed"]
	if _in_forest(r.pos):
		s *= 0.4 if r.is_cavalry() else 0.65
	if _in_river(r.pos):
		s *= 0.35
	if _on_hill(r.pos):
		s *= 0.85
	match r.formation:
		"square":
			s *= 0.6
		"wedge":
			s *= 1.1
	if r.routed or withdrawing[r.side]:
		s *= 1.2
	return s


func _move(r: Regiment) -> void:
	var to := r.goal - r.pos
	r.moving = false
	if r.engaged and not r.routed and not withdrawing[r.side]:
		var t := _reg(r.target)
		if t != null:
			r.facing = (t.pos - r.pos).normalized()
		return
	if to.length() < 0.4:
		if r.firing_at != -1:
			var t := _reg(r.firing_at)
			if t != null:
				r.facing = (t.pos - r.pos).normalized()
		return
	var step := minf(_speed_of(r) * STEP, to.length())
	var dir := to.normalized()
	var next := r.pos + dir * step
	# Walls: attackers only get in through a broken gate; defenders stay inside.
	if walls_side != -1 and not r.routed:
		if r.side != walls_side and next.distance_to(center) < wall_r + 1.5:
			var at_gate := (next - center).normalized().dot(gate_dir) > 0.93
			if not (gate_open() and at_gate):
				next = center + (next - center).normalized() * (wall_r + 1.5)
		elif r.side == walls_side and next.distance_to(center) > wall_r - 1.5:
			next = center + (next - center).normalized() * (wall_r - 1.5)
	r.pos = next
	r.moving = true
	r.travelled += step
	if not r.routed and not withdrawing[r.side]:
		r.facing = dir
	if r.hidden and not _in_forest(r.pos):
		r.hidden = false
	if (r.routed or withdrawing[r.side]) and r.pos.distance_to(center) > radius + 10.0:
		r.escaped = true


func _separate() -> void:
	for i in regiments.size():
		var a := regiments[i]
		if not a.alive():
			continue
		for j in range(i + 1, regiments.size()):
			var b := regiments[j]
			if not b.alive() or a.side != b.side:
				continue
			var min_d := (a.radius() + b.radius()) * 0.8
			var off := b.pos - a.pos
			var d := off.length()
			if d < min_d and d > 0.001:
				var push := off.normalized() * (min_d - d) * 0.5
				a.pos -= push
				b.pos += push


## 0 = hit from the front, 1 = side, 2 = rear.
func _flank(defender: Regiment, from: Vector2) -> int:
	if defender.formation == "square":
		return 0
	var dot := defender.facing.dot((from - defender.pos).normalized())
	if dot > 0.45:
		return 0
	if dot > -0.45:
		return 1
	return 2


func _fight() -> void:
	var damage := {}
	var shock := {}
	for r: Regiment in regiments:
		r.engaged = false
	# Melee.
	for i in regiments.size():
		var a := regiments[i]
		if not a.alive():
			continue
		for j in range(i + 1, regiments.size()):
			var b := regiments[j]
			if not b.alive() or a.side == b.side:
				continue
			if a.pos.distance_to(b.pos) > a.radius() + b.radius() + 0.6:
				continue
			if a.routed and b.routed:
				continue
			a.engaged = not a.routed
			b.engaged = not b.routed
			if not a.routed:
				_strike(a, b, damage, shock)
				a.target = b.id
			if not b.routed:
				_strike(b, a, damage, shock)
				b.target = a.id
	# Gate.
	if walls_side != -1 and gate_hp > 0.0:
		var ram_bonus := 3.0 if world.provinces[province].siege_progress >= 0.5 else 1.0
		for r: Regiment in regiments:
			if r.active() and r.side != walls_side and not r.is_ranged() and r.pos.distance_to(gate_point()) < r.radius() + 3.0:
				gate_hp -= r.men * 0.02 * ram_bonus * STEP
		if gate_hp <= 0.0:
			gate_hp = 0.0
	# Arrows.
	for r: Regiment in regiments:
		if not r.active() or r.engaged or not r.is_ranged() or r.ammo <= 0.0:
			continue
		var t: Regiment = null
		var best := _range_of(r)
		for o: Regiment in _enemies_of(r):
			if not _visible(r, o):
				continue
			var d := r.pos.distance_to(o.pos)
			if d < best:
				best = d
				t = o
		if t == null:
			continue
		var dmg := r.men * 0.0045 * sqrt(r.quality) * (1.0 + skill[r.side] * 0.04)
		if _in_forest(t.pos):
			dmg *= 0.5
		if _in_village(t.pos) and t.side != attacker:
			dmg *= 0.6
		if t.side == walls_side and _inside_walls(t.pos):
			dmg *= 0.5
		if t.formation == "square":
			dmg *= 1.3
		dmg /= sqrt(float(KINDS[t.kind]["armor"]))
		damage[t.id] = float(damage.get(t.id, 0.0)) + dmg * STEP
		r.ammo -= STEP
		r.firing_at = t.id
		r.hidden = false
	# Apply.
	for r: Regiment in regiments:
		if not r.alive():
			continue
		var took: float = minf(float(damage.get(r.id, 0.0)), r.men)
		if took > 0.0:
			r.men -= took
			losses[r.side] += took
			r.lost_since_corpse += took
			while r.lost_since_corpse >= 12.0 and fallen.size() < 500:
				r.lost_since_corpse -= 12.0
				fallen.append(r.pos + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * r.radius())
			r.morale -= took / maxf(r.men, 1.0) * 140.0
		r.morale -= float(shock.get(r.id, 0.0))
		if not r.engaged and took <= 0.0:
			r.morale = minf(r.morale + 1.5 * STEP, r.base_morale)
		if r.engaged:
			r.travelled = 0.0
		elif r.travelled > 10.0:
			r.charge_ready = true
		if not r.routed and r.morale < 12.0:
			r.routed = true
			_morale_ripple(r)
		elif r.routed and not r.rallied and not r.engaged and r.morale >= 35.0:
			r.routed = false
			r.rallied = true
		if r.routed and not r.engaged:
			r.morale += 2.0 * STEP


func _strike(att: Regiment, def: Regiment, damage: Dictionary, shock: Dictionary) -> void:
	var k: Dictionary = KINDS[att.kind]
	var flank := _flank(def, att.pos)
	var dmg := att.men * 0.010 * float(k["melee"]) * sqrt(att.quality) * (1.0 + skill[att.side] * 0.04) * might[att.side]
	if def.is_cavalry():
		dmg *= float(k["vs_cav"])
	if att.is_cavalry() and def.formation == "square":
		dmg *= 0.5
	dmg *= float([1.0, 1.5, 2.0][flank])
	if def.routed:
		dmg *= 1.5
	var armor: float = KINDS[def.kind]["armor"]
	if def.formation == "wedge":
		armor *= 0.85
	dmg /= armor
	if _in_village(def.pos) and def.side != attacker:
		dmg *= 0.75
	if _on_hill(def.pos):
		dmg *= 0.85
	if _in_river(def.pos):
		dmg *= 1.3
	if def.side == walls_side and _inside_walls(def.pos):
		dmg *= 0.6
	damage[def.id] = float(damage.get(def.id, 0.0)) + dmg * STEP
	var hit_shock: float = float([0.0, 3.0, 6.0][flank]) * STEP
	# Ambush from the trees.
	if att.hidden:
		hit_shock += 20.0
		att.hidden = false
	# The cavalry charge.
	if att.kind == "cavalry" and att.charge_ready:
		att.charge_ready = false
		var burst := att.men * 0.06 * 2.5 * (1.3 if att.formation == "wedge" else 1.0)
		var charge_shock := 15.0 * (1.0 + flank)
		if def.stakes and flank == 0:
			damage[att.id] = float(damage.get(att.id, 0.0)) + att.men * 0.15
			burst = 0.0
			charge_shock = 0.0
		elif def.kind == "spear" and flank == 0 and def.formation != "wedge":
			damage[att.id] = float(damage.get(att.id, 0.0)) + def.men * 0.04
			burst *= 0.5
		if def.formation == "square":
			burst *= 0.3
		if _in_forest(def.pos) or _in_village(def.pos):
			burst *= 0.3
		damage[def.id] = float(damage.get(def.id, 0.0)) + burst / armor
		hit_shock += charge_shock
	shock[def.id] = float(shock.get(def.id, 0.0)) + hit_shock


func _morale_ripple(broken: Regiment) -> void:
	for r: Regiment in regiments:
		if r.side == broken.side and r.active() and r.pos.distance_to(broken.pos) < 15.0:
			r.morale -= 8.0


func side_power(side: int) -> float:
	var p := 0.0
	for r: Regiment in regiments:
		if r.side == side and r.active():
			p += r.men * float(KINDS[r.kind]["melee"]) * sqrt(r.quality) * (r.morale / 70.0)
	return p


func side_men(side: int) -> int:
	var m := 0.0
	for r: Regiment in regiments:
		if r.side == side and r.alive():
			m += r.men
	return int(m)


func side_morale(side: int) -> int:
	var total := 0.0
	var men := 0.0
	for r: Regiment in regiments:
		if r.side == side and r.alive():
			total += r.morale * r.men
			men += r.men
	return int(total / maxf(men, 1.0))


func _consider_withdrawal() -> void:
	for side in 2:
		if commanded[side] or withdrawing[side] or time < 8.0:
			continue
		var mine := side_power(side)
		var theirs := maxf(side_power(1 - side), 1.0)
		if mine / theirs < float(STANCE_GIVE_UP[stance[side]]):
			order_withdraw(side)


func order_withdraw(side: int) -> void:
	if withdrawing[side]:
		return
	withdrawing[side] = true
	withdraw_time[side] = time


func _check_end() -> void:
	var standing: Array[bool] = [false, false]
	for r: Regiment in regiments:
		if r.active() and not withdrawing[r.side]:
			standing[r.side] = true
	for side in 2:
		if withdrawing[side] and time - withdraw_time[side] > 10.0:
			standing[side] = false
	if time > MAX_SECONDS:
		standing[attacker] = false   # the attack ran out of steam
	if standing[0] and standing[1]:
		return
	winner = 0 if standing[0] else 1
	if not standing[0] and not standing[1]:
		winner = 1 - attacker
	over = true


## Instant result from strength, terrain and luck (the Auto-resolve button).
func resolve_now() -> void:
	if over:
		return
	var power: Array[float] = [0.0, 0.0]
	for side in 2:
		power[side] = maxf(side_power(side), 1.0) * _rng.randf_range(0.8, 1.2)
	var defender := 1 - attacker
	power[defender] *= float(World.TERRAIN[world.provinces[province].terrain]["defense"])
	if walls_side != -1:
		power[walls_side] *= 1.0 + 0.35 * world.provinces[province].fort
	winner = 0 if power[0] >= power[1] else 1
	var ratio := minf(power[0], power[1]) / maxf(power[0], power[1])
	for r: Regiment in regiments:
		if not r.alive():
			continue
		var cut := 0.3 * ratio if r.side == winner else 0.35 + 0.4 * (1.0 - ratio)
		var dead := r.men * cut
		r.men -= dead
		losses[r.side] += dead
		if r.side != winner:
			r.routed = true
	over = true


## Men an army walks away with: the living, plus most of those who fled.
func survivors_of(army_id: int) -> int:
	var m := 0.0
	for r: Regiment in regiments:
		if r.army != army_id or r.men < 1.0:
			continue
		m += r.men * (0.85 if (r.routed or r.escaped) else 1.0)
	return int(m)


func army_side(army_id: int) -> int:
	for side in 2:
		if (armies[side] as Array).has(army_id):
			return side
	return -1


func regiment_at(pt: Vector2) -> Regiment:
	var best: Regiment = null
	var best_d := INF
	for r: Regiment in regiments:
		if not r.alive():
			continue
		var d := r.pos.distance_to(pt)
		if d < r.radius() + 1.5 and d < best_d:
			best_d = d
			best = r
	return best


func get_regiment(reg_id: int) -> Regiment:
	return _reg(reg_id)


func take_command(side: int, on: bool) -> void:
	commanded[side] = on
	for r: Regiment in regiments:
		if r.side == side:
			r.order_pos = Vector2.INF
			r.order_target = -1
			r.stance = "hold" if on else "charge"
