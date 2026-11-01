extends Node2D
## Wires the simulation (sim/), the map views (map/) and the HUD (ui/).
## Owns selection: tapping provinces, armies, and giving march orders.

var world: World
var map_view: MapView
var labels: LabelsView
var overlay: OverlayView
var battle_view: BattleView
var cam: CameraRig
var hud: Hud

var selected_province := -1
var selected_army := -1
var _info_kind := ""   # "", "province", "army", "build", "realm", "battle"
var selected_battle := -1
var selected_regiment := -1
var _pending := ""      # "raid" or "join": the next tap picks the target
var _alert_index := 0
var _diplo_target := -1
var _mode_timer := 0.0
var _speed_before_event := 1.0
const MAP_MODES := ["realms", "faiths", "diplomacy"]
var _ui_timer := 0.0


func _ready() -> void:
	map_view = MapView.new()
	add_child(map_view)
	labels = LabelsView.new()
	add_child(labels)
	battle_view = BattleView.new()
	add_child(battle_view)
	battle_view.font = labels.serif
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
	hud.battle_alert_pressed.connect(_on_battle_alert)
	hud.map_mode_pressed.connect(_on_map_mode)
	hud.dynasty_pressed.connect(_show_dynasty)
	hud.continue_pressed.connect(_on_continue)
	hud.event_closed.connect(_on_event_closed)

	randomize()
	_new_world(randi())


func _new_world(seed_value: int) -> void:
	world = World.new()
	world.setup(seed_value)
	world.news_posted.connect(_on_news)
	world.map_changed.connect(_on_map_changed)
	world.battle_fought.connect(func(pos: Vector2, troops: int) -> void: overlay.add_battle(pos, troops))
	world.player_lost.connect(_on_player_lost)
	world.battle_ended.connect(_on_battle_ended)
	world.dynasty_lost.connect(_on_dynasty_lost)
	map_view.world = world
	battle_view.world = world
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
	map_view.mode = "realms"
	hud.set_map_mode("Realms")


func _process(delta: float) -> void:
	world.advance(delta)
	var view := cam.view_size() / cam.zoom.x
	battle_view.view_rect = Rect2(cam.position - view * 0.5, view)
	_ui_timer += delta
	if _ui_timer >= 0.25:
		_ui_timer = 0.0
		_refresh_hud()
	if map_view.mode == "diplomacy":
		_mode_timer += delta
		if _mode_timer > 2.0:
			_mode_timer = 0.0
			map_view.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			_on_speed(0 if world.speed > 0 else 1)
		KEY_0, KEY_QUOTELEFT:
			_on_speed(0.25)
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
	battle_view.zoom = z


func _on_speed(s: float) -> void:
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
	_maybe_show_event()
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
	var fights := _player_battles()
	if fights.is_empty():
		hud.set_battle_alert("")
	else:
		var label := "Battle at %s" % world.provinces[fights[0].province].name
		if fights.size() > 1:
			label += " (+%d)" % (fights.size() - 1)
		hud.set_battle_alert(label)
	if world.player_realm == -1:
		hud.set_resources("")
	hud.refresh_log(world.news_log)
	if _info_kind == "province" and selected_province != -1:
		hud.update_info_body(_province_text(selected_province))
	elif _info_kind == "build" and selected_province != -1:
		hud.update_info_body(_build_text(selected_province))
	elif _info_kind == "battle":
		var b := world.battle_by_id(selected_battle)
		if b == null:
			_clear_selection()
			hud.hide_info()
		else:
			hud.update_info_body(_battle_text(b))
	elif _info_kind == "diplomacy" and _diplo_target != -1:
		if world.realms[_diplo_target].alive and world.player_realm != -1:
			hud.update_info_body(_diplomacy_text(_diplo_target))
	elif _info_kind == "dynasty" and world.player_realm != -1:
		hud.update_info_body(_dynasty_text(world.realms[world.player_realm]))
	elif _info_kind == "crusades":
		hud.update_info_body(_crusades_text())
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
	selected_battle = -1
	selected_regiment = -1
	_pending = ""
	_info_kind = ""
	if battle_view != null:
		battle_view.selected_battle = -1
		battle_view.selected_regiment = -1
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

	# Battles take taps first when you are looking at one.
	for b: Battle in world.battles:
		if world_pos.distance_to(b.center) < b.radius + 4.0 or (cam.zoom.x < BattleView.BLOCK_ZOOM and world_pos.distance_to(b.center + Vector2(0, -40) / clampf(cam.zoom.x, 0.3, 2.0)) < 20.0 / clampf(cam.zoom.x, 0.3, 2.0)):
			if _battle_tap(b, world_pos):
				return

	var army_id := _army_at(screen_pos)
	if _pending == "join" and selected_army != -1:
		if army_id != -1 and army_id != selected_army:
			world.join_army(selected_army, army_id)
			hud.add_news("Your army marches to join Lord %s." % world.army_by_id(army_id).general if world.army_by_id(army_id) != null else "Armies joined.")
		_clear_selection()
		hud.hide_info()
		return
	if army_id != -1 and army_id != selected_army:
		_select_army(army_id)
		return

	if selected_army != -1:
		var a := world.army_by_id(selected_army)
		if a != null and a.realm == world.player_realm and pid != -1 and (pid != a.province or _pending == "raid"):
			var kind := "raid" if _pending == "raid" else "take"
			var days := world.order_army(selected_army, pid, kind)
			if days >= 0:
				var verb := "rides out to raid" if kind == "raid" else "marches on"
				hud.add_news("Lord %s %s %s (about %d days)." % [a.general, verb, world.provinces[pid].name, days])
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


