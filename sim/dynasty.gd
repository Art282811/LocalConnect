class_name Dynasty
extends RefCounted
## Layer 5: the people behind the realms. Rulers age, marry, have children
## and die; succession laws pick heirs; great families scheme; generals gain
## experience and get captured; random events ask the player to choose.

const ADULT := 16
const LAWS := ["eldest_son", "eldest_child", "elective", "chosen"]
const LAW_NAMES := {"eldest_son": "Eldest son", "eldest_child": "Eldest child", "elective": "Elective", "chosen": "Chosen heir"}
const CULTURE_LAW := {"norse": "elective", "baltic": "elective", "turkic": "chosen", "arab": "chosen", "berber": "chosen"}
const BRIBE_GOLD := 50.0
const RANSOM_BASE := 40.0

var world: World
var people: Array[Character] = []
var pending_events: Array[Dictionary] = []   # for the player: {title, text, options: [[label, Callable]]}


func _init(w: World) -> void:
	world = w


func person(cid: int) -> Character:
	if cid < 0 or cid >= people.size():
		return null
	return people[cid]


func _rng() -> RandomNumberGenerator:
	return world.rng


# --- Making people ------------------------------------------------------------------------------

func make_person(realm_id: int, culture: String, house: String, female: bool, age_years: int, role := "family") -> Character:
	var c := Character.new()
	c.id = people.size()
	c.female = female
	c.name = world.names.person_name(culture, female)
	c.house = house
	c.realm = realm_id
	c.role = role
	c.born = world.day - age_years * World.DAYS_PER_YEAR - _rng().randi_range(0, World.DAYS_PER_YEAR - 1)
	c.personality = World.PERSONALITIES[_rng().randi() % World.PERSONALITIES.size()]
	c.martial = _rng().randi_range(2, 8)
	c.stewardship = _rng().randi_range(2, 8)
	c.diplomacy = _rng().randi_range(2, 8)
	c.learning = _rng().randi_range(2, 8)
	people.append(c)
	return c


func make_general(r: Realm, skill: int) -> Character:
	# Reuse an idle general of this realm if there is one.
	for c: Character in people:
		if c.alive() and c.role == "general" and c.realm == r.id and c.prisoner_of == -1 and not _commands_army(c.id):
			return c
	var c := make_person(r.id, r.culture, world.names.house_name(r.culture), _rng().randf() < 0.08, _rng().randi_range(22, 48), "general")
	c.tactics = clampi(skill + _rng().randi_range(0, 2), 0, 10)
	c.siegecraft = _rng().randi_range(0, 4)
	c.logistics = _rng().randi_range(0, 4)
	c.leadership = _rng().randi_range(0, 4)
	return c


func _commands_army(cid: int) -> bool:
	for a: Army in world.armies:
		if not a.dead and a.hero == cid:
			return true
	return false


func assign_general(a: Army) -> void:
	var c := make_general(world.realms[a.realm], a.skill)
	a.hero = c.id
	a.general = c.name
	a.skill = c.tactics


func _marry(a: Character, b: Character) -> void:
	a.spouse = b.id
	b.spouse = a.id


func _child(mother: Character, father: Character, realm_id: int, age_years: int) -> Character:
	var r := world.realms[realm_id]
	var house := father.house
	if mother.house == r.house and father.house != r.house:
		house = mother.house
	var c := make_person(realm_id, r.culture, house, _rng().randf() < 0.5, age_years)
	c.father = father.id
	c.mother = mother.id
	for k in mother.claims + father.claims:
		if not c.claims.has(k):
			c.claims.append(k)
	c.martial = clampi((mother.martial + father.martial) / 2 + _rng().randi_range(-2, 3), 0, 10)
	c.stewardship = clampi((mother.stewardship + father.stewardship) / 2 + _rng().randi_range(-2, 3), 0, 10)
	c.diplomacy = clampi((mother.diplomacy + father.diplomacy) / 2 + _rng().randi_range(-2, 3), 0, 10)
	c.learning = clampi((mother.learning + father.learning) / 2 + _rng().randi_range(-2, 3), 0, 10)
	mother.children.append(c.id)
	father.children.append(c.id)
	return c


## Gives a realm a ruling house: ruler, spouse, children, and three great families.
func setup_realm(r: Realm) -> void:
	r.house = world.names.house_name(r.culture)
	r.succession = str(CULTURE_LAW.get(r.culture, "eldest_son"))
	var ruler_age := _rng().randi_range(20, 55)
	var ruler := make_person(r.id, r.culture, r.house, _rng().randf() < 0.08, ruler_age)
	ruler.personality = r.personality
	r.ruler = ruler.id
	if ruler_age >= 20 and _rng().randf() < 0.85:
		var spouse_age := clampi(ruler_age - _rng().randi_range(-3, 8), 17, 60)
		var spouse := make_person(r.id, r.culture, world.names.house_name(r.culture), not ruler.female, spouse_age)
		_marry(ruler, spouse)
		var mother := spouse if spouse.female else ruler
		var father := ruler if mother == spouse else spouse
		var oldest := mini(ruler_age, spouse_age) - 18
		var kids := _rng().randi_range(0, clampi(oldest / 4, 0, 4))
		for i in kids:
			_child(mother, father, r.id, _rng().randi_range(0, maxi(oldest, 0)))
	r.nobles.clear()
	for i in 3:
		add_noble_family(r)


