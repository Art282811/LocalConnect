class_name Economy
extends RefCounted
## Layer 2: resources, buildings, population, taxes, happiness and revolts.
## Ticks daily for every owned province; AI realms manage themselves monthly.

const RESOURCES := ["food", "gold", "wood", "stone", "iron", "faith"]
const SEASON_FOOD := [0.8, 1.1, 1.7, 0.35]   # spring, summer, autumn (harvest), winter
const TAX_RATES := [0.6, 1.0, 1.5]
const TAX_NAMES := ["Low", "Normal", "High"]
const TAX_HAPPINESS := [10.0, 0.0, -15.0]
const FESTIVAL_COST := 80.0
const FESTIVAL_DAYS := 60
const TERRAIN_YIELD := {
	"plains": {"food": 2.4, "wood": 0.2, "stone": 0.0, "pop": 2600.0},
	"forest": {"food": 1.3, "wood": 1.0, "stone": 0.0, "pop": 1500.0},
	"hills": {"food": 1.4, "wood": 0.3, "stone": 0.5, "pop": 1600.0},
	"mountains": {"food": 0.8, "wood": 0.2, "stone": 0.8, "pop": 800.0},
	"marsh": {"food": 1.1, "wood": 0.4, "stone": 0.0, "pop": 900.0},
	"desert": {"food": 0.6, "wood": 0.0, "stone": 0.3, "pop": 700.0},
}
const TOWN_POP := 2000.0
const CITY_POP := 5000.0
const FOOD_PER_PERSON := 0.001        # per day
const SOLDIER_FOOD := 0.0015
const SOLDIER_UPKEEP := 0.002         # gold per soldier per day
const ADMIN_COST := 0.04              # x provinces^1.35 gold per day: big realms are costly to run
const LEVY_SIZE := 400
const LEVY_GOLD := 30.0
const MAA_SIZE := 250
const MAA_GOLD := 70.0
const MAA_IRON := 15.0

var world: World
var defs: Dictionary = {}             # building id -> definition
var order: Array[String] = []


func _init(w: World, data: Dictionary) -> void:
	world = w
	for b in data.get("buildings", []):
		defs[b["id"]] = b
		order.append(b["id"])


# --- Setup --------------------------------------------------------------------

func init_province(p: Province) -> void:
	var base: float = TERRAIN_YIELD[p.terrain]["pop"]
	p.pop = base * world.rng.randf_range(0.7, 1.3)
	p.happiness = 55.0
	if p.settlement == "port":
		p.buildings["port"] = 1
	_update_level(p, false)


# --- Queries --------------------------------------------------------------------

func productivity(p: Province) -> float:
	if p.happiness < 30.0:
		return 0.5   # riots
	return 0.8 + p.happiness / 250.0


func pop_cap(p: Province) -> float:
	var base: float = TERRAIN_YIELD[p.terrain]["pop"]
	return base * 1.8 + p.building_level("farm") * 700.0 + p.building_level("granary") * 900.0 \
		+ (1500.0 if _is_capital(p) else 0.0)


func yields(p: Province) -> Dictionary:
	var t: Dictionary = TERRAIN_YIELD[p.terrain]
	var r := world.realms[p.owner]
	var popf := clampf(p.pop / 2000.0, 0.25, 4.0)
	var k := productivity(p)
	var season := world.season()
	var food_mult: float = SEASON_FOOD[season]
	if season == 3 and p.building_level("granary") > 0:
		food_mult += 0.25 * p.building_level("granary")
	var port := p.building_level("port")
	var food := (float(t["food"]) * popf + p.building_level("farm") * 1.3 + port * 0.8 + (0.3 if p.coastal else 0.0)) * food_mult * k
	var gold := (popf * 0.5 * float(TAX_RATES[r.tax]) * (1.0 + 0.3 * p.building_level("market")) + port * 0.6 + 0.3 * (p.level - 1)) * k
	var wood := (float(t["wood"]) * popf * 0.5 + p.building_level("lumber_camp") * 1.2) * k
	var stone := (float(t["stone"]) + p.building_level("quarry") * 1.0) * k
	var iron := p.building_level("mine") * 0.6 * k
	var steward := world.dynasty.ruler_of(r)
	if steward != null:
		gold *= 1.0 + (steward.stewardship - 5) * 0.03
	if p.fief != "":
		gold *= 0.75   # the noble family keeps a share
		food *= 0.9
	var faith := (p.building_level("church") * 0.4 + (0.6 if p.settlement == "monastery" else 0.0) + 0.05) * k
	return {"food": food, "gold": gold, "wood": wood, "stone": stone, "iron": iron, "faith": faith}


