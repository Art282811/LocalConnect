extends Node2D
## Wires the simulation (sim/), the map views (map/) and the HUD (ui/).
## Owns selection: tapping provinces, armies, and giving march orders.

var world: World
var map_view: MapView
var labels: LabelsView
var overlay: OverlayView
var cam: CameraRig
var hud: Hud

var selected_province := -1
var selected_army := -1
var _info_kind := ""   # "", "province", "army"
var _ui_timer := 0.0


func _ready() -> void:
	map_view = MapView.new()
	add_child(map_view)
	labels = LabelsView.new()
	add_child(labels)
	overlay = OverlayView.new()
	add_child(overlay)
	overlay.font = labels.serif
	cam = CameraRig.new()
	add_child(cam)
	cam.make_current()
	cam.tapped.connect(_on_tap)
	cam.zoom_changed.connect(_on_zoom)

	hud = Hud.new()
	add_child(hud)
	hud.speed_chosen.connect(_on_speed)
	hud.steward_toggled.connect(func(on: bool) -> void: world.auto_rule = on)
	hud.spectate_pressed.connect(_on_spectate)
	hud.new_world_pressed.connect(func() -> void: _new_world(randi()))
	hud.rise_again_pressed.connect(_on_rise_again)

	randomize()
	_new_world(randi())


func _new_world(seed_value: int) -> void:
	world = World.new()
	world.setup(seed_value)
	world.news_posted.connect(_on_news)
	world.map_changed.connect(_on_map_changed)
	world.battle_fought.connect(func(pos: Vector2, troops: int) -> void: overlay.add_battle(pos, troops))
	world.player_lost.connect(_on_player_lost)
	map_view.world = world
	labels.world = world
	overlay.world = world
	_clear_selection()
	cam.setup(world.map_size)
	_on_zoom(cam.zoom.x)
	_on_map_changed()
	hud.show_spawn(true)
	hud.set_speed(0)
	hud.set_steward(false)
	hud.hide_info()


func _process(delta: float) -> void:
	world.advance(delta)
	_ui_timer += delta
	if _ui_timer >= 0.25:
		_ui_timer = 0.0
		_refresh_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			_on_speed(0 if world.speed > 0 else 1)
		KEY_1:
			_on_speed(1)
		KEY_2:
			_on_speed(2)
		KEY_3, KEY_4:
			_on_speed(4)
		KEY_ESCAPE:
			_clear_selection()
			hud.hide_info()


# --- World events -------------------------------------------------------------

func _on_news(text: String, importance: int) -> void:
	if importance >= 1:
		hud.add_news(text)


func _on_map_changed() -> void:
	map_view.queue_redraw()
	labels.queue_redraw()


func _on_player_lost() -> void:
	selected_army = -1
	overlay.selected_army = -1
	hud.set_speed(0)
	hud.show_game_over()


func _on_zoom(z: float) -> void:
	map_view.set_zoom(z)
	labels.set_zoom(z)
	overlay.zoom = z


func _on_speed(s: int) -> void:
	if world.spawn_mode:
		hud.set_speed(0)
		return
	world.speed = s
	hud.set_speed(s)


func _on_rise_again() -> void:
	world.spawn_mode = true
	world.speed = 0
	hud.set_speed(0)


func _on_spectate() -> void:
	world.spectate()
	hud.show_spawn(false)
	hud.hide_info()
	hud.set_speed(world.speed)


func _refresh_hud() -> void:
	hud.set_date(world.date_string())
	if world.player_realm != -1:
		var r := world.realms[world.player_realm]
		var text := "%s · %d provinces · %d troops" % [r.full_name(), r.provinces.size(), world.realm_troops(r)]
		if not r.enemies.is_empty():
			text += " · at war with " + _realm_list(r.enemies.keys())
		hud.set_realm_text(text)
	elif world.spawn_mode:
		hud.set_realm_text("Choose where your dynasty begins")
	else:
		var alive := 0
		for r: Realm in world.realms:
			if r.alive:
				alive += 1
		hud.set_realm_text("Watching · %d realms · %d unclaimed provinces" % [alive, world.unclaimed_count()])
	hud.refresh_log(world.news_log)
	if _info_kind == "province" and selected_province != -1:
		hud.update_info_body(_province_text(selected_province))
	elif _info_kind == "army":
		var a := world.army_by_id(selected_army)
		if a == null:
			_clear_selection()
			hud.hide_info()
		else:
			hud.update_info_body(_army_text(a))


func _realm_list(ids: Array) -> String:
	var names := PackedStringArray()
	for id in ids:
		names.append(world.realms[id].name)
	return ", ".join(names)


# --- Selection & orders ---------------------------------------------------------

func _clear_selection() -> void:
	selected_province = -1
	selected_army = -1
	_info_kind = ""
	if overlay != null:
		overlay.selected_army = -1
	if map_view != null and map_view.highlight != -1:
		map_view.highlight = -1
		map_view.queue_redraw()


