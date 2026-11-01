class_name Character
extends RefCounted
## A person: rulers, their families, generals and the heads of noble houses.

var id: int
var name: String
var house: String = ""
var female := false
var born: int = 0              # game day of birth (can be negative)
var died: int = -1
var realm: int = -1            # court they live at
var father: int = -1
var mother: int = -1
var spouse: int = -1
var children: Array[int] = []
var claims: Array[int] = []    # realms they could inherit
var personality: String = "cautious"
var health: float = 1.0        # below 1.0 = ill
# Ruler skills (0-10).
var martial: int = 4
var stewardship: int = 4
var diplomacy: int = 4
var learning: int = 4
# General skills (0-10) and experience.
var tactics: int = 1
var siegecraft: int = 1
var logistics: int = 1
var leadership: int = 1
var xp: float = 0.0
var level: int = 1
var prisoner_of: int = -1      # realm holding them
var role: String = "family"    # family, general, noble


func alive() -> bool:
	return died == -1


func age(today: int) -> int:
	return int(floor(float(today - born) / 360.0))


func title_name() -> String:
	return "%s %s" % [name, house] if house != "" else name
