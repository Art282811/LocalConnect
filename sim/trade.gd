class_name TradeNetwork
extends RefCounted
## Great trade routes that realms found, own and must protect. A route runs
## overland from one market or port to another through land the owner may use
## (its own, its allies', vassals' and trade partners'). The owner earns most
## of the profit; realms it passes through take a toll; allies may share it.
## Bandits strike unguarded stretches; enemies cut it by standing on it.

const FOUND_GOLD := 60.0
const PER_PROVINCE_GOLD := 10.0
const MAX_LENGTH := 28
const ROUTES_PER_HUB := 2
const OWNER_SHARE := 0.7
const ALLY_SHARE := 0.08
const TOLL_SHARE := 0.15
const GOODS_VALUE := {"silk": 0.4, "furs": 0.25, "wine": 0.2, "iron": 0.2, "salt": 0.15, "grain": 0.1, "timber": 0.1}

var world: World
var routes: Array[Dictionary] = []
# {id, owner, name, path: Array[int], goods, value, open (allies may use), cut_until,
#  status, blocker, last_raid_pid, founded}
var _next := 0


func _init(w: World) -> void:
	world = w


# --- Founding a route ----------------------------------------------------------------------------

func is_hub(p: Province) -> bool:
	return p.building_level("market") > 0 or p.building_level("port") > 0


## Can `rid`'s caravans travel through this province?
func may_pass(rid: int, p: Province) -> bool:
	if p.owner == -1 or p.owner == rid:
		return true
	var dip := world.diplomacy
	if world.at_war(rid, p.owner):
		return false
	return dip.has_treaty("alliance", rid, p.owner) or dip.has_treaty("trade", rid, p.owner) \
		or dip.has_treaty("vassal", rid, p.owner) or dip.has_treaty("vassal", p.owner, rid)


func may_end(rid: int, p: Province) -> bool:
	return is_hub(p) and may_pass(rid, p) and p.owner != -1


func routes_at(pid: int) -> int:
	var n := 0
	for r in routes:
		var path: Array = r["path"]
		if int(path[0]) == pid or int(path[path.size() - 1]) == pid:
			n += 1
	return n


## Cheapest caravan path (roads and bridges help; unclaimed wilds are allowed).
func find_route(rid: int, from: int, to: int) -> Array[int]:
	return path_in(_search(rid, from, to), from, to)


func path_in(tree: Dictionary, from: int, to: int) -> Array[int]:
	var path: Array[int] = []
	var prev: Dictionary = tree
	if to != from and not prev.has(to):
		return path
	var c := to
	while c != from:
		path.push_front(c)
		c = int(prev[c])
	path.push_front(from)
	return path


## Dijkstra from `from`; returns the predecessor map. Stops early at `stop_at`.
func _search(rid: int, from: int, stop_at: int = -1) -> Dictionary:
	var dist := {from: 0}
	var prev := {}
	var open: Array[int] = [from]
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if int(dist[open[i]]) < int(dist[open[best_i]]):
				best_i = i
		var cur: int = open[best_i]
		open.remove_at(best_i)
		if cur == stop_at:
			break
		if int(dist[cur]) > MAX_LENGTH * 14:
			continue
		for nb: int in world.provinces[cur].neighbors:
			var q := world.provinces[nb]
			if not may_pass(rid, q) or world.provinces[cur].straits.has(nb):
				continue
			var cost := int(dist[cur]) + world.move_days(cur, nb) + (4 if q.owner == -1 else 0)
			if not dist.has(nb) or cost < int(dist[nb]):
				dist[nb] = cost
				prev[nb] = cur
				if not open.has(nb):
					open.append(nb)
	return prev


