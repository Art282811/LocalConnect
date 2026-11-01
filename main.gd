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


func _process(delta: float) -> void:
	world.advance(delta)
	var view := cam.view_size() / cam.zoom.x
	battle_view.view_rect = Rect2(cam.position - view * 0.5, view)
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
