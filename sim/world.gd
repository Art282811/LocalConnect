class_name World
extends RefCounted
## The living world. Runs the same whether or not anyone is watching:
## clock, armies, claims, sieges, battles, AI wars, peace and rebellions.
## Nothing here draws anything; map/ and ui/ only read this state.

signal news_posted(text: String, importance: int)
signal map_changed
signal battle_fought(pos: Vector2, troops: int)
signal player_lost
signal battle_started(b: Battle)
signal battle_ended(b: Battle)

# --- Tuning knobs ---------------------------------------------------------
const DAY_SECONDS := 1.5          # real seconds per in-game day at 1x
const DAYS_PER_SEASON := 90
const DAYS_PER_YEAR := 360
const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const TRUCE_DAYS := 900
const START_TROOPS := 500
const MAX_TICKS_PER_FRAME := 8

const TERRAIN := {
	"plains": {"move": 6, "defense": 1.0, "dev": 3, "label": "Plains"},
	"forest": {"move": 9, "defense": 1.25, "dev": 2, "label": "Forest"},
	"hills": {"move": 9, "defense": 1.35, "dev": 2, "label": "Hills"},
	"mountains": {"move": 14, "defense": 1.7, "dev": 1, "label": "Mountains"},
	"marsh": {"move": 12, "defense": 1.3, "dev": 1, "label": "Marsh"},
	"desert": {"move": 11, "defense": 1.1, "dev": 1, "label": "Desert"},
}

const PERSONALITIES := ["ambitious", "cruel", "greedy", "pious", "cautious"]
const AGGRESSION := {"ambitious": 1.0, "cruel": 0.9, "greedy": 0.7, "pious": 0.45, "cautious": 0.25}

# --- State ----------------------------------------------------------------
var rng := RandomNumberGenerator.new()
var provinces: Array[Province] = []
var realms: Array[Realm] = []
var armies: Array[Army] = []
var battles: Array[Battle] = []
var wars: Array[Dictionary] = []  # {a, b, start, taken: {realm_id: provinces taken}}
var day: int = 0
var speed: float = 0.0
var player_realm: int = -1
var auto_rule := false            # "steward": AI also runs the player's realm
var spawn_mode := true
var news_log: Array[String] = []

var land_polys: Array[PackedVector2Array] = []
var water_polys: Array[PackedVector2Array] = []
var rivers: Array[PackedVector2Array] = []
var map_size := Vector2.ZERO
var hex_radius := 50.0

var names: NameGen
var economy: Economy
var _accum := 0.0
var _next_army_id := 0
var _next_battle_id := 0
var _targeted := {}               # province id -> army id heading there


func setup(seed_value: int) -> void:
	rng.seed = seed_value
	var world_data := _load_json("res://data/world.json")
	names = NameGen.new(_load_json("res://data/names.json"), rng)
	economy = Economy.new(self, _load_json("res://data/buildings.json"))

	var builder := MapBuilder.new(world_data)
	builder.build(rng)
	provinces = builder.provinces
	land_polys = builder.land
	water_polys = builder.water
	rivers = builder.rivers
	map_size = builder.map_size
	hex_radius = builder.radius

	var realm_data := _load_json("res://data/realms.json")
	for entry in realm_data.get("realms", []):
		names.reserve(entry["name"])
	for p: Province in provinces:
		p.name = names.place_name(p.culture)
		_roll_settlement(p)
		economy.init_province(p)

	for entry in realm_data.get("realms", []):
		_place_start_realm(entry, builder)


static func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("Could not read %s" % path)
	return {}


func _roll_settlement(p: Province) -> void:
	var roll := rng.randf()
	if p.coastal and roll < 0.45:
		p.settlement = "port"
	elif (p.terrain == "hills" or p.terrain == "mountains") and roll < 0.5:
		p.settlement = "castle"
	elif roll < 0.1:
		p.settlement = "monastery"
	elif roll < 0.22:
		p.settlement = "castle"
	else:
		p.settlement = "village"  # becomes a town once it has the people


## Siege strength: walls you build, plus a castle or a capital's defences.
func refresh_fort(p: Province) -> void:
	p.fort = p.building_level("walls") + (1 if p.settlement == "castle" else 0) \
		+ (1 if p.level >= 3 else 0) + (1 if _is_capital(p.id) else 0)


func _is_capital(pid: int) -> bool:
	var owner := provinces[pid].owner
	return owner != -1 and realms[owner].capital == pid


func _place_start_realm(entry: Dictionary, builder: MapBuilder) -> void:
	var target := builder.project(float(entry["lon"]), float(entry["lat"]))
	var best := -1
	var best_d := INF
	for p: Province in provinces:
		if p.owner != -1:
			continue
		var d := p.center.distance_squared_to(target)
		if d < best_d:
			best_d = d
			best = p.id
	if best == -1:
		return
	var r := _create_realm(entry["name"], entry["culture"], best, entry.get("personality", ""))
	if entry.has("hue"):
		r.hue = float(entry["hue"])
	var want: int = int(entry.get("size", 1))
	var frontier: Array[int] = [best]
	while r.provinces.size() < want and not frontier.is_empty():
		var cur: int = frontier.pop_front()
		for nb: int in provinces[cur].neighbors:
			if r.provinces.size() >= want:
				break
			if provinces[nb].owner == -1 and not provinces[cur].straits.has(nb):
				_set_owner(provinces[nb], r.id)
				frontier.append(nb)
	r.rank = Realm.rank_for_size(r.provinces.size())
	r.manpower = 300.0
	spawn_army(r.id, best, START_TROOPS)