## Returns true if the tap was used by the battle.
func _battle_tap(b: Battle, world_pos: Vector2) -> bool:
	var my_side := b.side_realm.find(world.player_realm) if world.player_realm != -1 else -1
	if cam.zoom.x >= BattleView.BLOCK_ZOOM:
		var reg := b.regiment_at(world_pos)
		var selected: Regiment = b.get_regiment(selected_regiment) if selected_battle == b.id else null
		if reg != null:
			if my_side != -1 and reg.side == my_side and b.commanded[my_side]:
				_select_regiment(b, reg.id)
				return true
			if selected != null and reg.side != selected.side and b.commanded[selected.side]:
				selected.order_target = reg.id
				selected.order_pos = Vector2.INF
				return true
			_show_battle(b)
			return true
		if selected != null and b.commanded[selected.side]:
			selected.order_pos = world_pos
			selected.order_target = -1
			return true
		if world_pos.distance_to(b.center) < b.radius:
			_show_battle(b)
			return true
		return false
	_show_battle(b)
	return true


func _select_regiment(b: Battle, reg_id: int) -> void:
	selected_battle = b.id
	selected_regiment = reg_id
	battle_view.selected_battle = b.id
	battle_view.selected_regiment = reg_id
	_show_battle(b)


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
	if a.battle != -1:
		var b := world.battle_by_id(a.battle)
		if b != null:
			_show_battle(b)
			return
	_info_kind = "army"
	selected_army = army_id
	overlay.selected_army = army_id
	hud.show_info("Lord %s's army" % a.general, _army_text(a), _army_actions(a))


const STANCE_NAMES := ["Cautious", "Balanced", "Aggressive"]


func _army_actions(a: Army) -> Array:
	var actions: Array = []
	if a.realm != world.player_realm:
		return actions
	actions.append(["Hold here", _act_hold.bind(a.id)])
	actions.append(["Raid…", _act_pending.bind(a.id, "raid")])
	actions.append(["Retreat", _act_retreat.bind(a.id)])
	actions.append(["Join…", _act_pending.bind(a.id, "join")])
	actions.append(["Stance: %s" % STANCE_NAMES[a.stance], _act_stance.bind(a.id)])
	var p := world.provinces[a.province]
	if p.owner != -1 and world.at_war(a.realm, p.owner) and a.path.is_empty():
		actions.append(["Assault walls (garrison ~%d)" % int(world.garrison_size(p)), _act_assault.bind(a.id)])
	actions.append(["Halt", _act_halt.bind(a.id)])
	var r := world.realms[a.realm]
	if a.hero != r.ruler:
		actions.append(["Lead it yourself", _act_lead.bind(a.id)])
	var c := world.religion.active_crusade(world.realms[a.realm].faith)
	if not c.is_empty():
		var leader := world.religion.lead_realm(c)
		if leader != -1 and leader != a.realm:
			actions.append(["Lend to the %s" % c["name"], _act_lend.bind(a.id, int(c["id"]))])
	return actions


func _act_hold(army_id: int) -> void:
	world.hold_army(army_id)
	_select_army(army_id)


func _act_retreat(army_id: int) -> void:
	if not world.retreat_army(army_id):
		hud.add_news("There is nowhere safe to fall back to.")
	_clear_selection()
	hud.hide_info()


func _act_pending(army_id: int, kind: String) -> void:
	_select_army(army_id)
	_pending = kind
	var hint := "Tap an enemy province to raid (or this one)." if kind == "raid" else "Tap one of your armies to join."
	hud.show_info("Lord %s awaits your word" % world.army_by_id(army_id).general, hint, [["Cancel", _select_army.bind(army_id)]])


func _act_stance(army_id: int) -> void:
	var a := world.army_by_id(army_id)
	if a != null:
		world.set_stance(army_id, (a.stance + 1) % 3)
	_select_army(army_id)


func _act_assault(army_id: int) -> void:
	if world.start_assault(army_id):
		var a := world.army_by_id(army_id)
		var b: Battle = world.battle_by_id(a.battle) if a != null else null
		if b != null:
			cam.focus(b.center, 2.4)
			_show_battle(b)
	else:
		hud.add_news("We can't storm the walls right now.")


func _act_halt(army_id: int) -> void:
	world.halt_army(army_id)
	_select_army(army_id)