## [ok, reason, path, cost, value per day, name]
func plan(rid: int, from: int, to: int) -> Array:
	var r := world.realms[rid]
	var a := world.provinces[from]
	var b := world.provinces[to]
	if from == to:
		return [false, "Pick a different town to trade with."]
	if a.owner != rid or not is_hub(a):
		return [false, "Routes start from one of your own markets or ports."]
	if not may_end(rid, b):
		return [false, "%s needs a market or port, and must be yours, an ally's or a trade partner's." % b.name]
	if routes_at(from) >= ROUTES_PER_HUB or routes_at(to) >= ROUTES_PER_HUB:
		return [false, "That town already handles %d great routes." % ROUTES_PER_HUB]
	for existing in routes:
		var p: Array = existing["path"]
		var ends := [int(p[0]), int(p[p.size() - 1])]
		if ends.has(from) and ends.has(to):
			return [false, "Those towns are already linked."]
	var path := find_route(rid, from, to)
	if path.is_empty():
		return [false, "No safe road leads there. You need allies or trade partners along the way."]
	if path.size() > MAX_LENGTH:
		return [false, "Too far for caravans (%d provinces, max %d)." % [path.size(), MAX_LENGTH]]
	var cost := FOUND_GOLD + PER_PROVINCE_GOLD * path.size()
	if float(r.res["gold"]) < cost:
		return [false, "Founding this route costs %d gold." % int(cost)]
	var info := _appraise(path)
	return [true, "", path, cost, float(info[0]), str(info[1]), str(info[2])]


## [value per day, route name, goods]
func _appraise(path: Array) -> Array:
	var a := world.provinces[int(path[0])]
	var b := world.provinces[int(path[path.size() - 1])]
	var ga := world.diplomacy.goods_of(a)
	var gb := world.diplomacy.goods_of(b)
	var value := 0.4 + 0.1 * path.size()
	value += float(GOODS_VALUE.get(ga, 0.1)) * 2.5 + float(GOODS_VALUE.get(gb, 0.1)) * 2.5
	value += 0.25 * (a.building_level("market") + a.building_level("port") + b.building_level("market") + b.building_level("port"))
	for pid in path:
		value += 0.3 * world.provinces[int(pid)].building_level("caravanserai")
	var name := "%s road" % (a.name if a.level >= b.level else b.name)
	var span := a.center.distance_to(b.center)
	if (ga == "silk" or gb == "silk") and span > 700.0:
		value *= 1.5
		name = "Silk Road"
	elif span > 900.0:
		name = "Great road of %s" % a.name
	if ga == gb:
		value *= 0.8   # little to trade between two towns selling the same thing
	return [value, name, "%s for %s" % [ga, gb]]


func found(rid: int, from: int, to: int) -> String:
	var p := plan(rid, from, to)
	if not p[0]:
		return str(p[1])
	var r := world.realms[rid]
	r.res["gold"] = float(r.res["gold"]) - float(p[3])
	var route := {"id": _next, "owner": rid, "name": p[5], "path": p[2], "goods": p[6], "value": p[4],
		"open": true, "cut_until": -1, "status": "active", "blocker": "", "last_raid_pid": -1, "founded": world.day}
	_next += 1
	routes.append(route)
	var importance := 2 if r.is_player else (1 if p[5] == "Silk Road" else 0)
	world.post_news("The %s founds the %s: %s, %d provinces long." % [r.full_name(), p[5], p[6], (p[2] as Array).size()], importance)
	return ""


func abandon(route_id: int) -> void:
	for i in routes.size():
		if int(routes[i]["id"]) == route_id:
			routes.remove_at(i)
			return


func route_by_id(route_id: int) -> Dictionary:
	for r in routes:
		if int(r["id"]) == route_id:
			return r
	return {}


# --- Running routes ---------------------------------------------------------------------------------