func _create_realm(realm_name: String, culture: String, capital: int, personality: String = "") -> Realm:
	var r := Realm.new()
	r.id = realms.size()
	r.name = realm_name
	r.culture = culture
	r.hue = fmod(r.id * 0.618034 + 0.13, 1.0)
	r.personality = personality if personality != "" else PERSONALITIES[rng.randi() % PERSONALITIES.size()]
	r.founded_day = day
	realms.append(r)
	r.capital = capital
	_set_owner(provinces[capital], r.id)
	var cap := provinces[capital]
	if cap.settlement == "monastery":
		cap.settlement = "castle"
	if cap.pop < Economy.TOWN_POP + 400.0:
		cap.pop = Economy.TOWN_POP + 400.0
		economy.init_level(cap)
	refresh_fort(cap)
	return r


func _set_owner(p: Province, realm_id: int) -> void:
	var old := p.owner
	if old != -1:
		realms[old].provinces.erase(p.id)
	p.owner = realm_id
	p.siege_army = -1
	p.siege_progress = 0.0
	if realm_id != -1:
		realms[realm_id].provinces.append(p.id)


# --- Clock ----------------------------------------------------------------

func advance(delta: float) -> void:
	if speed <= 0 or spawn_mode:
		return
	_update_battles(delta * speed / DAY_SECONDS * Battle.SECONDS_PER_DAY)
	_accum += delta * speed
	var ticks := 0
	while _accum >= DAY_SECONDS and ticks < MAX_TICKS_PER_FRAME:
		_accum -= DAY_SECONDS
		tick_day()
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_accum = 0.0


func day_fraction() -> float:
	return clampf(_accum / DAY_SECONDS, 0.0, 1.0)


func year() -> int:
	return day / DAYS_PER_YEAR + 1


func season() -> int:
	return (day % DAYS_PER_YEAR) / DAYS_PER_SEASON


func season_name() -> String:
	return SEASONS[season()]


func date_string() -> String:
	return "Year %d · %s · day %d" % [year(), season_name(), day % DAYS_PER_SEASON + 1]


func tick_day() -> void:
	day += 1
	_move_armies()
	_resolve_battles()
	_progress_occupations()
	economy.tick_day()
	if season() == 3:
		_winter_attrition()
	for r: Realm in realms:
		if r.alive and (r.id + day) % 5 == 0:
			_ai_think(r)
	if day % 30 == 0:
		_monthly()
	if day % DAYS_PER_SEASON == 0:
		_seasonal()
		post_news("%s of Year %d begins." % [season_name(), year()], 0)


func post_news(text: String, importance: int) -> void:
	var line := "Y%d %s: %s" % [year(), season_name(), text]
	news_log.append(line)
	if news_log.size() > 400:
		news_log.remove_at(0)
	news_posted.emit(text, importance)


# --- Queries --------------------------------------------------------------

func at_war(a: int, b: int) -> bool:
	return a != -1 and b != -1 and realms[a].enemies.has(b)


func enemies_of(realm_id: int) -> Array:
	return realms[realm_id].enemies.keys()


func can_enter(realm_id: int, pid: int) -> bool:
	var owner := provinces[pid].owner
	return owner == -1 or owner == realm_id or at_war(realm_id, owner)


func move_days(from: int, to: int) -> int:
	var days: int = TERRAIN[provinces[to].terrain]["move"]
	if provinces[to].building_level("road") > 0:
		days = maxi(int(days * 0.7), 3)
	if provinces[from].straits.has(to):
		days *= 2
	return days


func armies_of(realm_id: int) -> Array[Army]:
	var out: Array[Army] = []
	for a: Army in armies:
		if not a.dead and a.realm == realm_id:
			out.append(a)
	return out


func army_by_id(army_id: int) -> Army:
	for a: Army in armies:
		if a.id == army_id and not a.dead:
			return a
	return null


func realm_troops(r: Realm) -> int:
	var t := 0
	for a: Army in armies_of(r.id):
		t += a.troops
	return t


func realm_strength(r: Realm) -> float:
	var s := 0.0
	for a: Army in armies_of(r.id):
		s += a.troops * a.quality
	return s + r.manpower * 0.4 + maxf(float(r.res["gold"]), 0.0) * 2.0 + r.provinces.size() * 100.0


func neighbor_realms(r: Realm) -> Array[int]:
	var seen := {}
	for pid: int in r.provinces:
		for nb: int in provinces[pid].neighbors:
			var o := provinces[nb].owner
			if o != -1 and o != r.id:
				seen[o] = true
	var out: Array[int] = []
	for k in seen:
		out.append(k)
	return out


func province_at(pos: Vector2) -> int:
	var reach := hex_radius * hex_radius * 4.0
	for p: Province in provinces:
		if p.center.distance_squared_to(pos) > reach:
			continue
		for piece: PackedVector2Array in p.polygons:
			if Geometry2D.is_point_in_polygon(pos, piece):
				return p.id
	return -1


func army_position(a: Army) -> Vector2:
	var from := provinces[a.province].center
	if a.path.is_empty():
		return from
	var step := 1.0 / move_days(a.province, a.path[0]) * (0.6 if season() == 3 else 1.0)
	var t := clampf(a.progress + step * day_fraction() * (1.0 if speed > 0 else 0.0), 0.0, 1.0)
	return from.lerp(provinces[a.path[0]].center, t)