func add_noble_family(r: Realm) -> Dictionary:
	var house := world.names.house_name(r.culture)
	var head := make_person(r.id, r.culture, house, false, _rng().randi_range(28, 60), "noble")
	var fam := {"name": house, "head": head.id, "loyalty": _rng().randf_range(45.0, 65.0),
		"ambition": _rng().randf_range(20.0, 85.0), "base": _rng().randf_range(8.0, 22.0),
		"power": 0.0, "granted": [], "faction": false, "favor": 0.0}
	fam["power"] = float(fam["base"])
	r.nobles.append(fam)
	return fam


# --- Family queries ---------------------------------------------------------------------------------

func ruler_of(r: Realm) -> Character:
	return person(r.ruler)


func court(r: Realm) -> Array[Character]:
	var out: Array[Character] = []
	for c: Character in people:
		if c.alive() and c.realm == r.id and c.role == "family":
			out.append(c)
	return out


func family_of(r: Realm) -> Array[Character]:
	var out: Array[Character] = []
	for c: Character in court(r):
		if c.house == r.house:
			out.append(c)
	return out


## Primogeniture by law; `sons_only` prefers men but falls back to daughters.
func _line(r: Realm, sons_only: bool) -> int:
	var ruler := ruler_of(r)
	if ruler == null:
		return -1
	var pools: Array = []
	pools.append(_living(ruler.children))
	var grand: Array[int] = []
	for k in ruler.children:
		var kid := person(k)
		if kid != null:
			grand.append_array(kid.children)
	pools.append(_living(grand))
	var father := person(ruler.father)
	if father != null:
		pools.append(_living(father.children))
	var kin: Array[int] = []
	for c in family_of(r):
		kin.append(c.id)
	pools.append(_living(kin))
	for want_male in ([true, false] if sons_only else [false]):
		for pool in pools:
			var best: Character = null
			for cid in pool:
				var c := person(cid)
				if c.id == ruler.id or c.house != r.house or c.prisoner_of != -1:
					continue
				if want_male and c.female:
					continue
				if best == null or c.born < best.born:
					best = c
			if best != null:
				return best.id
	return -1


func _living(ids: Array) -> Array[int]:
	var out: Array[int] = []
	for cid in ids:
		var c := person(int(cid))
		if c != null and c.alive():
			out.append(c.id)
	return out


## Who would take the throne today. Elective realms report the projected winner.
func heir_of(r: Realm) -> int:
	match r.succession:
		"chosen":
			var c := person(r.chosen_heir)
			if c != null and c.alive() and c.house == r.house and c.id != r.ruler:
				return c.id
			return _line(r, false)
		"elective":
			return int(election(r)[0])
		"eldest_child":
			return _line(r, false)
	return _line(r, true)


## [winner id, votes for the house's candidate, votes for the rival, rival id]
func election(r: Realm) -> Array:
	var ours := _line(r, false)
	var rival := -1
	var rival_strength := -1.0
	for f in r.nobles:
		var s := float(f["power"]) * float(f["ambition"]) / 50.0
		if s > rival_strength:
			rival_strength = s
			rival = int(f["head"])
	var ruler := ruler_of(r)
	var for_us := 10.0 + (ruler.diplomacy * 2.0 if ruler != null else 0.0)
	var for_them := 0.0
	for f in r.nobles:
		if float(f["loyalty"]) >= 50.0:
			for_us += float(f["power"])
		else:
			for_them += float(f["power"])
	if ours == -1:
		return [rival, 0.0, for_them, rival]
	return [ours if for_us >= for_them else rival, for_us, for_them, rival]


func noble_factor(r: Realm) -> float:
	var refusing := 0
	for f in r.nobles:
		if float(f["loyalty"]) < 30.0:
			refusing += 1
	return maxf(1.0 - 0.15 * refusing, 0.4)


# --- Monthly life ----------------------------------------------------------------------------------

func monthly() -> void:
	var today := world.day
	for c: Character in people.duplicate():
		if not c.alive():
			continue
		var age := c.age(today)
		var p := 0.0008
		if age < 5:
			p = 0.003
		elif age >= 75:
			p = 0.03
		elif age >= 65:
			p = 0.012
		elif age >= 55:
			p = 0.005
		elif age >= 40:
			p = 0.002
		p *= 360.0 / World.DAYS_PER_YEAR   # same odds per year whatever the pace
		if c.health < 1.0:
			p *= 3.0
			c.health = minf(c.health + _rng().randf_range(-0.05, 0.12), 1.0)
		if _rng().randf() < p:
			die(c, "old age" if age >= 60 else "illness")
	_births()
	for r: Realm in world.realms:
		if r.alive:
			_nobles_month(r)
			_prisoners_month(r)
			_maybe_event(r)
	if today % World.DAYS_PER_YEAR == 0:
		_arrange_marriages()


