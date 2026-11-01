class_name Religion
extends RefCounted
## Layer 4: faiths, the AI-run religious heads, missionaries,
## excommunication, and crusades / jihads.

const CRUSADE_MIN_YEAR := 6        # design doc says ~20; lower so you see one sooner
const CRUSADE_DAYS := 720
const GATHER_DAYS := 45
const MISSION_DAYS := 120
const MISSION_COST := 40.0
const DONATION := 50.0
const LAUNCH_FAITH := 300.0
const LAUNCH_OPINION := 20.0
const PLEDGE_GOLD := 100.0

static var relic_defs: Dictionary = {}

var world: World
var faiths: Dictionary = {}        # id -> definition
var order: Array[String] = []
var head_mem: Dictionary = {}      # faith -> {realm id -> opinion from events}
var crusades: Array[Dictionary] = []
var _relic_names: Array[String] = []
var _next_crusade := 0


static func relic_effect(relic_name: String) -> String:
	return str(relic_defs.get(relic_name, {}).get("effect", ""))


func _init(w: World, data: Dictionary) -> void:
	world = w
	for f in data.get("faiths", []):
		faiths[f["id"]] = f
		order.append(f["id"])
		if f.has("head"):
			head_mem[f["id"]] = {}
	for r in data.get("relics", []):
		relic_defs[r["name"]] = r
		_relic_names.append(r["name"])


# --- Faith lookups ------------------------------------------------------------------------

func faith_name(id: String) -> String:
	return str(faiths.get(id, {}).get("name", id))


func group_of(id: String) -> String:
	return str(faiths.get(id, {}).get("group", ""))


func color_of(id: String) -> Color:
	var c: Array = faiths.get(id, {}).get("color", [0.5, 0.5, 0.5])
	return Color(float(c[0]), float(c[1]), float(c[2]))


func has_head(id: String) -> bool:
	return head_mem.has(id)


func head_title(id: String) -> String:
	return str(faiths.get(id, {}).get("head", ""))


func holy_war_name(id: String) -> String:
	return str(faiths.get(id, {}).get("holy_war", "Holy war"))


## Gives every province a majority faith: from its culture, then regional overrides.
func assign_faiths(data: Dictionary) -> void:
	var by_culture: Dictionary = data.get("culture_faith", {})
	for p: Province in world.provinces:
		p.faith = str(by_culture.get(p.culture, "catholic"))
		for reg in data.get("regional", []):
			var dx := (p.lonlat.x - float(reg["lon"])) / float(reg["rx"])
			var dy := (p.lonlat.y - float(reg["lat"])) / float(reg["ry"])
			if dx * dx + dy * dy <= 1.0 and (p.culture != "arab" or str(reg["faith"]) == "shia") \
					and not (group_of(p.faith) == "muslim" and group_of(str(reg["faith"])) != "muslim"):
				p.faith = str(reg["faith"])
	for site in data.get("holy_sites", []):
		var best: Province = null
		var best_d := INF
		for p: Province in world.provinces:
			var d := p.lonlat.distance_squared_to(Vector2(float(site["lon"]), float(site["lat"])))
			if d < best_d:
				best_d = d
				best = p
		if best != null and best.holy_site == "":
			best.holy_site = str(site["name"])
			best.sacred = site["faiths"]


func holy_site_faiths(p: Province) -> Array:
	return p.sacred


# --- Religious heads ---------------------------------------------------------------------------

func head_opinion_parts(r: Realm) -> Array:
	var parts: Array = []
	if not has_head(r.faith):
		return parts
	parts.append(["Piety", clampf(float(r.res["faith"]) / 20.0, 0.0, 25.0)])
	var mem := float((head_mem[r.faith] as Dictionary).get(r.id, 0.0))
	if absf(mem) >= 1.0:
		parts.append(["Deeds and gifts", mem])
	var wars := 0
	for w in world.wars:
		if int(w["a"]) == r.id and world.realms[int(w["b"])].faith == r.faith and not w.get("holy", false):
			wars += 1
	if wars > 0:
		parts.append(["Attacking the faithful", -20.0 * wars])
	var sites := 0
	for pid: int in r.provinces:
		var p := world.provinces[pid]
		if p.holy_site != "" and holy_site_faiths(p).has(r.faith):
			sites += 1
	if sites > 0:
		parts.append(["Guards holy sites", 10.0 * sites])
	return parts


func head_opinion(r: Realm) -> float:
	var total := 0.0
	for part in head_opinion_parts(r):
		total += float(part[1])
	return clampf(total, -100.0, 100.0)