func happiness_parts(p: Province) -> Array:
	## [[label, amount], ...] so the HUD can explain the mood.
	var r := world.realms[p.owner]
	var parts: Array = [["Base", 55.0]]
	if r.tax != 1:
		parts.append(["%s taxes" % TAX_NAMES[r.tax], float(TAX_HAPPINESS[r.tax])])
	if r.starving:
		parts.append(["Hunger", -25.0])
	if not r.enemies.is_empty():
		parts.append(["War weariness", -minf(r.enemies.size() * 5.0, 15.0)])
	if p.culture != r.culture:
		parts.append(["Foreign rulers", -10.0])
	if p.faith != r.faith:
		var related := world.religion.group_of(p.faith) == world.religion.group_of(r.faith)
		parts.append(["Ruler of another faith", -5.0 if related else -12.0])
	if p.mission_until > world.day:
		parts.append(["Missionaries", -8.0])
	if r.excommunicated and p.faith == r.faith:
		parts.append(["Excommunicated ruler", -10.0])
	if r.glory_until > world.day:
		parts.append(["Crusader glory", 10.0])
	var relic_joy := r.has_relic_effect("happiness")
	if relic_joy > 0:
		parts.append(["Holy relics", 5.0 * relic_joy])
	if p.occupied_until > world.day:
		parts.append(["Recently conquered", -15.0])
	var church := p.building_level("church")
	if church > 0:
		parts.append(["Church", church * 4.0])
	var tavern := p.building_level("tavern")
	if tavern > 0:
		parts.append(["Tavern", tavern * 5.0])
	if r.festival_until > world.day:
		parts.append(["Festival", 15.0])
	if _is_capital(p):
		parts.append(["Seat of the court", 5.0])
	return parts


func happiness_target(p: Province) -> float:
	var h := 0.0
	for part in happiness_parts(p):
		h += float(part[1])
	return clampf(h, 0.0, 100.0)


func slots(p: Province) -> int:
	return 1 + p.level + (1 if _is_capital(p) else 0)


func used_slots(p: Province) -> int:
	var n := 0
	for id in p.buildings:
		if int(p.buildings[id]) > 0 and not defs.get(id, {}).get("free_slot", false):
			n += 1
	return n


func building_name(id: String, level: int) -> String:
	var d: Dictionary = defs[id]
	if d.has("levels") and level >= 1 and level <= d["levels"].size():
		return d["levels"][level - 1]
	var roman := ["", "", " II", " III"]
	return str(d["name"]) + (roman[level] if level < roman.size() else "")


func cost_of(id: String, level: int) -> Dictionary:
	var out := {}
	var base: Dictionary = defs[id]["cost"]
	for k in base:
		out[k] = float(base[k]) * level
	return out


func days_of(id: String, level: int) -> float:
	return float(defs[id]["days"]) * (1.0 + 0.5 * (level - 1))


func cost_text(cost: Dictionary) -> String:
	var bits := PackedStringArray()
	for k in RESOURCES:
		if cost.has(k):
			bits.append("%d %s" % [int(cost[k]), k])
	return ", ".join(bits)