func _army_text(a: Army) -> String:
	var r := world.realms[a.realm]
	var task_names := {
		"idle": "Waiting for orders", "claim": "Claiming land", "siege": "Besieging",
		"attack": "Marching to war", "defend": "Defending", "retreat": "Retreating",
		"return": "Returning home", "order": "Marching on your orders", "hold": "Holding",
		"raid": "Raiding",
	}
	var text := "Lord [b]%s[/b] of %s · %s general, skill %d\n" % [a.general, r.name, a.general_trait, a.skill]
	var hero := world.dynasty.person(a.hero)
	if hero != null:
		if hero.id == r.ruler:
			text = "[b]%s[/b], ruler of %s, leads in person · %s\n" % [hero.name, r.name, a.general_trait]
		else:
			text += "Level %d · tactics %d, siegecraft %d, logistics %d, leadership %d\n" % [hero.level, hero.tactics, hero.siegecraft, hero.logistics, hero.leadership]
	text += "[b]%d[/b] troops · quality %.1f · stance %s\n" % [a.troops, a.quality, STANCE_NAMES[a.stance].to_lower()]
	text += "%s at %s" % [task_names.get(a.task, a.task), world.provinces[a.province].name]
	if not a.path.is_empty():
		text += " → %s" % world.provinces[a.path[a.path.size() - 1]].name
	if a.order == "hold":
		text += "\nDug in for %d days%s" % [int(a.dug_in), " · stakes planted" if a.dug_in >= 4.0 else ""]
	if a.order == "raid" and a.path.is_empty():
		text += "\nRaiding: day %d of 20" % a.raid_days
	if r.is_player:
		text += "\n[i]Tap a province to march there and take it.[/i]"
	return text


# --- Battles ----------------------------------------------------------------------

func _show_battle(b: Battle) -> void:
	_info_kind = "battle"
	selected_battle = b.id
	battle_view.selected_battle = b.id
	var my_side := b.side_realm.find(world.player_realm) if world.player_realm != -1 else -1
	var actions: Array = []
	if cam.zoom.x < BattleView.BLOCK_ZOOM:
		actions.append(["Zoom in", _act_zoom_battle.bind(b.id)])
	if my_side != -1:
		if b.commanded[my_side]:
			actions.append(["Hand back to general", _act_command.bind(b.id, my_side, false)])
		else:
			actions.append(["Take command", _act_command.bind(b.id, my_side, true)])
		actions.append(["Auto-resolve", _act_autoresolve.bind(b.id)])
		actions.append(["Withdraw", _act_withdraw.bind(b.id, my_side)])
		var reg: Regiment = b.get_regiment(selected_regiment) if selected_battle == b.id else null
		if reg != null and reg.side == my_side and b.commanded[my_side]:
			for f in ["line", "wedge", "square"]:
				actions.append([str(f).capitalize(), _act_formation.bind(b.id, reg.id, f), reg.formation != f])
			for st in ["hold", "charge", "skirmish"]:
				actions.append([str(st).capitalize(), _act_reg_stance.bind(b.id, reg.id, st), reg.stance != st])
	hud.show_info("Battle of %s" % world.provinces[b.province].name, _battle_text(b), actions)


func _battle_text(b: Battle) -> String:
	var text := ""
	for side in 2:
		var rid := b.side_realm[side]
		var realm_name: String = world.realms[rid].name if rid != -1 else "?"
		var leader := "Lord %s" % b.general[side] if b.general[side] != "" else "The garrison"
		var tag := " [color=#9a2a1a](withdrawing)[/color]" if b.withdrawing[side] else ""
		var role := "attacking" if side == b.attacker else "defending"
		text += "[b]%s[/b] — %s (%s, %s): %d men, morale %d%s\n" % [realm_name, leader, b.trait_of[side], role, b.side_men(side), b.side_morale(side), tag]
	if b.walls_side != -1:
		text += "Walls: gate %s\n" % ("broken!" if b.gate_hp <= 0.0 else "%d%%" % int(100.0 * b.gate_hp / maxf(b.gate_max, 1.0)))
	text += "Fighting for %d battle-seconds." % int(b.time)
	var reg: Regiment = b.get_regiment(selected_regiment) if selected_battle == b.id else null
	if reg != null:
		text += "\n\nSelected: [b]%s[/b], %d men, morale %d, %s, %s" % [Battle.KINDS[reg.kind]["label"], int(reg.men), int(reg.morale), reg.formation, reg.stance]
		text += "\n[i]Tap the ground to move, an enemy to attack.[/i]"
	else:
		var my_side := b.side_realm.find(world.player_realm) if world.player_realm != -1 else -1
		if my_side != -1 and b.commanded[my_side]:
			text += "\n[i]Zoom in and tap one of your regiments to command it.[/i]"
	return text


func _act_zoom_battle(battle_id: int) -> void:
	var b := world.battle_by_id(battle_id)
	if b != null:
		cam.focus(b.center, 2.6)
		_show_battle.call_deferred(b)


func _act_command(battle_id: int, side: int, on: bool) -> void:
	var b := world.battle_by_id(battle_id)
	if b == null:
		return
	b.take_command(side, on)
	if on:
		if cam.zoom.x < BattleView.BLOCK_ZOOM:
			cam.focus(b.center, 2.6)
		if world.speed > 0.25:
			_on_speed(0.25)
	_show_battle(b)


func _act_autoresolve(battle_id: int) -> void:
	world.resolve_battle_now(battle_id)
	_clear_selection()
	hud.hide_info()


func _act_withdraw(battle_id: int, side: int) -> void:
	var b := world.battle_by_id(battle_id)
	if b != null:
		b.order_withdraw(side)
		_show_battle(b)


func _act_formation(battle_id: int, reg_id: int, f: String) -> void:
	var b := world.battle_by_id(battle_id)
	if b == null:
		return
	var reg := b.get_regiment(reg_id)
	if reg != null:
		reg.formation = f
	_show_battle(b)


func _act_reg_stance(battle_id: int, reg_id: int, st: String) -> void:
	var b := world.battle_by_id(battle_id)
	if b == null:
		return
	var reg := b.get_regiment(reg_id)
	if reg != null:
		reg.stance = st
	_show_battle(b)


