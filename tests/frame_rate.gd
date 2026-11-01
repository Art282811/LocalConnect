extends SceneTree
## Runs the real main scene without a screen and measures how many frames per
## second the game logic and drawing code can produce (CPU side).
## Run: godot --headless --path . --script res://tests/frame_rate.gd

var main: Node
var frames := 0
var t0 := 0
var phase := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	match phase:
		0:
			if frames == 5:
				main._on_play()
				main._choose_spawn(main.world.provinces[150].id)
				main._on_speed(4.0)
				main.cam.focus(main.world.provinces[150].center, 1.6)
				phase = 1
				frames = 0
				t0 = Time.get_ticks_msec()
		1:
			if Time.get_ticks_msec() - t0 > 15000:
				_report("region zoom, 4x")
				main.cam.focus(main.world.map_size * 0.5, 0.35)
				phase = 2
				frames = 0
				t0 = Time.get_ticks_msec()
		2:
			if Time.get_ticks_msec() - t0 > 15000:
				_report("whole map, 4x")
				return true
	return false


func _report(label: String) -> void:
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("%-16s %5.1f fps (CPU), day %d" % [label, frames / secs, main.world.day])