## "" when the building can be started right now, otherwise the reason it can't.
func why_not(p: Province, id: String) -> String:
	if p.owner == -1:
		return "Unclaimed"
	if p.build_id != "":
		return "Already building"
	var d: Dictionary = defs[id]
	var next := p.building_level(id) + 1
	if next > int(d["max"]):
		return "Fully built"
	var needs: Dictionary = d.get("needs", {})
	if needs.has("terrain") and not (needs["terrain"] as Array).has(p.terrain):
		return "Wrong terrain"
	if needs.get("coastal", false) and not p.coastal:
		return "Needs a coast"
	if needs.get("river", false) and p.river_point == Vector2.INF:
		return "No river here"
	if p.level < int(needs.get("min_level", 0)):
		return "Needs a town"
	if needs.has("requires") and p.building_level(needs["requires"]) == 0:
		return "Needs %s" % defs[needs["requires"]]["name"]
	if next == 1 and not d.get("free_slot", false) and used_slots(p) >= slots(p):
		return "No free slot"
	if p.siege_army != -1:
		return "Under siege"
	var r := world.realms[p.owner]
	var cost := cost_of(id, next)
	for k in cost:
		if float(r.res.get(k, 0.0)) < float(cost[k]):
			return "Not enough %s" % k
	return ""


func start_building(p: Province, id: String) -> bool:
	if why_not(p, id) != "":
		return false
	var r := world.realms[p.owner]
	var next := p.building_level(id) + 1
	var cost := cost_of(id, next)
	for k in cost:
		r.res[k] = float(r.res[k]) - float(cost[k])
	p.build_id = id
	p.build_left = days_of(id, next)
	return true


# --- Daily tick -------------------------------------------------------------------

func tick_day() -> void:
	for r: Realm in world.realms:
		if r.alive:
			for k in RESOURCES:
				r.delta[k] = 0.0
	for p: Province in world.provinces:
		if p.owner == -1:
			continue
		var r := world.realms[p.owner]
		var y := yields(p)
		for k in y:
			r.delta[k] = float(r.delta[k]) + float(y[k])
		r.delta["food"] = float(r.delta["food"]) - p.pop * FOOD_PER_PERSON
		_construct(p, r)
	world.diplomacy.daily_trade()
	world.trade.daily()
	for r: Realm in world.realms:
		if r.alive and not r.relics.is_empty():
			r.delta["faith"] = float(r.delta["faith"]) + r.has_relic_effect("faith")
			r.delta["gold"] = float(r.delta["gold"]) + r.has_relic_effect("gold")
	for r: Realm in world.realms:
		var sage: Character = world.dynasty.ruler_of(r) if r.alive else null
		if sage != null:
			r.delta["faith"] = float(r.delta["faith"]) + sage.learning * 0.05
	for a: Army in world.armies:
		if a.dead:
			continue
		var r := world.realms[a.realm]
		r.delta["gold"] = float(r.delta["gold"]) - a.troops * SOLDIER_UPKEEP
		r.delta["food"] = float(r.delta["food"]) - a.troops * SOLDIER_FOOD
	for r: Realm in world.realms:
		if not r.alive:
			continue
		r.delta["gold"] = float(r.delta["gold"]) - admin_cost(r) - court_expenses(r)
		for k in RESOURCES:
			r.res[k] = float(r.res[k]) + float(r.delta[k])
		var was_starving := r.starving
		r.starving = float(r.res["food"]) <= 0.0
		if r.starving:
			r.res["food"] = 0.0
			if not was_starving and r.is_player:
				world.post_news("Famine! Your granaries are empty; people and soldiers are going hungry.", 2)
		var was_broke := r.broke
		r.broke = float(r.res["gold"]) < 0.0
		if r.broke:
			r.res["gold"] = maxf(float(r.res["gold"]), -300.0)
			if not was_broke and r.is_player:
				world.post_news("Your treasury is empty. Unpaid soldiers are deserting.", 2)
	for p: Province in world.provinces:
		if p.owner != -1:
			_update_people(p)
	for a: Army in world.armies:
		if a.dead:
			continue
		var r := world.realms[a.realm]
		if r.starving or r.broke:
			a.troops = int(a.troops * 0.997)
			if a.troops < 50:
				a.dead = true


func _construct(p: Province, r: Realm) -> void:
	if p.build_id == "":
		return
	p.build_left -= 0.5 if p.happiness < 30.0 else 1.0
	if p.build_left > 0.0:
		return
	var id := p.build_id
	p.build_id = ""
	p.buildings[id] = p.building_level(id) + 1
	if id == "walls":
		world.refresh_fort(p)
		world.map_changed.emit()
	if r.is_player:
		world.post_news("%s completed in %s." % [building_name(id, p.building_level(id)), p.name], 1)