func _births() -> void:
	for c: Character in people:
		if not c.alive() or not c.female or c.spouse == -1 or c.realm == -1 or c.role != "family":
			continue
		var age := c.age(world.day)
		if age < ADULT or age > 44:
			continue
		var husband := person(c.spouse)
		if husband == null or not husband.alive() or husband.prisoner_of != -1:
			continue
		var r := world.realms[c.realm]
		if not r.alive:
			continue
		if _rng().randf() < 0.025 * 360.0 / World.DAYS_PER_YEAR:
			var baby := _child(c, husband, r.id, 0)
			if r.is_player:
				world.post_news("A %s is born to %s: %s." % ["daughter" if baby.female else "son", r.house, baby.name], 1)


func die(c: Character, cause: String) -> void:
	if not c.alive():
		return
	c.died = world.day
	var spouse := person(c.spouse)
	if spouse != null:
		spouse.spouse = -1
	for r: Realm in world.realms:
		if r.prisoners.has(c.id):
			r.prisoners.erase(c.id)
	for a: Army in world.armies:
		if not a.dead and a.hero == c.id:
			a.hero = -1
			assign_general(a)
	if c.realm != -1 and c.realm < world.realms.size():
		var r := world.realms[c.realm]
		if r.alive and r.ruler == c.id:
			_succession(r, c, cause)
			return
		for f in r.nobles:
			if int(f["head"]) == c.id:
				var heir := make_person(r.id, r.culture, str(f["name"]), false, _rng().randi_range(18, 45), "noble")
				f["head"] = heir.id
		if r.is_player and c.house == r.house and c.role == "family":
			world.post_news("%s of %s has died (%s)." % [c.name, r.house, cause], 1)


# --- Succession ---------------------------------------------------------------------------------------

func _succession(r: Realm, old: Character, cause: String) -> void:
	var title := "%s %s" % ["Queen" if old.female else "King", old.name] if r.rank >= 2 else old.name
	var heir := -1
	if r.succession == "elective":
		var vote := election(r)
		heir = int(vote[0])
		if heir != -1 and r.is_player:
			world.post_news("The great families vote: %d for the house, %d for its rival." % [int(vote[1]), int(vote[2])], 2)
	else:
		heir = heir_of(r)
	if heir == -1:
		var claimant := best_claimant(r)
		if claimant != null:
			var home := claimant.realm
			if home != -1 and home != r.id and world.realms[home].alive and world.realms[home].ruler == claimant.id:
				world.post_news("%s of %s dies without an heir. %s inherits the %s by right of blood!" % [title, r.name, claimant.title_name(), r.full_name()], 2)
				var player_dynasty_lives := r.is_player and claimant.house == r.house
				world.annex_realm(r, home, player_dynasty_lives)
				return
			heir = claimant.id
	if heir == -1:
		# The strongest great family takes the crown.
		var best: Dictionary = {}
		for f in r.nobles:
			if best.is_empty() or float(f["power"]) > float(best["power"]):
				best = f
		if best.is_empty():
			heir = make_person(r.id, r.culture, world.names.house_name(r.culture), false, 35).id
		else:
			heir = int(best["head"])
			r.nobles.erase(best)
			add_noble_family(r)
	_crown(r, person(heir), "%s dies (%s)." % [title, cause])


func _crown(r: Realm, h: Character, why: String) -> void:
	var old_house := r.house
	h.realm = r.id
	h.role = "family"
	h.prisoner_of = -1
	r.ruler = h.id
	r.chosen_heir = -1
	r.personality = h.personality
	var new_house := h.house != old_house
	r.house = h.house
	var regency := h.age(world.day) < ADULT
	if regency:
		for f in r.nobles:
			f["loyalty"] = float(f["loyalty"]) - 10.0
	var text := "%s %s succeeds%s." % [why, h.title_name(), " (a child, under a regency)" if regency else ""]
	if new_house:
		text = "%s The house of %s is no more on the throne of %s; %s takes power." % [why, old_house, r.name, h.house]
	world.post_news(text, 2 if r.is_player else (1 if r.rank >= 2 else 0))
	if r.is_player and new_house:
		world.dynasty_lost.emit("The house of %s has lost the throne of %s." % [old_house, r.name], true)


func best_claimant(r: Realm) -> Character:
	var best: Character = null
	var best_score := -INF
	for c: Character in people:
		if not c.alive() or not c.claims.has(r.id) or c.prisoner_of != -1:
			continue
		var score := 0.0
		if c.realm != -1 and world.realms[c.realm].alive and world.realms[c.realm].ruler == c.id:
			score += 100.0 + world.realm_strength(world.realms[c.realm]) / 100.0
		if c.age(world.day) >= ADULT:
			score += 20.0
		score -= c.born / 10000.0
		if score > best_score:
			best_score = score
			best = c
	return best


