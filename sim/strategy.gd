class_name Strategy
extends RefCounted
## The AI's strategic mind. Each AI realm keeps a "mind": who threatens it,
## what it wants, and a war plan that moves through stages:
##   expand / build  ->  prepare (stage armies, secure flanks)  ->  war  ->  peace
## Decisions are reasoned from strength (including likely allies), the value of
## land, terrain and forts, timing and personality, not from dice rolls.

const WAR_THRESHOLD := 2.0
const MIN_PREP_DAYS := 25
const MAX_PREP_DAYS := 240
## Minimum chance of winning each personality needs before it plans a war.
const NERVE := {"ambitious": 0.52, "cruel": 0.55, "greedy": 0.6, "pious": 0.6, "cautious": 0.72}
## How strongly each personality is drawn to conquest.
const APPETITE := {"ambitious": 1.4, "cruel": 1.2, "greedy": 1.0, "pious": 0.9, "cautious": 0.6}

var world: World
var minds := {}       # realm id -> Dictionary
var _power := {}      # realm id -> float, refreshed monthly


func _init(w: World) -> void:
	world = w


func mind(rid: int) -> Dictionary:
	if not minds.has(rid):
		minds[rid] = {"posture": "expand", "target": -1, "objectives": [], "since": 0, "staging": -1,
			"threats": [], "top_threat": -1, "threat_score": 0.0, "warned": false, "asked": {}}
	return minds[rid]


func _ai_runs(r: Realm) -> bool:
	return r.alive and (not r.is_player or world.auto_rule)


# --- Strength -------------------------------------------------------------------------------------

## Field armies (quality and generals count) plus what could still be raised.
func power(rid: int) -> float:
	if _power.has(rid):
		return float(_power[rid])
	var r := world.realms[rid]
	var p := r.manpower * 0.5
	for a: Army in world.armies_of(rid):
		p += a.troops * a.quality * (1.0 + 0.06 * a.skill)
	for v in world.diplomacy.vassals_of(rid):
		for a: Army in world.armies_of(v):
			p += a.troops * a.quality * 0.5
	_power[rid] = p
	return p


func army_power(a: Army) -> float:
	return a.troops * a.quality * (1.0 + 0.08 * a.skill)


## How likely `ally` is to actually fight for `friend` against `enemy`.
func join_likelihood(ally: int, friend: int, enemy: int) -> float:
	if world.at_war(ally, enemy):
		return 1.0
	var o := world.diplomacy.opinion(ally, friend)
	var p := 0.25
	if o > 30.0:
		p = 0.8
	elif o > 0.0:
		p = 0.5
	if mind(ally)["top_threat"] == enemy:
		p = minf(p + 0.3, 1.0)
	return p


func _reach(helper: int, a: int, b: int) -> float:
	var h := world.realms[helper]
	if world.diplomacy.shares_border(h, world.realms[a]) or world.diplomacy.shares_border(h, world.realms[b]):
		return 1.0
	return 0.5


## Strength `target` can bring against `attacker`: itself, allies who would come,
## vassals, minus what is tied up fighting others.
func defender_side(target: int, attacker: int) -> float:
	var total := power(target)
	for ally in world.diplomacy.allies_of(target, ["alliance", "defensive"]):
		if ally != attacker:
			total += power(ally) * join_likelihood(ally, target, attacker) * _reach(ally, target, attacker)
	var distracted := 0.0
	for e in world.realms[target].enemies.keys():
		if int(e) != attacker:
			distracted += power(int(e))
	if distracted > 0.0:
		total *= 1.0 - minf(0.5, distracted / maxf(power(target), 1.0) * 0.3)
	var ruler := world.dynasty.ruler_of(world.realms[target])
	if ruler != null and ruler.age(world.day) < Dynasty.ADULT:
		total *= 0.85   # a child on the throne
	return total


func attacker_side(attacker: int, target: int) -> float:
	var total := power(attacker)
	for ally in world.diplomacy.allies_of(attacker, ["alliance"]):
		if ally != target:
			total += power(ally) * join_likelihood(ally, attacker, target) * _reach(ally, attacker, target)
	for e in world.realms[target].enemies.keys():
		var co := int(e)
		if co != attacker and world.diplomacy.opinion(co, attacker) >= 0.0:
			total += power(co) * 0.4   # someone else is already fighting them
	return total


