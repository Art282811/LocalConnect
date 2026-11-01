class_name NameGen
extends RefCounted
## Invents culture-flavoured place names from syllables in data/names.json.

var _data: Dictionary
var _used: Dictionary = {}
var _rng: RandomNumberGenerator


func _init(data: Dictionary, rng: RandomNumberGenerator) -> void:
	_data = data
	_rng = rng


func reserve(n: String) -> void:
	_used[n] = true


func person_name(culture: String, female := false) -> String:
	var c: Dictionary = _data.get(culture, _data.get("latin", {}))
	var given: Array = c.get("given_f" if female else "given", ["Aldric"])
	return str(given[_rng.randi() % given.size()])


## A family name like "of Valtorre" — not reserved, so houses may echo places.
func house_name(culture: String) -> String:
	var c: Dictionary = _data.get(culture, _data.get("latin", {}))
	var starts: Array = c.get("start", ["Nova"])
	var ends: Array = c.get("end", ["ria"])
	return str(starts[_rng.randi() % starts.size()]) + str(ends[_rng.randi() % ends.size()])


func place_name(culture: String) -> String:
	var c: Dictionary = _data.get(culture, _data.get("latin", {}))
	var starts: Array = c.get("start", ["Nova"])
	var ends: Array = c.get("end", ["ria"])
	var n := ""
	for attempt in 60:
		n = str(starts[_rng.randi() % starts.size()]) + str(ends[_rng.randi() % ends.size()])
		if not _used.has(n):
			break
	if _used.has(n):
		var suffix := 2
		while _used.has("%s %d" % [n, suffix]):
			suffix += 1
		n = "%s %d" % [n, suffix]
	_used[n] = true
	return n
