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
var quality: float = 1.0       # 1.0 = levies; men-at-arms fight harder

# Layer 3: generals, orders and battles.
var general: String = "Aldric"
var general_trait: String = "steady"   # cautious, steady, reckless: how they fight
var stance: int = 1            # 0 cautious, 1 balanced, 2 aggressive: when to give up
var order: String = ""         # "", "take", "hold", "raid", "join", "retreat"
var join_target: int = -1
var dug_in: float = 0.0        # days spent holding: stakes after a few
var raid_days: int = 0
var came_from: int = -1        # province we marched in from (battle facing)
var battle: int = -1           # battle id while fighting
var dead := false
