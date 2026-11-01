extends SceneTree
## Zooms into a town and a battle-free map and reports any shape the renderer
## would reject. Run: godot --headless --path . --script res://tests/tri_test.gd
var main: Node
var frames := 0
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Figures.debug_bad = true
func _process(_d: float) -> bool:
	frames += 1
	if frames == 5:
		main._on_play()
		main._choose_spawn(main.world.provinces[150].id)
		main.cam.focus(main.world.provinces[150].center, 6.0)
	if frames == 60:
		main.cam.focus(main.world.provinces[150].center, 2.2)
	return frames > 120