func set_law(r: Realm, law: String) -> String:
	if not LAWS.has(law) or law == r.succession:
		return ""
	var ruler := ruler_of(r)
	if ruler == null or ruler.age(world.day) < ADULT:
		return "A child ruler cannot change the law."
	r.succession = law
	for f in r.nobles:
		f["loyalty"] = float(f["loyalty"]) - 10.0
	return "Succession is now: %s. The great families grumble." % LAW_NAMES[law]


# --- Marriage --------------------------------------------------------------------------------------

func eligible(c: Character) -> bool:
	return c != null and c.alive() and c.spouse == -1 and c.prisoner_of == -1 and c.age(world.day) >= ADULT and c.age(world.day) <= 45


## Unmarried adults of other ruling courts who could wed `c`.
func candidates_for(c: Character, limit := 8) -> Array[Character]:
	var out: Array[Character] = []
	var mine := world.realms[c.realm]
	for o: Character in people:
		if o.realm == c.realm or o.realm == -1 or o.female == c.female or not eligible(o) or o.role != "family":
			continue
		var r := world.realms[o.realm]
		if not r.alive or r.ruler == o.id and world.realms[c.realm].ruler == c.id:
			continue
		if o.house != r.house:
			continue
		out.append(o)
	out.sort_custom(func(x: Character, y: Character) -> bool: return world.diplomacy.opinion(x.realm, mine.id) > world.diplomacy.opinion(y.realm, mine.id))
	if out.size() > limit:
		out.resize(limit)
	return out


## Marry two people of different courts. The one who is not a ruler (or heir)
## moves; they keep a claim on the throne of the court they leave.
func wed(a: Character, b: Character) -> void:
	var ra := world.realms[a.realm]
	var rb := world.realms[b.realm]
	var mover := b
	var stays := a
	if ra.ruler != a.id and (rb.ruler == b.id or heir_of(rb) == b.id or (a.female and not b.female)):
		mover = a
		stays = b
	var origin := world.realms[mover.realm]
	if origin.alive and mover.house == origin.house and not mover.claims.has(origin.id):
		mover.claims.append(origin.id)
	mover.realm = stays.realm
	_marry(a, b)
	world.diplomacy.remember(ra.id, rb.id, 20.0)
	world.diplomacy.remember(rb.id, ra.id, 20.0)
	var importance := 2 if (ra.is_player or rb.is_player) else 0
	world.post_news("Royal wedding: %s of %s marries %s of %s." % [a.name, ra.name, b.name, rb.name], importance)


func propose_marriage(mine: Character, theirs: Character) -> String:
	var them := world.realms[theirs.realm]
	var me := world.realms[mine.realm]
	if not eligible(mine) or not eligible(theirs):
		return "That match is no longer possible."
	var o := world.diplomacy.opinion(them.id, me.id)
	if o < -10.0 or world.at_war(me.id, them.id):
		return "%s declines the match (opinion %d)." % [them.name, int(o)]
	wed(mine, theirs)
	return ""


func _arrange_marriages() -> void:
	for r: Realm in world.realms:
		if not r.alive or (r.is_player and not world.auto_rule) or _rng().randf() > 0.4:
			continue
		for c in family_of(r):
			if not eligible(c):
				continue
			var options := candidates_for(c, 3)
			if options.is_empty():
				continue
			var pick := options[0]
			var them := world.realms[pick.realm]
			if them.is_player:
				world.diplomacy._offer("marriage", r.id, "%s proposes that %s wed %s." % [r.full_name(), c.name, pick.name], {"theirs": c.id, "mine": pick.id})
			elif world.diplomacy.opinion(them.id, r.id) >= -10.0:
				wed(c, pick)
			break


# --- Great families -------------------------------------------------------------------------------------

func _nobles_month(r: Realm) -> void:
	var ruler := ruler_of(r)
	for f in r.nobles.duplicate():
		f["favor"] = move_toward(float(f["favor"]), 0.0, 1.0)
		var granted: Array = f["granted"]
		f["power"] = float(f["base"]) + granted.size() * 5.0
		var target := 50.0 + granted.size() * 6.0 - (float(f["ambition"]) - 50.0) / 4.0 + float(f["favor"])
		if ruler != null:
			target += (ruler.diplomacy - 5) * 3.0
			if ruler.age(world.day) < ADULT:
				target -= 10.0
		target += float([5.0, 0.0, -10.0][r.tax])
		if r.festival_until > world.day:
			target += 5.0
		f["loyalty"] = clampf(move_toward(float(f["loyalty"]), target, 2.0), 0.0, 100.0)
		var loyalty := float(f["loyalty"])
		if loyalty < 25.0 and float(f["ambition"]) > 50.0 and not f["faction"]:
			f["faction"] = true
			if r.is_player:
				world.post_news("The %s family forms a faction against you." % f["name"], 2)
		elif loyalty > 40.0:
			f["faction"] = false
		if r.is_player and loyalty < 35.0 and float(f["power"]) >= 15.0 and _rng().randf() < 0.06:
			_event_demands_title(r, f)
		if f["faction"] and loyalty < 15.0 and _rng().randf() < 0.05:
			_plot(r, f)
			return