func win_chance(attacker: int, target: int) -> float:
	var ratio := attacker_side(attacker, target) / maxf(defender_side(target, attacker), 1.0)
	return ratio * ratio / (1.0 + ratio * ratio)


# --- Assessment ----------------------------------------------------------------------------------------

func monthly() -> void:
	_power.clear()
	var powers: Array[float] = []
	for r: Realm in world.realms:
		if r.alive:
			powers.append(power(r.id))
	powers.sort()
	var median := powers[powers.size() / 2] if not powers.is_empty() else 1.0
	for r: Realm in world.realms:
		if _ai_runs(r):
			_assess(r, median)
	for r: Realm in world.realms:
		if _ai_runs(r):
			_plan_war(r)
	for r: Realm in world.realms:
		if r.alive and not r.is_player:
			_diplomacy(r)
	_peace_month()


func _assess(r: Realm, median: float) -> void:
	var m := mind(r.id)
	var scored: Array = []
	for other: Realm in world.realms:
		if not other.alive or other == r:
			continue
		var s := threat_score(r, other, median)
		if s > 0.05:
			scored.append([other.id, s])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))
	m["threats"] = scored
	m["top_threat"] = int(scored[0][0]) if not scored.is_empty() else -1
	m["threat_score"] = float(scored[0][1]) if not scored.is_empty() else 0.0


func threat_score(r: Realm, o: Realm, median: float) -> float:
	var dip := world.diplomacy
	if dip.has_treaty("alliance", r.id, o.id) or r.liege == o.id or o.liege == r.id:
		return 0.0
	var border := dip.shares_border(r, o)
	var proximity := 1.0 if border else 0.0
	if not border and r.capital != -1 and o.capital != -1:
		if world.provinces[r.capital].center.distance_to(world.provinces[o.capital].center) < 600.0:
			proximity = 0.35
	if proximity == 0.0:
		return 0.0
	var hostility := clampf((20.0 - dip.opinion(o.id, r.id)) / 60.0, 0.0, 2.0)
	if o.personality == "ambitious" or o.personality == "cruel":
		hostility += 0.4
	if world.at_war(o.id, r.id):
		hostility += 1.0
	if _massing_against(o, r):
		hostility += 0.6
	if dip.has_treaty("nap", r.id, o.id) or dip.has_treaty("defensive", r.id, o.id):
		hostility *= 0.5
	var ratio := defender_side(o.id, r.id) / maxf(power(r.id), 1.0)
	var score := ratio * hostility * proximity
	# Balance of power: a realm far stronger than the rest scares everyone.
	if power(o.id) > median * 3.0:
		score *= 1.5
	return score


## Are `o`'s armies standing on or next to `r`'s border?
func _massing_against(o: Realm, r: Realm) -> bool:
	var near := 0.0
	for a: Army in world.armies_of(o.id):
		var p := world.provinces[a.province]
		for nb: int in p.neighbors:
			if world.provinces[nb].owner == r.id:
				near += a.troops
				break
	return near > maxf(power(r.id) * 0.4, 400.0)


func _shares_threat(a: int, b: int, threat: int) -> bool:
	for t in mind(b)["threats"]:
		if int(t[0]) == threat and float(t[1]) > 0.5:
			return true
	return world.diplomacy.shares_border(world.realms[b], world.realms[threat])


# --- Choosing wars --------------------------------------------------------------------------------------

func province_value(r: Realm, p: Province) -> float:
	var v := 1.0 + p.pop / 1500.0 + 0.7 * p.building_level("market") + 0.7 * p.building_level("port")
	if p.holy_site != "" and p.sacred.has(r.faith):
		v += 4.0
	if p.culture == r.culture:
		v += 0.6
	if p.faith == r.faith:
		v += 0.6
	# Trade roads: secure our own, cut our rivals'.
	for route in world.trade.routes:
		if (route["path"] as Array).has(p.id) or (route["path"] as Array).has(float(p.id)):
			v += 2.0 if int(route["owner"]) == r.id else 1.0
	return v


