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
var _info_kind := ""   # "", "province", "army", "build", "realm"
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
	hud.realm_pressed.connect(_show_realm)

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
		hud.set_resources(_resource_bar(r))
	elif world.spawn_mode:
		hud.set_realm_text("Choose where your dynasty begins")
	else:
		var alive := 0
		for r: Realm in world.realms:
			if r.alive:
				alive += 1
		hud.set_realm_text("Watching · %d realms · %d unclaimed provinces" % [alive, world.unclaimed_count()])
	if world.player_realm == -1:
		hud.set_resources("")
	hud.refresh_log(world.news_log)
	if _info_kind == "province" and selected_province != -1:
		hud.update_info_body(_province_text(selected_province))
	elif _info_kind == "build" and selected_province != -1:
		hud.update_info_body(_build_text(selected_province))
	elif _info_kind == "realm":
		if world.player_realm == -1:
			_info_kind = ""
			hud.hide_info()
		else:
			hud.update_info_body(_realm_text(world.realms[world.player_realm]))
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
	elif world.player_realm != -1 and p.owner == world.player_realm:
		var r := world.realms[p.owner]
		var eco := world.economy
		actions.append(["Build…", _show_build_menu.bind(pid), p.build_id == ""])
		var levy := eco.levy_problem(r, p)
		actions.append(["Raise levy (%d men, %dg)" % [Economy.LEVY_SIZE, int(Economy.LEVY_GOLD)] if levy == "" else "Levy: " + levy, _act_levy.bind(pid), levy == ""])
		if p.building_level("barracks") > 0:
			var maa := eco.maa_problem(r, p)
			actions.append(["Men-at-arms (%d, %dg %d iron)" % [Economy.MAA_SIZE, int(Economy.MAA_GOLD), int(Economy.MAA_IRON)] if maa == "" else "Men-at-arms: " + maa, _act_maa.bind(pid), maa == ""])
	hud.show_info(p.name, _province_text(pid), actions)


func _act_levy(pid: int) -> void:
	if world.economy.raise_levy(world.realms[world.player_realm], world.provinces[pid]):
		hud.add_news("Levies gather at %s." % world.provinces[pid].name)
	_show_province(pid)


func _act_maa(pid: int) -> void:
	if world.economy.hire_men_at_arms(world.realms[world.player_realm], world.provinces[pid]):
		hud.add_news("Men-at-arms take service at %s." % world.provinces[pid].name)
	_show_province(pid)


# --- Building ------------------------------------------------------------------

const RES_SHORT := {"food": "f", "gold": "g", "wood": "w", "stone": "s", "iron": " iron", "faith": " faith"}


func _short_cost(cost: Dictionary) -> String:
	var bits := PackedStringArray()
	for k in Economy.RESOURCES:
		if cost.has(k):
			bits.append("%d%s" % [int(cost[k]), RES_SHORT[k]])
	return " ".join(bits)


func _show_build_menu(pid: int) -> void:
	_info_kind = "build"
	selected_province = pid
	var p := world.provinces[pid]
	var eco := world.economy
	var actions: Array = []
	for id in eco.order:
		var reason := eco.why_not(p, id)
		if reason in ["Fully built", "Wrong terrain", "Needs a coast"]:
			continue
		var next := p.building_level(id) + 1
		var label := "%s · %s" % [eco.building_name(id, next), _short_cost(eco.cost_of(id, next))]
		actions.append([label, _act_build.bind(pid, id), reason == ""])
	actions.append(["Back", _show_province.bind(pid)])
	hud.show_info("Build in %s" % p.name, _build_text(pid), actions)


func _build_text(pid: int) -> String:
	var p := world.provinces[pid]
	var eco := world.economy
	var text := "Slots used: %d / %d" % [eco.used_slots(p), eco.slots(p)]
	if p.build_id != "":
		text += " · building %s, %d days left" % [eco.building_name(p.build_id, p.building_level(p.build_id) + 1), ceili(p.build_left)]
	for id in eco.order:
		var reason := eco.why_not(p, id)
		if reason in ["Wrong terrain", "Needs a coast"]:
			continue
		var next := p.building_level(id) + 1
		var line := "\n[b]%s[/b]: %s" % [eco.building_name(id, mini(next, int(eco.defs[id]["max"]))), eco.defs[id]["desc"]]
		if reason == "Fully built":
			line += " [i](done)[/i]"
		elif reason != "":
			line += " [color=#8a2a1a](%s)[/color]" % reason
		else:
			line += " · %d days" % int(eco.days_of(id, next))
		text += line
	return text


func _act_build(pid: int, id: String) -> void:
	var p := world.provinces[pid]
	if world.economy.start_building(p, id):
		hud.add_news("Work begins on %s in %s." % [world.economy.building_name(id, p.building_level(id) + 1), p.name])
	_show_province(pid)


# --- Realm panel -----------------------------------------------------------------