func unclaimed_count() -> int:
	var n := 0
	for p: Province in provinces:
		if p.owner == -1:
			n += 1
	return n


# --- Pathfinding (Dial's algorithm: integer day costs) ---------------------

## Finds the cheapest route from `start` to the nearest province for which
## `goal` returns true, walking only where `realm_id` may march.
## Returns the path without `start`, or [] when nothing is in reach.
func find_path(start: int, realm_id: int, max_days: int, goal: Callable) -> Array[int]:
	var dist := {start: 0}
	var prev := {}
	var buckets: Array = []
	buckets.resize(max_days + 1)
	buckets[0] = [start]
	for cost in max_days + 1:
		var bucket: Variant = buckets[cost]
		if bucket == null:
			continue
		for pid in bucket:
			if dist[pid] != cost:
				continue
			if pid != start and goal.call(pid):
				var path: Array[int] = []
				var cur: int = pid
				while cur != start:
					path.push_front(cur)
					cur = prev[cur]
				return path
			for nb: int in provinces[pid].neighbors:
				if not can_enter(realm_id, nb):
					continue
				var nc: int = cost + move_days(pid, nb)
				if nc > max_days:
					continue
				if not dist.has(nb) or nc < dist[nb]:
					dist[nb] = nc
					prev[nb] = pid
					if buckets[nc] == null:
						buckets[nc] = []
					buckets[nc].append(nb)
	var none: Array[int] = []
	return none


# --- Armies ---------------------------------------------------------------

func spawn_army(realm_id: int, pid: int, troops: int) -> Army:
	var a := Army.new()
	a.id = _next_army_id
	_next_army_id += 1
	a.realm = realm_id
	a.troops = troops
	a.province = pid
	a.skill = rng.randi_range(0, 3)
	var r := realms[realm_id]
	a.general = names.person_name(r.culture)
	a.general_trait = ["cautious", "steady", "steady", "reckless"][rng.randi() % 4]
	match r.personality:
		"cautious", "pious":
			a.stance = 0
		"ambitious", "cruel":
			a.stance = 2
		_:
			a.stance = 1
	armies.append(a)
	return a


func _move_armies() -> void:
	var winter := season() == 3
	for a: Army in armies:
		if a.dead or a.battle != -1:
			continue
		if a.path.is_empty():
			if a.order == "join":
				_try_join(a)
			continue
		a.dug_in = 0.0
		var next: int = a.path[0]
		if not can_enter(a.realm, next):
			_stop(a)
			continue
		a.progress += 1.0 / move_days(a.province, next) * (0.6 if winter else 1.0)
		if a.progress >= 1.0:
			a.progress = 0.0
			a.path.pop_front()
			a.came_from = a.province
			a.province = next
			if a.path.is_empty():
				_targeted.erase(next)
				if a.order == "join":
					_try_join(a)
				elif a.order != "hold" and a.order != "raid":
					a.manual = false
					a.order = ""


func _stop(a: Army) -> void:
	a.path.clear()
	a.progress = 0.0
	a.manual = false
	a.task = "idle"
	a.order = ""
	a.join_target = -1


func _try_join(a: Army) -> void:
	var other := army_by_id(a.join_target)
	if other == null or other.realm != a.realm or other == a:
		_stop(a)
		return
	if other.province == a.province and other.battle == -1:
		other.quality = (other.troops * other.quality + a.troops * a.quality) / float(other.troops + a.troops)
		other.troops += a.troops
		if a.skill > other.skill:
			other.skill = a.skill
			other.general = a.general
			other.general_trait = a.general_trait
		a.dead = true
		if realms[a.realm].is_player:
			post_news("Your armies join under Lord %s." % other.general, 1)
		return
	if a.path.is_empty():
		var path := find_path(a.province, a.realm, 400, _is_target.bind(other.province))
		if path.is_empty():
			_stop(a)
		else:
			a.path = path


## Hostile armies in the same province start (or join) a battle there.
func _resolve_battles() -> void:
	var by_prov := {}
	for a: Army in armies:
		# Beaten armies falling back don't turn round and start another fight.
		if a.dead or (a.task == "retreat" and not a.path.is_empty()):
			continue
		if not by_prov.has(a.province):
			by_prov[a.province] = []
		by_prov[a.province].append(a)
	for pid in by_prov:
		var here: Array = by_prov[pid]
		var b := battle_at(pid)
		if b != null:
			for a: Army in here:
				if a.battle == -1 and a.path.is_empty():
					var side := b.side_realm.find(a.realm)
					if side != -1:
						b.add_army(a, side)
			continue
		if here.size() < 2:
			continue
		here.sort_custom(func(x: Army, y: Army) -> bool: return x.troops > y.troops)
		var first: Army = null
		var second: Army = null
		for a: Army in here:
			if a.battle != -1:
				continue
			if first == null:
				first = a
			elif second == null and at_war(first.realm, a.realm):
				second = a
		if first == null or second == null:
			continue
		var side0: Array[Army] = []
		var side1: Array[Army] = []
		for a: Army in here:
			if a.battle != -1:
				continue
			if a.realm == first.realm:
				side0.append(a)
			elif a.realm == second.realm:
				side1.append(a)
		# The side standing on its own land is defending; the other marched in.
		var attacking := 1 if provinces[pid].owner == first.realm else 0
		_start_battle(pid, side0, side1, attacking, false)