func _update_people(p: Province) -> void:
	var r := world.realms[p.owner]
	# Mood drifts toward its target.
	var before := p.happiness
	if (p.id + world.day) % 5 == 0:
		p.happiness = move_toward(p.happiness, happiness_target(p), 2.0)
	if r.is_player and before >= 30.0 and p.happiness < 30.0:
		world.post_news("Riots break out in %s!" % p.name, 2)
	# Population grows when fed and content, shrinks in famine.
	if r.starving:
		p.pop *= 0.9985
	elif p.pop < pop_cap(p):
		p.pop += p.pop * 0.0003 * (0.5 + p.happiness / 100.0)
	p.pop = maxf(p.pop, 200.0)
	_update_level(p, r.is_player)
	# Deep misery can boil over.
	if p.happiness < 12.0 and r.capital != p.id and world.rng.randf() < 0.0006:
		world.peasant_revolt(p)


func init_level(p: Province) -> void:
	_update_level(p, false)


func _update_level(p: Province, announce: bool) -> void:
	var lvl := 1
	if p.pop >= CITY_POP:
		lvl = 3
	elif p.pop >= TOWN_POP:
		lvl = 2
	if lvl == p.level:
		return
	var grew := lvl > p.level
	p.level = lvl
	if p.settlement == "village" and lvl >= 2:
		p.settlement = "town"
	elif p.settlement == "town" and lvl == 1:
		p.settlement = "village"
	if world.provinces.size() > p.id:
		world.refresh_fort(p)
	if announce and grew:
		world.post_news("%s has grown into a %s." % [p.name, "city" if lvl == 3 else "town"], 1)
	world.map_changed.emit()


func _is_capital(p: Province) -> bool:
	return p.owner != -1 and world.realms[p.owner].capital == p.id


# --- Manpower & recruiting ------------------------------------------------------------

## Courts, clerks and castellans: grows faster than the realm itself.
func admin_cost(r: Realm) -> float:
	return ADMIN_COST * pow(float(r.provinces.size()), 1.35)


## A full treasury draws hangers-on: 0.2% a day of everything above 1,000 gold.
func court_expenses(r: Realm) -> float:
	return maxf(float(r.res["gold"]) - 1000.0, 0.0) * 0.002


func monthly_manpower(r: Realm) -> float:
	var m := 0.0
	for pid: int in r.provinces:
		var p := world.provinces[pid]
		m += p.pop * 0.05 * (1.0 + 0.3 * p.building_level("barracks")) * clampf(p.happiness / 55.0, 0.4, 1.3)
	return m * world.dynasty.noble_factor(r)


func manpower_cap(r: Realm) -> float:
	var m := 0.0
	for pid: int in r.provinces:
		m += world.provinces[pid].pop * 0.25
	return m


func levy_problem(r: Realm, p: Province) -> String:
	if p.owner != r.id:
		return "Not your land"
	if r.manpower < LEVY_SIZE:
		return "Need %d manpower" % LEVY_SIZE
	if float(r.res["gold"]) < LEVY_GOLD:
		return "Need %d gold" % int(LEVY_GOLD)
	return ""


func maa_problem(r: Realm, p: Province) -> String:
	if p.owner != r.id:
		return "Not your land"
	if p.building_level("barracks") == 0:
		return "Needs barracks"
	if r.manpower < MAA_SIZE:
		return "Need %d manpower" % MAA_SIZE
	if float(r.res["gold"]) < MAA_GOLD:
		return "Need %d gold" % int(MAA_GOLD)
	if float(r.res["iron"]) < MAA_IRON:
		return "Need %d iron" % int(MAA_IRON)
	return ""


func raise_levy(r: Realm, p: Province) -> bool:
	if levy_problem(r, p) != "":
		return false
	r.manpower -= LEVY_SIZE
	r.res["gold"] = float(r.res["gold"]) - LEVY_GOLD
	p.pop = maxf(p.pop - LEVY_SIZE * 0.5, 200.0)
	_add_troops(r, p, LEVY_SIZE, 1.0)
	return true