func province_difficulty(p: Province) -> float:
	return 1.0 + 0.5 * p.fort + (float(World.TERRAIN[p.terrain]["defense"]) - 1.0) * 2.0


## Where to strike: the best-value, easiest provinces of `t` on our frontier,
## and the capital if the target is small enough to be finished off.
func objectives(r: Realm, t: Realm) -> Array[int]:
	var frontier := {}
	for pid: int in r.provinces:
		for nb: int in world.provinces[pid].neighbors:
			if world.provinces[nb].owner == t.id:
				frontier[nb] = true
	var scored: Array = []
	for pid in frontier:
		var p := world.provinces[int(pid)]
		scored.append([int(pid), province_value(r, p) / province_difficulty(p)])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))
	var out: Array[int] = []
	for s in scored:
		if out.size() >= 3:
			break
		out.append(int(s[0]))
	if t.provinces.size() <= 4 and t.capital != -1 and not out.has(t.capital) and not out.is_empty():
		out.append(t.capital)
	return out


## [desire, chance of winning, objectives]
func war_desire(r: Realm, t: Realm) -> Array:
	var none := [0.0, 0.0, []]
	var dip := world.diplomacy
	if not t.alive or t == r or t.liege == r.id or r.liege == t.id:
		return none
	if int(r.truces.get(t.id, -1)) > world.day or world.at_war(r.id, t.id):
		return none
	var pact := dip.has_treaty("nap", r.id, t.id) or dip.has_treaty("alliance", r.id, t.id) or dip.has_treaty("defensive", r.id, t.id)
	if pact and (r.personality == "pious" or r.personality == "cautious"):
		return none
	var objs := objectives(r, t)
	if objs.is_empty():
		return none
	var p := win_chance(r.id, t.id)
	if p < float(NERVE.get(r.personality, 0.6)):
		return [0.0, p, objs]
	var gain := 0.0
	for pid in objs:
		gain += province_value(r, world.provinces[pid])
	var exposed := 2.0
	for pid: int in r.provinces:
		for nb: int in world.provinces[pid].neighbors:
			if world.provinces[nb].owner == t.id:
				exposed += province_value(r, world.provinces[pid]) * 0.5
				break
	var desire := (p * gain - (1.0 - p) * exposed) * float(APPETITE.get(r.personality, 1.0))
	desire += maxf(0.0, -dip.opinion(r.id, t.id)) / 40.0
	var rel := world.religion
	if rel.group_of(r.faith) != rel.group_of(t.faith) and r.personality == "pious":
		desire += 1.5
	if t.excommunicated and t.faith == r.faith:
		desire += 1.0
	for c in world.dynasty.family_of(r):
		if c.claims.has(t.id):
			desire += 3.0
			break
	var hungry := true
	for pid: int in r.provinces:
		for nb: int in world.provinces[pid].neighbors:
			if world.provinces[nb].owner == -1:
				hungry = false
	desire *= 1.3 if hungry else 0.6
	if pact:
		desire -= 3.0   # breaking an oath costs standing with everyone
	return [desire, p, objs]


func _in_crisis(r: Realm) -> bool:
	if r.starving or r.broke:
		return true
	var mood := 0.0
	for pid: int in r.provinces:
		mood += world.provinces[pid].happiness
	if not r.provinces.is_empty() and mood / r.provinces.size() < 30.0:
		return true
	for f in r.nobles:
		if f["faction"]:
			return true
	return false