func _on_tap(world_pos: Vector2, screen_pos: Vector2) -> void:
	var pid := world.province_at(world_pos)
	if world.spawn_mode:
		if pid != -1:
			_select_province(pid)
		return

	var army_id := _army_at(screen_pos)
	if army_id != -1 and army_id != selected_army:
		_select_army(army_id)
		return

	if selected_army != -1:
		var a := world.army_by_id(selected_army)
		if a != null and a.realm == world.player_realm and pid != -1 and pid != a.province:
			var days := world.order_army(selected_army, pid)
			if days >= 0:
				hud.add_news("Your army marches on %s (about %d days)." % [world.provinces[pid].name, days])
			else:
				hud.add_news("No road leads to %s. Armies cannot cross neutral realms; declare war first." % world.provinces[pid].name)
			_clear_selection()
			hud.hide_info()
			return

	if pid == -1:
		_clear_selection()
		hud.hide_info()
		return
	_select_province(pid)


func _army_at(screen_pos: Vector2) -> int:
	var best := -1
	var best_d := 30.0
	var view := cam.view_size()
	for id in overlay.positions:
		var wp: Vector2 = overlay.positions[id]
		var sp := (wp - cam.position) * cam.zoom.x + view * 0.5 + Vector2(0, -12)
		var d := sp.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = id
	return best


func _select_province(pid: int) -> void:
	_clear_selection()
	selected_province = pid
	_info_kind = "province"
	map_view.highlight = pid
	map_view.queue_redraw()
	_show_province(pid)


func _select_army(army_id: int) -> void:
	_clear_selection()
	var a := world.army_by_id(army_id)
	if a == null:
		return
	_info_kind = "army"
	selected_army = army_id
	overlay.selected_army = army_id
	var actions: Array = []
	if a.realm == world.player_realm:
		actions.append(["Halt", world.halt_army.bind(army_id)])
	hud.show_info("Army of %s" % world.realms[a.realm].name, _army_text(a), actions)


func _army_text(a: Army) -> String:
	var r := world.realms[a.realm]
	var task_names := {
		"idle": "Waiting for orders", "claim": "Claiming land", "siege": "Besieging",
		"attack": "Marching to war", "defend": "Defending", "retreat": "Retreating",
		"return": "Returning home", "order": "Marching on your orders",
	}
	var text := "[b]%d[/b] troops · general skill %d\n" % [a.troops, a.skill]
	text += "%s at %s" % [task_names.get(a.task, a.task), world.provinces[a.province].name]
	if not a.path.is_empty():
		text += " → %s" % world.provinces[a.path[a.path.size() - 1]].name
	if r.is_player:
		text += "\n[i]Tap a province to march there.[/i]"
	return text


func _show_province(pid: int) -> void:
	var p := world.provinces[pid]
	var actions: Array = []
	if world.spawn_mode:
		var label := "Found a realm here" if p.owner == -1 else "Rule the %s" % world.realms[p.owner].name
		actions.append([label, _choose_spawn.bind(pid)])
	elif world.player_realm != -1 and p.owner != -1 and p.owner != world.player_realm:
		var me := world.player_realm
		var them := p.owner
		if world.at_war(me, them):
			actions.append(["Offer peace", _act_offer_peace.bind(them, pid)])
		else:
			var truce_end: int = world.realms[me].truces.get(them, -1)
			var ok := truce_end <= world.day
			var label := "Declare war" if ok else "Truce until Y%d" % (truce_end / World.DAYS_PER_YEAR + 1)
			actions.append([label, _act_declare_war.bind(them, pid), ok])
	hud.show_info(p.name, _province_text(pid), actions)


func _act_offer_peace(them: int, pid: int) -> void:
	world.offer_peace(world.player_realm, them)
	_show_province(pid)


func _act_declare_war(them: int, pid: int) -> void:
	world.declare_war(world.player_realm, them)
	_show_province(pid)


func _province_text(pid: int) -> String:
	var p := world.provinces[pid]
	var terrain: Dictionary = World.TERRAIN[p.terrain]
	var text := "%s · %s (level %d) · %s culture\n" % [terrain["label"], p.settlement.capitalize(), p.level, p.culture.capitalize()]
	if p.owner == -1:
		text += "Unclaimed land. Any army standing here will claim it."
	else:
		var r := world.realms[p.owner]
		text += "Ruled by the [b]%s[/b]%s\n" % [r.full_name(), " (you)" if r.is_player else ""]
		text += "%d provinces · %d troops · %s ruler" % [r.provinces.size(), world.realm_troops(r), r.personality]
		if r.capital == pid:
			text += " · capital"
		if not r.enemies.is_empty():
			text += "\nAt war with " + _realm_list(r.enemies.keys())
	if p.siege_army != -1:
		var verb := "Being claimed" if p.owner == -1 else "Under siege"
		text += "\n[color=#8a2a1a]%s: %d%%[/color]" % [verb, int(p.siege_progress * 100.0)]
	return text


func _choose_spawn(pid: int) -> void:
	world.found_player_realm(pid)
	hud.show_spawn(false)
	hud.set_speed(world.speed)
	_clear_selection()
	hud.hide_info()
	cam.focus(world.provinces[pid].center, 1.0)