func battle_at(pid: int) -> Battle:
	for b: Battle in battles:
		if b.province == pid and not b.over:
			return b
	return null


func battle_by_id(battle_id: int) -> Battle:
	for b: Battle in battles:
		if b.id == battle_id:
			return b
	return null


func _start_battle(pid: int, side0: Array[Army], side1: Array[Army], attacking: int, is_assault: bool) -> Battle:
	var b := Battle.new()
	b.setup(self, _next_battle_id, pid, side0, side1, attacking, is_assault)
	_next_battle_id += 1
	battles.append(b)
	for a: Army in side0 + side1:
		a.path.clear()
		a.progress = 0.0
	var r0 := realms[b.side_realm[0]]
	var r1 := realms[b.side_realm[1]]
	if r0.is_player or r1.is_player:
		var mine := 0 if r0.is_player else 1
		var verb := "storms the walls of" if is_assault else "gives battle at"
		post_news("%s %s %s!" % ["Lord " + b.general[mine] if b.general[mine] != "" else "Your army", verb, provinces[pid].name], 2)
	battle_started.emit(b)
	return b


## Besiegers can storm the walls instead of starving the town out.
func start_assault(army_id: int) -> bool:
	var a := army_by_id(army_id)
	if a == null or a.battle != -1 or not a.path.is_empty():
		return false
	var p := provinces[a.province]
	if p.owner == -1 or not at_war(a.realm, p.owner) or _hostile_army_in(a.realm, p.id):
		return false
	var side0: Array[Army] = []
	for other: Army in armies:
		if not other.dead and other.realm == a.realm and other.province == p.id and other.battle == -1 and other.path.is_empty():
			side0.append(other)
	var side1: Array[Army] = []
	_start_battle(p.id, side0, side1, 0, true)
	return true


func garrison_size(p: Province) -> float:
	return clampf(p.pop * 0.03 + p.fort * 120.0, 60.0, 900.0)


func _update_battles(dt: float) -> void:
	for b: Battle in battles.duplicate():
		b.update(dt)
		if b.over:
			_finish_battle(b)


func resolve_battle_now(battle_id: int) -> void:
	var b := battle_by_id(battle_id)
	if b != null and not b.over:
		b.resolve_now()
		_finish_battle(b)


func _finish_battle(b: Battle) -> void:
	battles.erase(b)
	var p := provinces[b.province]
	var loser := 1 - b.winner
	var wr := realms[b.side_realm[b.winner]]
	var lr := realms[b.side_realm[loser]]
	var total := 0
	for side in 2:
		for aid in b.armies[side]:
			var a := army_by_id(aid)
			if a == null:
				continue
			total += a.troops
			a.battle = -1
			a.troops = b.survivors_of(a.id)
			a.dug_in = 0.0
			if a.troops < 80:
				a.dead = true
				continue
			if side == loser:
				_retreat(a)
			elif a.skill < 5 and rng.randf() < 0.3:
				a.skill += 1
	var winner_name := b.general[b.winner]
	var who := ("Lord %s of %s" % [winner_name, wr.name]) if winner_name != "" else ("The garrison of %s" % p.name)
	var verb := "holds" if b.winner != b.attacker else ("storms" if b.assault else "wins at")
	var importance := 2 if (wr.is_player or lr.is_player) else (1 if total >= 2500 else 0)
	post_news("%s %s %s: %d enemy dead, %d lost." % [who, verb, p.name, int(b.losses[loser]), int(b.losses[b.winner])], importance)
	battle_fought.emit(b.center, total)
	if b.assault and b.winner == b.attacker and p.owner == lr.id:
		_take_province(p, wr.id)
	battle_ended.emit(b)


func _retreat(a: Army) -> void:
	_stop(a)
	if provinces[a.province].siege_army == a.id:
		provinces[a.province].siege_army = -1
	var back := find_path(a.province, a.realm, 200, _is_own_land.bind(a.realm))
	if back.is_empty():
		a.dead = true
		post_news("The army of %s is scattered." % realms[a.realm].name, 1 if realms[a.realm].is_player else 0)
		return
	a.path = back
	a.task = "retreat"


## Armies standing on unclaimed or enemy land slowly take it over.
func _progress_occupations() -> void:
	for p: Province in provinces:
		if p.siege_army != -1:
			var s := army_by_id(p.siege_army)
			if s == null or s.province != p.id or not s.path.is_empty():
				p.siege_army = -1
				p.siege_progress = 0.0
	for a: Army in armies:
		if a.dead or not a.path.is_empty() or a.battle != -1:
			continue
		if a.order == "hold":
			a.dug_in += 1.0
			continue
		var p := provinces[a.province]
		if a.order == "raid":
			_raid(a, p)
			continue
		if p.owner == a.realm:
			continue
		if p.owner != -1 and not at_war(a.realm, p.owner):
			continue
		if _hostile_army_in(a.realm, p.id):
			continue
		if p.siege_army != a.id:
			if p.siege_army != -1:
				continue
			p.siege_army = a.id
			p.siege_progress = 0.0
		var defense: float = TERRAIN[p.terrain]["defense"]
		var days_needed: float
		if p.owner == -1:
			a.task = "claim"
			days_needed = 16.0 * defense * (1.0 + p.level * 0.2) / clampf(a.troops / 600.0, 0.5, 2.0)
		else:
			a.task = "siege"
			days_needed = (20.0 + 25.0 * p.fort) * defense / clampf(a.troops / 900.0, 0.4, 2.5)
		p.siege_progress += 1.0 / days_needed
		if p.siege_progress >= 1.0:
			_take_province(p, a.realm)
			a.task = "idle"