func _on_battle_ended(b: Battle) -> void:
	if selected_battle == b.id:
		_clear_selection()
		hud.hide_info()


func _player_battles() -> Array[Battle]:
	var out: Array[Battle] = []
	if world.player_realm == -1:
		return out
	for b: Battle in world.battles:
		if b.side_realm.has(world.player_realm):
			out.append(b)
	return out


func _on_battle_alert() -> void:
	var mine := _player_battles()
	if mine.is_empty():
		return
	_alert_index = (_alert_index + 1) % mine.size()
	var b := mine[_alert_index]
	cam.focus(b.center, 2.6)
	_show_battle(b)


func _show_province(pid: int) -> void:
	var p := world.provinces[pid]
	var actions: Array = []
	if world.spawn_mode:
		var label := "Found a realm here" if p.owner == -1 else "Rule the %s" % world.realms[p.owner].name
		actions.append([label, _choose_spawn.bind(pid)])
	elif world.player_realm != -1 and p.owner != -1 and p.owner != world.player_realm:
		var me := world.player_realm
		var them := p.owner
		actions.append(["Diplomacy…", _show_diplomacy.bind(them)])
		if world.at_war(me, them):
			actions.append(["Offer peace", _act_offer_peace.bind(them, pid)])
		else:
			var truce_end: int = world.realms[me].truces.get(them, -1)
			var ok := truce_end <= world.day
			var label := "Declare war" if ok else "Truce until Y%d" % (truce_end / World.DAYS_PER_YEAR + 1)
			actions.append([label, _act_declare_war.bind(them, pid), ok])
		var why := world.religion.launch_problem(world.realms[me], pid)
		if world.religion.group_of(world.realms[them].faith) != world.religion.group_of(world.realms[me].faith):
			var hw := world.religion.holy_war_name(world.realms[me].faith)
			actions.append(["Call a %s here" % hw if why == "" else "%s: %s" % [hw, why], _act_launch.bind(pid), why == ""])
	elif world.player_realm != -1 and p.owner == world.player_realm:
		var r := world.realms[p.owner]
		var eco := world.economy
		actions.append(["Build…", _show_build_menu.bind(pid), p.build_id == ""])
		var levy := eco.levy_problem(r, p)
		actions.append(["Raise levy (%d men, %dg)" % [Economy.LEVY_SIZE, int(Economy.LEVY_GOLD)] if levy == "" else "Levy: " + levy, _act_levy.bind(pid), levy == ""])
		if p.faith != r.faith:
			var mp := world.religion.mission_problem(r, p)
			actions.append(["Send missionaries (%d faith)" % int(Religion.MISSION_COST) if mp == "" else "Missionaries: " + mp, _act_mission.bind(pid), mp == ""])
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
	if world.religion.has_head(r.faith):
		var title := world.religion.head_title(r.faith)
		actions.append(["Donate to the %s (%dg)" % [title, int(Religion.DONATION)], _act_donate, float(r.res["gold"]) >= Religion.DONATION])
	actions.append(["Offers (%d)" % world.diplomacy.offers.size(), _show_offers, not world.diplomacy.offers.is_empty()])
	actions.append(["Holy wars (%d)" % world.religion.crusades.size(), _show_crusades])
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
	var text := ""
	var ruler := world.dynasty.ruler_of(r)
	if ruler != null:
		text += "Ruled by [b]%s %s[/b], age %d\n" % [ruler.name, r.house, ruler.age(world.day)]
	text += "%d provinces · %d people · average happiness %d\n" % [r.provinces.size(), int(pop), int(mood / n)]
	text += "Taxes: [b]%s[/b] · troops %d · manpower %d / %d\n" % [Economy.TAX_NAMES[r.tax], world.realm_troops(r), int(r.manpower), int(eco.manpower_cap(r))]
	text += "Constructions under way: %d\n" % building
	var rel := world.religion
	text += "Faith: [b]%s[/b]" % rel.faith_name(r.faith)
	if rel.has_head(r.faith):
		text += " · the %s thinks of you %+d" % [rel.head_title(r.faith), int(rel.head_opinion(r))]
	if r.excommunicated:
		text += " · [color=#9a2a1a]EXCOMMUNICATED[/color]"
	text += "\n"
	if not r.relics.is_empty():
		text += "Relics: %s\n" % ", ".join(PackedStringArray(r.relics))
	var trade := world.diplomacy.trade_income(r.id)
	if trade > 0.0:
		text += "Trade routes bring %.1f gold a day\n" % trade
	var pacts := PackedStringArray()
	for t in world.diplomacy.treaties:
		if int(t["a"]) == r.id or int(t["b"]) == r.id:
			var other := int(t["b"]) if int(t["a"]) == r.id else int(t["a"])
			pacts.append("%s with %s" % [Diplomacy.TREATY_NAMES[t["type"]], world.realms[other].name])
	if not pacts.is_empty():
		text += "Treaties: %s\n" % ", ".join(pacts)
	if r.liege != -1:
		text += "You are a vassal of the %s.\n" % world.realms[r.liege].full_name()
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


func _act_donate() -> void:
	if world.religion.donate(world.realms[world.player_realm]):
		hud.add_news("Your gift pleases the %s." % world.religion.head_title(world.realms[world.player_realm].faith))
	_show_realm()