func _plan_war(r: Realm) -> void:
	var m := mind(r.id)
	if not r.enemies.is_empty():
		m["posture"] = "war"
		return
	if m["posture"] == "war":
		m["posture"] = "recover"
		m["since"] = world.day
		m["target"] = -1
	if r.liege != -1:
		_consider_independence(r)
		return
	if _in_crisis(r):
		m["posture"] = "consolidate"
		m["target"] = -1
		return
	if m["posture"] == "recover" and world.day - int(m["since"]) < 180:
		return
	if m["posture"] == "prepare":
		var t := world.realms[int(m["target"])]
		var check := war_desire(r, t)
		if float(check[0]) < WAR_THRESHOLD * 0.6 or world.day - int(m["since"]) > MAX_PREP_DAYS:
			m["posture"] = "expand"
			m["target"] = -1
			return
		m["objectives"] = check[2]
		if _ready(r, m, float(check[1])):
			world.declare_war(r.id, t.id)
			m["posture"] = "war"
		return
	var best: Realm = null
	var best_d: Array = []
	for oid in world.neighbor_realms(r):
		var o := world.realms[oid]
		var d := war_desire(r, o)
		if best == null or float(d[0]) > float(best_d[0]):
			best = o
			best_d = d
	if best != null and float(best_d[0]) >= WAR_THRESHOLD:
		# Overwhelmingly stronger? Demand submission first; fight if refused.
		if float(best_d[1]) >= 0.9 and (r.personality == "greedy" or r.personality == "ambitious" or r.personality == "cruel"):
			var asked: Dictionary = m["asked"]
			if world.day - int(asked.get(best.id, -9999)) > 720:
				asked[best.id] = world.day
				var kind := "vassal" if best.provinces.size() <= 3 and r.personality == "ambitious" else "tribute"
				var result := world.diplomacy.propose(kind, r.id, best.id)
				if result.contains("agrees") or best.is_player:
					return
		m["posture"] = "prepare"
		m["target"] = best.id
		m["objectives"] = best_d[2]
		m["since"] = world.day
		m["warned"] = false
		m["staging"] = _staging_point(r, best_d[2])
		return
	m["posture"] = "expand" if _has_free_land(r) else "build"


func _has_free_land(r: Realm) -> bool:
	for pid: int in r.provinces:
		for nb: int in world.provinces[pid].neighbors:
			if world.provinces[nb].owner == -1:
				return true
	return false


## Our province next to the first objective, preferring a strong fort.
func _staging_point(r: Realm, objs: Array) -> int:
	if objs.is_empty():
		return r.capital
	var first := int(objs[0])
	var best := -1
	var best_s := -INF
	for nb: int in world.provinces[first].neighbors:
		var p := world.provinces[nb]
		if p.owner == r.id:
			var s := p.fort * 2.0 + float(World.TERRAIN[p.terrain]["defense"])
			if s > best_s:
				best_s = s
				best = nb
	return best if best != -1 else r.capital


func _ready(r: Realm, m: Dictionary, chance: float) -> bool:
	if world.day - int(m["since"]) < MIN_PREP_DAYS:
		return false
	var season := world.season()
	if season == 3 or (season == 2 and world.day % World.DAYS_PER_SEASON > World.DAYS_PER_SEASON / 2):
		return false   # no campaigns into winter
	if chance < float(NERVE.get(r.personality, 0.6)):
		return false
	var mine := world.armies_of(r.id)
	if mine.is_empty():
		return false
	var main := _strongest(mine)
	var staging := int(m["staging"])
	if main.province != staging and not world.provinces[staging].neighbors.has(main.province):
		return false
	return r.manpower >= world.economy.manpower_cap(r) * 0.4 or float(r.res["gold"]) >= 80.0


func _consider_independence(r: Realm) -> void:
	var liege := world.realms[r.liege]
	if world.diplomacy.opinion(r.id, liege.id) < -10.0 and win_chance(r.id, liege.id) >= 0.6:
		world.declare_war(r.id, liege.id)


# --- Commanding armies (every few days) -----------------------------------------------------------------

func _strongest(list: Array[Army]) -> Army:
	var best: Army = null
	for a in list:
		if best == null or army_power(a) > army_power(best):
			best = a
	return best


func _move(a: Army, pid: int, task: String) -> bool:
	if a.province == pid:
		return true
	var path := world.find_path(a.province, a.realm, 300, world._is_target.bind(pid))
	if path.is_empty():
		return false
	a.path = path
	a.progress = 0.0
	a.task = task
	a.order = ""
	return true


