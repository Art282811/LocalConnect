extends SceneTree
## Compiles every script in the project and reports which fail.
## Run: godot --headless --path . --script res://tests/check_scripts.gd

func _init() -> void:
	var failed := 0
	var files := _find("res://", [])
	for path in files:
		var s: Script = load(path)
		if s == null or not s.can_instantiate():
			print("FAIL ", path)
			failed += 1
	print("checked %d scripts, %d failed" % [files.size(), failed])
	quit(1 if failed > 0 else 0)


func _find(dir: String, out: Array) -> Array:
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_find(dir.path_join(sub), out)
	return out