func _plot(r: Realm, f: Dictionary) -> void:
	var rebels := 0.0
	var crown := 20.0
	var ruler := ruler_of(r)
	if ruler != null:
		crown += ruler.martial * 3.0
	for other in r.nobles:
		if other["faction"]:
			rebels += float(other["power"])
		elif float(other["loyalty"]) >= 50.0:
			crown += float(other["power"])
	var head := person(int(f["head"]))
	if rebels > crown and head != null:
		r.nobles.erase(f)
		# The fallen house becomes a bitter noble family.
		var old := {"name": r.house, "head": r.ruler, "loyalty": 15.0, "ambition": 80.0, "base": 15.0,
			"power": 15.0, "granted": [], "faction": false, "favor": 0.0}
		if ruler != null:
			ruler.role = "noble"
		_crown(r, head, "Coup in %s! The %s family seizes the crown." % [r.name, f["name"]])
		r.nobles.append(old)
		return
	var granted: Array = f["granted"]
	if granted.size() >= 1 and r.provinces.size() > granted.size() + 1 and _rng().randf() < 0.5:
		r.nobles.erase(f)
		var pids: Array[int] = []
		for pid in granted:
			if world.provinces[int(pid)].owner == r.id and int(pid) != r.capital:
				pids.append(int(pid))
		if not pids.is_empty() and head != null:
			world.secede(r, pids, head, str(f["name"]))
			add_noble_family(r)
			return
	# The plot fails.
	f["faction"] = false
	f["loyalty"] = 40.0
	f["base"] = maxf(float(f["base"]) - 8.0, 3.0)
	if head != null:
		die(head, "executed for treason")
	world.post_news("A plot by the %s family in %s is uncovered and crushed." % [f["name"], r.name], 2 if r.is_player else 0)


func grant_province(r: Realm, f: Dictionary, pid: int) -> String:
	var p := world.provinces[pid]
	if p.owner != r.id or pid == r.capital or p.fief != "":
		return "That province cannot be granted."
	(f["granted"] as Array).append(pid)
	p.fief = str(f["name"])
	f["favor"] = float(f["favor"]) + 15.0
	f["loyalty"] = minf(float(f["loyalty"]) + 10.0, 100.0)
	return "%s is granted to the %s family." % [p.name, f["name"]]


func revoke(r: Realm, f: Dictionary) -> String:
	var granted: Array = f["granted"]
	if granted.is_empty():
		return "They hold nothing to revoke."
	var pid := int(granted.pop_back())
	world.provinces[pid].fief = ""
	f["favor"] = float(f["favor"]) - 25.0
	f["loyalty"] = maxf(float(f["loyalty"]) - 15.0, 0.0)
	return "You take %s back from the %s family." % [world.provinces[pid].name, f["name"]]


func bribe(r: Realm, f: Dictionary) -> String:
	if float(r.res["gold"]) < BRIBE_GOLD:
		return "Not enough gold."
	r.res["gold"] = float(r.res["gold"]) - BRIBE_GOLD
	f["favor"] = float(f["favor"]) + 12.0
	f["loyalty"] = minf(float(f["loyalty"]) + 6.0, 100.0)
	return "The %s family accepts your generosity." % f["name"]


func marry_into(r: Realm, f: Dictionary, c: Character) -> String:
	if not eligible(c) or c.realm != r.id:
		return "They cannot marry now."
	var match_person := make_person(r.id, r.culture, str(f["name"]), not c.female, clampi(c.age(world.day) + _rng().randi_range(-4, 4), ADULT, 40))
	_marry(c, match_person)
	f["favor"] = float(f["favor"]) + 20.0
	f["loyalty"] = minf(float(f["loyalty"]) + 12.0, 100.0)
	return "%s weds %s of the %s family." % [c.name, match_person.name, f["name"]]


# --- Heroes, battles and prisoners -------------------------------------------------------------------