func command_armies(r: Realm) -> void:
	if not r.enemies.is_empty() and not r.is_player:
		for a: Army in world.armies_of(r.id):
			if a.order == "patrol":
				a.order = ""
				a.manual = false   # war comes first; caravans can wait
	var mine: Array[Army] = []
	for a: Army in world.armies_of(r.id):
		if a.battle == -1 and not a.manual and a.path.is_empty():
			mine.append(a)
	var all_mine := world.armies_of(r.id)
	if mine.is_empty() or all_mine.is_empty():
		return
	var main := _strongest(all_mine)
	var m := mind(r.id)
	if not r.enemies.is_empty():
		_command_war(r, m, mine, main)
		return
	if m["posture"] == "prepare":
		var staging := int(m["staging"])
		for a in mine:
			if a == main or a.troops > main.troops * 0.6:
				if a.province == staging:
					a.task = "hold"
				else:
					_move(a, staging, "muster")
			elif not _busy(a):
				world.join_army(a.id, main.id)
		var t := world.realms[int(m["target"])]
		if t.is_player and not m["warned"] and main.province == staging:
			m["warned"] = true
			world.post_news("Scouts report that the %s is massing troops near %s!" % [r.full_name(), world.provinces[staging].name], 2)
		return
	# Peace: keep a guard toward the main threat, send the rest to claim land.
	var guard: Army = null
	if int(m["top_threat"]) != -1 and float(m["threat_score"]) >= 1.0 and all_mine.size() >= 2:
		guard = main
		var post := _guard_post(r, int(m["top_threat"]))
		if guard in mine and post != -1 and guard.province != post:
			_move(guard, post, "guard")
	# Guard our most threatened trade road with a spare army.
	if not r.is_player and all_mine.size() >= 2:
		var worst: Dictionary = {}
		for route in world.trade.routes:
			if int(route["owner"]) == r.id and world.trade.risk(route) >= 0.2 and (worst.is_empty() or world.trade.risk(route) > world.trade.risk(worst)):
				worst = route
		var patrolling := false
		for a: Army in all_mine:
			if a.order == "patrol":
				patrolling = true
		if not worst.is_empty() and not patrolling:
			for a in mine:
				if a != guard and a != main and not _busy(a):
					world.trade.assign_patrol(a, int(worst["id"]))
					break
	for a in mine:
		if a == guard or _busy(a) or a.order == "patrol":
			continue
		if a.order == "hold":
			a.order = ""   # stop digging in; peace has work to do
		world._assign_task(r, a)


func _busy(a: Army) -> bool:
	if a.task != "claim" and a.task != "siege":
		return false
	var p := world.provinces[a.province]
	return p.owner == -1 or world.at_war(a.realm, p.owner)


## Our best-fortified province facing `threat`.
func _guard_post(r: Realm, threat: int) -> int:
	var best := -1
	var best_s := -INF
	for pid: int in r.provinces:
		var p := world.provinces[pid]
		var faces := false
		for nb: int in p.neighbors:
			if world.provinces[nb].owner == threat:
				faces = true
				break
		if not faces:
			continue
		var s := p.fort * 2.0 + float(World.TERRAIN[p.terrain]["defense"]) + (1.0 if pid == r.capital else 0.0)
		if s > best_s:
			best_s = s
			best = pid
	return best


func _enemy_armies(r: Realm) -> Array[Army]:
	var out: Array[Army] = []
	for a: Army in world.armies:
		if not a.dead and world.at_war(r.id, a.realm):
			out.append(a)
	return out


## Enemy strength standing on `pid` or next to it.
func _danger_at(r: Realm, pid: int, enemies: Array[Army]) -> float:
	var total := 0.0
	var p := world.provinces[pid]
	for e in enemies:
		if e.province == pid or p.neighbors.has(e.province):
			var s := army_power(e)
			if world.provinces[e.province].owner == e.realm:
				s *= float(World.TERRAIN[world.provinces[e.province].terrain]["defense"])
			total += s
	return total