## Raiders burn and loot instead of besieging, then head home.
func _raid(a: Army, p: Province) -> void:
	if p.owner == -1 or not at_war(a.realm, p.owner) or _hostile_army_in(a.realm, p.id):
		if p.owner == -1 or not at_war(a.realm, p.owner):
			a.order = ""
			a.manual = false
		return
	a.task = "raid"
	var victim := realms[p.owner]
	var loot := p.pop * 0.0015
	victim.res["gold"] = float(victim.res["gold"]) - loot * 0.5
	realms[a.realm].res["gold"] = float(realms[a.realm].res["gold"]) + loot
	p.pop *= 0.998
	p.happiness = maxf(p.happiness - 0.4, 0.0)
	a.raid_days += 1
	if a.raid_days >= 20:
		var who := realms[a.realm]
		var importance := 2 if (who.is_player or victim.is_player) else 0
		post_news("Lord %s of %s raids %s and carries off the harvest." % [a.general, who.name, p.name], importance)
		a.raid_days = 0
		a.order = ""
		a.manual = false
		a.task = "idle"


func _hostile_army_in(realm_id: int, pid: int) -> bool:
	for a: Army in armies:
		if not a.dead and a.province == pid and at_war(realm_id, a.realm):
			return true
	return false


func _take_province(p: Province, new_owner: int) -> void:
	var old := p.owner
	var nr := realms[new_owner]
	_set_owner(p, new_owner)
	_targeted.erase(p.id)
	if old == -1:
		if nr.is_player:
			post_news("You claim %s." % p.name, 1)
	else:
		var orl := realms[old]
		for w in wars:
			if (w["a"] == old and w["b"] == new_owner) or (w["a"] == new_owner and w["b"] == old):
				w["taken"][new_owner] = int(w["taken"].get(new_owner, 0)) + 1
		var importance := 2 if (nr.is_player or orl.is_player) else 0
		post_news("%s takes %s from %s." % [nr.name, p.name, orl.name], importance)
		# Conquest scars: plunder, broken walls, a sullen population.
		var loot := maxf(float(orl.res["gold"]), 0.0) * 0.15 + p.pop * 0.01
		orl.res["gold"] = float(orl.res["gold"]) - minf(loot, maxf(float(orl.res["gold"]), 0.0))
		nr.res["gold"] = float(nr.res["gold"]) + loot
		p.occupied_until = day + DAYS_PER_YEAR
		p.pop *= 0.9
		p.build_id = ""
		if p.building_level("walls") > 0:
			p.buildings["walls"] = p.building_level("walls") - 1
		if orl.provinces.is_empty():
			_realm_falls(orl, nr)
		else:
			if orl.capital == p.id:
				_move_capital(orl)
			_update_rank(orl)
	refresh_fort(p)
	_update_rank(nr)
	map_changed.emit()


## A miserable province throws off its lord and fights for itself.
func peasant_revolt(p: Province) -> void:
	if p.owner == -1:
		return
	var old := realms[p.owner]
	if old.provinces.size() <= 1 or old.capital == p.id:
		return
	var old_name := old.full_name()
	var rebel := _create_realm(p.name, p.culture, p.id, "cruel")
	rebel.rank = Realm.rank_for_size(rebel.provinces.size())
	rebel.manpower = 100.0
	rebel.res = {"food": 120.0, "gold": 30.0, "wood": 10.0, "stone": 0.0, "iron": 0.0, "faith": 0.0}
	spawn_army(rebel.id, p.id, int(clampf(p.pop * 0.12, 200.0, 1200.0)))
	p.happiness = 50.0
	_update_rank(old)
	declare_war(rebel.id, old.id, true)
	post_news("The peasants of %s rise against the %s!" % [p.name, old_name], 2 if old.is_player else 1)
	map_changed.emit()


func _move_capital(r: Realm) -> void:
	var best := r.provinces[0]
	for pid: int in r.provinces:
		if provinces[pid].level > provinces[best].level:
			best = pid
	r.capital = best
	refresh_fort(provinces[best])
	post_news("The %s moves its court to %s." % [r.full_name(), provinces[best].name], 2 if r.is_player else 0)


func _update_rank(r: Realm) -> void:
	var n := r.provinces.size()
	var new_rank := Realm.rank_for_size(n)
	if new_rank > r.rank:
		r.rank = new_rank
		var importance := 2 if (r.is_player or new_rank >= 2) else 1
		post_news("%s has risen to the %s!" % [r.name, r.full_name()], importance)
	elif new_rank < r.rank and Realm.rank_for_size(n + 2) < r.rank:
		r.rank = new_rank
		post_news("%s is reduced to the %s." % [r.name, r.full_name()], 2 if r.is_player else 1)


func _realm_falls(r: Realm, conqueror: Realm) -> void:
	var old_name := r.full_name()
	r.alive = false
	for a: Army in armies:
		if a.realm == r.id:
			a.dead = true
	for other in r.enemies.keys():
		_end_war(r.id, other)
	post_news("The %s has fallen to %s." % [old_name, conqueror.name], 2)
	if r.is_player:
		r.is_player = false
		player_realm = -1
		speed = 0
		player_lost.emit()


