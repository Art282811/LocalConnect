class_name SaveGame
extends RefCounted
## Saves the world as a JSON snapshot. The map itself is rebuilt from the
## world's seed on load; everything that changes during play is stored.
## Battles in progress are not saved: the armies simply meet again.

const SLOT := "user://save.json"
const AUTOSAVE := "user://autosave.json"
const VERSION := 1
const PROVINCE_FIELDS := ["name", "owner", "settlement", "level", "fort", "pop", "happiness", "buildings",
	"build_id", "build_left", "occupied_until", "faith", "mission_until", "mission_faith", "fief",
	"siege_army", "siege_progress"]


static func exists(path: String = SLOT) -> bool:
	return FileAccess.file_exists(path)


static func newest() -> String:
	var a := FileAccess.get_modified_time(SLOT) if exists(SLOT) else 0
	var b := FileAccess.get_modified_time(AUTOSAVE) if exists(AUTOSAVE) else 0
	if a == 0 and b == 0:
		return ""
	return SLOT if a >= b else AUTOSAVE


# --- Saving ------------------------------------------------------------------------------------------

static func save(w: World, path: String = SLOT) -> bool:
	var d := {
		"version": VERSION, "seed": w.world_seed, "year_days": World.DAYS_PER_YEAR, "rng": str(w.rng.state), "day": w.day,
		"player_realm": w.player_realm, "auto_rule": w.auto_rule,
		"next_army": w._next_army_id, "next_battle": w._next_battle_id,
		"news": w.news_log.slice(maxi(w.news_log.size() - 120, 0)),
		"wars": w.wars,
		"provinces": [], "realms": [], "armies": [], "people": [],
		"treaties": w.diplomacy.treaties, "routes": w.diplomacy.routes, "offers": w.diplomacy.offers,
		"cooldown": w.diplomacy._cooldown, "next_offer": w.diplomacy._next_offer,
		"grand_routes": w.trade.routes, "next_route": w.trade._next,
		"head_mem": w.religion.head_mem, "crusades": w.religion.crusades, "next_crusade": w.religion._next_crusade,
	}
	for p: Province in w.provinces:
		var pd := {}
		for f in PROVINCE_FIELDS:
			pd[f] = p.get(f)
		d["provinces"].append(pd)
	for r: Realm in w.realms:
		d["realms"].append(_dump(r))
	for a: Army in w.armies:
		if not a.dead:
			d["armies"].append(_dump(a))
	for c: Character in w.dynasty.people:
		d["people"].append(_dump(c))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(d))
	return true


## Every script variable of an object, as plain JSON-friendly values.
static func _dump(obj: Object) -> Dictionary:
	var out := {}
	for prop in obj.get_property_list():
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var v: Variant = obj.get(prop["name"])
		match typeof(v):
			TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_VECTOR2, TYPE_PACKED_VECTOR2_ARRAY:
				continue
		out[prop["name"]] = v
	return out


# --- Loading -------------------------------------------------------------------------------------------

static func load_world(path: String = SLOT) -> World:
	if not exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("Save file is damaged: %s" % path)
		return null
	var d: Dictionary = _fix(parsed)
	World.set_year_length(int(d.get("year_days", 360)))
	var w := World.new()
	w.setup(int(d["seed"]))
	w.day = int(d["day"])
	w.rng.state = int(str(d["rng"]))
	w.player_realm = int(d["player_realm"])
	w.auto_rule = bool(d["auto_rule"])
	w.spawn_mode = false
	w.speed = 0.0
	w._next_army_id = int(d["next_army"])
	w._next_battle_id = int(d["next_battle"])
	w.news_log.clear()
	for line in d.get("news", []):
		w.news_log.append(str(line))
	w.wars.clear()
	for war in d.get("wars", []):
		w.wars.append(war)

	var pdata: Array = d["provinces"]
	for i in mini(pdata.size(), w.provinces.size()):
		var p := w.provinces[i]
		var pd: Dictionary = pdata[i]
		for f in PROVINCE_FIELDS:
			if pd.has(f):
				_assign(p, f, pd[f])
	w.realms.clear()
	for rd in d["realms"]:
		var r := Realm.new()
		_apply(r, rd)
		w.realms.append(r)
	w.armies.clear()
	for ad in d["armies"]:
		var a := Army.new()
		_apply(a, ad)
		a.battle = -1
		w.armies.append(a)
	w.dynasty.people.clear()
	for cd in d["people"]:
		var c := Character.new()
		_apply(c, cd)
		w.dynasty.people.append(c)
	w.battles.clear()
	w.dynasty.pending_events.clear()
	w.diplomacy.treaties.clear()
	for t in d.get("treaties", []):
		w.diplomacy.treaties.append(t)
	w.diplomacy.routes.clear()
	for rt in d.get("routes", []):
		w.diplomacy.routes.append(rt)
	w.diplomacy.offers.clear()
	for o in d.get("offers", []):
		w.diplomacy.offers.append(o)
	w.diplomacy._cooldown = d.get("cooldown", {})
	w.diplomacy._next_offer = int(d.get("next_offer", 0))
	var hm: Dictionary = d.get("head_mem", {})
	for f in w.religion.head_mem.keys():
		w.religion.head_mem[f] = hm.get(f, {})
	w.religion.crusades.clear()
	for c in d.get("crusades", []):
		w.religion.crusades.append(c)
	w.religion._next_crusade = int(d.get("next_crusade", 0))
	w.trade.routes.clear()
	for gr in d.get("grand_routes", []):
		w.trade.routes.append(gr)
	w.trade._next = int(d.get("next_route", 0))
	for p: Province in w.provinces:
		w.refresh_fort(p)
	return w


## Copy saved values into an object, converting JSON numbers back to the
## right types and refilling typed arrays in place.
static func _apply(obj: Object, data: Dictionary) -> void:
	for key in data:
		_assign(obj, str(key), data[key])


static func _assign(obj: Object, field: String, value: Variant) -> void:
	var current: Variant = obj.get(field)
	match typeof(current):
		TYPE_NIL:
			return
		TYPE_INT:
			obj.set(field, int(value))
		TYPE_FLOAT:
			obj.set(field, float(value))
		TYPE_BOOL:
			obj.set(field, bool(value))
		TYPE_STRING:
			obj.set(field, str(value))
		TYPE_ARRAY:
			var arr: Array = current
			arr.clear()
			var kind := arr.get_typed_builtin()
			for e in value:
				match kind:
					TYPE_INT:
						arr.append(int(e))
					TYPE_FLOAT:
						arr.append(float(e))
					TYPE_STRING:
						arr.append(str(e))
					_:
						arr.append(e)
		TYPE_DICTIONARY:
			var dict: Dictionary = current
			dict.clear()
			if value is Dictionary:
				dict.merge(value)
		_:
			obj.set(field, value)


## JSON turns integer dictionary keys into strings; turn them back.
static func _fix(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			var key: Variant = k
			if k is String and (k as String).is_valid_int():
				key = int(k)
			out[key] = _fix(v[k])
		return out
	if v is Array:
		var arr := []
		for e in v:
			arr.append(_fix(e))
		return arr
	return v