func _command_war(r: Realm, m: Dictionary, mine: Array[Army], main: Army) -> void:
	var enemies := _enemy_armies(r)
	var invaders: Array[Army] = []
	for e in enemies:
		if world.provinces[e.province].owner == r.id:
			invaders.append(e)
	var objs: Array = m.get("objectives", [])
	var targets := _war_objectives(r, objs)
	for a in mine:
		var mine_power := army_power(a)
		# Keep a siege going unless something bigger is coming.
		if _busy(a) and _danger_at(r, a.province, enemies) < mine_power * 0.9:
			_maybe_assault(a)
			continue
		# 1. Throw out invaders we can beat.
		var hunt: Army = null
		for inv in invaders:
			var theirs := army_power(inv)
			if mine_power >= theirs * 1.15 and (hunt == null or a.province == inv.province or theirs > army_power(hunt)):
				hunt = inv
		if hunt != null:
			_move(a, hunt.province, "defend")
			continue
		# 2. Outmatched by an invader: fall back behind walls and dig in.
		if a == main and not invaders.is_empty():
			var fort := _fallback_fort(r, a)
			if fort != -1 and fort != a.province:
				_move(a, fort, "retreat")
				continue
			world.hold_army(a.id)
			a.manual = false
			continue
		# 3. Small detachments join the main army.
		if a != main and a.troops < main.troops * 0.45 and main.battle == -1:
			world.join_army(a.id, main.id)
			continue
		# 4. March on an objective, unless a stronger army guards it.
		var went := false
		for pid in targets:
			if _danger_at(r, pid, enemies) > mine_power * 0.9:
				continue
			if _move(a, pid, "attack"):
				went = true
				break
		if not went and a.province != int(m.get("staging", r.capital)) and world.provinces[a.province].owner != r.id:
			_move(a, int(m.get("staging", r.capital)), "regroup")


## Objectives still to take; once they are ours, the next best enemy land nearby.
func _war_objectives(r: Realm, objs: Array) -> Array[int]:
	var out: Array[int] = []
	for pid in objs:
		var o := world.provinces[int(pid)].owner
		if o != r.id and o != -1 and world.at_war(r.id, o):
			out.append(int(pid))
	if not out.is_empty():
		return out
	for e in r.enemies.keys():
		for pid in objectives(r, world.realms[int(e)]):
			if not out.has(pid):
				out.append(pid)
	return out


func _fallback_fort(r: Realm, a: Army) -> int:
	var best := -1
	var best_s := -INF
	for pid: int in r.provinces:
		var p := world.provinces[pid]
		var dist := world.provinces[a.province].center.distance_to(p.center) / 150.0
		var s := p.fort * 3.0 + float(World.TERRAIN[p.terrain]["defense"]) * 2.0 - dist
		if s > best_s:
			best_s = s
			best = pid
	return best


func _maybe_assault(a: Army) -> void:
	var p := world.provinces[a.province]
	if p.owner == -1 or a.task != "siege":
		return
	var g := world.garrison_size(p) * (1.0 + 0.35 * p.fort)
	var bold := a.general_trait == "reckless" or a.stance == 2
	if (bold and p.siege_progress > 0.3 and army_power(a) > g * 2.5) or (p.siege_progress > 0.6 and army_power(a) > g * 1.8):
		world.start_assault(a.id)


# --- Peace -----------------------------------------------------------------------------------------------

func _peace_month() -> void:
	for w in world.wars.duplicate():
		var x := int(w["a"])
		var y := int(w["b"])
		if not world.at_war(x, y):
			continue
		var rx := world.realms[x]
		var ry := world.realms[y]
		var x_ai := _ai_runs(rx)
		var y_ai := _ai_runs(ry)
		if x_ai and y_ai:
			if (wants_peace(x, y, w) and (wants_peace(y, x, w) or losing(y, x, w))) \
					or (wants_peace(y, x, w) and losing(x, y, w)):
				world.make_peace(x, y)
		elif x_ai != y_ai:
			var ai := x if x_ai else y
			var human := y if x_ai else x
			if wants_peace(ai, human, w) and world.diplomacy.cooldown_left(ai, human, "peace") == 0:
				world.diplomacy._cooldown["%d:%d:peace" % [ai, human]] = world.day + 60
				world.diplomacy._offer("peace", ai, "%s sends envoys seeking peace." % world.realms[ai].full_name(), {})