func _winter_attrition() -> void:
	for a: Army in armies:
		if not a.dead and provinces[a.province].owner != a.realm:
			a.troops = int(a.troops * 0.996)


# --- Monthly / seasonal ----------------------------------------------------

func _monthly() -> void:
	for r: Realm in realms:
		if not r.alive:
			continue
		r.manpower = minf(r.manpower + economy.monthly_manpower(r), economy.manpower_cap(r))
		var ai_runs := not r.is_player or auto_rule
		if ai_runs:
			economy.ai_manage(r)
		_recruit(r, ai_runs)
	_check_peace()
	var alive_armies: Array[Army] = []
	for a: Army in armies:
		if not a.dead:
			alive_armies.append(a)
	armies = alive_armies


## Tops up armies standing at home (all realms) and, for AI-run realms, raises
## new ones. Every soldier costs manpower and gold, the same as a levy.
func _recruit(r: Realm, raise_new: bool) -> void:
	var gold_per_man := Economy.LEVY_GOLD / Economy.LEVY_SIZE
	var mine := armies_of(r.id)
	var cap := 400 + r.provinces.size() * 120
	for a: Army in mine:
		if provinces[a.province].owner != r.id or a.troops >= cap or r.manpower <= 0.0:
			continue
		var affordable := float(r.res["gold"]) / gold_per_man
		var add := int(minf(minf(cap - a.troops, r.manpower), affordable))
		if add <= 0:
			continue
		a.quality = (a.troops * a.quality + add * 1.0) / float(a.troops + add)
		a.troops += add
		r.manpower -= add
		r.res["gold"] = float(r.res["gold"]) - add * gold_per_man
	var max_armies := 1 + r.provinces.size() / 5
	if raise_new and mine.size() < max_armies and r.manpower >= 300.0 and r.capital != -1:
		var t := int(minf(minf(r.manpower, cap), float(r.res["gold"]) / gold_per_man))
		if t >= 300:
			spawn_army(r.id, r.capital, t)
			r.manpower -= t
			r.res["gold"] = float(r.res["gold"]) - t * gold_per_man


func _seasonal() -> void:
	for r: Realm in realms.duplicate():
		if r.alive:
			_maybe_rebel(r)
	_maybe_spawn_realm()


## Big realms crack: a far-flung province rises and takes its neighbours with it.
func _maybe_rebel(r: Realm) -> void:
	var n := r.provinces.size()
	if n < 9:
		return
	var chance := (n - 8) * 0.012 + (0.04 if not r.enemies.is_empty() else 0.0)
	if r.is_player and not auto_rule:
		chance *= 0.5
	if rng.randf() > chance:
		return
	# Farthest province from the capital (by steps through the realm).
	var hops := {r.capital: 0}
	var queue: Array[int] = [r.capital]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nb: int in provinces[cur].neighbors:
			if provinces[nb].owner == r.id and not hops.has(nb):
				hops[nb] = hops[cur] + 1
				queue.append(nb)
	var far := -1
	var far_d := -1
	for pid: int in r.provinces:
		if pid == r.capital:
			continue
		var d: int = hops.get(pid, 99)
		if d > far_d or (d == far_d and rng.randf() < 0.3):
			far_d = d
			far = pid
	if far == -1:
		return
	var want := clampi(n / 4, 2, 8)
	var cluster: Array[int] = [far]
	var i := 0
	while i < cluster.size() and cluster.size() < want:
		for nb: int in provinces[cluster[i]].neighbors:
			if cluster.size() >= want:
				break
			if provinces[nb].owner == r.id and nb != r.capital and not cluster.has(nb):
				cluster.append(nb)
		i += 1
	var seat := provinces[far]
	var old_name := r.full_name()
	var rebel := _create_realm(seat.name, seat.culture, far)
	for pid: int in cluster:
		if pid != far:
			_set_owner(provinces[pid], rebel.id)
	rebel.rank = Realm.rank_for_size(rebel.provinces.size())
	rebel.manpower = 200.0
	spawn_army(rebel.id, far, 300 + cluster.size() * 250)
	_update_rank(r)
	declare_war(rebel.id, r.id, true)
	post_news("Rebels in %s rise against the %s and proclaim the %s!" % [seat.name, old_name, rebel.full_name()], 2 if r.is_player else 1)
	map_changed.emit()


## Keeps empty land alive: chieftains found petty realms in the wilds.
func _maybe_spawn_realm() -> void:
	if unclaimed_count() < 15 or rng.randf() > 0.5:
		return
	var options: Array[int] = []
	for p: Province in provinces:
		if p.owner != -1:
			continue
		var lonely := true
		for nb: int in p.neighbors:
			if provinces[nb].owner != -1:
				lonely = false
				break
		if lonely:
			options.append(p.id)
	if options.is_empty():
		return
	var pid: int = options[rng.randi() % options.size()]
	var p := provinces[pid]
	var r := _create_realm(p.name, p.culture, pid)
	r.manpower = 200.0
	spawn_army(r.id, pid, 400)
	post_news("A chieftain founds the %s." % r.full_name(), 0)
	map_changed.emit()


# --- War & peace -------------------------------------------------------------

