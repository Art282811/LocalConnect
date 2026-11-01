class_name Diplomacy
extends RefCounted
## Layer 4: opinions between realms, treaties, trade routes, calls to arms,
## tribute and vassals, and the AI's statecraft. Offers aimed at the player
## wait in `offers` until answered.

const TREATY_NAMES := {
	"nap": "Non-aggression pact", "alliance": "Alliance", "defensive": "Defensive pact",
	"trade": "Trade agreement", "tribute": "Tribute", "vassal": "Vassalage",
}
const SYMMETRIC := ["nap", "alliance", "defensive", "trade"]
const GIFT_GOLD := 50.0
const NAP_DAYS := 1800
const TRIBUTE_DAYS := 1800
const OFFER_DAYS := 40
const COOLDOWN_DAYS := 30
const GOODS_VALUE := {"silk": 0.4, "furs": 0.25, "wine": 0.2, "iron": 0.2, "salt": 0.15, "grain": 0.1, "timber": 0.1}

var world: World
var treaties: Array[Dictionary] = []  # {type, a, b, start, until}; tribute/vassal: a = receiver/liege
var routes: Array[Dictionary] = []    # {a, b, from, to, path, sea, goods, value, cut_until}
var offers: Array[Dictionary] = []    # to the player: {id, kind, from, text, expires, data}
var _cooldown := {}                   # "from:to:kind" -> day it can be asked again
var _next_offer := 0


func _init(w: World) -> void:
	world = w


# --- Opinion ---------------------------------------------------------------------------------

var _cache_day := -1
var _borders := {}    # realm id -> {neighbour realm id: true}, rebuilt once a day
var _opinions := {}   # a * 100000 + b -> opinion, cleared daily and on any change


func _fresh() -> void:
	if _cache_day == world.day:
		return
	_cache_day = world.day
	_opinions.clear()
	_borders.clear()
	for p: Province in world.provinces:
		if p.owner == -1:
			continue
		for nb: int in p.neighbors:
			var o := world.provinces[nb].owner
			if o != -1 and o != p.owner:
				if not _borders.has(p.owner):
					_borders[p.owner] = {}
				_borders[p.owner][o] = true


func invalidate() -> void:
	_cache_day = -1


func shares_border(a: Realm, b: Realm) -> bool:
	_fresh()
	return _borders.has(a.id) and (_borders[a.id] as Dictionary).has(b.id)


## Why `of_id` feels the way it does about `toward_id`: [[label, value], ...].
func opinion_parts(of_id: int, toward_id: int) -> Array:
	var a := world.realms[of_id]
	var b := world.realms[toward_id]
	var rel := world.religion
	var parts: Array = []
	var border := shares_border(a, b)
	if border:
		parts.append(["Shared border", -10.0])
	if a.faith == b.faith:
		parts.append(["Same faith", 15.0])
	elif rel.group_of(a.faith) == rel.group_of(b.faith):
		parts.append(["Related faith", 5.0])
	else:
		parts.append(["Unbelievers", -20.0])
	if b.excommunicated and b.faith == a.faith:
		parts.append(["Excommunicated", -30.0])
	if a.culture == b.culture:
		parts.append(["Same culture", 5.0])
	if world.at_war(a.id, b.id):
		parts.append(["At war", -50.0])
	elif int(a.truces.get(b.id, -1)) > world.day:
		parts.append(["Recent war", -15.0])
	for t in treaties_between(a.id, b.id):
		match str(t["type"]):
			"alliance":
				parts.append(["Allies", 30.0])
			"defensive":
				parts.append(["Defensive pact", 20.0])
			"nap":
				parts.append(["Non-aggression pact", 10.0])
			"trade":
				parts.append(["Trade partners", 15.0 if a.personality == "greedy" else 10.0])
			"tribute":
				parts.append(["Pays them tribute" if int(t["b"]) == a.id else "Receives their tribute", -15.0 if int(t["b"]) == a.id else 5.0])
			"vassal":
				parts.append(["Their vassal" if int(t["b"]) == a.id else "Our vassal", -5.0 if int(t["b"]) == a.id else 10.0])
	match a.personality:
		"ambitious":
			if border and world.strategy.power(b.id) < world.strategy.power(a.id) * 0.7:
				parts.append(["Covets their land", -15.0])
		"cruel":
			parts.append(["Cruel ruler", -5.0])
		"pious":
			parts.append(["Pious ruler", 10.0 if a.faith == b.faith else -10.0])
	if b.oathbreaker >= 1.0:
		parts.append(["Oathbreaker", -b.oathbreaker])
	var their_ruler := world.dynasty.ruler_of(b)
	if their_ruler != null and their_ruler.diplomacy != 5:
		parts.append(["Ruler's charm", (their_ruler.diplomacy - 5) * 2.0])
	var mem := float(a.memories.get(b.id, 0.0))
	if absf(mem) >= 1.0:
		parts.append(["Past dealings", mem])
	return parts