func _resource_bar(r: Realm) -> String:
	var bits := PackedStringArray()
	for k in Economy.RESOURCES:
		var amount := float(r.res.get(k, 0.0))
		var d := float(r.delta.get(k, 0.0))
		var col := "#3c6a2a" if d >= 0.0 else "#9a2a1a"
		var warn := k == "food" and r.starving or k == "gold" and r.broke
		var name_col := "#9a2a1a" if warn else "#3d2a17"
		bits.append("[color=%s][b]%s[/b][/color] %d [color=%s]%+.1f[/color]" % [name_col, k.capitalize(), int(amount), col, d])
	bits.append("[b]Men[/b] %d" % int(r.manpower))
	return "   ".join(bits)


func _show_realm() -> void:
	if world.player_realm == -1:
		return
	_clear_selection()
	_info_kind = "realm"
	var r := world.realms[world.player_realm]
	var actions: Array = []
	for i in Economy.TAX_NAMES.size():
		actions.append(["%s taxes" % Economy.TAX_NAMES[i], _act_tax.bind(i), r.tax != i])
	var fest_ok := float(r.res["gold"]) >= Economy.FESTIVAL_COST and r.festival_until <= world.day
	actions.append(["Hold festival (%dg)" % int(Economy.FESTIVAL_COST), _act_festival, fest_ok])
	if r.capital != -1:
		actions.append(["Go to capital", _act_go_capital])
	hud.show_info(r.full_name(), _realm_text(r), actions)


func _realm_text(r: Realm) -> String:
	var eco := world.economy
	var pop := 0.0
	var mood := 0.0
	var building := 0
	for pid: int in r.provinces:
		var p := world.provinces[pid]
		pop += p.pop
		mood += p.happiness
		if p.build_id != "":
			building += 1
	var n := maxi(r.provinces.size(), 1)
	var text := "%d provinces · %d people · average happiness %d\n" % [r.provinces.size(), int(pop), int(mood / n)]
	text += "Taxes: [b]%s[/b] · troops %d · manpower %d / %d\n" % [Economy.TAX_NAMES[r.tax], world.realm_troops(r), int(r.manpower), int(eco.manpower_cap(r))]
	text += "Constructions under way: %d\n" % building
	if r.festival_until > world.day:
		text += "Festival: %d days left\n" % (r.festival_until - world.day)
	if r.starving:
		text += "[color=#9a2a1a]Famine: build farms, a granary, or disband troops.[/color]\n"
	if r.broke:
		text += "[color=#9a2a1a]Treasury empty: soldiers are deserting.[/color]\n"
	text += "\n" + _resource_bar(r).replace("   ", "\n")
	return text


func _act_tax(level: int) -> void:
	world.realms[world.player_realm].tax = level
	_show_realm()


func _act_festival() -> void:
	world.economy.hold_festival(world.realms[world.player_realm])
	_show_realm()


func _act_go_capital() -> void:
	var r := world.realms[world.player_realm]
	cam.focus(world.provinces[r.capital].center, 1.2)


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
		text += "\nPopulation %d · happiness %d" % [int(p.pop), int(p.happiness)]
		if p.happiness < 30.0:
			text += " [color=#9a2a1a](rioting)[/color]"
		if r.is_player:
			text += _own_province_text(p)
	if p.siege_army != -1:
		var verb := "Being claimed" if p.owner == -1 else "Under siege"
		text += "\n[color=#8a2a1a]%s: %d%%[/color]" % [verb, int(p.siege_progress * 100.0)]
	return text


func _own_province_text(p: Province) -> String:
	var eco := world.economy
	var text := ""
	var mood := PackedStringArray()
	for part in eco.happiness_parts(p):
		mood.append("%s %+d" % [part[0], int(part[1])])
	text += "\n[font_size=14]Mood: %s[/font_size]" % ", ".join(mood)
	var y := eco.yields(p)
	var made := PackedStringArray()
	for k in Economy.RESOURCES:
		if float(y[k]) >= 0.05:
			made.append("%s +%.1f" % [k, float(y[k])])
	text += "\nMakes per day: %s · eats %.1f food" % [", ".join(made), p.pop * Economy.FOOD_PER_PERSON]
	var built := PackedStringArray()
	for id in eco.order:
		var lvl := p.building_level(id)
		if lvl > 0:
			built.append(eco.building_name(id, lvl))
	text += "\nBuildings (%d/%d slots): %s" % [eco.used_slots(p), eco.slots(p), ", ".join(built) if not built.is_empty() else "none"]
	if p.build_id != "":
		text += "\nBuilding %s: %d days left" % [eco.building_name(p.build_id, p.building_level(p.build_id) + 1), ceili(p.build_left)]
	return text


func _choose_spawn(pid: int) -> void:
	world.found_player_realm(pid)
	hud.show_spawn(false)
	hud.set_speed(world.speed)
	_clear_selection()
	hud.hide_info()
	cam.focus(world.provinces[pid].center, 1.0)
