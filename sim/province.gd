class_name Province
extends RefCounted
## One map province: a hex cell clipped to the coastline.

var id: int
var name: String = ""
var center: Vector2            # world position (px) of the main settlement
var lonlat: Vector2            # approximate real-world position
var hex: PackedVector2Array    # unclipped hex outline
var polygons: Array[PackedVector2Array] = []  # land pieces (hex clipped to coast)
var neighbors: Array[int] = []
var straits: Array[int] = []   # neighbors reached across a short stretch of sea
var edges: Array[Dictionary] = []  # {nb: int, segments: Array[PackedVector2Array]} land border pieces
var glyphs: PackedVector2Array # where terrain art is painted
var terrain: String = "plains"
var culture: String = "latin"
var coastal := false

var owner: int = -1            # realm id, -1 = unclaimed
var settlement: String = "village"  # village, town, castle, port, monastery
var level: int = 1             # 1 village, 2 town, 3 city (capital adds one)
var fort: int = 0              # defensive level used by sieges

# Layer 2: people and buildings.
var pop: float = 1500.0
var happiness: float = 55.0
var buildings: Dictionary = {} # building id -> level
var build_id: String = ""      # under construction, "" = nothing
var build_left: float = 0.0    # days of work left
var occupied_until: int = -1   # recently conquered: unhappy until this day

# Layer 4: faith.
var faith: String = "catholic"
var mission_until: int = -1    # missionaries at work until this day
var mission_faith: String = ""
var holy_site: String = ""     # e.g. "Jerusalem"
var sacred: Array = []         # faiths that hold the holy site sacred
var fief: String = ""          # noble family it is granted to


func building_level(id: String) -> int:
	return int(buildings.get(id, 0))

# Occupation in progress (claiming unclaimed land or besieging enemy land).
var siege_army: int = -1
var siege_progress: float = 0.0
