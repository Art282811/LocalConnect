class_name Regiment
extends RefCounted
## One block of soldiers inside a battle. Battles fight with these;
## when you zoom in they are drawn as individual stick figures.

var id: int
var side: int
var army: int                  # army id, -1 for a town garrison
var kind: String = "spear"     # spear, sword, archer, cavalry, horse_archer
var men: float = 100.0
var start_men: float = 100.0
var quality: float = 1.0
var pos := Vector2.ZERO
var facing := Vector2.RIGHT    # unit vector toward the enemy
var goal := Vector2.ZERO
var morale: float = 70.0
var base_morale: float = 70.0
var formation: String = "line" # line, wedge, square
var stance: String = "charge"  # hold, charge, skirmish (used under your command)
var target: int = -1
var order_pos := Vector2.INF   # your move order
var order_target: int = -1     # your attack order
var routed := false
var rallied := false
var escaped := false
var engaged := false
var moving := false
var ammo: float = 40.0         # seconds of shooting
var firing_at: int = -1
var charge_ready := true
var travelled: float = 0.0
var stakes := false
var hidden := false
var lost_since_corpse: float = 0.0


func alive() -> bool:
	return men >= 1.0 and not escaped


func active() -> bool:
	return alive() and not routed


func is_cavalry() -> bool:
	return kind == "cavalry" or kind == "horse_archer"


func is_ranged() -> bool:
	return kind == "archer" or kind == "horse_archer"


## Block size in world pixels: width along the front, depth front-to-back.
func dims() -> Vector2:
	var s := sqrt(maxf(men, 1.0)) * 0.5 + 2.0
	match formation:
		"wedge":
			return Vector2(s * 1.1, s * 1.0)
		"square":
			return Vector2(s * 1.0, s * 1.0)
	return Vector2(s * 1.6, s * (0.75 if is_cavalry() else 0.6))


func radius() -> float:
	var d := dims()
	return maxf(d.x, d.y) * 0.5