func _act_mission(pid: int) -> void:
	if world.religion.start_mission(world.realms[world.player_realm], world.provinces[pid]):
		hud.add_news("Missionaries set out for %s." % world.provinces[pid].name)
	_show_province(pid)


func _act_launch(pid: int) -> void:
	if world.religion.launch(world.realms[world.player_realm], pid):
		_show_crusades()


func _on_map_mode() -> void:
	var i := (MAP_MODES.find(map_view.mode) + 1) % MAP_MODES.size()
	map_view.mode = MAP_MODES[i]
	hud.set_map_mode(str(MAP_MODES[i]).capitalize())
	map_view.queue_redraw()


# --- Diplomacy screen -------------------------------------------------------------------

const PROPOSALS := [
	["gift", "Send a gift (50g)"], ["nap", "Non-aggression pact"], ["alliance", "Alliance"],
	["defensive", "Defensive pact"], ["trade", "Trade agreement"], ["tribute", "Demand tribute"],
	["vassal", "Demand vassalage"], ["offer_vassal", "Become their vassal"], ["insult", "Insult them"],
]


func _show_diplomacy(rid: int) -> void:
	_clear_selection()
	_info_kind = "diplomacy"
	_diplo_target = rid
	var me := world.player_realm
	var dip := world.diplomacy
	var actions: Array = []
	for prop in PROPOSALS:
		var kind: String = prop[0]
		var label: String = prop[1]
		if kind in ["nap", "alliance", "defensive", "trade"] and dip.has_treaty(kind, me, rid):
			actions.append(["Cancel " + label.to_lower(), _act_break.bind(kind, rid)])
			continue
		if kind == "tribute" and dip.has_treaty("tribute", me, rid):
			continue
		if (kind == "vassal" or kind == "offer_vassal") and (dip.has_treaty("vassal", me, rid) or dip.has_treaty("vassal", rid, me)):
			continue
		var enabled := true
		if not (kind in ["gift", "insult"]):
			var verdict := dip.evaluate(kind, me, rid)
			label += " (likely)" if verdict[0] else " (unlikely)"
			enabled = dip.cooldown_left(me, rid, kind) == 0 and not world.at_war(me, rid)
		elif kind == "gift":
			enabled = float(world.realms[me].res["gold"]) >= Diplomacy.GIFT_GOLD
		actions.append([label, _act_propose.bind(kind, rid), enabled])
	if dip.has_treaty("vassal", me, rid):
		actions.append(["Release vassal", _act_break.bind("vassal_release", rid)])
	actions.append(["Royal marriage…", _show_royal_match.bind(rid)])
	actions.append(["Back", _show_province.bind(world.realms[rid].capital)])
	hud.show_info("Diplomacy: %s" % world.realms[rid].full_name(), _diplomacy_text(rid), actions)


func _diplomacy_text(rid: int) -> String:
	var me := world.player_realm
	var them := world.realms[rid]
	var dip := world.diplomacy
	var text := "%s · %s ruler · %d provinces\n" % [world.religion.faith_name(them.faith), them.personality, them.provinces.size()]
	text += "Strength: theirs %d vs yours %d\n" % [int(world.realm_strength(them)), int(world.realm_strength(world.realms[me]))]
	text += "They think of you: [b]%+d[/b]\n" % int(dip.opinion(rid, me))
	var bits := PackedStringArray()
	for part in dip.opinion_parts(rid, me):
		bits.append("%s %+d" % [part[0], int(part[1])])
	text += "[font_size=14]%s[/font_size]\n" % ", ".join(bits)
	text += "You think of them: %+d\n" % int(dip.opinion(me, rid))
	var friends := PackedStringArray()
	for a in dip.allies_of(rid, ["alliance", "defensive"]):
		friends.append(world.realms[a].name)
	if not friends.is_empty():
		text += "Their allies: %s\n" % ", ".join(friends)
	if them.oathbreaker >= 1.0:
		text += "[color=#9a2a1a]Known oathbreaker[/color]\n"
	return text


func _act_propose(kind: String, rid: int) -> void:
	var result := world.diplomacy.propose(kind, world.player_realm, rid)
	if result != "":
		hud.add_news(result)
	_show_diplomacy(rid)


func _act_break(kind: String, rid: int) -> void:
	if kind == "vassal_release":
		world.diplomacy.remove_treaty("vassal", world.player_realm, rid)
	else:
		world.diplomacy.break_treaty(kind, world.player_realm, rid)
	hud.add_news("Treaty with %s ended." % world.realms[rid].name)
	_show_diplomacy(rid)


func _show_offers() -> void:
	_clear_selection()
	_info_kind = "offers"
	var actions: Array = []
	var text := ""
	for o in world.diplomacy.offers:
		text += "• %s [i](%d days to answer)[/i]\n" % [o["text"], int(o["expires"]) - world.day]
		var who := world.realms[int(o["from"])].name
		actions.append(["Accept: %s" % who, _act_answer.bind(int(o["id"]), true)])
		actions.append(["Refuse: %s" % who, _act_answer.bind(int(o["id"]), false)])
	if text == "":
		text = "No envoys are waiting."
	actions.append(["Back", _show_realm])
	hud.show_info("Envoys at court", text, actions)


func _act_answer(offer_id: int, accept: bool) -> void:
	world.diplomacy.answer_offer(offer_id, accept)
	if world.diplomacy.offers.is_empty():
		_show_realm()
	else:
		_show_offers()