func declare_war(attacker: int, defender: int, quiet := false) -> bool:
	if attacker == defender or at_war(attacker, defender):
		return false
	var a := realms[attacker]
	var d := realms[defender]
	if not a.alive or not d.alive:
		return false
	a.enemies[defender] = true
	d.enemies[attacker] = true
	a.truces.erase(defender)
	d.truces.erase(attacker)
	wars.append({"a": attacker, "b": defender, "start": day, "taken": {}})
	if not quiet:
		var importance := 2 if (a.is_player or d.is_player) else 1
		post_news("%s declares war on %s!" % [a.full_name(), d.full_name()], importance)
	return true


func _end_war(x: int, y: int) -> void:
	realms[x].enemies.erase(y)
	realms[y].enemies.erase(x)
	realms[x].truces[y] = day + TRUCE_DAYS
	realms[y].truces[x] = day + TRUCE_DAYS
	for i in range(wars.size() - 1, -1, -1):
		var w := wars[i]
		if (w["a"] == x and w["b"] == y) or (w["a"] == y and w["b"] == x):
			wars.remove_at(i)
	for a: Army in armies:
		if not a.dead and (a.realm == x or a.realm == y):
			var o := provinces[a.province].owner
			if o != -1 and o != a.realm and not at_war(a.realm, o):
				_send_home(a)


func _send_home(a: Army) -> void:
	_stop(a)
	var home := find_path(a.province, a.realm, 300, _is_own_land.bind(a.realm))
	if home.is_empty():
		# Boxed in by neutral land after the peace: the army is shipped home.
		if realms[a.realm].capital != -1:
			a.province = realms[a.realm].capital
	else:
		a.path = home
		a.task = "return"


func make_peace(x: int, y: int) -> void:
	var w := _war_between(x, y)
	if w.is_empty():
		return
	var gained_x: int = w["taken"].get(x, 0)
	var gained_y: int = w["taken"].get(y, 0)
	var rx := realms[x]
	var ry := realms[y]
	_end_war(x, y)
	var importance := 2 if (rx.is_player or ry.is_player) else 1
	post_news("Peace between %s and %s (%d / %d provinces changed hands)." % [rx.name, ry.name, gained_x, gained_y], importance)


func _war_between(x: int, y: int) -> Dictionary:
	for w in wars:
		if (w["a"] == x and w["b"] == y) or (w["a"] == y and w["b"] == x):
			return w
	return {}


func _check_peace() -> void:
	for w in wars.duplicate():
		var x: int = w["a"]
		var y: int = w["b"]
		var rx := realms[x]
		var ry := realms[y]
		if (rx.is_player or ry.is_player) and not auto_rule:
			continue  # the player decides their own peace
		var length := day - int(w["start"])
		if length < 90:
			continue
		var chance := clampf((length - 90) / 900.0, 0.0, 0.45)
		if armies_of(x).is_empty() or armies_of(y).is_empty():
			chance += 0.25
		if rng.randf() < chance:
			make_peace(x, y)


## Player asks for peace. The AI accepts more readily if it is losing.
func offer_peace(from: int, to: int) -> bool:
	var w := _war_between(from, to)
	if w.is_empty():
		return false
	var r := realms[to]
	if r.peace_refused_until > day:
		post_news("%s will not hear envoys again so soon." % r.name, 2)
		return false
	var length := day - int(w["start"])
	var they_lost: int = w["taken"].get(from, 0)
	var they_won: int = w["taken"].get(to, 0)
	var chance := 0.2 + clampf(length / 600.0, 0.0, 0.3) + 0.15 * (they_lost - they_won)
	if realm_strength(r) < realm_strength(realms[from]) * 0.7:
		chance += 0.25
	if rng.randf() < clampf(chance, 0.05, 0.95):
		make_peace(from, to)
		return true
	r.peace_refused_until = day + 30
	post_news("%s refuses your offer of peace." % r.full_name(), 2)
	return false


# --- AI ----------------------------------------------------------------------

func _ai_think(r: Realm) -> void:
	var ai_runs := not r.is_player or auto_rule
	if not ai_runs:
		return
	if r.enemies.is_empty():
		_consider_war(r)
	for a: Army in armies_of(r.id):
		if a.manual or not a.path.is_empty() or a.battle != -1 or a.order != "":
			continue
		if a.task == "claim" or a.task == "siege":
			var p := provinces[a.province]
			if p.owner == -1 or at_war(r.id, p.owner):
				# Storm the walls if the siege drags and we clearly outnumber the garrison.
				if p.owner != -1 and a.task == "siege":
					var g := garrison_size(p)
					var bold := a.general_trait == "reckless" or a.stance == 2
					if (bold and p.siege_progress > 0.3 and a.troops > g * 2.5) or (p.siege_progress > 0.6 and a.troops > g * 1.8):
						start_assault(a.id)
				continue  # still busy taking this province
		_assign_task(r, a)


func _assign_task(r: Realm, a: Army) -> void:
	var path: Array[int] = []
	if not r.enemies.is_empty():
		# Defend home first, then march on the nearest enemy province.
		path = find_path(a.province, r.id, 60, _is_invaded_home.bind(r.id))
		if path.is_empty():
			var reach := 90 if r.personality == "cautious" else 160
			path = find_path(a.province, r.id, reach, _is_enemy_land.bind(r.id))
		if not path.is_empty():
			a.task = "attack"
	if path.is_empty():
		path = find_path(a.province, r.id, 50, _is_free_land)
		if not path.is_empty():
			a.task = "claim"
			_targeted[path[path.size() - 1]] = a.id
	if path.is_empty() and provinces[a.province].owner != r.id:
		path = find_path(a.province, r.id, 200, _is_own_land.bind(r.id))
		a.task = "return"
	if not path.is_empty():
		a.path = path
		a.progress = 0.0