func opinion(of_id: int, toward_id: int) -> float:
	if of_id == toward_id:
		return 100.0
	_fresh()
	var key := of_id * 100000 + toward_id
	if _opinions.has(key):
		return float(_opinions[key])
	var total := 0.0
	for part in opinion_parts(of_id, toward_id):
		total += float(part[1])
	total = clampf(total, -100.0, 100.0)
	_opinions[key] = total
	return total


func remember(of_id: int, toward_id: int, amount: float) -> void:
	_opinions.clear()
	var a := world.realms[of_id]
	a.memories[toward_id] = clampf(float(a.memories.get(toward_id, 0.0)) + amount, -60.0, 60.0)


# --- Treaties ----------------------------------------------------------------------------------

func treaties_between(x: int, y: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _of(x):
		if int(t["a"]) == y or int(t["b"]) == y:
			out.append(t)
	return out


## For tribute and vassal, `x` is the receiver / liege.
var _treaty_index := {}   # "kind:a:b" -> true
var _indexed_count := -1


func _treaty_key(kind: String, x: int, y: int) -> String:
	return "%s:%d:%d" % [kind, x, y]


var _by_realm := {}       # realm id -> Array of its treaties


func _reindex() -> void:
	_treaty_index.clear()
	_by_realm.clear()
	for t in treaties:
		_treaty_index[_treaty_key(str(t["type"]), int(t["a"]), int(t["b"]))] = true
		for side in ["a", "b"]:
			var rid := int(t[side])
			if not _by_realm.has(rid):
				_by_realm[rid] = []
			_by_realm[rid].append(t)
	_indexed_count = treaties.size()


func _of(rid: int) -> Array:
	if _indexed_count != treaties.size():
		_reindex()
	return _by_realm.get(rid, [])


func has_treaty(kind: String, x: int, y: int) -> bool:
	if _indexed_count != treaties.size():
		_reindex()
	if _treaty_index.has(_treaty_key(kind, x, y)):
		return true
	return SYMMETRIC.has(kind) and _treaty_index.has(_treaty_key(kind, y, x))


func add_treaty(kind: String, x: int, y: int) -> void:
	if has_treaty(kind, x, y):
		return
	var until := -1
	if kind == "nap":
		until = world.day + NAP_DAYS
	elif kind == "tribute":
		until = world.day + TRIBUTE_DAYS
	treaties.append({"type": kind, "a": x, "b": y, "start": world.day, "until": until})
	_opinions.clear()
	_indexed_count = -1
	if kind == "trade":
		_open_route(x, y)
	elif kind == "vassal":
		world.realms[y].liege = x
		world.map_changed.emit()


func remove_treaty(kind: String, x: int, y: int) -> void:
	_opinions.clear()
	_indexed_count = -1
	for i in range(treaties.size() - 1, -1, -1):
		var t := treaties[i]
		if t["type"] != kind:
			continue
		var match_dir := int(t["a"]) == x and int(t["b"]) == y
		var match_rev := SYMMETRIC.has(kind) and int(t["a"]) == y and int(t["b"]) == x
		if match_dir or match_rev:
			treaties.remove_at(i)
			if kind == "vassal":
				world.realms[int(t["b"])].liege = -1
				world.map_changed.emit()
	if kind == "trade":
		for i in range(routes.size() - 1, -1, -1):
			var r := routes[i]
			if (int(r["a"]) == x and int(r["b"]) == y) or (int(r["a"]) == y and int(r["b"]) == x):
				routes.remove_at(i)


func allies_of(rid: int, kinds: Array) -> Array[int]:
	var out: Array[int] = []
	for t in _of(rid):
		if not kinds.has(t["type"]):
			continue
		var other := -1
		if int(t["a"]) == rid:
			other = int(t["b"])
		elif int(t["b"]) == rid:
			other = int(t["a"])
		if other != -1 and not out.has(other) and world.realms[other].alive:
			out.append(other)
	return out


func vassals_of(rid: int) -> Array[int]:
	var out: Array[int] = []
	for t in _of(rid):
		if t["type"] == "vassal" and int(t["a"]) == rid and world.realms[int(t["b"])].alive:
			out.append(int(t["b"]))
	return out


# --- War hooks ---------------------------------------------------------------------------------

## Called before a war starts: breaking pacts makes you an oathbreaker.
func on_war_declared(attacker: int, defender: int, holy: bool) -> void:
	var a := world.realms[attacker]
	var d := world.realms[defender]
	var broken := PackedStringArray()
	for kind in ["nap", "alliance", "defensive", "trade"]:
		if has_treaty(kind, attacker, defender):
			remove_treaty(kind, attacker, defender)
			if kind != "trade":
				broken.append(str(TREATY_NAMES[kind]).to_lower())
	if has_treaty("vassal", defender, attacker):
		remove_treaty("vassal", defender, attacker)
		world.post_news("%s rises against its overlord, the %s!" % [a.name, d.full_name()], 2 if (a.is_player or d.is_player) else 1)
	if has_treaty("tribute", defender, attacker):
		remove_treaty("tribute", defender, attacker)
	if not broken.is_empty():
		a.oathbreaker = minf(a.oathbreaker + (15.0 if holy else 30.0), 60.0)
		remember(defender, attacker, -40.0)
		world.post_news("%s breaks its %s with %s! All rulers take note." % [a.name, ", ".join(broken), d.name], 2 if (a.is_player or d.is_player) else 1)


## After a war starts: defender's allies, defensive pacts and vassals are called,
## and so are the attacker's allies and vassals.
func call_allies(attacker: int, defender: int) -> void:
	var pair := [attacker, defender]
	for v in vassals_of(defender):
		if v != attacker:
			world.declare_war(v, attacker, true, false, false, pair)
	for v in vassals_of(attacker):
		if v != defender:
			world.declare_war(v, defender, true, false, false, pair)
	for ally in allies_of(defender, ["alliance", "defensive"]):
		if ally != attacker and not world.at_war(ally, attacker):
			_ask_to_join(ally, defender, attacker, pair)
	for ally in allies_of(attacker, ["alliance"]):
		if ally != defender and not world.at_war(ally, defender):
			_ask_to_join(ally, attacker, defender, pair)


func _ask_to_join(ally: int, friend: int, enemy: int, pair: Array) -> void:
	var r := world.realms[ally]
	if r.is_player:
		_offer("call", friend, "%s calls you to arms against %s!" % [world.realms[friend].full_name(), world.realms[enemy].name], {"enemy": enemy, "pair": pair})
		return
	if world.strategy.will_join(ally, friend, enemy):
		world.declare_war(ally, enemy, true, false, false, pair)
		world.post_news("%s honours its pact and joins the war on %s." % [r.name, world.realms[enemy].name], 2 if world.realms[friend].is_player else 1)
	else:
		_abandon(ally, friend)


func _abandon(ally: int, friend: int) -> void:
	remove_treaty("alliance", ally, friend)
	remove_treaty("defensive", ally, friend)
	remember(friend, ally, -25.0)
	world.post_news("%s abandons its ally, %s, in the hour of need." % [world.realms[ally].name, world.realms[friend].name], 2 if (world.realms[friend].is_player or world.realms[ally].is_player) else 1)


func on_realm_gone(rid: int) -> void:
	_indexed_count = -1
	_opinions.clear()
	for i in range(treaties.size() - 1, -1, -1):
		var t := treaties[i]
		if int(t["a"]) == rid or int(t["b"]) == rid:
			if t["type"] == "vassal":
				world.realms[int(t["b"])].liege = -1
			treaties.remove_at(i)
	for i in range(routes.size() - 1, -1, -1):
		if int(routes[i]["a"]) == rid or int(routes[i]["b"]) == rid:
			routes.remove_at(i)
	for i in range(offers.size() - 1, -1, -1):
		if int(offers[i]["from"]) == rid:
			offers.remove_at(i)


# --- Trade -----------------------------------------------------------------------------------------

func trade_hub(r: Realm) -> int:
	var best := -1
	var best_s := 0.0
	for pid: int in r.provinces:
		var p := world.provinces[pid]
		var s := p.building_level("market") * 2.0 + p.building_level("port") * 2.0 + p.level * 0.5
		if s > best_s:
			best_s = s
			best = pid
	return best


func has_market(r: Realm) -> bool:
	for pid: int in r.provinces:
		var p := world.provinces[pid]
		if p.building_level("market") > 0 or p.building_level("port") > 0:
			return true
	return false


func goods_of(p: Province) -> String:
	if ["arab", "greek", "turkic"].has(p.culture) and p.level >= 2:
		return "silk"
	if p.building_level("mine") > 0:
		return "iron"
	if p.terrain == "forest" and ["norse", "baltic", "slavic"].has(p.culture):
		return "furs"
	if p.terrain == "forest":
		return "timber"
	if p.coastal and ["latin", "frankish", "greek"].has(p.culture):
		return "wine"
	if p.terrain == "desert" or p.coastal:
		return "salt"
	return "grain"


func _open_route(x: int, y: int) -> void:
	var hx := trade_hub(world.realms[x])
	var hy := trade_hub(world.realms[y])
	if hx == -1 or hy == -1:
		return
	var px := world.provinces[hx]
	var py := world.provinces[hy]
	var path := _land_path(hx, hy, 16)
	var sea := path.is_empty() or (px.building_level("port") > 0 and py.building_level("port") > 0 and path.size() > 6)
	if sea and not (px.coastal and py.coastal):
		if path.is_empty():
			return
		sea = false
	var gx := goods_of(px)
	var gy := goods_of(py)
	var value := 0.3 + 0.1 * (px.building_level("market") + py.building_level("market") + px.building_level("port") + py.building_level("port"))
	value += float(GOODS_VALUE.get(gx, 0.1)) + float(GOODS_VALUE.get(gy, 0.1))
	routes.append({"a": x, "b": y, "from": hx, "to": hy, "path": [] if sea else path, "sea": sea,
		"goods": "%s for %s" % [gx, gy], "value": value, "cut_until": -1})


## Any-owner land path by hops, used for caravans.
func _land_path(from: int, to: int, max_hops: int) -> Array[int]:
	var prev := {from: -1}
	var queue: Array[int] = [from]
	var hops := {from: 0}
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == to:
			var path: Array[int] = []
			var c := cur
			while c != -1:
				path.push_front(c)
				c = prev[c]
			return path
		if int(hops[cur]) >= max_hops:
			continue
		for nb: int in world.provinces[cur].neighbors:
			if not prev.has(nb) and not world.provinces[cur].straits.has(nb):
				prev[nb] = cur
				hops[nb] = int(hops[cur]) + 1
				queue.append(nb)
	var none: Array[int] = []
	return none


func route_active(route: Dictionary) -> bool:
	if int(route["cut_until"]) > world.day:
		return false
	var x := int(route["a"])
	var y := int(route["b"])
	for pid in route["path"]:
		var o := world.provinces[int(pid)].owner
		if o != -1 and (world.at_war(o, x) or world.at_war(o, y)):
			return false
		if world.battle_at(int(pid)) != null:
			return false
	return true


func daily_trade() -> void:
	for route in routes:
		if not route_active(route):
			continue
		for key in ["a", "b"]:
			var r := world.realms[int(route[key])]
			if r.alive and r.delta.has("gold"):
				r.delta["gold"] = float(r.delta["gold"]) + float(route["value"])


func trade_income(rid: int) -> float:
	var total := 0.0
	for route in routes:
		if (int(route["a"]) == rid or int(route["b"]) == rid) and route_active(route):
			total += float(route["value"])
	return total


# --- Player offers -------------------------------------------------------------------------------

func _offer(kind: String, from: int, text: String, data: Dictionary = {}) -> void:
	for o in offers:
		if o["kind"] == kind and int(o["from"]) == from:
			return
	offers.append({"id": _next_offer, "kind": kind, "from": from, "text": text, "expires": world.day + OFFER_DAYS, "data": data})
	_next_offer += 1
	world.post_news(text + " (see Realm, then Offers)", 2)


func answer_offer(offer_id: int, accept: bool) -> void:
	var o: Dictionary = {}
	for i in offers.size():
		if int(offers[i]["id"]) == offer_id:
			o = offers[i]
			offers.remove_at(i)
			break
	if o.is_empty():
		return
	var me := world.player_realm
	var from := int(o["from"])
	if me == -1 or not world.realms[from].alive:
		return
	var data: Dictionary = o["data"]
	match str(o["kind"]):
		"call":
			if accept:
				world.declare_war(me, int(data["enemy"]), false, false, false, data["pair"])
				remember(from, me, 15.0)
			else:
				_abandon(me, from)
		"tribute_demand":
			if accept:
				add_treaty("tribute", from, me)
				world.post_news("You agree to pay tribute to %s." % world.realms[from].name, 1)
			else:
				remember(from, me, -30.0)
				world.post_news("You refuse %s's demand. They will not forget it." % world.realms[from].name, 1)
		"peace":
			if accept and world.at_war(me, from):
				world.make_peace(me, from)
			elif not accept:
				_cooldown["%d:%d:peace" % [from, me]] = world.day + 90
		"marriage":
			var theirs := world.dynasty.person(int(data["theirs"]))
			var mine := world.dynasty.person(int(data["mine"]))
			if accept and world.dynasty.eligible(theirs) and world.dynasty.eligible(mine):
				world.dynasty.wed(mine, theirs)
			elif not accept:
				remember(from, me, -5.0)
		"vassal_demand":
			if accept:
				add_treaty("vassal", from, me)
				world.post_news("You bend the knee to the %s." % world.realms[from].full_name(), 2)
			else:
				remember(from, me, -25.0)
		_:
			if accept:
				add_treaty(str(o["kind"]), from, me)
				remember(from, me, 5.0)
				world.post_news("You sign a %s with %s." % [str(TREATY_NAMES.get(o["kind"], o["kind"])).to_lower(), world.realms[from].name], 1)
			else:
				remember(from, me, -5.0)


# --- Proposals (player → AI and AI → AI) ---------------------------------------------------------

## [accepts: bool, reason: String] for `from` asking `to` for `kind`.
func evaluate(kind: String, from: int, to: int) -> Array:
	var a := world.realms[from]
	var b := world.realms[to]
	var o := opinion(to, from)
	if kind == "nap" or kind == "alliance" or kind == "defensive":
		o += world.strategy.pact_bias(kind, from, to)
	var ratio := world.realm_strength(a) / maxf(world.realm_strength(b), 1.0)
	if world.at_war(from, to) and kind != "gift":
		return [false, "You are at war"]
	match kind:
		"nap":
			return [o >= -5.0, "opinion %d (needs -5)" % int(o)]
		"alliance":
			var need := 30.0 - (10.0 if a.faith == b.faith else 0.0) - (25.0 if not b.enemies.is_empty() else 0.0)
			return [o >= need, "opinion %d (needs %d)" % [int(o), int(need)]]
		"defensive":
			var need_d := 15.0 - (15.0 if ratio > 1.5 else 0.0)
			return [o >= need_d, "opinion %d (needs %d)" % [int(o), int(need_d)]]
		"trade":
			if not has_market(a) or not has_market(b):
				return [false, "Both need a market or port"]
			var need_t := -25.0 if b.personality == "greedy" else -10.0
			return [o >= need_t, "opinion %d (needs %d)" % [int(o), int(need_t)]]
		"tribute":
			var yields := world.strategy.would_submit(to, from, "tribute")
			return [yields, "they fear a war with you" if yields else "they would rather fight than pay"]
		"vassal":
			if b.liege != -1 or b.is_player:
				return [false, "They will not kneel"]
			var kneels := world.strategy.would_submit(to, from, "vassal") and o >= -30.0
			return [kneels, "they see no hope of resisting you" if kneels else "they would rather fight than kneel"]
		"offer_vassal":
			return [ratio <= 0.9 and o >= -20.0, "they must be stronger and not hostile"]
	return [false, ""]


func cooldown_left(from: int, to: int, kind: String) -> int:
	return maxi(int(_cooldown.get("%d:%d:%s" % [from, to, kind], 0)) - world.day, 0)


## Player (or AI) proposes. Returns a short result for the news.
func propose(kind: String, from: int, to: int) -> String:
	var a := world.realms[from]
	var b := world.realms[to]
	if kind == "gift":
		if float(a.res["gold"]) < GIFT_GOLD:
			return "Not enough gold for a gift."
		a.res["gold"] = float(a.res["gold"]) - GIFT_GOLD
		b.res["gold"] = float(b.res["gold"]) + GIFT_GOLD
		remember(to, from, 15.0)
		return "%s gladly accepts your gift." % b.name
	if kind == "insult":
		remember(to, from, -30.0)
		return "Your envoy insults the %s. Their court seethes." % b.full_name()
	if cooldown_left(from, to, kind) > 0:
		return "%s will not hear that again so soon." % b.name
	if b.is_player:
		var text := "%s proposes a %s." % [a.full_name(), str(TREATY_NAMES.get(kind, kind)).to_lower()]
		if kind == "tribute":
			_offer("tribute_demand", from, "%s demands that you pay tribute!" % a.full_name())
		elif kind == "vassal":
			_offer("vassal_demand", from, "%s demands that you become its vassal!" % a.full_name())
		else:
			_offer(kind, from, text)
		return ""
	var verdict := evaluate(kind, from, to)
	_cooldown["%d:%d:%s" % [from, to, kind]] = world.day + COOLDOWN_DAYS
	if not verdict[0]:
		if kind == "tribute" or kind == "vassal":
			remember(to, from, -15.0)
		return "%s refuses (%s)." % [b.name, verdict[1]]
	match kind:
		"tribute":
			add_treaty("tribute", from, to)
		"vassal":
			add_treaty("vassal", from, to)
		"offer_vassal":
			add_treaty("vassal", to, from)
		_:
			add_treaty(kind, from, to)
	return "%s agrees: %s." % [b.name, str(TREATY_NAMES.get(kind if kind != "offer_vassal" else "vassal", kind)).to_lower()]


func break_treaty(kind: String, from: int, to: int) -> void:
	if kind == "vassal":
		remove_treaty("vassal", to, from)
	else:
		remove_treaty(kind, from, to)
	remember(to, from, -25.0)
	if kind == "alliance" or kind == "defensive":
		world.realms[from].oathbreaker = minf(world.realms[from].oathbreaker + 10.0, 60.0)


# --- Monthly ---------------------------------------------------------------------------------------

func monthly() -> void:
	_indexed_count = -1   # treaties may expire below
	for r: Realm in world.realms:
		if not r.alive:
			continue
		for k in r.memories.keys():
			r.memories[k] = move_toward(float(r.memories[k]), 0.0, 1.0)
		r.oathbreaker = maxf(r.oathbreaker - 0.5, 0.0)
	# Tribute and vassal dues.
	for t in treaties.duplicate():
		var recv := world.realms[int(t["a"])]
		var payer := world.realms[int(t["b"])]
		if t["type"] == "tribute" or t["type"] == "vassal":
			var share := 0.2 if t["type"] == "tribute" else 0.15
			var due := maxf(float(payer.delta.get("gold", 0.0)) * 30.0 * share, 4.0)
			due = minf(due, maxf(float(payer.res["gold"]), 0.0))
			payer.res["gold"] = float(payer.res["gold"]) - due
			recv.res["gold"] = float(recv.res["gold"]) + due
		if int(t["until"]) != -1 and int(t["until"]) <= world.day:
			treaties.erase(t)
			if recv.is_player or payer.is_player:
				world.post_news("The %s between %s and %s has run its course." % [str(TREATY_NAMES[t["type"]]).to_lower(), recv.name, payer.name], 1)
	# Pirates.
	for route in routes:
		if route["sea"] and int(route["cut_until"]) <= world.day and world.rng.randf() < 0.04:
			route["cut_until"] = world.day + 30
			var x := world.realms[int(route["a"])]
			var y := world.realms[int(route["b"])]
			if x.is_player or y.is_player:
				world.post_news("Pirates prey on the sea lane between %s and %s." % [x.name, y.name], 1)
	# Unanswered offers lapse (an unanswered call to arms is a refusal).
	for o in offers.duplicate():
		if int(o["expires"]) <= world.day:
			offers.erase(o)
			if o["kind"] == "call" and world.player_realm != -1:
				_abandon(world.player_realm, int(o["from"]))
	# AI statecraft (pacts, alliances, demands) lives in sim/strategy.gd.