## After a battle: experience for the living, capture or death for the unlucky.
func after_battle(a: Army, won: bool, enemies_killed: float, captor: int) -> void:
	var c := person(a.hero)
	if c == null:
		return
	c.xp += 8.0 + enemies_killed / 80.0
	while c.xp >= c.level * 25.0:
		c.xp -= c.level * 25.0
		c.level += 1
		match _rng().randi() % 4:
			0:
				c.tactics = mini(c.tactics + 1, 10)
			1:
				c.siegecraft = mini(c.siegecraft + 1, 10)
			2:
				c.logistics = mini(c.logistics + 1, 10)
			_:
				c.leadership = mini(c.leadership + 1, 10)
		if world.realms[a.realm].is_player:
			world.post_news("Lord %s grows in renown (level %d)." % [c.name, c.level], 1)
	a.skill = c.tactics if c.role == "general" else maxi(c.martial / 2, c.tactics)
	var roll := _rng().randf()
	var r := world.realms[a.realm]
	if not won and roll < 0.06:
		die(c, "slain in battle")
		world.post_news("%s falls in battle!" % c.title_name(), 2 if r.is_player else (1 if r.ruler == c.id else 0))
	elif not won and roll < 0.18 and captor != -1:
		capture(c, captor)
		a.hero = -1
		if not a.dead:
			assign_general(a)
	elif won and roll < 0.02:
		die(c, "slain in battle")


func capture(c: Character, captor: int) -> void:
	c.prisoner_of = captor
	world.realms[captor].prisoners.append(c.id)
	var holder := world.realms[captor]
	var victim_realm: Realm = world.realms[c.realm] if c.realm != -1 else null
	var big := victim_realm != null and victim_realm.ruler == c.id
	var importance := 2 if (holder.is_player or (victim_realm != null and victim_realm.is_player)) else (1 if big else 0)
	world.post_news("%s is taken prisoner by %s!" % [c.title_name(), holder.name], importance)


func ransom_price(c: Character) -> float:
	var price := RANSOM_BASE * c.level
	if c.realm != -1 and world.realms[c.realm].ruler == c.id:
		price += 300.0
	elif c.role == "family":
		price += 120.0
	return price


func release(c: Character, ransom: bool) -> String:
	var holder: Realm = world.realms[c.prisoner_of] if c.prisoner_of != -1 else null
	if holder == null:
		return ""
	var home: Realm = world.realms[c.realm] if c.realm != -1 else null
	if ransom:
		var price := ransom_price(c)
		if home == null or not home.alive or float(home.res["gold"]) < price:
			return "They cannot pay the ransom."
		home.res["gold"] = float(home.res["gold"]) - price
		holder.res["gold"] = float(holder.res["gold"]) + price
	elif home != null and home.alive:
		world.diplomacy.remember(home.id, holder.id, 10.0)
	holder.prisoners.erase(c.id)
	c.prisoner_of = -1
	return "%s goes home%s." % [c.name, " for %d gold" % int(ransom_price(c)) if ransom else ""]


func execute(c: Character) -> String:
	var holder: Realm = world.realms[c.prisoner_of] if c.prisoner_of != -1 else null
	if holder == null:
		return ""
	if c.realm != -1 and world.realms[c.realm].alive:
		world.diplomacy.remember(c.realm, holder.id, -40.0)
	holder.oathbreaker = minf(holder.oathbreaker + 8.0, 60.0)
	die(c, "executed")
	return "%s is put to death. The other courts are appalled." % c.name


func _prisoners_month(holder: Realm) -> void:
	for cid in holder.prisoners.duplicate():
		var c := person(cid)
		if c == null or not c.alive():
			holder.prisoners.erase(cid)
			continue
		var home: Realm = world.realms[c.realm] if c.realm != -1 else null
		if home == null or not home.alive:
			continue
		if holder.is_player:
			continue  # the player decides in the Dynasty panel
		if home.is_player:
			if _rng().randf() < 0.15:
				_event_ransom(home, holder, c)
			continue
		if float(home.res["gold"]) >= ransom_price(c) and _rng().randf() < 0.4:
			release(c, true)
		elif holder.personality == "cruel" and _rng().randf() < 0.03:
			execute(c)


# --- Events ------------------------------------------------------------------------------------------------