# --- Holy wars ---------------------------------------------------------------------------

func _show_crusades() -> void:
	_clear_selection()
	_info_kind = "crusades"
	var me: Realm = world.realms[world.player_realm] if world.player_realm != -1 else null
	var rel := world.religion
	var actions: Array = []
	for c in rel.crusades:
		if me == null:
			continue
		var cid := int(c["id"])
		if c["faith"] == me.faith:
			var jp := rel.join_problem(c, me)
			if jp == "":
				actions.append(["Join the %s" % c["name"], _act_join_crusade.bind(cid)])
			actions.append(["Pledge %dg" % int(Religion.PLEDGE_GOLD), _act_pledge.bind(cid), float(me.res["gold"]) >= Religion.PLEDGE_GOLD])
	actions.append(["Back", _show_realm])
	hud.show_info("Holy wars", _crusades_text(), actions)


func _crusades_text() -> String:
	var rel := world.religion
	var text := ""
	for c in rel.crusades:
		var target := world.realms[int(c["target_realm"])]
		var members := PackedStringArray()
		for rid in c["members"]:
			members.append(world.realms[int(rid)].name)
		var days_left := Religion.GATHER_DAYS - (world.day - int(c["start"])) if c["phase"] == "gathering" else Religion.CRUSADE_DAYS - (world.day - int(c["start"]))
		text += "[b]%s[/b] (%s faith) against the %s\n" % [c["name"], rel.faith_name(str(c["faith"])), target.full_name()]
		text += "%s · %d days left · %s\n" % ["Gathering" if c["phase"] == "gathering" else "At war", days_left, ("Crusaders: " + ", ".join(members)) if not members.is_empty() else "No one has joined yet"]
		var held := 0
		for pid in c["provinces"]:
			var o := world.provinces[int(pid)].owner
			if o != -1 and (c["members"] as Dictionary).has(o):
				held += 1
		text += "Target lands taken: %d / %d\n\n" % [held, (c["provinces"] as Array).size()]
	if text == "":
		text = "No holy war is under way.\n\n"
	if world.year() < Religion.CRUSADE_MIN_YEAR:
		text += "Holy wars can be called from Year %d.\n" % Religion.CRUSADE_MIN_YEAR
	text += "[i]Join to fight, pledge gold to share the blessing, or lend an army (tap your army). To call your own, tap a province ruled by unbelievers (needs %d faith and the favour of your faith's head).[/i]" % int(Religion.LAUNCH_FAITH)
	return text


func _act_join_crusade(cid: int) -> void:
	var c := world.religion.crusade_by_id(cid)
	if not c.is_empty():
		world.religion.join(c, world.realms[world.player_realm])
	_show_crusades()


func _act_pledge(cid: int) -> void:
	var c := world.religion.crusade_by_id(cid)
	if not c.is_empty() and world.religion.pledge(c, world.realms[world.player_realm]):
		hud.add_news("Your gold goes to the %s." % c["name"])
	_show_crusades()


func _act_lend(army_id: int, cid: int) -> void:
	var c := world.religion.crusade_by_id(cid)
	var a := world.army_by_id(army_id)
	if not c.is_empty() and a != null and world.religion.lend_army(c, a):
		_clear_selection()
		hud.hide_info()


# --- Dynasty ------------------------------------------------------------------------------

func _person_line(c: Character) -> String:
	var bits := "%s, %d" % [c.name, c.age(world.day)]
	var spouse := world.dynasty.person(c.spouse)
	if spouse != null:
		bits += ", wed to %s" % spouse.name
	if c.prisoner_of != -1:
		bits += " [color=#9a2a1a](prisoner of %s)[/color]" % world.realms[c.prisoner_of].name
	return bits


func _dynasty_text(r: Realm) -> String:
	var dyn := world.dynasty
	var ruler := dyn.ruler_of(r)
	var text := ""
	if ruler != null:
		text += "[b]%s %s[/b], age %d · %s\n" % [ruler.name, r.house, ruler.age(world.day), ruler.personality]
		text += "Martial %d · stewardship %d · diplomacy %d · learning %d" % [ruler.martial, ruler.stewardship, ruler.diplomacy, ruler.learning]
		if ruler.health < 1.0:
			text += " · [color=#9a2a1a]ill[/color]"
		text += "\n"
		var spouse := dyn.person(ruler.spouse)
		text += "Spouse: %s\n" % (_person_line(spouse) if spouse != null else "none")
		var kids := PackedStringArray()
		for cid in ruler.children:
			var k := dyn.person(cid)
			if k != null and k.alive():
				kids.append("%s (%s)" % [_person_line(k), "daughter" if k.female else "son"])
		text += "Children: %s\n" % (", ".join(kids) if not kids.is_empty() else "none")
	text += "Succession: [b]%s[/b] · " % Dynasty.LAW_NAMES[r.succession]
	var heir := dyn.person(dyn.heir_of(r))
	if r.succession == "elective":
		var vote := dyn.election(r)
		text += "projected vote: your house %d, rivals %d" % [int(vote[1]), int(vote[2])]
		if heir != null and heir.house != r.house:
			text += " [color=#9a2a1a](you would lose the crown!)[/color]"
		text += "\n"
	elif heir != null:
		text += "heir: %s\n" % _person_line(heir)
	else:
		text += "[color=#9a2a1a]no heir! If you die, your line ends.[/color]\n"
	var claims := PackedStringArray()
	for c in dyn.family_of(r):
		for k in c.claims:
			if world.realms[k].alive and k != r.id:
				claims.append("%s → %s" % [c.name, world.realms[k].name])
	if not claims.is_empty():
		text += "Claims: %s\n" % ", ".join(claims)
	text += "\n[b]Great families[/b]\n"
	for f in r.nobles:
		text += "%s — loyalty %d, power %d, ambition %d%s%s\n" % [f["name"], int(f["loyalty"]), int(f["power"]), int(f["ambition"]),
			" · holds %d" % (f["granted"] as Array).size() if not (f["granted"] as Array).is_empty() else "",
			" · [color=#9a2a1a]FACTION[/color]" if f["faction"] else ""]
	if not r.prisoners.is_empty():
		text += "\nPrisoners at your court: %d\n" % r.prisoners.size()
	return text