func wants_peace(rid: int, enemy: int, w: Dictionary) -> bool:
	var r := world.realms[rid]
	var taken: Dictionary = w["taken"]
	var gained := int(taken.get(rid, 0))
	var lost := int(taken.get(enemy, 0))
	var length := world.day - int(w["start"])
	if length < 60:
		return false
	var ratio := power(rid) / maxf(power(enemy), 1.0)
	if world.armies_of(rid).is_empty():
		return true
	var objs: Array = mind(rid).get("objectives", [])
	if not objs.is_empty() and int(w["a"]) == rid:
		var all_ours := true
		for pid in objs:
			if world.provinces[int(pid)].owner != rid:
				all_ours = false
		if all_ours and not (ratio > 3.0 and r.personality == "ambitious"):
			return true
	if lost > gained and ratio < 0.9:
		return true
	if length > 540 and ratio < 1.5:
		return true
	if (r.starving or r.broke) and gained <= lost:
		return true
	return false


func losing(rid: int, enemy: int, w: Dictionary) -> bool:
	var taken: Dictionary = w["taken"]
	return int(taken.get(enemy, 0)) > int(taken.get(rid, 0)) or power(rid) < power(enemy) * 0.7


## The player asks for peace.
func accepts_peace(ai: int, human: int, w: Dictionary) -> bool:
	return wants_peace(ai, human, w) or losing(ai, human, w)


# --- Diplomacy ---------------------------------------------------------------------------------------------

func _diplomacy(r: Realm) -> void:
	var dip := world.diplomacy
	var m := mind(r.id)
	var target := int(m["target"])
	var threat := int(m["top_threat"])
	# 1. Drop allies who have become a danger or a target.
	for ally in dip.allies_of(r.id, ["alliance", "defensive"]):
		if ally == target or ally == threat or dip.opinion(r.id, ally) < -20.0:
			var kind := "alliance" if dip.has_treaty("alliance", r.id, ally) else "defensive"
			dip.break_treaty(kind, r.id, ally)
			world.post_news("%s ends its %s with %s." % [r.name, kind if kind == "alliance" else "defensive pact", world.realms[ally].name], 2 if world.realms[ally].is_player else 0)
			return
	# 2. Preparing a war: secure the flanks, court the target's enemies.
	if m["posture"] == "prepare" and target != -1:
		for t in m["threats"]:
			var other := int(t[0])
			if other != target and float(t[1]) > 0.4 and not dip.has_treaty("nap", r.id, other) and _try(r, "nap", other):
				return
		for other: Realm in world.realms:
			if other.alive and other.id != target and other != r and dip.opinion(other.id, target) < -20.0 \
					and not dip.has_treaty("alliance", r.id, other.id) and dip.shares_border(other, world.realms[target]) \
					and _try(r, "alliance", other.id):
				return
	# 3. Threatened: find partners who fear the same realm.
	if threat != -1 and float(m["threat_score"]) >= 0.8:
		var best := -1
		var best_score := -INF
		for other: Realm in world.realms:
			if not other.alive or other == r or other.id == threat or dip.has_treaty("alliance", r.id, other.id):
				continue
			if dip.allies_of(threat, ["alliance", "defensive"]).has(other.id):
				continue
			if not _shares_threat(r.id, other.id, threat):
				continue
			var s := dip.opinion(other.id, r.id) + power(other.id) / 100.0
			if s > best_score:
				best_score = s
				best = other.id
		if best != -1:
			var kind := "alliance" if dip.opinion(best, r.id) >= 20.0 else "defensive"
			if not dip.has_treaty(kind, r.id, best) and _try(r, kind, best):
				if world.rng.randf() < 0.5:
					world.post_news("Fearing %s, %s and %s draw closer." % [world.realms[threat].name, r.name, world.realms[best].name], 1)
				return
		# Appease a dangerous neighbour we cannot hope to fight.
		if (r.personality == "cautious" or win_chance(r.id, threat) < 0.25) and float(r.res["gold"]) > 150.0 \
				and dip.opinion(threat, r.id) < 0.0 and _try(r, "gift", threat):
			return
		if not dip.has_treaty("nap", r.id, threat) and _try(r, "nap", threat):
			return
	# 4. Trade with friendly neighbours.
	if dip.has_market(r):
		for oid in world.neighbor_realms(r):
			if oid != target and oid != threat and dip.has_market(world.realms[oid]) and not dip.has_treaty("trade", r.id, oid) \
					and dip.opinion(oid, r.id) >= -10.0 and _try(r, "trade", oid):
				return
	# 5. Calm borders with neutral neighbours when we have no plans for them.
	for oid in world.neighbor_realms(r):
		if oid != target and not dip.has_treaty("nap", r.id, oid) and dip.opinion(r.id, oid) >= 10.0 and _try(r, "nap", oid):
			return