func _maybe_event(r: Realm) -> void:
	var chance := 0.1 if r.is_player else 0.03
	if _rng().randf() > chance or r.provinces.is_empty():
		return
	var kinds := ["plague", "bad_harvest", "bumper", "mercenaries", "relic", "merchant", "comet", "insult", "knight", "prodigy", "illness"]
	var kind: String = kinds[_rng().randi() % kinds.size()]
	if not r.is_player:
		_ai_event(r, kind)
		return
	if pending_events.size() >= 3:
		return
	match kind:
		"plague":
			var p := world.provinces[r.provinces[_rng().randi() % r.provinces.size()]]
			_push("Plague in %s" % p.name, "Sickness spreads through %s. The people beg for help." % p.name, [
				["Quarantine the town (−25 gold)", _ev_plague.bind(p.id, "quarantine")],
				["Pray for deliverance (−20 faith)", _ev_plague.bind(p.id, "pray")],
				["Do nothing", _ev_plague.bind(p.id, "nothing")]])
		"bad_harvest":
			_push("A bad harvest", "Rain rots the grain in the fields. The granaries will be thin this year.", [
				["Open the treasury to buy grain (−40 gold)", _ev_res.bind(r.id, {"gold": -40.0, "food": -40.0}, "")],
				["Let them tighten their belts", _ev_res.bind(r.id, {"food": -150.0}, "mood-5")]])
		"bumper":
			_push("A bumper harvest", "The barns overflow and the people sing in the fields.", [
				["Praise be", _ev_res.bind(r.id, {"food": 200.0}, "mood+5")]])
		"mercenaries":
			_push("Wandering mercenaries", "A company of hardened sellswords offers its swords: 600 veterans.", [
				["Hire them (−120 gold)", _ev_mercs.bind(r.id)],
				["Send them on their way", _ev_res.bind(r.id, {}, "")]])
		"relic":
			_push("A relic is found", "Monks unearth bones they swear belong to a saint.", [
				["Enshrine it (+60 faith)", _ev_res.bind(r.id, {"faith": 60.0}, "")],
				["Sell it to a pilgrim (+80 gold)", _ev_res.bind(r.id, {"gold": 80.0}, "")]])
		"merchant":
			_push("A travelling merchant", "A merchant with laden mules arrives at court.", [
				["Buy iron (−40 gold, +30 iron)", _ev_res.bind(r.id, {"gold": -40.0, "iron": 30.0}, "")],
				["Buy timber and stone (−40 gold, +40 each)", _ev_res.bind(r.id, {"gold": -40.0, "wood": 40.0, "stone": 40.0}, "")],
				["No, thank you", _ev_res.bind(r.id, {}, "")]])
		"comet":
			_push("A comet in the sky", "A fiery star crosses the heavens. The people wonder what it means.", [
				["Hold prayers: a good omen (−20 faith)", _ev_res.bind(r.id, {"faith": -20.0}, "mood+5")],
				["Ignore it", _ev_res.bind(r.id, {}, "mood-5")]])
		"insult":
			var foe := _worst_neighbour(r)
			if foe == -1:
				return
			_push("An insult from %s" % world.realms[foe].name, "The ruler of %s mocks you before the envoys of Europe." % world.realms[foe].name, [
				["Demand an apology", _ev_insult.bind(r.id, foe, "demand")],
				["Swallow your pride", _ev_insult.bind(r.id, foe, "swallow")],
				["Declare war!", _ev_insult.bind(r.id, foe, "war")]])
		"knight":
			_push("A famous knight", "A renowned knight asks to serve under your banner.", [
				["Take him into service (−40 gold)", _ev_knight.bind(r.id)],
				["Turn him away", _ev_res.bind(r.id, {}, "")]])
		"prodigy":
			var kid := _youngest_child(r)
			if kid == null:
				return
			_push("A child prodigy", "%s astonishes the tutors with a quick mind." % kid.name, [
				["Wonderful", _ev_prodigy.bind(kid.id)]])
		"illness":
			var ruler := ruler_of(r)
			if ruler == null:
				return
			ruler.health = 0.6
			_push("The ruler falls ill", "%s is struck by fever." % ruler.name, [
				["Summon physicians (−30 gold)", _ev_ill.bind(ruler.id, r.id, true)],
				["Trust in God", _ev_ill.bind(ruler.id, r.id, false)]])


func _push(title: String, text: String, options: Array) -> void:
	pending_events.append({"title": title, "text": text, "options": options})


func _ai_event(r: Realm, kind: String) -> void:
	match kind:
		"plague":
			var p := world.provinces[r.provinces[_rng().randi() % r.provinces.size()]]
			_spread_plague(p, 0.5)
		"bad_harvest":
			r.res["food"] = maxf(float(r.res["food"]) - 150.0, 0.0)
		"bumper":
			r.res["food"] = float(r.res["food"]) + 200.0
		"relic":
			r.res["faith"] = float(r.res["faith"]) + 60.0
		"illness":
			var ruler := ruler_of(r)
			if ruler != null:
				ruler.health = 0.6


func _spread_plague(p: Province, spread_chance: float) -> void:
	p.pop *= 0.85
	p.happiness = maxf(p.happiness - 15.0, 0.0)
	for nb: int in p.neighbors:
		if _rng().randf() < spread_chance * 0.4:
			var q := world.provinces[nb]
			q.pop *= 0.92
			q.happiness = maxf(q.happiness - 8.0, 0.0)


func _ev_plague(pid: int, choice: String) -> void:
	var p := world.provinces[pid]
	var r: Realm = world.realms[p.owner] if p.owner != -1 else null
	match choice:
		"quarantine":
			if r != null:
				r.res["gold"] = float(r.res["gold"]) - 25.0
			p.pop *= 0.93
		"pray":
			if r != null:
				r.res["faith"] = float(r.res["faith"]) - 20.0
			p.pop *= 0.9
			_spread_plague(p, 0.3)
			p.pop /= 0.85
		_:
			_spread_plague(p, 1.0)


func _ev_res(rid: int, changes: Dictionary, mood: String) -> void:
	var r := world.realms[rid]
	for k in changes:
		r.res[k] = maxf(float(r.res.get(k, 0.0)) + float(changes[k]), 0.0 if k == "food" else -300.0)
	if mood != "":
		var amount := 5.0 if mood == "mood+5" else -5.0
		for pid: int in r.provinces:
			var p := world.provinces[pid]
			p.happiness = clampf(p.happiness + amount, 0.0, 100.0)


