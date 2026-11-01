class_name World
extends RefCounted
## The living world. Runs the same whether or not anyone is watching:
## clock, armies, claims, sieges, battles, AI wars, peace and rebellions.
## Nothing here draws anything; map/ and ui/ only read this state.

signal news_posted(text: String, importance: int)
signal map_changed
signal battle_fought(pos: Vector2, troops: int)
signal player_lost

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
var wars: Array[Dictionary] = []  # {a, b, start, taken: {realm_id: provinces taken}}
var day: int = 0
var speed: int = 0
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
var _accum := 0.0
var _next_army_id := 0
var _targeted := {}               # province id -> army id heading there


func setup(seed_value: int) -> void:
	rng.seed = seed_value
	var world_data := _load_json("res://data/world.json")
	names = NameGen.new(_load_json("res://data/names.json"), rng)

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
	elif p.terrain == "plains" and roll < 0.55:
		p.settlement = "town"
	elif roll < 0.25:
		p.settlement = "castle"
	else:
		p.settlement = "village"
	p.level = 1 if p.settlement == "village" else rng.randi_range(1, 2)
	_refresh_fort(p)


func _refresh_fort(p: Province) -> void:
	var base := {"castle": 2, "town": 1, "port": 1, "monastery": 0, "village": 0}
	p.fort = int(base.get(p.settlement, 0)) + (1 if _is_capital(p.id) else 0)


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
	if cap.settlement == "village" or cap.settlement == "monastery":
		cap.settlement = "castle"
	cap.level = maxi(cap.level, 2)
	_refresh_fort(cap)
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
	return realm_troops(r) + r.manpower * 0.5 + r.provinces.size() * 100.0


func province_dev(p: Province) -> int:
	return int(TERRAIN[p.terrain]["dev"]) + p.level


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
	armies.append(a)
	return a


func _move_armies() -> void:
	var winter := season() == 3
	for a: Army in armies:
		if a.dead or a.path.is_empty():
			continue
		var next: int = a.path[0]
		if not can_enter(a.realm, next):
			_stop(a)
			continue
		a.progress += 1.0 / move_days(a.province, next) * (0.6 if winter else 1.0)
		if a.progress >= 1.0:
			a.progress = 0.0
			a.path.pop_front()
			a.province = next
			if a.path.is_empty():
				a.manual = false
				_targeted.erase(next)


func _stop(a: Army) -> void:
	a.path.clear()
	a.progress = 0.0
	a.manual = false
	a.task = "idle"


func _resolve_battles() -> void:
	var by_prov := {}
	for a: Army in armies:
		if a.dead:
			continue
		if not by_prov.has(a.province):
			by_prov[a.province] = []
		by_prov[a.province].append(a)
	for pid in by_prov:
		var here: Array = by_prov[pid]
		if here.size() < 2:
			continue
		here.sort_custom(func(x: Army, y: Army) -> bool: return x.troops > y.troops)
		for i in here.size():
			var a: Army = here[i]
			if a.dead:
				continue
			for j in range(i + 1, here.size()):
				var b: Army = here[j]
				if not b.dead and at_war(a.realm, b.realm):
					_battle(a, b, provinces[pid])
					break


func _battle(a: Army, b: Army, p: Province) -> void:
	var defense: float = TERRAIN[p.terrain]["defense"]
	var sa := a.troops * rng.randf_range(0.75, 1.25) * (1.0 + a.skill * 0.08)
	var sb := b.troops * rng.randf_range(0.75, 1.25) * (1.0 + b.skill * 0.08)
	if p.owner == b.realm:
		sb *= defense
	elif p.owner == a.realm:
		sa *= defense
	var winner := a if sa >= sb else b
	var loser := b if winner == a else a
	var ratio := minf(sa, sb) / maxf(maxf(sa, sb), 1.0)
	var winner_loss := int(winner.troops * 0.3 * ratio)
	var loser_loss := int(loser.troops * (0.35 + 0.4 * (1.0 - ratio)))
	var total := a.troops + b.troops
	winner.troops = maxi(winner.troops - winner_loss, 1)
	loser.troops -= loser_loss
	if winner.skill < 5 and rng.randf() < 0.3:
		winner.skill += 1

	var wr := realms[winner.realm]
	var lr := realms[loser.realm]
	var importance := 2 if (wr.is_player or lr.is_player) else (1 if total >= 2500 else 0)
	post_news("Battle of %s: %s defeats %s (%d vs %d dead)." % [p.name, wr.name, lr.name, winner_loss, loser_loss], importance)
	battle_fought.emit(p.center, total)

	if loser.troops < 80:
		loser.dead = true
		return
	_stop(loser)
	var retreat := find_path(loser.province, loser.realm, 200, _is_own_land.bind(loser.realm))
	if retreat.is_empty():
		loser.dead = true
		post_news("The army of %s is scattered." % lr.name, 1 if lr.is_player else 0)
		return
	loser.path = retreat
	loser.task = "retreat"
	if provinces[loser.province].siege_army == loser.id:
		provinces[loser.province].siege_army = -1


## Armies standing on unclaimed or enemy land slowly take it over.
func _progress_occupations() -> void:
	for p: Province in provinces:
		if p.siege_army != -1:
			var s := army_by_id(p.siege_army)
			if s == null or s.province != p.id or not s.path.is_empty():
				p.siege_army = -1
				p.siege_progress = 0.0
	for a: Army in armies:
		if a.dead or not a.path.is_empty():
			continue
		var p := provinces[a.province]
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
		if orl.provinces.is_empty():
			_realm_falls(orl, nr)
		else:
			if orl.capital == p.id:
				_move_capital(orl)
			_update_rank(orl)
	_refresh_fort(p)
	_update_rank(nr)
	map_changed.emit()


func _move_capital(r: Realm) -> void:
	var best := r.provinces[0]
	for pid: int in r.provinces:
		if provinces[pid].level > provinces[best].level:
			best = pid
	r.capital = best
	_refresh_fort(provinces[best])
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
		var dev := 0
		for pid: int in r.provinces:
			dev += province_dev(provinces[pid])
		r.manpower = minf(r.manpower + dev * 28.0, dev * 350.0)
		_recruit(r)
	_check_peace()
	var alive_armies: Array[Army] = []
	for a: Army in armies:
		if not a.dead:
			alive_armies.append(a)
	armies = alive_armies


func _recruit(r: Realm) -> void:
	var mine := armies_of(r.id)
	var cap := 400 + r.provinces.size() * 120
	for a: Army in mine:
		if provinces[a.province].owner == r.id and a.troops < cap and r.manpower > 0.0:
			var add := int(minf(cap - a.troops, r.manpower))
			a.troops += add
			r.manpower -= add
	var max_armies := 1 + r.provinces.size() / 5
	if mine.size() < max_armies and r.manpower >= 300.0 and r.capital != -1:
		var t := int(minf(r.manpower, cap))
		spawn_army(r.id, r.capital, t)
		r.manpower -= t


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
		if a.manual or not a.path.is_empty():
			continue
		if a.task == "claim" or a.task == "siege":
			var p := provinces[a.province]
			if p.owner == -1 or at_war(r.id, p.owner):
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


func order_army(army_id: int, target: int) -> int:
	## Returns the march length in days, or -1 if there is no route.
	var a := army_by_id(army_id)
	if a == null or a.province == target:
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
	a.path = path
	a.progress = 0.0
	a.manual = true
	a.task = "order"
	return days


func halt_army(army_id: int) -> void:
	var a := army_by_id(army_id)
	if a != null:
		_stop(a)