## Propose once in a while; returns true if an attempt was made.
func _try(r: Realm, kind: String, other: int) -> bool:
	var dip := world.diplomacy
	if dip.cooldown_left(r.id, other, kind) > 0:
		return false
	var result := dip.propose(kind, r.id, other)
	if result.contains("agrees") and (kind == "alliance" or kind == "defensive"):
		world.post_news(result.replace("agrees", "and %s agree" % r.name), 2 if world.realms[other].is_player else 1)
	return true


## Extra willingness (opinion points) for `to` to accept a pact from `from`.
func pact_bias(kind: String, from: int, to: int) -> float:
	if world.realms[to].is_player:
		return 0.0
	var m := mind(to)
	var bias := 0.0
	var their_target := int(mind(from)["target"])
	if int(m["target"]) == from or their_target == to:
		return -60.0
	var threat := int(m["top_threat"])
	match kind:
		"alliance", "defensive":
			if threat != -1 and threat != from and _shares_threat(to, from, threat):
				bias += 25.0
			if float(m["threat_score"]) >= 0.8 and power(from) > power(to) * 1.5:
				bias += 15.0
			if threat != -1 and world.diplomacy.allies_of(threat, ["alliance", "defensive"]).has(from):
				bias -= 30.0
		"nap":
			if m["posture"] == "prepare":
				bias += 20.0   # a quiet flank
			if threat == from:
				bias += 15.0   # appease the dangerous
	return bias


## Would `victim` give in to a demand from `bully` rather than fight?
func would_submit(victim: int, bully: int, kind: String) -> bool:
	var lose := 1.0 - win_chance(victim, bully) if not world.at_war(victim, bully) else 0.0
	var their_odds := win_chance(bully, victim)
	var fear := maxf(lose, their_odds)
	return fear >= (0.92 if kind == "vassal" else 0.82)


## Answer an ally's call to arms by weighing it, not by chance.
func will_join(ally: int, friend: int, enemy: int) -> bool:
	if world.at_war(ally, enemy):
		return true
	var a := world.realms[ally]
	var m := mind(ally)
	var score := world.diplomacy.opinion(ally, friend) / 50.0
	if int(m["top_threat"]) == enemy or int(m["target"]) == enemy:
		score += 1.5
	var together := power(ally) + power(friend)
	var ratio := together / maxf(defender_side(enemy, friend), 1.0)
	score += (ratio * ratio / (1.0 + ratio * ratio) - 0.5) * 3.0
	score += 1.0 if world.diplomacy.has_treaty("alliance", ally, friend) else 0.5
	if a.personality == "pious" or a.personality == "ambitious":
		score += 0.3
	if not a.enemies.is_empty():
		score -= 1.0
	if world.diplomacy.shares_border(a, world.realms[enemy]) and power(ally) < power(enemy) * 0.3:
		score -= 1.5   # a small neighbour fears the reprisal
	return score > 0.5


## A short line of what the player's envoys can sense about `rid`.
func intent_toward(rid: int, player: int) -> String:
	if not minds.has(rid):
		return ""
	var m := mind(rid)
	var r := world.realms[rid]
	if world.at_war(rid, player):
		return "At war with you."
	if m["posture"] == "prepare" and int(m["target"]) == player and _massing_against(r, world.realms[player]):
		return "[color=#9a2a1a]Their armies are gathering on your border![/color]"
	if m["posture"] == "prepare":
		return "Their court is preparing for war against someone."
	if int(m["top_threat"]) == player:
		return "They see you as their greatest threat."
	if world.diplomacy.opinion(rid, player) >= 30.0:
		return "They count you a friend."
	return "Their envoys reveal little."