## Is something closing the route right now? Sets status and blocker.
func _check(route: Dictionary) -> bool:
	var owner := int(route["owner"])
	if int(route["cut_until"]) > world.day:
		route["status"] = "raided"
		return false
	for pid in route["path"]:
		var p := world.provinces[int(pid)]
		if not may_pass(owner, p):
			route["status"] = "closed"
			route["blocker"] = "%s will not let your caravans through %s" % [world.realms[p.owner].name, p.name] if p.owner != -1 else p.name
			return false
		if world.battle_at(p.id) != null:
			route["status"] = "closed"
			route["blocker"] = "battle at %s" % p.name
			return false
		for a: Army in world.armies_at(p.id):
			if not a.dead and world.at_war(owner, a.realm):
				route["status"] = "closed"
				route["blocker"] = "%s's army sits on the road at %s" % [world.realms[a.realm].name, p.name]
				return false
	route["status"] = "active"
	route["blocker"] = ""
	return true


func users(route: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if not route["open"]:
		return out
	for ally in world.diplomacy.allies_of(int(route["owner"]), ["alliance"]):
		out.append(ally)
	return out


## Gold per day this route pays each realm involved: {realm id: gold}.
func payouts(route: Dictionary) -> Dictionary:
	var owner := int(route["owner"])
	var allies := users(route)
	var value := float(route["value"]) * (1.0 + 0.1 * allies.size())
	var out := {owner: value * OWNER_SHARE}
	for ally in allies:
		out[ally] = float(out.get(ally, 0.0)) + value * ALLY_SHARE
	var transit := {}
	for pid in route["path"]:
		var o := world.provinces[int(pid)].owner
		if o != -1 and o != owner:
			transit[o] = int(transit.get(o, 0)) + 1
	var steps := (route["path"] as Array).size()
	for o in transit:
		out[o] = float(out.get(o, 0.0)) + value * TOLL_SHARE * float(transit[o]) / steps
	return out


func daily() -> void:
	daily_bandits()
	for route in routes.duplicate():
		if not world.realms[int(route["owner"])].alive:
			routes.erase(route)
			continue
		if not _check(route):
			continue
		var pay := payouts(route)
		for rid in pay:
			var r := world.realms[int(rid)]
			if r.alive and r.delta.has("gold"):
				r.delta["gold"] = float(r.delta["gold"]) + float(pay[rid])
		# Enemies who sit on a road plunder it.
	for route in routes:
		if route["status"] == "closed":
			for pid in route["path"]:
				for a: Army in world.armies_at(int(pid)):
					if not a.dead and world.at_war(int(route["owner"]), a.realm):
						var r := world.realms[a.realm]
						if r.delta.has("gold"):
							r.delta["gold"] = float(r.delta["gold"]) + float(route["value"]) * 0.3


func income(rid: int) -> float:
	var total := 0.0
	for route in routes:
		if route["status"] == "active":
			total += float(payouts(route).get(rid, 0.0))
	return total


# --- Bandits and guards -------------------------------------------------------------------------------

## Is this stretch watched by the owner's or an ally's troops, or a watchtower?
func guarded(route: Dictionary, pid: int) -> bool:
	var owner := int(route["owner"])
	var p := world.provinces[pid]
	var friends := world.diplomacy.allies_of(owner, ["alliance"])
	var spots: Array[int] = [pid]
	spots.append_array(p.neighbors)
	for spot in spots:
		for a: Army in world.armies_at(spot):
			if not a.dead and (a.realm == owner or friends.has(a.realm)):
				return true
	return false


func stretch_risk(route: Dictionary, pid: int) -> float:
	var p := world.provinces[pid]
	if guarded(route, pid):
		return 0.0
	var risk := 0.02
	if p.owner == -1:
		risk = 0.08
	elif p.happiness < 30.0:
		risk = 0.05
	if p.terrain == "desert" or p.terrain == "mountains" or p.terrain == "forest":
		risk += 0.02
	var tower := p.building_level("watchtower") > 0
	for nb: int in p.neighbors:
		if world.provinces[nb].building_level("watchtower") > 0:
			tower = true
	if tower:
		risk *= 0.35
	if p.building_level("caravanserai") > 0:
		risk *= 0.6
	return risk


func risk(route: Dictionary) -> float:
	var total := 0.0
	for pid in route["path"]:
		total += stretch_risk(route, int(pid))
	return minf(total, 0.9)


## Unguarded stretches, worst first: where to send troops.
func weak_points(route: Dictionary, limit := 3) -> Array[int]:
	var scored: Array = []
	for pid in route["path"]:
		var r := stretch_risk(route, int(pid))
		if r > 0.0:
			scored.append([int(pid), r])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))
	var out: Array[int] = []
	for s in scored:
		if out.size() >= limit:
			break
		out.append(int(s[0]))
	return out