# Path goals. Extra arguments arrive through Callable.bind().
func _is_own_land(pid: int, realm_id: int) -> bool:
	return provinces[pid].owner == realm_id


func _is_invaded_home(pid: int, realm_id: int) -> bool:
	return provinces[pid].owner == realm_id and _hostile_army_in(realm_id, pid)


func _is_enemy_land(pid: int, realm_id: int) -> bool:
	var o := provinces[pid].owner
	return o != -1 and realms[realm_id].enemies.has(o)


func _is_target(pid: int, target: int) -> bool:
	return pid == target


## Unclaimed and not already the destination of another army.
func _is_free_land(pid: int) -> bool:
	if provinces[pid].owner != -1:
		return false
	if not _targeted.has(pid):
		return true
	var other := army_by_id(_targeted[pid])
	if other != null and not other.path.is_empty() and other.path[other.path.size() - 1] == pid:
		return false
	_targeted.erase(pid)
	return true


func _has_unclaimed_frontier(r: Realm) -> bool:
	for pid: int in r.provinces:
		for nb: int in provinces[pid].neighbors:
			if provinces[nb].owner == -1:
				return true
	return false


func _consider_war(r: Realm) -> void:
	if day < 60 or r.provinces.is_empty():
		return
	var aggression: float = AGGRESSION.get(r.personality, 0.5)
	var hungry := not _has_unclaimed_frontier(r)
	if rng.randf() > aggression * (0.07 if hungry else 0.015):
		return
	var mine := realm_strength(r)
	var best := -1
	var best_score := 0.0
	for other in neighbor_realms(r):
		var o := realms[other]
		if int(r.truces.get(other, -1)) > day:
			continue
		var ratio := mine / maxf(realm_strength(o), 1.0)
		if ratio < 1.25:
			continue
		var score := ratio + rng.randf() * 0.5
		if score > best_score:
			best_score = score
			best = other
	if best != -1:
		declare_war(r.id, best)


# --- Player actions -----------------------------------------------------------

func found_player_realm(pid: int) -> void:
	var p := provinces[pid]
	var r: Realm
	if p.owner == -1:
		r = _create_realm(p.name, p.culture, pid, "ambitious")
		r.manpower = 400.0
		spawn_army(r.id, pid, 600)
		post_news("You raise your banner over %s and found the %s." % [p.name, r.full_name()], 2)
	else:
		r = realms[p.owner]
		post_news("You take the throne of the %s." % r.full_name(), 2)
	r.is_player = true
	player_realm = r.id
	spawn_mode = false
	if speed == 0:
		speed = 1
	map_changed.emit()


func spectate() -> void:
	spawn_mode = false
	player_realm = -1
	if speed == 0:
		speed = 1


## Take: march there and claim or besiege it. Returns days, or -1 if no route.
func order_army(army_id: int, target: int, kind: String = "take") -> int:
	var a := army_by_id(army_id)
	if a == null or a.battle != -1:
		return -1
	if a.province == target:
		if kind == "raid" or kind == "hold":
			_stop(a)
			a.order = kind
			a.manual = true
			return 0
		return -1
	var path := find_path(a.province, a.realm, 500, _is_target.bind(target))
	if path.is_empty():
		return -1
	var days := 0
	var prev := a.province
	for pid in path:
		days += move_days(prev, pid)
		prev = pid
	if provinces[a.province].siege_army == a.id:
		provinces[a.province].siege_army = -1
	_stop(a)
	a.path = path
	a.manual = true
	a.task = "order"
	a.order = kind
	return days


## Hold: stay put and dig in. After a few days the army has stakes out.
func hold_army(army_id: int) -> void:
	var a := army_by_id(army_id)
	if a == null or a.battle != -1:
		return
	_stop(a)
	a.order = "hold"
	a.manual = true
	a.task = "hold"


## Retreat to the strongest of our own fortresses within reach.
func retreat_army(army_id: int) -> bool:
	var a := army_by_id(army_id)
	if a == null or a.battle != -1:
		return false
	var best := -1
	var best_score := -INF
	for pid: int in realms[a.realm].provinces:
		var score := provinces[pid].fort * 10.0 - provinces[a.province].center.distance_to(provinces[pid].center) / 100.0
		if score > best_score:
			best_score = score
			best = pid
	if best == -1:
		return false
	if best == a.province:
		hold_army(army_id)
		return true
	return order_army(army_id, best, "retreat") >= 0


func join_army(army_id: int, other_id: int) -> bool:
	var a := army_by_id(army_id)
	var other := army_by_id(other_id)
	if a == null or other == null or a == other or a.realm != other.realm or a.battle != -1:
		return false
	_stop(a)
	a.order = "join"
	a.join_target = other_id
	a.manual = true
	_try_join(a)
	return true


func set_stance(army_id: int, value: int) -> void:
	var a := army_by_id(army_id)
	if a != null:
		a.stance = clampi(value, 0, 2)


func halt_army(army_id: int) -> void:
	var a := army_by_id(army_id)
	if a != null and a.battle == -1:
		_stop(a)