func _ev_mercs(rid: int) -> void:
	var r := world.realms[rid]
	if float(r.res["gold"]) < 120.0:
		world.post_news("You cannot afford the mercenaries.", 2)
		return
	r.res["gold"] = float(r.res["gold"]) - 120.0
	var a := world.spawn_army(r.id, r.capital, 600)
	a.quality = 1.5
	world.post_news("Lord %s's company of mercenaries joins your cause." % a.general, 1)


func _ev_insult(rid: int, foe: int, choice: String) -> void:
	var r := world.realms[rid]
	match choice:
		"demand":
			world.diplomacy.remember(foe, rid, -10.0)
			for f in r.nobles:
				f["favor"] = float(f["favor"]) + 5.0
		"swallow":
			for f in r.nobles:
				f["favor"] = float(f["favor"]) - 5.0
		"war":
			world.declare_war(rid, foe)


func _ev_knight(rid: int) -> void:
	var r := world.realms[rid]
	if float(r.res["gold"]) < 40.0:
		return
	r.res["gold"] = float(r.res["gold"]) - 40.0
	var c := make_person(r.id, r.culture, world.names.house_name(r.culture), false, _rng().randi_range(25, 40), "general")
	c.tactics = _rng().randi_range(6, 9)
	c.leadership = _rng().randi_range(4, 7)
	c.level = 3
	var best: Army = null
	for a: Army in world.armies_of(r.id):
		if a.battle == -1 and (best == null or a.troops > best.troops) and person(a.hero) != null and person(a.hero).role == "general":
			best = a
	if best != null:
		best.hero = c.id
		best.general = c.name
		best.skill = c.tactics
		world.post_news("Sir %s now leads your largest army." % c.name, 1)


func _ev_prodigy(cid: int) -> void:
	var c := person(cid)
	if c != null:
		c.learning = mini(c.learning + 3, 10)
		c.diplomacy = mini(c.diplomacy + 2, 10)


func _ev_ill(cid: int, rid: int, physicians: bool) -> void:
	var c := person(cid)
	if c == null:
		return
	if physicians:
		var r := world.realms[rid]
		r.res["gold"] = float(r.res["gold"]) - 30.0
		c.health = 0.85 if _rng().randf() < 0.75 else 0.5
	else:
		c.health = 0.75 if _rng().randf() < 0.5 else 0.45


func _event_demands_title(r: Realm, f: Dictionary) -> void:
	var options: Array = []
	for pid: int in r.provinces:
		if pid != r.capital and world.provinces[pid].fief == "":
			options.append(["Grant them %s" % world.provinces[pid].name, _ev_grant.bind(r.id, str(f["name"]), pid)])
			break
	options.append(["Refuse", _ev_refuse.bind(r.id, str(f["name"]))])
	_push("The %s family demands a title" % f["name"], "Lord %s of the %s family demands lands worthy of his name." % [person(int(f["head"])).name, f["name"]], options)


func _family(r: Realm, fam_name: String) -> Dictionary:
	for f in r.nobles:
		if f["name"] == fam_name:
			return f
	return {}


func _ev_grant(rid: int, fam_name: String, pid: int) -> void:
	var r := world.realms[rid]
	var f := _family(r, fam_name)
	if not f.is_empty():
		world.post_news(grant_province(r, f, pid), 1)


func _ev_refuse(rid: int, fam_name: String) -> void:
	var f := _family(world.realms[rid], fam_name)
	if not f.is_empty():
		f["favor"] = float(f["favor"]) - 15.0


func _event_ransom(home: Realm, holder: Realm, c: Character) -> void:
	var price := ransom_price(c)
	_push("Ransom for %s" % c.name, "%s holds %s and asks %d gold for their return." % [holder.full_name(), c.title_name(), int(price)], [
		["Pay the ransom (−%d gold)" % int(price), _ev_pay_ransom.bind(c.id)],
		["Refuse", _ev_res.bind(home.id, {}, "")]])


func _ev_pay_ransom(cid: int) -> void:
	var c := person(cid)
	if c != null:
		var result := release(c, true)
		if result != "":
			world.post_news(result, 1)


func _worst_neighbour(r: Realm) -> int:
	var worst := -1
	var worst_o := INF
	for other in world.neighbor_realms(r):
		var o := world.diplomacy.opinion(other, r.id)
		if o < worst_o:
			worst_o = o
			worst = other
	return worst


func _youngest_child(r: Realm) -> Character:
	var ruler := ruler_of(r)
	if ruler == null:
		return null
	var best: Character = null
	for cid in ruler.children:
		var c := person(cid)
		if c != null and c.alive() and c.age(world.day) < ADULT and (best == null or c.born > best.born):
			best = c
	return best