func hire_men_at_arms(r: Realm, p: Province) -> bool:
	if maa_problem(r, p) != "":
		return false
	r.manpower -= MAA_SIZE
	r.res["gold"] = float(r.res["gold"]) - MAA_GOLD
	r.res["iron"] = float(r.res["iron"]) - MAA_IRON
	_add_troops(r, p, MAA_SIZE, 1.8 + 0.25 * p.building_level("blacksmith"))
	return true


func _add_troops(r: Realm, p: Province, n: int, quality: float) -> void:
	for a: Army in world.armies_of(r.id):
		if a.province == p.id and a.path.is_empty():
			a.quality = (a.troops * a.quality + n * quality) / float(a.troops + n)
			a.troops += n
			return
	var fresh := world.spawn_army(r.id, p.id, n)
	fresh.quality = quality


# --- AI stewardship (monthly) ----------------------------------------------------------

func ai_manage(r: Realm) -> void:
	if r.provinces.is_empty():
		return
	var avg := 0.0
	for pid: int in r.provinces:
		avg += world.provinces[pid].happiness
	avg /= r.provinces.size()
	if avg < 35.0:
		r.tax = 0
	elif float(r.res["gold"]) < 30.0 and avg > 45.0:
		r.tax = 2
	else:
		r.tax = 1
	if avg < 32.0 and float(r.res["gold"]) > FESTIVAL_COST * 2.0 and r.festival_until < world.day:
		hold_festival(r)
	# Surplus gold becomes better-drilled, better-armed troops.
	if float(r.res["gold"]) > 600.0:
		for a: Army in world.armies_of(r.id):
			if a.quality < 1.8 and float(r.res["gold"]) > 500.0:
				var spend := minf(float(r.res["gold"]) - 500.0, a.troops * 0.1)
				a.quality = minf(a.quality + spend / maxf(a.troops, 1.0) * 0.5, 1.8)
				r.res["gold"] = float(r.res["gold"]) - spend
	_ai_build(r)


func hold_festival(r: Realm) -> bool:
	if float(r.res["gold"]) < FESTIVAL_COST or r.festival_until > world.day:
		return false
	r.res["gold"] = float(r.res["gold"]) - FESTIVAL_COST
	r.festival_until = world.day + FESTIVAL_DAYS
	if r.is_player:
		world.post_news("Bells ring and tables groan: a festival across your realm.", 1)
	return true


func _ai_build(r: Realm) -> void:
	var busy := 0
	for pid: int in r.provinces:
		if world.provinces[pid].build_id != "":
			busy += 1
	var limit := 1 + r.provinces.size() / 3
	if float(r.res["gold"]) > 400.0:
		limit = 2 + r.provinces.size() / 2   # a rich treasury builds on many fronts
	if busy >= limit:
		return
	var food_in := float(r.delta.get("food", 0.0))
	var gold_in := float(r.delta.get("gold", 0.0))
	var best_score := 0.0
	var best_p: Province = null
	var best_id := ""
	for pid: int in r.provinces:
		var p := world.provinces[pid]
		for id in order:
			if why_not(p, id) != "":
				continue
			var s := 0.5
			match id:
				"farm":
					s = 3.0 if food_in < 1.0 else 1.0
				"market":
					s = 2.5 if gold_in < 2.0 else 1.2
				"walls":
					s = 2.0 if not r.enemies.is_empty() else 0.4
				"barracks":
					s = 1.2
				"church", "tavern":
					s = 2.2 if p.happiness < 40.0 else 0.5
				"lumber_camp":
					s = 2.0 if float(r.res["wood"]) < 50.0 else 0.4
				"quarry":
					s = 2.0 if float(r.res["stone"]) < 50.0 else 0.4
				"mine":
					s = 1.0 if float(r.res["iron"]) < 30.0 else 0.3
				"port":
					s = 1.5
				"granary":
					s = 0.8
			s += world.rng.randf() * 0.6
			if s > best_score:
				best_score = s
				best_p = p
				best_id = id
	if best_p != null:
		start_building(best_p, best_id)
