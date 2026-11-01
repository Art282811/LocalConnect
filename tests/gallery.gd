extends Node2D
## Art check: draws the soldier figures large. Open the web build with ?gallery.

var t := 0.0


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.62, 0.74, 0.86))
	var k := 7.0
	var white := Color(0.96, 0.96, 0.94)
	var red := Color(0.78, 0.12, 0.1)
	Figures.footman(self, Vector2(150, 330), k, 1.0, {"surcoat": white, "emblem": red, "helm": "great", "weapon": "sword"})
	Figures.footman(self, Vector2(330, 330), k, 1.0, {"surcoat": white, "emblem": red, "helm": "nasal", "weapon": "spear", "moving": true, "phase": t * 6.0})
	Figures.footman(self, Vector2(510, 330), k, 1.0, {"surcoat": white, "emblem": red, "helm": "kettle", "weapon": "bow"})
	Figures.footman(self, Vector2(690, 330), k, 1.0, {"surcoat": Color(0.75, 0.82, 0.95), "emblem": Color(0.2, 0.3, 0.6), "helm": "great", "weapon": "sword", "fighting": true, "phase": t * 6.0})
	Figures.footman(self, Vector2(870, 330), k, -1.0, {"surcoat": Color(0.95, 0.85, 0.7), "cross": false, "helm": "nasal", "weapon": "spear", "fighting": true, "phase": t * 6.0})
	Figures.rider(self, Vector2(300, 640), k * 0.85, 1.0, {"surcoat": white, "emblem": red, "pennant": red, "moving": true, "phase": t * 6.0})
	Figures.rider(self, Vector2(800, 640), k * 0.85, -1.0, {"surcoat": Color(0.85, 0.9, 0.75), "cross": false, "pennant": Color(0.3, 0.5, 0.2), "horse": Color(0.3, 0.24, 0.2)})
	Figures.fallen(self, Vector2(1100, 330), k, 1.0, white)