func _show_dynasty() -> void:
	if world.player_realm == -1:
		return
	_clear_selection()
	_info_kind = "dynasty"
	var r := world.realms[world.player_realm]
	var actions: Array = [["Family…", _show_family], ["Great families…", _show_nobles], ["Prisoners (%d)…" % r.prisoners.size(), _show_prisoners, not r.prisoners.is_empty()]]
	for law in Dynasty.LAWS:
		if law != r.succession:
			actions.append(["Law: %s" % Dynasty.LAW_NAMES[law], _act_law.bind(law)])
	hud.show_info("House %s" % r.house, _dynasty_text(r), actions)


func _act_law(law: String) -> void:
	var msg := world.dynasty.set_law(world.realms[world.player_realm], law)
	if msg != "":
		hud.add_news(msg)
	_show_dynasty()


func _show_family() -> void:
	_info_kind = "family"
	var r := world.realms[world.player_realm]
	var dyn := world.dynasty
	var text := ""
	var actions: Array = []
	for c in dyn.family_of(r):
		var role := "kin"
		if c.id == r.ruler:
			role = "ruler"
		elif c.father == r.ruler or c.mother == r.ruler:
			role = "daughter" if c.female else "son"
		text += "• %s — %s · M%d S%d D%d L%d\n" % [_person_line(c), role, c.martial, c.stewardship, c.diplomacy, c.learning]
		if r.succession == "chosen" and c.id != r.ruler and r.chosen_heir != c.id:
			actions.append(["Make %s heir" % c.name, _act_choose_heir.bind(c.id)])
		if dyn.eligible(c):
			actions.append(["Find a match for %s" % c.name, _show_matches.bind(c.id)])
	if text == "":
		text = "Your house has no one else at court."
	actions.append(["Back", _show_dynasty])
	hud.show_info("The family", text, actions)


func _act_choose_heir(cid: int) -> void:
	world.realms[world.player_realm].chosen_heir = cid
	hud.add_news("%s is named heir." % world.dynasty.person(cid).name)
	_show_family()


func _show_matches(cid: int) -> void:
	var dyn := world.dynasty
	var c := dyn.person(cid)
	var r := world.realms[world.player_realm]
	var actions: Array = []
	var text := "Matches for %s, age %d:\n" % [c.name, c.age(world.day)]
	for o in dyn.candidates_for(c, 6):
		var them := world.realms[o.realm]
		var op := int(world.diplomacy.opinion(them.id, r.id))
		text += "• %s of %s, %d (they think of you %+d)\n" % [o.name, them.name, o.age(world.day), op]
		actions.append(["Wed %s of %s" % [o.name, them.name], _act_wed.bind(cid, o.id)])
	for f in r.nobles:
		actions.append(["Marry into the %s family" % f["name"], _act_marry_noble.bind(cid, str(f["name"]))])
	actions.append(["Back", _show_family])
	hud.show_info("A match for %s" % c.name, text, actions)


func _act_wed(cid: int, oid: int) -> void:
	var msg := world.dynasty.propose_marriage(world.dynasty.person(cid), world.dynasty.person(oid))
	if msg != "":
		hud.add_news(msg)
	_show_family()


func _act_marry_noble(cid: int, fam: String) -> void:
	var r := world.realms[world.player_realm]
	for f in r.nobles:
		if f["name"] == fam:
			hud.add_news(world.dynasty.marry_into(r, f, world.dynasty.person(cid)))
	_show_family()


func _show_royal_match(rid: int) -> void:
	var dyn := world.dynasty
	var me := world.realms[world.player_realm]
	var actions: Array = []
	var text := "Unwed members of both houses:\n"
	for mine in dyn.family_of(me):
		if not dyn.eligible(mine):
			continue
		for theirs in dyn.family_of(world.realms[rid]):
			if dyn.eligible(theirs) and theirs.female != mine.female:
				actions.append(["Wed %s to %s" % [mine.name, theirs.name], _act_wed.bind(mine.id, theirs.id)])
	if actions.is_empty():
		text = "No suitable match between your houses right now."
	actions.append(["Back", _show_diplomacy.bind(rid)])
	hud.show_info("Royal marriage with %s" % world.realms[rid].name, text, actions)


