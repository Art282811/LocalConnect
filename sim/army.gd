class_name Army
extends RefCounted
## An army token on the campaign map. Layer 1 tracks a single troop count;
## regiments and generals arrive with Layer 3.

var id: int
var realm: int
var troops: int
var province: int
var path: Array[int] = []      # provinces still to walk through, next first
var progress: float = 0.0      # 0..1 along the edge to path[0]
var task: String = "idle"      # idle, claim, attack, defend, retreat, order
var manual := false            # player order in progress; AI leaves it alone
var skill: int = 1
var dead := false