func add_head_memory(r: Realm, amount: float) -> void:
	if not has_head(r.faith):
		return
	var m: Dictionary = head_mem[r.faith]
	m[r.id] = clampf(float(m.get(r.id, 0.0)) + amount, -80.0, 80.0)


func donate(r: Realm) -> bool:
	if not has_head(r.faith) or float(r.res["gold"]) < DONATION:
		return false
	r.res["gold"] = float(r.res["gold"]) - DONATION
	add_head_memory(r, 12.0)
	return true


# --- Missionaries ------------------------------------------------------------------------------

func mission_problem(r: Realm, p: Province) -> String:
	if p.owner != r.id:
		return "Not your land"
	if p.faith == r.faith:
		return "Already of your faith"
	if p.mission_until > world.day:
		return "Missionaries already there"
	if float(r.res["faith"]) < MISSION_COST:
		return "Need %d faith" % int(MISSION_COST)
	return ""


func start_mission(r: Realm, p: Province) -> bool:
	if mission_problem(r, p) != "":
		return false
	r.res["faith"] = float(r.res["faith"]) - MISSION_COST
	p.mission_until = world.day + MISSION_DAYS
	p.mission_faith = r.faith
	return true


# --- Monthly -------------------------------------------------------------------------------------

func monthly() -> void:
	for f in head_mem:
		var m: Dictionary = head_mem[f]
		for rid in m.keys():
			m[rid] = move_toward(float(m[rid]), 0.0, 1.0)
	for r: Realm in world.realms:
		if not r.alive or not has_head(r.faith):
			r.excommunicated = false
			continue
		var op := head_opinion(r)
		if not r.excommunicated and op < -50.0 and world.rng.randf() < 0.3:
			r.excommunicated = true
			world.post_news("The %s excommunicates the ruler of %s!" % [head_title(r.faith), r.name], 2 if r.is_player else 1)
		elif r.excommunicated and op > -10.0:
			r.excommunicated = false
			world.post_news("The %s lifts the excommunication of %s." % [head_title(r.faith), r.name], 2 if r.is_player else 0)
	for p: Province in world.provinces:
		if p.mission_faith != "" and p.mission_until <= world.day:
			var success := p.owner != -1 and world.realms[p.owner].faith == p.mission_faith and world.rng.randf() < 0.7
			if success:
				p.faith = p.mission_faith
				p.happiness = minf(p.happiness + 5.0, 100.0)
				if world.realms[p.owner].is_player:
					world.post_news("%s converts to the %s faith." % [p.name, faith_name(p.faith)], 1)
			elif p.owner != -1 and world.realms[p.owner].is_player:
				world.post_news("Your missionaries in %s are driven out." % p.name, 1)
			p.mission_faith = ""
	_update_crusades()
	if world.year() >= CRUSADE_MIN_YEAR:
		for f in head_mem:
			if active_crusade(f).is_empty() and world.rng.randf() < 0.06:
				var target := pick_target(f)
				if target != -1:
					call_crusade(f, target, -1)


# --- Crusades ------------------------------------------------------------------------------------

func active_crusade(faith: String) -> Dictionary:
	for c in crusades:
		if c["faith"] == faith:
			return c
	return {}


func crusade_by_id(cid: int) -> Dictionary:
	for c in crusades:
		if int(c["id"]) == cid:
			return c
	return {}


