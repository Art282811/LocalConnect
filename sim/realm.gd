class_name Realm
extends RefCounted
## A kingdom, AI or player run. Same rules for both.

const RANK_TITLES := {
	"default": ["County", "Duchy", "Kingdom", "Empire"],
	"latin": ["County", "Duchy", "Kingdom", "Empire"],
	"norse": ["Jarldom", "Duchy", "Kingdom", "Empire"],
	"slavic": ["County", "Principality", "Kingdom", "Tsardom"],
	"baltic": ["County", "Principality", "Kingdom", "Empire"],
	"greek": ["Theme", "Despotate", "Kingdom", "Empire"],
	"turkic": ["Beylik", "Khanate", "Sultanate", "Great Khanate"],
	"arab": ["Sheikhdom", "Emirate", "Sultanate", "Caliphate"],
	"berber": ["Sheikhdom", "Emirate", "Sultanate", "Caliphate"],
}

var id: int
var name: String
var culture: String
var hue: float
var personality: String = "cautious"
var capital: int = -1
var provinces: Array[int] = []
var alive := true
var is_player := false
var manpower: float = 0.0
var rank: int = 0
var founded_day: int = 0
var enemies: Dictionary = {}   # realm id -> true while at war
var truces: Dictionary = {}    # realm id -> day the truce ends
var peace_refused_until: int = 0

# Layer 2: the treasury.
var res: Dictionary = {"food": 600.0, "gold": 120.0, "wood": 60.0, "stone": 40.0, "iron": 10.0, "faith": 0.0}
var delta: Dictionary = {}     # yesterday's change per resource, for the HUD
var tax: int = 1               # 0 low, 1 normal, 2 high
var festival_until: int = -1
var starving := false
var broke := false

# Layer 4: faith, standing and treaties.
var faith: String = "catholic"
var excommunicated := false
var liege: int = -1            # realm this one is a vassal of
var glory_until: int = -1      # crusader glory: happier people
var relics: Array[String] = []
var memories: Dictionary = {}  # other realm id -> opinion from events (decays)
var oathbreaker: float = 0.0   # opinion penalty everyone applies (decays)

# Layer 5: the ruling house and the great families.
var ruler: int = -1            # character id
var house: String = ""         # ruling dynasty
var succession: String = "eldest_son"  # eldest_son, eldest_child, elective, chosen
var chosen_heir: int = -1
var nobles: Array[Dictionary] = []      # {name, head, loyalty, ambition, power, granted: Array[int], faction}
var prisoners: Array[int] = []          # characters held at this court


func has_relic_effect(effect: String) -> int:
	var n := 0
	for r in relics:
		if Religion.relic_effect(r) == effect:
			n += 1
	return n


static func rank_for_size(n: int) -> int:
	if n >= 16:
		return 3
	if n >= 7:
		return 2
	if n >= 3:
		return 1
	return 0


func title() -> String:
	var titles: Array = RANK_TITLES.get(culture, RANK_TITLES["default"])
	return titles[rank]


func full_name() -> String:
	return "%s of %s" % [title(), name]


## Small realms read as muted earth tones; big ones get stronger colours.
func color() -> Color:
	var t := clampf((provinces.size() - 1) / 15.0, 0.0, 1.0)
	return Color.from_hsv(hue, lerpf(0.24, 0.66, t), lerpf(0.80, 0.62, t))


func border_color() -> Color:
	return color().darkened(0.45)