func _show_nobles() -> void:
	_info_kind = "nobles"
	var r := world.realms[world.player_realm]
	var actions: Array = []
	var free := -1
	for pid: int in r.provinces:
		if pid != r.capital and world.provinces[pid].fief == "":
			free = pid
			break
	var text := "Loyal families send troops and back your heir. Disloyal ones refuse troops, form factions, and may try a coup or break away with the lands you granted them.\n\n"
	for f in r.nobles:
		var head := world.dynasty.person(int(f["head"]))
		text += "[b]%s[/b] (Lord %s) — loyalty %d, power %d, ambition %d%s\n" % [f["name"], head.name if head != null else "?", int(f["loyalty"]), int(f["power"]), int(f["ambition"]), " · [color=#9a2a1a]FACTION[/color]" if f["faction"] else ""]
		var fam := str(f["name"])
		actions.append(["Bribe %s (%dg)" % [fam, int(Dynasty.BRIBE_GOLD)], _act_noble.bind(fam, "bribe", -1), float(r.res["gold"]) >= Dynasty.BRIBE_GOLD])
		if free != -1:
			actions.append(["Grant %s to %s" % [world.provinces[free].name, fam], _act_noble.bind(fam, "grant", free)])
		if not (f["granted"] as Array).is_empty():
			actions.append(["Revoke land from %s" % fam, _act_noble.bind(fam, "revoke", -1)])
	actions.append(["Back", _show_dynasty])
	hud.show_info("Great families of %s" % r.name, text, actions)


func _act_noble(fam: String, what: String, pid: int) -> void:
	var r := world.realms[world.player_realm]
	for f in r.nobles:
		if f["name"] != fam:
			continue
		match what:
			"bribe":
				hud.add_news(world.dynasty.bribe(r, f))
			"grant":
				hud.add_news(world.dynasty.grant_province(r, f, pid))
			"revoke":
				hud.add_news(world.dynasty.revoke(r, f))
	_show_nobles()


func _show_prisoners() -> void:
	_info_kind = "prisoners"
	var r := world.realms[world.player_realm]
	var dyn := world.dynasty
	var actions: Array = []
	var text := ""
	for cid in r.prisoners:
		var c := dyn.person(cid)
		if c == null:
			continue
		var home := world.realms[c.realm].name if c.realm != -1 else "nowhere"
		text += "• %s of %s (ransom %d gold)\n" % [c.title_name(), home, int(dyn.ransom_price(c))]
		actions.append(["Ransom %s" % c.name, _act_prisoner.bind(cid, "ransom")])
		actions.append(["Release %s" % c.name, _act_prisoner.bind(cid, "release")])
		actions.append(["Execute %s" % c.name, _act_prisoner.bind(cid, "execute")])
	if text == "":
		text = "Your dungeons are empty."
	actions.append(["Back", _show_dynasty])
	hud.show_info("Prisoners", text, actions)


func _act_prisoner(cid: int, what: String) -> void:
	var c := world.dynasty.person(cid)
	if c == null:
		return
	var msg := ""
	match what:
		"ransom":
			msg = world.dynasty.release(c, true)
		"release":
			msg = world.dynasty.release(c, false)
		"execute":
			msg = world.dynasty.execute(c)
	if msg != "":
		hud.add_news(msg)
	_show_prisoners()


func _act_lead(army_id: int) -> void:
	var msg := world.lead_army(army_id)
	if msg != "":
		hud.add_news(msg)
	_select_army(army_id)


# --- Events and endings ----------------------------------------------------------------------

func _maybe_show_event() -> void:
	if hud.is_event_open() or world.player_realm == -1 or world.dynasty.pending_events.is_empty():
		return
	var ev: Dictionary = world.dynasty.pending_events.pop_front()
	_speed_before_event = world.speed if world.speed > 0.0 else _speed_before_event
	world.speed = 0.0
	hud.set_speed(0.0)
	hud.show_event(str(ev["title"]), str(ev["text"]), ev["options"])


func _on_event_closed() -> void:
	if world.dynasty.pending_events.is_empty() and world.player_realm != -1:
		world.speed = _speed_before_event
		hud.set_speed(world.speed)


func _on_dynasty_lost(text: String, can_continue: bool) -> void:
	world.speed = 0.0
	hud.set_speed(0.0)
	_clear_selection()
	hud.hide_info()
	hud.show_game_over("Your dynasty has fallen", text, can_continue)


func _on_continue() -> void:
	world.speed = 1.0
	hud.set_speed(1.0)
	if world.player_realm != -1:
		hud.add_news("You play on as the house of %s." % world.realms[world.player_realm].house)


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
		text += "\nPopulation %d · happiness %d · %s faith" % [int(p.pop), int(p.happiness), world.religion.faith_name(p.faith)]
		if p.holy_site != "":
			text += " · [b]holy site of %s[/b]" % p.holy_site
		if p.mission_until > world.day:
			text += " · missionaries at work (%d days)" % (p.mission_until - world.day)
		if world.player_realm != -1 and p.owner != world.player_realm:
			var me := world.player_realm
			var o := int(world.diplomacy.opinion(p.owner, me))
			text += "\nThey think of you: [b]%+d[/b]" % o
			var pacts := PackedStringArray()
			for t in world.diplomacy.treaties_between(me, p.owner):
				pacts.append(str(Diplomacy.TREATY_NAMES[t["type"]]))
			if not pacts.is_empty():
				text += " · " + ", ".join(pacts)
		if r.liege != -1:
			text += "\nVassal of the %s" % world.realms[r.liege].full_name()
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