func crusade_against(realm_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in crusades:
		if int(c["target_realm"]) == realm_id:
			out.append(c)
	return out


## Best target for a holy war: our holy sites held by unbelievers first,
## otherwise rich unbelieving land next to our faithful.
func pick_target(faith: String) -> int:
	var group := group_of(faith)
	var best := -1
	var best_score := 0.0
	for p: Province in world.provinces:
		if p.owner == -1:
			continue
		var owner := world.realms[p.owner]
		if group_of(owner.faith) == group:
			continue
		var near_faithful := false
		for nb: int in p.neighbors:
			var o := world.provinces[nb].owner
			if o != -1 and world.realms[o].faith == faith:
				near_faithful = true
				break
		var score := p.pop / 1000.0 + world.rng.randf()
		if p.holy_site != "" and holy_site_faiths(p).has(faith):
			score += 100.0
		elif not near_faithful:
			continue
		if score > best_score:
			best_score = score
			best = p.id
	return best


func call_crusade(faith: String, target_pid: int, leader: int) -> Dictionary:
	var tp := world.provinces[target_pid]
	var target := world.realms[tp.owner]
	var region: Array[int] = [target_pid]
	for nb: int in tp.neighbors:
		if region.size() >= 5:
			break
		if world.provinces[nb].owner == target.id:
			region.append(nb)
	var place := tp.holy_site if tp.holy_site != "" else tp.name
	var c := {
		"id": _next_crusade, "faith": faith, "target_realm": target.id, "provinces": region,
		"name": "%s for %s" % [holy_war_name(faith), place], "start": world.day,
		"phase": "gathering", "leader": leader, "members": {}, "pledges": {}, "lent": [],
	}
	_next_crusade += 1
	if leader != -1:
		c["members"][leader] = true
	crusades.append(c)
	var caller := "The %s" % head_title(faith) if leader == -1 else world.realms[leader].full_name()
	var player := world.player_realm
	var importance := 1
	if player != -1 and (world.realms[player].faith == faith or player == target.id):
		importance = 2
	world.post_news("%s calls the %s against the %s! The faithful have %d days to gather." % [caller, c["name"], target.full_name(), GATHER_DAYS], importance)
	return c


func launch_problem(r: Realm, target_pid: int) -> String:
	if not has_head(r.faith):
		return "Your faith has no one to bless a holy war"
	if not active_crusade(r.faith).is_empty():
		return "A %s is already under way" % holy_war_name(r.faith)
	if world.year() < CRUSADE_MIN_YEAR:
		return "The world is too young (Year %d+)" % CRUSADE_MIN_YEAR
	var p := world.provinces[target_pid]
	if p.owner == -1 or group_of(world.realms[p.owner].faith) == group_of(r.faith):
		return "Target must be ruled by unbelievers"
	if float(r.res["faith"]) < LAUNCH_FAITH:
		return "Need %d faith" % int(LAUNCH_FAITH)
	if head_opinion(r) < LAUNCH_OPINION:
		return "The %s does not trust you enough" % head_title(r.faith)
	if r.excommunicated:
		return "You are excommunicated"
	return ""


func launch(r: Realm, target_pid: int) -> bool:
	if launch_problem(r, target_pid) != "":
		return false
	r.res["faith"] = float(r.res["faith"]) - LAUNCH_FAITH * 0.5
	call_crusade(r.faith, target_pid, r.id)
	return true


func join_problem(c: Dictionary, r: Realm) -> String:
	if r.faith != c["faith"]:
		return "Not your faith"
	if r.excommunicated:
		return "You are excommunicated"
	if (c["members"] as Dictionary).has(r.id):
		return "Already joined"
	if r.id == int(c["target_realm"]):
		return "You are the target"
	return ""


func join(c: Dictionary, r: Realm) -> bool:
	if join_problem(c, r) != "":
		return false
	c["members"][r.id] = true
	if c["phase"] == "war":
		_holy_war(r.id, int(c["target_realm"]))
	if r.is_player:
		world.post_news("You take the cross: you join the %s." % c["name"], 1)
	return true


func pledge(c: Dictionary, r: Realm) -> bool:
	if r.faith != c["faith"] or float(r.res["gold"]) < PLEDGE_GOLD:
		return false
	r.res["gold"] = float(r.res["gold"]) - PLEDGE_GOLD
	c["pledges"][r.id] = float(c["pledges"].get(r.id, 0.0)) + PLEDGE_GOLD
	add_head_memory(r, 6.0)
	return true


## Lend an army to the crusade's leader: it fights under their banner and
## comes home when the crusade ends.
func lend_army(c: Dictionary, a: Army) -> bool:
	var leader := lead_realm(c)
	if leader == -1 or leader == a.realm or a.battle != -1:
		return false
	(c["lent"] as Array).append([a.id, a.realm])
	if not (c["pledges"] as Dictionary).has(a.realm):
		c["pledges"][a.realm] = 0.0
	c["pledges"][a.realm] = float(c["pledges"][a.realm]) + a.troops * 0.1
	var owner := world.realms[a.realm]
	world.halt_army(a.id)
	a.realm = leader
	add_head_memory(owner, 8.0)
	if owner.is_player:
		world.post_news("Lord %s rides under the banner of %s." % [a.general, world.realms[leader].name], 1)
	return true


func lead_realm(c: Dictionary) -> int:
	var leader := int(c["leader"])
	if leader != -1 and world.realms[leader].alive and (c["members"] as Dictionary).has(leader):
		return leader
	var best := -1
	var best_s := -1.0
	for rid in c["members"]:
		var r := world.realms[int(rid)]
		if r.alive and not r.is_player and world.realm_strength(r) > best_s:
			best_s = world.realm_strength(r)
			best = r.id
	if best == -1:
		for rid in c["members"]:
			if world.realms[int(rid)].alive:
				return int(rid)
	return best


func _holy_war(member: int, target: int) -> void:
	if not world.at_war(member, target):
		world.declare_war(member, target, true, true)


func _update_crusades() -> void:
	for c in crusades.duplicate():
		var target := world.realms[int(c["target_realm"])]
		var age := world.day - int(c["start"])
		if c["phase"] == "gathering":
			_ai_consider_joining(c)
			if age >= GATHER_DAYS:
				if (c["members"] as Dictionary).is_empty():
					world.post_news("No one answers the call: the %s comes to nothing." % c["name"], 1)
					crusades.erase(c)
					continue
				c["phase"] = "war"
				if int(c["leader"]) == -1:
					c["leader"] = lead_realm(c)
				for rid in c["members"]:
					_holy_war(int(rid), target.id)
				world.post_news("The %s marches! %d realms ride against the %s." % [c["name"], (c["members"] as Dictionary).size(), target.full_name()], 2 if _player_involved(c) else 1)
			continue
		var held := 0
		for pid in c["provinces"]:
			var o := world.provinces[int(pid)].owner
			if o != -1 and (c["members"] as Dictionary).has(o):
				held += 1
		var fighting := false
		for rid in c["members"]:
			if world.realms[int(rid)].alive and world.at_war(int(rid), target.id):
				fighting = true
		if held == (c["provinces"] as Array).size() or not target.alive:
			_end_crusade(c, true)
		elif age > CRUSADE_DAYS or not fighting:
			_end_crusade(c, held > 0)


func _player_involved(c: Dictionary) -> bool:
	var p := world.player_realm
	return p != -1 and ((c["members"] as Dictionary).has(p) or int(c["target_realm"]) == p or (c["pledges"] as Dictionary).has(p))


func _ai_consider_joining(c: Dictionary) -> void:
	var tp := world.provinces[int((c["provinces"] as Array)[0])]
	for r: Realm in world.realms:
		if not r.alive or r.is_player or join_problem(c, r) != "":
			continue
		var chance := 0.08 + head_opinion(r) / 400.0
		if r.personality == "pious":
			chance += 0.12
		if not r.enemies.is_empty():
			chance -= 0.08
		var close := false
		for pid: int in r.provinces:
			if world.provinces[pid].center.distance_to(tp.center) < 700.0:
				close = true
				break
		if not close:
			chance *= 0.35
		if world.rng.randf() < chance:
			join(c, r)


func _end_crusade(c: Dictionary, won: bool) -> void:
	crusades.erase(c)
	var target := world.realms[int(c["target_realm"])]
	var members: Dictionary = c["members"]
	# Bring lent armies home.
	for entry in c["lent"]:
		var a := world.army_by_id(int(entry[0]))
		if a != null and world.realms[int(entry[1])].alive:
			world.halt_army(a.id)
			a.realm = int(entry[1])
			world.send_home(a)
	# Peace for every crusader with the target.
	for rid in members:
		if world.at_war(int(rid), target.id):
			world.make_peace(int(rid), target.id)
	if won:
		var loot := maxf(float(target.res["gold"]), 0.0) * 0.5
		target.res["gold"] = float(target.res["gold"]) - loot
		var share := loot / maxf(members.size(), 1.0)
		var leader := int(c["leader"])
		for rid in members:
			var r := world.realms[int(rid)]
			if not r.alive:
				continue
			r.res["faith"] = float(r.res["faith"]) + 120.0
			r.res["gold"] = float(r.res["gold"]) + share
			r.glory_until = world.day + World.DAYS_PER_YEAR
			add_head_memory(r, 25.0)
			for other in members:
				if int(other) != r.id:
					world.diplomacy.remember(r.id, int(other), 15.0)
		for rid in c["pledges"]:
			var r := world.realms[int(rid)]
			if r.alive:
				r.res["faith"] = float(r.res["faith"]) + 40.0
				add_head_memory(r, 12.0)
		var relic_to := leader if leader != -1 and world.realms[leader].alive else -1
		if relic_to != -1 and not _relic_names.is_empty():
			var relic: String = _relic_names[world.rng.randi() % _relic_names.size()]
			world.realms[relic_to].relics.append(relic)
			world.post_news("The %s triumphs! The %s brings home the %s." % [c["name"], world.realms[relic_to].name, relic], 2 if _player_involved(c) else 1)
		else:
			world.post_news("The %s triumphs against the %s!" % [c["name"], target.full_name()], 2 if _player_involved(c) else 1)
	else:
		for rid in members:
			var r := world.realms[int(rid)]
			if r.alive:
				r.res["faith"] = maxf(float(r.res["faith"]) - 40.0, 0.0)
				add_head_memory(r, -10.0)
		world.post_news("The %s fails. The %s stands." % [c["name"], target.full_name()], 2 if _player_involved(c) else 1)