func monthly() -> void:
	_ai_found_routes()


## Bandits: each route is checked once a month, on its own day.
func daily_bandits() -> void:
	for route in routes:
		if (int(route["id"]) + world.day) % 30 != 0 or route["status"] != "active":
			continue
		var chance := risk(route)
		if world.rng.randf() >= chance:
			continue
		var worst := weak_points(route, 1)
		if worst.is_empty():
			continue
		var pid := worst[0]
		route["cut_until"] = world.day + world.rng.randi_range(20, 45)
		route["last_raid_pid"] = pid
		var owner := world.realms[int(route["owner"])]
		owner.res["gold"] = maxf(float(owner.res["gold"]) - float(route["value"]) * 8.0, -300.0)
		var importance := 2 if owner.is_player else 0
		world.post_news("Bandits plunder caravans on the %s near %s. Guard the road with troops or build watchtowers." % [route["name"], world.provinces[pid].name], importance)


## AI merchants found routes too: rich, greedy realms most of all.
func _ai_found_routes() -> void:
	for r: Realm in world.realms:
		if not r.alive or r.is_player:
			continue
		var owned := 0
		for route in routes:
			if int(route["owner"]) == r.id:
				owned += 1
		if owned >= 2:
			continue
		var keen := 0.02 + (0.03 if r.personality == "greedy" else 0.0)
		if world.rng.randf() > keen or float(r.res["gold"]) < 250.0:
			continue
		var best: Array = []
		var best_v := 0.0
		for pid: int in r.provinces:
			var a := world.provinces[pid]
			if not is_hub(a) or routes_at(pid) >= ROUTES_PER_HUB:
				continue
			var tree := _search(r.id, pid)   # one search, then judge every destination
			for q: Province in world.provinces:
				if q.id == pid or not may_end(r.id, q) or routes_at(q.id) >= ROUTES_PER_HUB:
					continue
				var span := a.center.distance_to(q.center)
				if span > 1100.0 or span < 200.0:
					continue
				var path := path_in(tree, pid, q.id)
				if path.size() < 2 or path.size() > MAX_LENGTH:
					continue
				var v := float(_appraise(path)[0])
				if v > best_v and float(r.res["gold"]) >= FOUND_GOLD + PER_PROVINCE_GOLD * path.size() + 100.0:
					best_v = v
					best = [pid, q.id]
			break   # one hub per month keeps this cheap
		if not best.is_empty():
			found(r.id, int(best[0]), int(best[1]))


# --- Patrols ---------------------------------------------------------------------------------------------

## Send an army up and down a route to keep it safe.
func assign_patrol(a: Army, route_id: int) -> bool:
	var route := route_by_id(route_id)
	if route.is_empty() or a.battle != -1:
		return false
	world.halt_army(a.id)
	a.order = "patrol"
	a.join_target = route_id   # reused: which route we patrol
	a.manual = true
	a.task = "patrol"
	next_patrol_leg(a)
	return true


## Walk to the weakest point, then the far end, and keep circling.
func next_patrol_leg(a: Army) -> void:
	var route := route_by_id(a.join_target)
	if route.is_empty():
		world.halt_army(a.id)
		return
	var path: Array = route["path"]
	var target := -1
	var weak := weak_points(route, 1)
	if not weak.is_empty() and weak[0] != a.province:
		target = weak[0]
	else:
		var first := int(path[0])
		var last := int(path[path.size() - 1])
		target = last if a.province != last else first
	var leg := world.find_path(a.province, a.realm, 300, world._is_target.bind(target))
	if not leg.is_empty():
		a.path = leg
		a.progress = 0.0
